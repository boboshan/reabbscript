-- @description Move selected items to new tracks by take name
-- @version 1.3
-- @author bbs
-- @about
--   Creates one track below the source track for each selected item with an active take.
--   Uses take names and selection order. Skips locked items and items without a take.
--   New tracks remain inside the source track folder; folder-parent items move to new children.
-- @changelog
--   Preserve folder closures, skip locked items, and protect undo/UI refresh cleanup.

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

local function main()
  local edits = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local take = reaper.GetActiveTake(item)
    if take and (math.floor(reaper.GetMediaItemInfo_Value(item, "C_LOCK")) & 1) == 0 then
      edits[#edits + 1] = { item = item, track = reaper.GetMediaItemTrack(item), name = reaper.GetTakeName(take) }
    end
  end
  if #edits == 0 then
    reaper.ShowMessageBox("Select at least one unlocked item with an active take.", "Reabbscript", 0)
    return
  end
  run_edit("Move selected items to new tracks by name", function()
    -- Reverse insertion keeps the original selection order below each source.
    for i = #edits, 1, -1 do
      local edit = edits[i]
      local index = math.floor(reaper.GetMediaTrackInfo_Value(edit.track, "IP_TRACKNUMBER"))
      local closure = reaper.GetMediaTrackInfo_Value(edit.track, "I_FOLDERDEPTH")
      reaper.InsertTrackAtIndex(index, false)
      local track = assert(reaper.GetTrack(0, index), "Could not create a track.")
      assert(reaper.GetSetMediaTrackInfo_String(track, "P_NAME", edit.name, true), "Could not name the new track.")
      if closure < 0 then
        assert(reaper.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", closure), "Could not preserve folder closure.")
        assert(reaper.SetMediaTrackInfo_Value(edit.track, "I_FOLDERDEPTH", 0), "Could not extend source folder.")
      end
      assert(reaper.MoveMediaItemToTrack(edit.item, track), "Could not move an item.")
    end
    reaper.TrackList_AdjustWindows(false)
  end)
end

-- Explicit undo blocks above own edits; no automatic undo point for a no-op.
reaper.defer(function() end)
main()
