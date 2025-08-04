-- @description Renames selected tracks using a multiline list from the clipboard.
-- @version 1.1
-- @author bbs
-- @provides _BBS_RENAMETRACKSFROMCLIP
-- @about
--   # Rename Selected Tracks from Clipboard
--   Renames selected tracks using a multiline list from the clipboard.
--   The first line of the clipboard text is applied to the first selected track, the second line to the second, and so on.

function split_string(input_str, separator)
  local result = {}
  for match in (input_str .. separator):gmatch("(.-)" .. separator) do
    table.insert(result, match:gsub("\r", ""))
  end
  return result
end

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

  local names_to_apply = split_string(clipboard_content, "\n")

  reaper.Undo_BeginBlock()

  for i = 0, num_selected_tracks - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    local new_name = names_to_apply[i + 1]

    if track and new_name then
      reaper.GetSetMediaTrackInfo_String(track, 'P_NAME', new_name, true)
    end
  end

  reaper.Undo_EndBlock("Rename selected tracks from clipboard", -1)
  reaper.UpdateArrange()
end

main()