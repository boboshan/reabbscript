-- @description Renames selected takes using a multiline list from the clipboard.
-- @version 1.1
-- @author bbs
-- @provides _BBS_RENAMETAKESFROMCLIP
-- @dependencies SWS/S&M Extension
-- @about
--   # Rename Selected Takes from Clipboard
--   Renames the active takes of selected items using a multiline list from the clipboard.
--   The first line of the clipboard text is applied to the first selected item, the second line to the second, and so on.
--   Requires the SWS/S&M Extension for advanced clipboard functions.

function check_dependencies()
  if not reaper.CF_GetClipboardBig_Big then
    reaper.ShowMessageBox("This script requires the SWS/S&M extension for advanced clipboard functions.", "Dependency Error", 0)
    return false
  end
  return true
end

function split_string(input_str, separator)
  local result = {}
  for match in (input_str .. separator):gmatch("(.-)" .. separator) do
    -- Remove carriage returns that can linger from Windows clipboards
    table.insert(result, match:gsub("\r", ""))
  end
  return result
end

function main()
  if not check_dependencies() then return end

  local num_selected_items = reaper.CountSelectedMediaItems(0)
  if num_selected_items == 0 then
    reaper.ShowMessageBox("No items selected.", "Script Aborted", 0)
    return
  end

  local clipboard_content = reaper.CF_GetClipboardBig_Big('')
  if not clipboard_content or clipboard_content == "" then
    reaper.ShowMessageBox("Clipboard is empty.", "Script Aborted", 0)
    return
  end

  local names_to_apply = split_string(clipboard_content, "\n")

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  for i = 0, num_selected_items - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local new_name = names_to_apply[i + 1]

    if item and new_name then
      local take = reaper.GetActiveTake(item)
      if take then
        reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", new_name, true)
      end
    end
  end

  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("Rename selected takes from clipboard", -1)
  reaper.UpdateArrange()
end

main()