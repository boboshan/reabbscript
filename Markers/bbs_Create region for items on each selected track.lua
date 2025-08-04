-- @description For each selected track, creates a region spanning all its items.
-- @version 1.1
-- @author bbs
-- @about
--   # Create Region For Items on Each Selected Track
--   For each selected track, this script finds the start of the first item
--   and the end of the last item, and creates a single project region
--   that spans them. The region is named after the track.

function main()
  local num_selected_tracks = reaper.CountSelectedTracks(0)
  if num_selected_tracks == 0 then
    reaper.ShowMessageBox("No tracks selected.", "Script Aborted", 0)
    return
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  for i = 0, num_selected_tracks - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    if track then
      local num_items = reaper.CountTrackMediaItems(track)
      if num_items > 0 then
        local min_start_pos = -1
        local max_end_pos = 0

        for j = 0, num_items - 1 do
          local item = reaper.GetTrackMediaItem(track, j)
          local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
          local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

          if min_start_pos == -1 or item_start < min_start_pos then
            min_start_pos = item_start
          end
          if item_end > max_end_pos then
            max_end_pos = item_end
          end
        end

        if min_start_pos ~= -1 then
          local _, track_name = reaper.GetTrackName(track)
          local track_color = reaper.GetTrackColor(track)
          reaper.AddProjectMarker2(0, true, min_start_pos, max_end_pos, track_name, -1, track_color)
        end
      end
    end
  end

  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("Create region for items on each selected track", -1)
  reaper.UpdateArrange()
end

main()