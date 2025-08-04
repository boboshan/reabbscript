-- @description Copies the names of selected tracks to the clipboard.
-- @version 1.1
-- @author bbs
-- @provides [main] _BBS_COPYTRACKNAMETOCLIP
-- @about
--   # Copy Selected Track Names to Clipboard
--   Copies the names of all selected tracks to the clipboard.
--   Each name is placed on a new line.

function main()
  local num_selected_tracks = reaper.CountSelectedTracks(0)
  if num_selected_tracks == 0 then
    reaper.ShowMessageBox("No tracks selected.", "Script Aborted", 0)
    return
  end

  local names_list = {}
  for i = 0, num_selected_tracks - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    if track then
      local _, track_name = reaper.GetTrackName(track)
      table.insert(names_list, track_name)
    end
  end

  if #names_list > 0 then
    local clipboard_string = table.concat(names_list, "\n")
    reaper.CF_SetClipboard(clipboard_string)
    reaper.ShowMessageBox(
      "Copied " .. #names_list .. " track names to the clipboard.",
      "Success",
      0
    )
  else
    reaper.ShowMessageBox("Could not retrieve track names.", "Error", 0)
  end
end

main()