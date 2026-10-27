-- @description Generate osu!mania hit objects from selected items
-- @version 1.2
-- @author bbs
-- @about
--   Copies a four-key [HitObjects] section to the clipboard. Requires SWS/S&M.
--   Track names 1-4 select columns. Active take names must be type,hitsound.
--   Supported types: 1 or 5 (tap), 128 (hold). Hitsounds: 0-15.
--   The earliest selected item anchors time zero, including invalid items.
--   This exports hit objects, not a complete .osu beatmap.
-- @changelog
--   Validate complete names/hitsounds and dependencies; sort simultaneous notes by column.

local COLUMNS = { 64, 192, 320, 448 }

local function main()
  if not reaper.CF_SetClipboard then
    reaper.ShowMessageBox("Install the SWS/S&M extension to use clipboard actions.", "Reabbscript", 0)
    return
  end
  local count = reaper.CountSelectedMediaItems(0)
  if count == 0 then
    reaper.ShowMessageBox("Select at least one item to export.", "Reabbscript", 0)
    return
  end
  local first, notes = math.huge, {}
  for i = 0, count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    first = math.min(first, pos)
    local _, track_name = reaper.GetTrackName(reaper.GetMediaItemTrack(item))
    local column = tonumber(track_name:match("^%s*([1-4])%s*$"))
    local take = reaper.GetActiveTake(item)
    local kind, sound = (take and reaper.GetTakeName(take) or ""):match("^%s*(%d+)%s*,%s*(%d+)%s*$")
    kind, sound = tonumber(kind), tonumber(sound)
    if column and (kind == 1 or kind == 5 or kind == 128) and sound and sound <= 15 then
      notes[#notes + 1] = {
        pos = pos, tail = pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH"),
        x = COLUMNS[column], kind = kind, sound = sound, order = i,
      }
    end
  end
  if #notes == 0 then
    reaper.ShowMessageBox("No valid notes. Use tracks 1-4 and take names type,hitsound (types 1, 5, 128; hitsounds 0-15).",
      "Reabbscript", 0)
    return
  end
  for _, note in ipairs(notes) do
    note.time = math.floor((note.pos - first) * 1000)
    note.end_time = math.floor((note.tail - first) * 1000)
  end
  table.sort(notes, function(a, b)
    if a.time ~= b.time then return a.time < b.time end
    if a.x ~= b.x then return a.x < b.x end
    return a.order < b.order
  end)
  local lines = { "[HitObjects]" }
  for _, note in ipairs(notes) do
    local params = note.kind == 128 and (note.end_time .. ":0:0:0:0:") or "0:0:0:0:"
    lines[#lines + 1] = string.format("%d,192,%d,%d,%d,%s", note.x, note.time, note.kind, note.sound, params)
  end
  reaper.CF_SetClipboard(table.concat(lines, "\n"))
end

-- Explicit undo blocks above own edits; no automatic undo point for a no-op.
reaper.defer(function() end)
main()
