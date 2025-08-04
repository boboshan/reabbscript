-- @description Renames selected takes using a multiline list from the clipboard.
-- @version 1.1
-- @author bbs
-- @dependencies SWS/S&M Extension
-- @about
--   # Rename Selected Takes from Clipboard
--   Renames the active takes of selected items using a multiline list from the clipboard.
--   The first line of the clipboard text is applied to the first selected item, the second line to the second, and so on.
--   Requires the SWS/S&M Extension for advanced clipboard functions.

function check_dependencies()
  -- Use a known SWS function to check if the extension is loaded.
  if not reaper.SNM_CreateFastString then
    reaper.ShowMessageBox(
      "This script requires the SWS/S&M extension, but it seems to be missing or not loaded correctly.\n\n" ..
      "Please make sure SWS is installed and enabled in REAPER.\n\n" ..
      "You can check this by going to the 'Extensions' menu. If you don't see an 'SWS/S&M' option, the extension is not loaded.",
      "SWS Dependency Error",
      0
    )
    return false
  end
  return true
end

function get_clipboard_content()
  -- Use the SWS fast string method for compatibility.
  local fs = reaper.SNM_CreateFastString('')
  local content = reaper.CF_GetClipboardBig(fs)
  reaper.SNM_DeleteFastString(fs)
  return content
end

function main()
  if not check_dependencies() then return end

  local num_selected_items = reaper.CountSelectedMediaItems(0)
  if num_selected_items == 0 then
    reaper.ShowMessageBox("No items selected.", "Script Aborted", 0)
    return
  end

  local clipboard_content = get_clipboard_content()
  if not clipboard_content or clipboard_content == "" then
    reaper.ShowMessageBox("Clipboard is empty.", "Script Aborted", 0)
    return
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local takes_renamed = 0
  local index = 0
  -- Iterate through each line in the clipboard content
  for line in clipboard_content:gmatch("([^\r\n]*)") do
    local item = reaper.GetSelectedMediaItem(0, index)

    -- Stop if we run out of selected items
    if not item then
      break
    end

    local take = reaper.GetActiveTake(item)
    if take then
      reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", line, true)
      takes_renamed = takes_renamed + 1
    end
    
    index = index + 1
  end

  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("Rename selected takes from clipboard", -1)
  reaper.UpdateArrange()
  
  reaper.ShowMessageBox("Renamed " .. takes_renamed .. " take(s).", "Success", 0)
end

main()