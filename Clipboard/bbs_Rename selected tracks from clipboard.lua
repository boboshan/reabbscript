-- @description Rename selected tracks from clipboard
-- @version 1.4
-- @author bbs
-- @about
--   Applies one clipboard line to each selected track, in REAPER selection order.
--   Requires SWS/S&M. Empty lines clear names; a final newline is ignored.
--   Extra lines are ignored; unmatched tracks keep their names.
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
  for i = 0, reaper.CountSelectedTracks(0) - 1 do
    targets[#targets + 1] = reaper.GetSelectedTrack(0, i)
  end
  if #targets == 0 then
    reaper.ShowMessageBox("Select at least one track.", "Reabbscript", 0)
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
    local _, name = reaper.GetSetMediaTrackInfo_String(target, "P_NAME", "", false)
    if name ~= lines[i] then edits[#edits + 1] = { target = target, name = lines[i] } end
  end
  if #edits == 0 then return end
  run_edit("Rename selected tracks from clipboard", function()
    for _, edit in ipairs(edits) do
      assert(reaper.GetSetMediaTrackInfo_String(edit.target, "P_NAME", edit.name, true), "Could not rename track.")
    end
  end)
end

-- Explicit undo blocks above own edits; no automatic undo point for a no-op.
reaper.defer(function() end)
main()
