-- @description Rename selected takes from clipboard
-- @version 1.3
-- @author bbs
-- @about
--   Applies one clipboard line to each selected take, in REAPER selection order.
--   Requires SWS/S&M. Empty lines clear names; a final newline is ignored.
--   Items without an active take are skipped, matching the copy action.
-- @changelog
--   Handle CRLF and blank names, validate SWS, and always release undo/UI refresh.

local function run_edit(description, edit)
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  local ok, err = xpcall(edit, debug.traceback)
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock(description, -1)
  reaper.UpdateArrange()
  if not ok then
    reaper.ShowMessageBox(
      "The action stopped. Undo once to revert any completed changes.\n\n" .. tostring(err),
      "Reabbscript", 0
    )
  end
end

local function clipboard_lines(text)
  text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  -- One final newline terminates the last record; interior empty records count.
  if text:sub(-1) == "\n" then text = text:sub(1, -2) end
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  return lines
end

local function main()
  if not reaper.CF_GetClipboard then
    reaper.ShowMessageBox("Install the SWS/S&M extension to use clipboard actions.", "Reabbscript", 0)
    return
  end
  local targets = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local take = reaper.GetActiveTake(reaper.GetSelectedMediaItem(0, i))
    if take then targets[#targets + 1] = take end
  end
  if #targets == 0 then
    reaper.ShowMessageBox("Select at least one item with an active take.", "Reabbscript", 0)
    return
  end
  local text = reaper.CF_GetClipboard()
  if not text or text == "" then
    reaper.ShowMessageBox("The clipboard is empty.", "Reabbscript", 0)
    return
  end
  local lines, edits = clipboard_lines(text), {}
  for i = 1, math.min(#targets, #lines) do
    local target = targets[i]
    local name = reaper.GetTakeName(target)
    if name ~= lines[i] then edits[#edits + 1] = { target = target, name = lines[i] } end
  end
  if #edits == 0 then return end
  run_edit("Rename selected takes from clipboard", function()
    for _, edit in ipairs(edits) do
      assert(reaper.GetSetMediaItemTakeInfo_String(edit.target, "P_NAME", edit.name, true), "Could not rename take.")
    end
  end)
end

-- Explicit undo blocks above own edits; no automatic undo point for a no-op.
reaper.defer(function() end)
main()
