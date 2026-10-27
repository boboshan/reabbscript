-- @description Split selected items by reference tracks and delete gaps
-- @version 1.0
-- @author bbs
-- @about
--   Selected tracks supply reference spans from all their items. Selecting a
--   folder includes its own items and every nested descendant track. Overlapping
--   and touching reference spans are merged across all reference tracks.
--
--   Selected items are the targets. They are split at reference boundaries, and
--   portions outside the reference spans are deleted, including targets entirely
--   outside those spans. Reference items cover themselves and remain unchanged.
--   Surviving target pieces remain selected; other selections are preserved.
--
--   Empty reference sets abort safely. Locked targets are skipped and counted.
--   Native item splitting preserves take sources, offsets, and playback rates.
--   Changes share one undo entry. If splitting fails, no gaps are deleted; use
--   Undo to restore any partial splits before correcting the error and retrying.
-- @changelog
--   + Initial release.

local ACTION_NAME = "Split selected items by reference tracks and delete gaps"
-- Absorb arithmetic roundoff, far below one audio sample (one nanosecond).
local TIME_EPSILON = 1e-9

local function collect_reference_spans()
  local spans = {}
  local selected_folder_depth = 0
  -- Visit each track once, even when both a folder and its child are selected.
  for index = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, index)
    local selected = reaper.IsTrackSelected(track)
    local depth_change = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    local in_selected_folder = selected_folder_depth > 0
    if selected or in_selected_folder then
      for item_index = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, item_index)
        local start_time = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        if length > 0 then
          spans[#spans + 1] = { start_time = start_time, end_time = start_time + length }
        end
      end
    end
    if in_selected_folder then
      selected_folder_depth = math.max(0, selected_folder_depth + depth_change)
    elseif selected and depth_change > 0 then
      selected_folder_depth = depth_change
    end
  end
  return spans
end

local function collect_targets()
  local targets = {}
  for index = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local item = reaper.GetSelectedMediaItem(0, index)
    local start_time = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    targets[#targets + 1] = {
      item = item,
      track = reaper.GetMediaItemTrack(item),
      start_time = start_time,
      end_time = start_time + reaper.GetMediaItemInfo_Value(item, "D_LENGTH"),
      locked = (math.floor(reaper.GetMediaItemInfo_Value(item, "C_LOCK")) & 1) ~= 0,
    }
  end
  return targets
end

local function merge_spans(spans)
  table.sort(spans, function(a, b)
    if a.start_time == b.start_time then return a.end_time < b.end_time end
    return a.start_time < b.start_time
  end)
  local merged = {}
  for _, span in ipairs(spans) do
    local previous = merged[#merged]
    if previous and span.start_time - previous.end_time <= TIME_EPSILON then
      previous.end_time = math.max(previous.end_time, span.end_time)
    else
      merged[#merged + 1] = span
    end
  end
  return merged
end

local function first_overlapping_span(spans, start_time)
  local low, high = 1, #spans + 1
  while low < high do
    local middle = math.floor((low + high) / 2)
    if spans[middle].end_time <= start_time then
      low = middle + 1
    else
      high = middle
    end
  end
  return low
end

local function build_plans(targets, spans)
  local plans = {}
  local locked_count = 0
  for _, target in ipairs(targets) do
    if target.locked then
      locked_count = locked_count + 1
    elseif target.end_time > target.start_time then
      local segments = {}
      local cursor = target.start_time
      local span_index = first_overlapping_span(spans, cursor)
      while span_index <= #spans and spans[span_index].start_time < target.end_time do
        local span = spans[span_index]
        local keep_start = math.max(target.start_time, span.start_time)
        local keep_end = math.min(target.end_time, span.end_time)
        -- Do not create microscopic pieces at an existing item edge.
        if keep_start - target.start_time <= TIME_EPSILON then keep_start = target.start_time end
        if target.end_time - keep_end <= TIME_EPSILON then keep_end = target.end_time end
        if cursor < keep_start then
          segments[#segments + 1] = { end_time = keep_start, keep = false }
        end
        segments[#segments + 1] = { end_time = keep_end, keep = true }
        cursor = keep_end
        span_index = span_index + 1
      end
      if cursor < target.end_time then
        segments[#segments + 1] = { end_time = target.end_time, keep = false }
      end
      if #segments > 1 or (#segments == 1 and not segments[1].keep) then
        plans[#plans + 1] = { item = target.item, track = target.track, segments = segments }
      end
    end
  end
  return plans, locked_count
end

local function apply_plans(plans)
  local gaps = {}
  -- Complete every split before deleting anything, including wholly outside targets.
  for _, plan in ipairs(plans) do
    local piece = plan.item
    for index, segment in ipairs(plan.segments) do
      local right
      if index < #plan.segments then
        right = reaper.SplitMediaItem(piece, segment.end_time)
        if not right then
          error(string.format(
            "REAPER could not split a selected item at %.9f seconds. No gap items were deleted.",
            segment.end_time
          ), 0)
        end
        reaper.SetMediaItemSelected(right, true)
      end
      reaper.SetMediaItemSelected(piece, true)
      if not segment.keep then
        gaps[#gaps + 1] = { track = plan.track, item = piece }
      end
      piece = right
    end
  end
  for _, gap in ipairs(gaps) do
    if not reaper.DeleteTrackMediaItem(gap.track, gap.item) then
      error("REAPER could not delete a gap item. Further deletion was stopped.", 0)
    end
  end
end

local function locked_message(count)
  return string.format("Skipped %d locked selected item%s. Unlock them and run the action again if needed.",
    count, count == 1 and "" or "s")
end

local undo_started = false
local refresh_suppressed = false
local locked_count = 0

local function main()
  local references = collect_reference_spans()
  local targets = collect_targets()
  if #targets == 0 then
    reaper.ShowMessageBox("Select target items to split. Selected tracks provide the reference spans.",
      ACTION_NAME, 0)
    return
  end
  if #references == 0 then
    reaper.ShowMessageBox(
      "No positive-length reference items were found. Select reference tracks containing items "
        .. "(or their parent folders), then run the action again. Target items were not changed.",
      ACTION_NAME, 0)
    return
  end

  local plans
  plans, locked_count = build_plans(targets, merge_spans(references))
  if #plans == 0 then return end

  reaper.Undo_BeginBlock2(0)
  undo_started = true
  reaper.PreventUIRefresh(1)
  refresh_suppressed = true
  apply_plans(plans)
end

-- Suppress REAPER's automatic undo point; only actual edit plans open a block.
reaper.defer(function() end)
local ok, failure = xpcall(main, debug.traceback)
if refresh_suppressed then reaper.PreventUIRefresh(-1) end
if undo_started then
  reaper.Undo_EndBlock2(0, ACTION_NAME .. (ok and "" or " (incomplete)"), -1)
  reaper.UpdateArrange()
end
if not ok then
  local recovery = undo_started
    and "Use Edit > Undo to restore any partial changes. Check item locking before retrying."
    or "No items were changed. Check the selected reference tracks and target items before retrying."
  local skipped = locked_count > 0 and ("\n\n" .. locked_message(locked_count)) or ""
  reaper.ShowMessageBox("The action stopped:\n\n" .. tostring(failure) .. "\n\n" .. recovery .. skipped,
    ACTION_NAME, 0)
elseif locked_count > 0 then
  reaper.ShowMessageBox(locked_message(locked_count), ACTION_NAME, 0)
end
