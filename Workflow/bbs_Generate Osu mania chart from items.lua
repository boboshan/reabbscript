-- @description Exports selected items as an osu!mania chart to the clipboard.
-- @version 1.1
-- @author bbs
-- @provides [main] _BBS_GENERATEOSUMAP
-- @about
--   # Generate Osu!mania Chart From Items
--   Exports selected REAPER items as osu!mania hit objects to the clipboard.
--   - Track names ("1", "2", "3", "4") determine column position.
--   - Item names must be "type,hitsound" (e.g. "1,0" for a note, "128,0" for a hold).
--   - The earliest selected item is used as the time anchor (timestamp 0).

-- Mania constants
local OSU_MANIA_Y = 192
local OSU_MANIA_COLS = {
  [1] = 64,
  [2] = 192,
  [3] = 320,
  [4] = 448
}

function main()
  local num_selected_items = reaper.CountSelectedMediaItems(0)
  if num_selected_items == 0 then
    reaper.ShowMessageBox("No items selected to export.", "Script Aborted", 0)
    return
  end

  local hit_objects = {}
  local earliest_pos = -1

  -- First pass: find the earliest item to use as a time anchor
  for i = 0, num_selected_items - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    if item then
      local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      if earliest_pos == -1 or item_pos < earliest_pos then
        earliest_pos = item_pos
      end
    end
  end

  -- Second pass: process all items into hit objects
  for i = 0, num_selected_items - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    if item then
      local track = reaper.GetMediaItemTrack(item)
      local _, track_name = reaper.GetTrackName(track)
      local column_num = tonumber(track_name:match("^%s*(%d+)%s*$"))
      local x_pos = OSU_MANIA_COLS[column_num or 0]

      local take = reaper.GetActiveTake(item)
      local take_name = take and reaper.GetTakeName(take) or ""
      local note_type_str, hitsound_str = take_name:match("(%d+),(%d+)")

      -- Validate that the item is a valid hit object
      if x_pos and note_type_str and hitsound_str then
        local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local timestamp = math.floor((item_pos - earliest_pos) * 1000)

        local params = ""
        if note_type_str == "1" or note_type_str == "5" then -- Regular Note
          params = "0:0:0:0:"
        elseif note_type_str == "128" then -- Hold Note
          local end_timestamp = math.floor((item_pos + item_len - earliest_pos) * 1000)
          params = end_timestamp .. ":0:0:0:0:"
        end

        if params ~= "" then
          table.insert(hit_objects, {
            timestamp = timestamp,
            x = x_pos,
            note_type = note_type_str,
            hitsound = hitsound_str,
            params = params
          })
        end
      end
    end
  end

  if #hit_objects == 0 then
    reaper.ShowMessageBox("No valid hit objects found. Check track names (1-4) and item names ('type,hitsound').", "Warning", 0)
    return
  end

  -- Sort hit objects by timestamp before generating the output
  table.sort(hit_objects, function(a, b) return a.timestamp < b.timestamp end)

  local output_lines = {"[HitObjects]"}
  for _, obj in ipairs(hit_objects) do
    table.insert(output_lines,
      string.format("%d,%d,%d,%s,%s,%s",
        obj.x, OSU_MANIA_Y, obj.timestamp, obj.note_type, obj.hitsound, obj.params
      )
    )
  end

  local clipboard_string = table.concat(output_lines, "\n")
  reaper.CF_SetClipboard(clipboard_string)
  reaper.ShowMessageBox("Generated " .. #hit_objects .. " hit objects and copied to clipboard.", "Success", 0)
end

main()

