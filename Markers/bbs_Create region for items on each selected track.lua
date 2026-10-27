-- @description Create a region for items on each selected track
-- @version 1.2
-- @author bbs
-- @about
--   Creates one named, colored region spanning all items directly on each selected track.
--   Empty tracks are skipped. Folder children are not included by this action.
-- @changelog
--   Handle negative positions and custom colors; avoid empty undo and protect cleanup.

local function run_edit(description, edit)
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  local ok, err = xpcall(edit, debug.traceback)
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock(description, -1)
  reaper.UpdateArrange()
  if not ok then
    reaper.ShowMessageBox(
      "The action stopped. Undo once to revert any completed changes.\n\n" .. tostring(err),
      "Reabbscript", 0
    )
  end
end

local function main()
  if reaper.CountSelectedTracks(0) == 0 then
    reaper.ShowMessageBox("Select at least one track.", "Reabbscript", 0)
    return
  end
  local regions = {}
  for i = 0, reaper.CountSelectedTracks(0) - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    local first, last = math.huge, -math.huge
    for j = 0, reaper.CountTrackMediaItems(track) - 1 do
      local item = reaper.GetTrackMediaItem(track, j)
      local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      first = math.min(first, pos)
      last = math.max(last, pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH"))
    end
    if last > first then
      local _, name = reaper.GetTrackName(track)
      local color = reaper.GetTrackColor(track)
      if color ~= 0 then color = color | 0x1000000 end
      regions[#regions + 1] = { first = first, last = last, name = name, color = color }
    end
  end
  if #regions == 0 then return end
  run_edit("Create regions for items on selected tracks", function()
    for _, region in ipairs(regions) do
      assert(reaper.AddProjectMarker2(0, true, region.first, region.last, region.name, -1, region.color) >= 0,
        "REAPER could not create a region.")
    end
  end)
end

-- Explicit undo blocks above own edits; no automatic undo point for a no-op.
reaper.defer(function() end)
main()
