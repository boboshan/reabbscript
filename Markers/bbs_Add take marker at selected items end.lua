-- @description Adds a take marker at the end position of each selected item.
-- @version 1.1
-- @author bbs
-- @provides _BBS_ADDTAKEMARKER_END
-- @about
--   # Add Take Marker at Item End
--   Adds a take marker at the end position of each selected item.
--   You will be prompted for a marker name and a time offset.
--   You can choose to create Project or Take markers.

function main()
  local num_selected_items = reaper.CountSelectedMediaItems(0)
  if num_selected_items == 0 then
    reaper.ShowMessageBox("No items selected.", "Script Aborted", 0)
    return
  end

  -- Prompt for user input
  local ret_input, user_input = reaper.GetUserInputs(
    "Add Take Marker at Item End", 3,
    "Marker Name,Position Offset (sec),Marker Type (p=Project, t=Take)" .. ",extrawidth=100", -- extrawidth requires SWS
    "End,0.0,t"
  )

  if not ret_input then return end

  local marker_name, pos_offset_str, marker_type = user_input:match("([^,]+),([^,]+),([^,]+)")
  local pos_offset = tonumber(pos_offset_str) or 0

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  for i = 0, num_selected_items - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    if item then
      local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      local item_end = item_pos + item_len

      if marker_type:lower() == 't' then
        -- Add as a take marker. Position is relative to the start of the take.
        local take = reaper.GetActiveTake(item)
        if take then
          -- The position for a take marker is an offset from the item start.
          reaper.SetTakeMarker(take, -1, marker_name, item_len + pos_offset)
        end
      else
        -- Add as a project marker at the item's absolute end position.
        reaper.AddProjectMarker(0, false, item_end + pos_offset, 0, marker_name, -1)
      end
    end
  end

  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("Add take marker at selected item end", -1)
  reaper.UpdateArrange()
end

main()