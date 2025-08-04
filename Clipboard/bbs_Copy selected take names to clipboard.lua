-- @description Copies the active take names of selected items to the clipboard.
-- @version 1.1
-- @author bbs
-- @provides _BBS_COPYTAKETOCLIP
-- @about
--   # Copy Selected Take Names to Clipboard
--   Copies the active take names of all selected items to the clipboard.
--   Each name is placed on a new line.

function main()
  local num_selected_items = reaper.CountSelectedMediaItems(0)
  if num_selected_items == 0 then
    reaper.ShowMessageBox("No items selected.", "Script Aborted", 0)
    return
  end

  local names_list = {}
  for i = 0, num_selected_items - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    if item then
      local take = reaper.GetActiveTake(item)
      if take then
        local take_name = reaper.GetTakeName(take)
        table.insert(names_list, take_name)
      end
    end
  end

  if #names_list > 0 then
    local clipboard_string = table.concat(names_list, "\n")
    reaper.CF_SetClipboard(clipboard_string)
    reaper.ShowMessageBox(
      "Copied " .. #names_list .. " take names to the clipboard.",
      "Success",
      0
    )
  else
    reaper.ShowMessageBox("No active takes found in selected items.", "Script Aborted", 0)
  end
end

main()