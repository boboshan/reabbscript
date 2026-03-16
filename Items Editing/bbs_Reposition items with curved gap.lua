-- @description Repositions selected items in batches with an optional curved gap.
-- @version 1.3
-- @author bbs
-- @about
--   # Reposition Item Groups with Curved Gap
--   Groups selected items into batches of N and repositions each batch with
--   a fixed or curved (accelerating/decelerating) gap between batches.
--   Items sharing a REAPER group ID are treated as one logical unit and
--   shifted together across all tracks.
--   The script remembers your last-used settings.
--
--   - Set Start Gap = End Gap for a uniform gap between all batches.
--   - Set Items per group = 1 to apply a gap between every individual item.
--   - Spacing Mode 'end': gap is measured from the end of the last item in
--     the previous batch (default). 'start': from the start of its first item.
--   - Curve > 1: gaps widen over time (ease-out). Curve < 1: gaps narrow (ease-in).

local SECTION        = "bbs_RepositionGroupsCurvedGap"
local KEY_START_GAP  = "start_gap"
local KEY_END_GAP    = "end_gap"
local KEY_CURVE      = "curve_power"
local KEY_MODE       = "spacing_mode"
local KEY_GROUP_SIZE = "group_size"

local function main()
  local num_selected = reaper.CountSelectedMediaItems(0)
  if num_selected < 2 then
    reaper.ShowMessageBox("Please select at least two items.", "Script Aborted", 0)
    return
  end

  -- Load persisted settings, falling back to sensible defaults
  local function get_state(key, default)
    local v = reaper.GetExtState(SECTION, key)
    return (v ~= "") and v or default
  end

  local last_start_gap  = get_state(KEY_START_GAP,  "0.5")
  local last_end_gap    = get_state(KEY_END_GAP,    "0.5")
  local last_curve      = get_state(KEY_CURVE,      "1.0")
  local last_mode       = get_state(KEY_MODE,       "end")
  local last_group_size = get_state(KEY_GROUP_SIZE, "3")

  local ret, user_input = reaper.GetUserInputs(
    "Reposition Item Groups with Curved Gap", 5,
    "Start Gap (sec),End Gap (sec),Curve Power (>0),Spacing (end/start),Items per group",
    last_start_gap .. "," .. last_end_gap .. "," .. last_curve .. "," .. last_mode .. "," .. last_group_size
  )
  if not ret then return end

  local sg_str, eg_str, cp_str, mode_str, gs_str =
    user_input:match("([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)")

  local start_gap    = tonumber(sg_str)  or 0.5
  local end_gap      = tonumber(eg_str)  or 0.5
  local curve_power  = tonumber(cp_str)  or 1.0
  local spacing_mode = (mode_str or "end"):lower()
  local group_size   = math.floor(tonumber(gs_str) or 3)

  if curve_power <= 0 then curve_power = 1 end
  if group_size < 1   then group_size  = 1 end

  -- Persist settings for next run
  reaper.SetExtState(SECTION, KEY_START_GAP,  tostring(start_gap),   true)
  reaper.SetExtState(SECTION, KEY_END_GAP,    tostring(end_gap),     true)
  reaper.SetExtState(SECTION, KEY_CURVE,      tostring(curve_power), true)
  reaper.SetExtState(SECTION, KEY_MODE,       spacing_mode,          true)
  reaper.SetExtState(SECTION, KEY_GROUP_SIZE, tostring(group_size),  true)

  -- Collect items with position, length, and REAPER group ID
  local item_data = {}
  for i = 0, num_selected - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local pos  = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len  = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local gid  = math.floor(reaper.GetMediaItemInfo_Value(item, "I_GROUPID"))
    table.insert(item_data, { item = item, pos = pos, len = len, gid = gid })
  end
  table.sort(item_data, function(a, b) return a.pos < b.pos end)

  -- Build logical units:
  --   Items sharing a REAPER group ID > 0 → one shared unit (moved together)
  --   Ungrouped items (gid == 0)           → each their own unit
  local units         = {}
  local group_to_unit = {}

  for _, d in ipairs(item_data) do
    if d.gid > 0 and group_to_unit[d.gid] then
      local u = units[group_to_unit[d.gid]]
      table.insert(u.items, d)
      if d.pos           < u.pos  then u.pos  = d.pos           end
      if d.pos + d.len   > u.tail then u.tail = d.pos + d.len   end
    else
      local u = { pos = d.pos, tail = d.pos + d.len, items = { d } }
      table.insert(units, u)
      if d.gid > 0 then group_to_unit[d.gid] = #units end
    end
  end
  table.sort(units, function(a, b) return a.pos < b.pos end)

  -- Pack units into batches of group_size
  local batches = {}
  for i = 1, #units, group_size do
    local batch = { units = {}, pos = units[i].pos, tail = units[i].tail }
    for j = i, math.min(i + group_size - 1, #units) do
      table.insert(batch.units, units[j])
      if units[j].pos  < batch.pos  then batch.pos  = units[j].pos  end
      if units[j].tail > batch.tail then batch.tail = units[j].tail end
    end
    table.insert(batches, batch)
  end

  local num_gaps = #batches - 1
  if num_gaps < 1 then
    reaper.ShowMessageBox("All items fall in a single batch — nothing to reposition.", "Script Aborted", 0)
    return
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  -- Batch 1 is the anchor and never moves.
  -- Each subsequent batch is placed exactly current_gap seconds after the
  -- reference point of the previous batch (absolute, not additive).
  local prev_pos  = batches[1].pos
  local prev_tail = batches[1].tail

  for i = 2, #batches do
    -- progress: 0 at the first gap, 1 at the last gap
    local progress    = (num_gaps == 1) and 0 or ((i - 2) / (num_gaps - 1))
    local current_gap = start_gap + (end_gap - start_gap) * (progress ^ curve_power)

    local ref       = (spacing_mode == "start") and prev_pos or prev_tail
    local new_start = ref + current_gap
    local shift     = new_start - batches[i].pos

    for _, u in ipairs(batches[i].units) do
      for _, d in ipairs(u.items) do
        reaper.SetMediaItemInfo_Value(d.item, "D_POSITION", d.pos + shift)
      end
    end

    -- Advance the reference for the next iteration
    prev_pos  = new_start
    prev_tail = batches[i].tail + shift
  end

  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("Reposition item groups with curved gap", -1)
  reaper.UpdateArrange()

  reaper.ShowMessageBox(
    "Done. Repositioned " .. #batches .. " batch(es) with " .. num_gaps .. " gap(s).",
    "Reposition Item Groups with Curved Gap", 0
  )
end

main()
