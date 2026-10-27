-- @description Copy selected track names to clipboard
-- @version 1.2
-- @author bbs
-- @about
--   Copies selected track names, one per line, in REAPER selection order.
--   Requires SWS/S&M.
-- @changelog
--   Check the clipboard dependency before running; keep the action silent on success.

local function main()
  if not reaper.CF_SetClipboard then
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
  local names = {}
  for _, target in ipairs(targets) do
    local _, name = reaper.GetSetMediaTrackInfo_String(target, "P_NAME", "", false)
    names[#names + 1] = name or ""
  end
  -- Encode an empty final record separately from a line terminator.
  local text = table.concat(names, "\n")
  if names[#names] == "" then text = text .. "\n" end
  reaper.CF_SetClipboard(text)
end

-- Explicit undo blocks above own edits; no automatic undo point for a no-op.
reaper.defer(function() end)
main()
