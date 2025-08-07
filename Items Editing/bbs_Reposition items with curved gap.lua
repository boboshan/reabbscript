-- @description Repositions selected items with a curved (non-linear) gap.
-- @version 1.2
-- @author bbs
-- @about
--   # Reposition Items with Curved Gap
--   Creates an accelerando or ritardando effect by repositioning selected items.
--   It lets you define a starting gap, an ending gap, a curve factor, and a spacing mode.
--   The script remembers your last-used settings.
--
--   - Spacing Mode: 'end' (default) measures gap from the end of the previous item. 'start' measures from the start.
--   - Curve Factor > 1: Ease-out (fast change at start)
--   - Curve Factor = 1: Linear
--   - Curve Factor < 1 (but > 0): Ease-in (slow change at start)

-- Define keys for storing settings

local SECTION = "bbs_RepositionCurvedGap"
local KEY_START_GAP = "start_gap"
local KEY_END_GAP = "end_gap"
local KEY_CURVE = "curve_power"
local KEY_MODE = "spacing_mode"

function main()
  -- Check for enough selected items
  local num_selected_items = reaper.CountSelectedMediaItems(0)
  if num_selected_items < 2 then
    reaper.ShowMessageBox("Please select at least two items.", "Script Aborted", 0)
    return
  end

  -- Load last used settings or set defaults
  local last_start_gap = reaper.GetExtState(SECTION, KEY_START_GAP)
  if last_start_gap == "" then last_start_gap = "0.5" end
  
  local last_end_gap = reaper.GetExtState(SECTION, KEY_END_GAP)
  if last_end_gap == "" then last_end_gap = "0.1" end
  
  local last_curve = reaper.GetExtState(SECTION, KEY_CURVE)
  if last_curve == "" then last_curve = "2.0" end
  
  local last_mode = reaper.GetExtState(SECTION, KEY_MODE)
  if last_mode == "" then last_mode = "end" end

  -- Get user settings for the gaps and curve
  local input_captions = "Start Gap (sec),End Gap (sec),Curve Power (>0),Spacing Mode (end/start)"
  local input_defaults = last_start_gap .. "," .. last_end_gap .. "," .. last_curve .. "," .. last_mode
  
  local ret, user_input = reaper.GetUserInputs("Reposition with Curved Gap", 4, input_captions, input_defaults)
  if not ret then return end

  local start_gap_str, end_gap_str, curve_power_str, spacing_mode_str = user_input:match("([^,]+),([^,]+),([^,]+),([^,]+)")
  
  local start_gap = tonumber(start_gap_str) or 0.2
  local end_gap = tonumber(end_gap_str) or 0.8
  local curve_power = tonumber(curve_power_str) or 1.0
  local spacing_mode = spacing_mode_str:lower() or "start"
  if curve_power <= 0 then curve_power = 1 end

  -- Save the new settings for next time
  reaper.SetExtState(SECTION, KEY_START_GAP, start_gap, true)
  reaper.SetExtState(SECTION, KEY_END_GAP, end_gap, true)
  reaper.SetExtState(SECTION, KEY_CURVE, curve_power, true)
  reaper.SetExtState(SECTION, KEY_MODE, spacing_mode, true)
  
  -- Collect and sort items by position
  local items = {}
  for i = 0, num_selected_items - 1 do
    table.insert(items, reaper.GetSelectedMediaItem(0, i))
  end
  table.sort(items, function(a, b)
    return reaper.GetMediaItemInfo_Value(a, "D_POSITION") < reaper.GetMediaItemInfo_Value(b, "D_POSITION")
  end)

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  -- The first item is our anchor. Get its properties.
  local prev_item_pos = reaper.GetMediaItemInfo_Value(items[1], "D_POSITION")
  local prev_item_len = reaper.GetMediaItemInfo_Value(items[1], "D_LENGTH")
  local num_gaps = #items - 1

  -- Loop through the rest of the items to reposition them
  for i = 2, #items do
    local item = items[i]
    
    local progress = (i - 2) / (num_gaps - 1)
    if num_gaps == 1 then progress = 1 end
    
    local curved_progress = progress ^ curve_power
    local current_gap = start_gap + (end_gap - start_gap) * curved_progress
    
    local anchor_pos
    if spacing_mode == "start" then
      anchor_pos = prev_item_pos
    else
      anchor_pos = prev_item_pos + prev_item_len
    end

    local new_pos = anchor_pos + current_gap
    reaper.SetMediaItemInfo_Value(item, "D_POSITION", new_pos, true)
    
    prev_item_pos = new_pos
    prev_item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  end

  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("Reposition items with curved gap", -1)
  reaper.UpdateArrange()
  
  reaper.ShowMessageBox("Repositioned " .. num_selected_items .. " items with a curved gap.", "Success", 0)
end

main()
