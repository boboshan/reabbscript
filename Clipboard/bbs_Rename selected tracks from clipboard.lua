-- @description Renames selected tracks using a multiline list from the clipboard.
-- @version 1.2
-- @author bbs
-- @about
--   # Rename Selected Tracks from Clipboard
--   Renames selected tracks using a multiline list from the clipboard.
--   The first line of the clipboard text is applied to the first selected track, the second line to the second, and so on.

function main()
  local num_selected_tracks = reaper.CountSelectedTracks(0)
  if num_selected_tracks == 0 then
    reaper.ShowMessageBox("No tracks selected.", "Script Aborted", 0)
    return
  end

  local clipboard_content = reaper.CF_GetClipboard('')
  if not clipboard_content or clipboard_content == "" then
    reaper.ShowMessageBox("Clipboard is empty.", "Script Aborted", 0)
    return
  end

  reaper.Undo_BeginBlock()

  local tracks_renamed = 0
  local index = 0
  -- Iterate through each line in the clipboard content
  for line in clipboard_content:gmatch("([^\r\n]*)") do
    local track = reaper.GetSelectedTrack(0, index)
    
    -- Stop if we run out of selected tracks
    if not track then
      break
    end

    -- Apply the name to the track
    reaper.GetSetMediaTrackInfo_String(track, 'P_NAME', line, true)
    tracks_renamed = tracks_renamed + 1
    index = index + 1
  end

  reaper.Undo_EndBlock("Rename selected tracks from clipboard", -1)
  reaper.UpdateArrange()
  
  reaper.ShowMessageBox("Renamed " .. tracks_renamed .. " track(s).", "Success", 0)
end

main()