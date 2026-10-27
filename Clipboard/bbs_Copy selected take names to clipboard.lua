-- @description Copy selected take names to clipboard
-- @version 1.2
-- @author bbs
-- @about
--   Copies selected take names, one per line, in REAPER selection order.
--   Requires SWS/S&M. Items without an active take are skipped.
-- @changelog
--   Check the clipboard dependency before running; keep the action silent on success.

local function main()
  if not reaper.CF_SetClipboard then
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
  local names = {}
  for _, target in ipairs(targets) do
    local name = reaper.GetTakeName(target)
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
