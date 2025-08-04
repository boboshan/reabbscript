-- @description Moves each selected item to a new track named after the item's take.
-- @version 1.1
-- @author bbs
-- @about
--   # Move Selected Items to New Tracks by Name
--   For each selected item, this script:
--   1. Reads the item's active take name.
--   2. Creates a new track below the item's current track.
--   3. Names the new track using the take name.
--   4. Moves the item to the new track.

function main()
  local num_selected_items = reaper.CountSelectedMediaItems(0)
  if num_selected_items == 0 then
    reaper.ShowMessageBox("No items selected.", "Script Aborted", 0)
    return
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  -- Collect all selected items first to have a static list
  local items_to_process = {}
  for i = 0, num_selected_items - 1 do
    table.insert(items_to_process, reaper.GetSelectedMediaItem(0, i))
  end

  local items_moved = 0
  -- Process the list of items in reverse order.
  -- This prevents track index changes from affecting subsequent operations.
  for i = #items_to_process, 1, -1 do
    local item = items_to_process[i]
    if item then
      local take = reaper.GetActiveTake(item)
      local original_track = reaper.GetMediaItemTrack(item)

      if take and original_track then
        local take_name = reaper.GetTakeName(take)
        local original_track_index = reaper.CSurf_TrackToID(original_track, false)

        -- Insert a new track right below the item's original track
        reaper.InsertTrackAtIndex(original_track_index, false)
        local new_track = reaper.GetTrack(0, original_track_index)

        reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", take_name, true)
        if reaper.MoveMediaItemToTrack(item, new_track) then
          items_moved = items_moved + 1
        end
      end
    end
  end

  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("Move selected items to new tracks by name", -1)
  reaper.UpdateArrange()
  
  reaper.ShowMessageBox("Moved " .. items_moved .. " item(s) to new tracks.", "Success", 0)
end

main()