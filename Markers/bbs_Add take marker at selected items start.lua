-- @description Add take or project markers at selected item starts
-- @version 1.2
-- @author bbs
-- @about
--   Adds markers at each selected item start, plus an offset in project seconds.
--   Choose t for active-take markers or p for project markers. Empty names are allowed.
--   Take positions include the source offset and playback rate.
--   Takes with stretch markers are skipped; use project markers for warped audio.
-- @changelog
--   Correct trimmed/rate-adjusted take positions, validate inputs, and protect undo cleanup.

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

local function finite(value)
  return value and value == value and value > -math.huge and value < math.huge
end

local function main()
  if reaper.CountSelectedMediaItems(0) == 0 then
    reaper.ShowMessageBox("Select at least one item.", "Reabbscript", 0)
    return
  end
  local accepted, input = reaper.GetUserInputs(
    "Add markers at item starts", 3,
    "Marker name,Offset (project seconds),Type (t=take / p=project),extrawidth=100",
    "Start,0,t"
  )
  if not accepted then return end
  local name, offset_text, marker_type = input:match("^(.*),([^,]*),([^,]*)$")
  local offset = tonumber(offset_text)
  marker_type = marker_type and marker_type:match("^%s*(.-)%s*$"):lower()
  if not finite(offset) or (marker_type ~= "t" and marker_type ~= "p") then
    reaper.ShowMessageBox("Enter a finite numeric offset and marker type t or p.", "Reabbscript", 0)
    return
  end
  local markers, warped = {}, 0
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local relative = offset
    if marker_type == "p" then
      markers[#markers + 1] = { pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION") + relative }
    else
      local take = reaper.GetActiveTake(item)
      if take then
        if reaper.GetTakeNumStretchMarkers(take) > 0 then
          warped = warped + 1
        else
          local pos = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
            + relative * reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
          markers[#markers + 1] = { take = take, pos = pos }
        end
      end
    end
  end
  if #markers > 0 then
    run_edit("Add markers at selected item starts", function()
      for _, marker in ipairs(markers) do
        local index
        if marker.take then
          index = reaper.SetTakeMarker(marker.take, -1, name, marker.pos)
        else
          index = reaper.AddProjectMarker(0, false, marker.pos, 0, name, -1)
        end
        assert(index >= 0, "REAPER could not create a marker.")
      end
    end)
  end
  if warped > 0 then
    reaper.ShowMessageBox(
      "Skipped " .. warped .. " take(s) with stretch markers. Use project markers for these items.",
      "Reabbscript", 0
    )
  end
end

-- Explicit undo blocks above own edits; no automatic undo point for a no-op.
reaper.defer(function() end)
main()
