-- Run from the repository root: lua tests/test_split.lua
-- REAPER owns item pointers and source timing, so only its API boundary is faked.
local test_dir = debug.getinfo(1, "S").source:sub(2):match("^(.*[\\/])") or ""
local action_path = test_dir .. "../Items Editing/bbs_Split selected items by reference tracks and delete gaps.lua"
local action, load_error = loadfile(action_path)
assert(action, "Split action must exist and load: " .. tostring(load_error))

local tests = {}

local function test(name, body)
  tests[#tests + 1] = { name = name, body = body }
end

local function equal(actual, expected, label)
  assert(actual == expected, (label or "value") .. ": expected " .. tostring(expected)
    .. ", got " .. tostring(actual))
end

local function near(actual, expected, label)
  assert(math.abs(actual - expected) < 1e-9,
    (label or "time") .. ": expected " .. expected .. ", got " .. actual)
end

local function item(start_time, end_time, selected, options)
  options = options or {}
  return {
    position = start_time,
    length = end_time - start_time,
    selected = selected == true,
    locked = options.locked or 0,
    takes = options.takes or { { source = "audio.wav", offset = 0, rate = 1 } },
  }
end

local function track(selected, depth, items)
  return { selected = selected, depth = depth, items = items or {} }
end

local function run(tracks, options)
  options = options or {}
  local state = {
    tracks = tracks,
    messages = {},
    splits = {},
    deletes = 0,
    undo_begin = 0,
    undo_end = 0,
    undo_depth = 0,
    refresh_depth = 0,
    updates = 0,
    reference_reads = {},
  }
  for _, owner in ipairs(tracks) do
    for _, media_item in ipairs(owner.items) do
      media_item.track = owner
    end
  end

  local function before_mutation()
    equal(state.undo_depth, 1, "edits must be in one undo block")
    equal(state.refresh_depth, 1, "edits must suppress UI refresh")
    state.mutated = true
  end

  local function before_snapshot_read()
    assert(not state.mutated, "References and selected targets must be snapshotted before editing")
  end

  local function selected_items()
    before_snapshot_read()
    local selected = {}
    for _, owner in ipairs(tracks) do
      for _, media_item in ipairs(owner.items) do
        if media_item.selected then selected[#selected + 1] = media_item end
      end
    end
    return selected
  end

  _G.reaper = {
    CountTracks = function() return #tracks end,
    GetTrack = function(_, index) return tracks[index + 1] end,
    IsTrackSelected = function(owner)
      before_snapshot_read()
      return owner.selected
    end,
    GetMediaTrackInfo_Value = function(owner, key)
      equal(key, "I_FOLDERDEPTH", "track property")
      return owner.depth
    end,
    CountTrackMediaItems = function(owner)
      before_snapshot_read()
      return #owner.items
    end,
    GetTrackMediaItem = function(owner, index)
      before_snapshot_read()
      state.reference_reads[owner] = (state.reference_reads[owner] or 0) + 1
      return owner.items[index + 1]
    end,
    CountSelectedMediaItems = function() return #selected_items() end,
    GetSelectedMediaItem = function(_, index) return selected_items()[index + 1] end,
    GetMediaItemTrack = function(media_item) return media_item.track end,
    GetMediaItemInfo_Value = function(media_item, key)
      assert(not media_item.deleted, "Reading a deleted item")
      if key == "D_POSITION" then return media_item.position end
      if key == "D_LENGTH" then return media_item.length end
      if key == "C_LOCK" then return media_item.locked end
      error("Unexpected item property: " .. key)
    end,
    SetMediaItemSelected = function(media_item, selected)
      before_mutation()
      assert(not media_item.deleted, "Selecting a deleted item")
      if options.selection_error then error("Injected selection failure") end
      media_item.selected = selected
    end,
    SplitMediaItem = function(media_item, position)
      before_mutation()
      assert(not media_item.deleted, "Splitting a deleted item")
      state.splits[#state.splits + 1] = { item = media_item, position = position }
      if options.split_error == #state.splits then error("Injected split failure") end
      if options.split_failure == #state.splits then return nil end
      assert(position > media_item.position and position < media_item.position + media_item.length,
        "A split must be strictly inside the item")
      local right = item(position, media_item.position + media_item.length, false, {
        locked = media_item.locked,
        takes = {},
      })
      right.track = media_item.track
      for _, take in ipairs(media_item.takes) do
        right.takes[#right.takes + 1] = {
          source = take.source,
          offset = take.offset + (position - media_item.position) * take.rate,
          rate = take.rate,
        }
      end
      media_item.length = position - media_item.position
      -- Exercise independence from the user's split-selection preference.
      media_item.selected = false
      right.track.items[#right.track.items + 1] = right
      return right
    end,
    DeleteTrackMediaItem = function(owner, media_item)
      before_mutation()
      equal(owner, media_item.track, "delete owner")
      state.deletes = state.deletes + 1
      if options.delete_failure == state.deletes then return false end
      for index, candidate in ipairs(owner.items) do
        if candidate == media_item then
          table.remove(owner.items, index)
          media_item.deleted = true
          return true
        end
      end
      error("Deleting an item that is no longer on the track")
    end,
    Undo_BeginBlock2 = function(project)
      equal(project, 0, "undo project")
      state.undo_begin = state.undo_begin + 1
      state.undo_depth = state.undo_depth + 1
      equal(state.undo_depth, 1, "nested undo block")
    end,
    Undo_EndBlock2 = function(project, description)
      equal(project, 0, "undo project")
      state.undo_end = state.undo_end + 1
      state.undo_depth = state.undo_depth - 1
      state.undo_description = description
    end,
    PreventUIRefresh = function(change)
      state.refresh_depth = state.refresh_depth + change
      assert(state.refresh_depth >= 0, "Unbalanced UI refresh")
    end,
    UpdateArrange = function() state.updates = state.updates + 1 end,
    ShowMessageBox = function(message)
      state.messages[#state.messages + 1] = message
      return 0
    end,
    defer = function() state.deferred = true end,
  }

  action()
  equal(state.refresh_depth, 0, "UI refresh must be restored")
  equal(state.undo_depth, 0, "undo block must be closed")
  equal(state.undo_begin, state.undo_end, "undo begin/end balance")
  return state
end

local function expect_items(owner, expected)
  table.sort(owner.items, function(a, b) return a.position < b.position end)
  equal(#owner.items, #expected, "item count")
  for index, bounds in ipairs(expected) do
    local media_item = owner.items[index]
    near(media_item.position, bounds[1], "item " .. index .. " start")
    near(media_item.position + media_item.length, bounds[2], "item " .. index .. " end")
    equal(media_item.selected, bounds[3] ~= false, "item " .. index .. " selection")
  end
end

local function message_contains(state, pattern)
  local messages = table.concat(state.messages, "\n")
  assert(messages:lower():find(pattern:lower()), "Expected message matching " .. pattern .. ": " .. messages)
end

local function expect_no_undo(state)
  equal(state.undo_begin, 0, "no-op undo blocks")
  assert(state.deferred, "No-op actions must suppress REAPER's implicit undo point")
  equal(#state.splits, 0, "no-op splits")
  equal(state.deletes, 0, "no-op deletions")
end

test("keeps only the reference span and preserves reference audio", function()
  local reference = track(true, 0, { item(2, 6, false) })
  local target = track(false, 0, { item(0, 10, true) })
  local state = run({ reference, target })
  expect_items(target, { { 2, 6 } })
  expect_items(reference, { { 2, 6, false } })
  equal(#state.splits, 2, "split count")
  equal(state.deletes, 2, "deleted gaps")
  equal(state.undo_begin, 1, "undo entries")
  equal(#state.messages, 0, "successful action messages")
end)

test("uses the global union of separate selected reference tracks", function()
  local first = track(true, 0, { item(1, 3, false) })
  local second = track(true, 0, { item(6, 8, false) })
  local target = track(false, 0, { item(0, 10, true) })
  local state = run({ first, second, target })
  expect_items(target, { { 1, 3 }, { 6, 8 } })
  equal(#state.splits, 4, "split count")
end)

test("merges unsorted chained overlaps and nested reference spans", function()
  local reference = track(true, 0, {
    item(4, 8, false), item(1, 5, false), item(2, 3, false), item(7, 10, false),
  })
  local target = track(false, 0, { item(0, 12, true) })
  local state = run({ reference, target })
  expect_items(target, { { 1, 10 } })
  equal(#state.splits, 2, "overlaps must not add internal splits")
end)

test("touching references create one span without an internal split", function()
  local reference = track(true, 0, { item(2, 4, false), item(6, 9, false), item(4, 6, false) })
  local target = track(false, 0, { item(0, 10, true) })
  local state = run({ reference, target })
  expect_items(target, { { 2, 9 } })
  equal(#state.splits, 2, "touching reference splits")
end)

test("exact boundaries and fully covered targets are no-ops", function()
  local reference = track(true, 0, { item(2, 6, false) })
  local target = track(false, 0, { item(2, 6, true), item(3, 4, true) })
  local state = run({ reference, target })
  expect_items(target, { { 2, 6 }, { 3, 4 } })
  expect_no_undo(state)
end)

test("targets only touching reference endpoints are deleted without splitting", function()
  local reference = track(true, 0, { item(2, 6, false) })
  local target = track(false, 0, { item(0, 2, true), item(6, 7, true) })
  local state = run({ reference, target })
  expect_items(target, {})
  equal(#state.splits, 0, "endpoint splits")
  equal(state.deletes, 2, "outside targets")
end)

test("snapshots selected targets before deleting fully outside items", function()
  local reference = track(true, 0, { item(2, 3, false) })
  local target = track(false, 0, {
    item(-5, -1, true), item(0, 5, true), item(8, 9, true), item(20, 30, false),
  })
  run({ reference, target })
  expect_items(target, { { 2, 3 }, { 20, 30, false } })
  equal(reference.selected, true, "reference track selection")
  equal(target.selected, false, "target track selection")
end)

test("no selected reference track aborts without deleting targets", function()
  local target = track(false, 0, { item(0, 10, true) })
  local state = run({ target })
  expect_items(target, { { 0, 10 } })
  expect_no_undo(state)
  message_contains(state, "reference")
end)

test("empty and zero-length references abort without deleting targets", function()
  local target = track(false, 0, { item(0, 10, true) })
  local state = run({ track(true, 0), track(true, 0, { item(4, 4, false) }), target })
  expect_items(target, { { 0, 10 } })
  expect_no_undo(state)
  message_contains(state, "reference")
end)

test("no selected targets creates no undo entry", function()
  local state = run({ track(true, 0, { item(2, 6, false) }) })
  expect_no_undo(state)
  message_contains(state, "select")
end)

test("includes folder-owned items and all descendants through a minus-two closure", function()
  local parent = track(true, 1, { item(0, 1, false) })
  local nested = track(false, 1, { item(2, 3, false) })
  local child = track(false, 0, { item(4, 5, false) })
  local last = track(false, -2, { item(6, 7, false) })
  local outside = track(false, 0, { item(8, 9, false) })
  local target = track(false, 0, { item(0, 10, true) })
  run({ parent, nested, child, last, outside, target })
  expect_items(target, { { 0, 1 }, { 2, 3 }, { 4, 5 }, { 6, 7 } })
  expect_items(outside, { { 8, 9, false } })
end)

test("selected parent and selected descendants contribute reference items once", function()
  local parent = track(true, 1, { item(1, 3, false) })
  local nested = track(true, 1, { item(3, 4, false) })
  local child = track(true, -2, { item(4, 6, false) })
  local target = track(false, 0, { item(0, 8, true) })
  local state = run({ parent, nested, child, target })
  expect_items(target, { { 1, 6 } })
  equal(state.reference_reads[parent], 1, "parent reference reads")
  equal(state.reference_reads[nested], 1, "nested reference reads")
  equal(state.reference_reads[child], 1, "child reference reads")
end)

test("a selected non-folder child does not include its siblings", function()
  local parent = track(false, 1, { item(0, 1, false) })
  local child = track(true, 0, { item(2, 3, false) })
  local sibling = track(false, -1, { item(4, 5, false) })
  local target = track(false, 0, { item(0, 6, true) })
  run({ parent, child, sibling, target })
  expect_items(target, { { 2, 3 } })
end)

test("a selected reference item covers itself and remains untouched", function()
  local reference_item = item(0, 5, true)
  local reference = track(true, 0, { reference_item })
  local target = track(false, 0, { item(4, 7, true) })
  local state = run({ reference, target })
  expect_items(reference, { { 0, 5 } })
  equal(reference.items[1], reference_item, "reference identity")
  expect_items(target, { { 4, 5 } })
  equal(#state.splits, 1, "only the non-reference target is split")
end)

test("a selection containing only references is a no-op", function()
  local reference = track(true, 0, { item(2, 6, true) })
  local state = run({ reference })
  expect_items(reference, { { 2, 6 } })
  expect_no_undo(state)
end)

test("locked targets stay intact and the skipped count is reported", function()
  local reference = track(true, 0, { item(2, 6, false) })
  local target = track(false, 0, {
    item(0, 10, true, { locked = 1 }),
    item(20, 30, true, { locked = 3 }),
    item(1, 7, true),
  })
  local state = run({ reference, target })
  expect_items(target, { { 0, 10 }, { 2, 6 }, { 20, 30 } })
  message_contains(state, "2 locked")
end)

test("an entirely locked selection creates no undo entry", function()
  local target = track(false, 0, { item(0, 10, true, { locked = 1 }) })
  local state = run({ track(true, 0, { item(2, 6, false) }), target })
  expect_items(target, { { 0, 10 } })
  expect_no_undo(state)
  message_contains(state, "1 locked")
end)

test("only the lock bit prevents editing", function()
  local target = track(false, 0, { item(0, 10, true, { locked = 2 }) })
  local state = run({ track(true, 0, { item(2, 6, false) }), target })
  expect_items(target, { { 2, 6 } })
  equal(#state.messages, 0, "non-lock flag warnings")
end)

test("all surviving split pieces are selected and native take timing survives", function()
  local reference = track(true, 0, { item(12, 14, false), item(17, 19, false) })
  local target = track(false, 0, { item(10, 20, true, { takes = {
    { source = "take-a.wav", offset = 3.5, rate = 2 },
    { source = "take-b.wav", offset = 8, rate = 0.5 },
  } }) })
  run({ reference, target })
  expect_items(target, { { 12, 14 }, { 17, 19 } })
  local first, second = target.items[1], target.items[2]
  equal(#first.takes, 2, "first piece take count")
  equal(#second.takes, 2, "second piece take count")
  near(first.takes[1].offset, 7.5, "first fast take offset")
  near(first.takes[2].offset, 9, "first slow take offset")
  near(second.takes[1].offset, 17.5, "second fast take offset")
  near(second.takes[2].offset, 11.5, "second slow take offset")
  for _, piece in ipairs(target.items) do
    equal(piece.takes[1].source, "take-a.wav", "first source")
    equal(piece.takes[2].source, "take-b.wav", "second source")
    near(piece.takes[1].rate, 2, "first take rate")
    near(piece.takes[2].rate, 0.5, "second take rate")
  end
end)

test("a failed first split preserves audio and reports how to recover", function()
  local target = track(false, 0, { item(0, 10, true) })
  local state = run({ track(true, 0, { item(2, 6, false) }), target }, { split_failure = 1 })
  expect_items(target, { { 0, 10 } })
  equal(state.deletes, 0, "deletions after failed split")
  message_contains(state, "split")
  message_contains(state, "undo")
end)

test("all splits must succeed before even fully outside targets are deleted", function()
  local target = track(false, 0, { item(-4, -2, true), item(0, 10, true) })
  local state = run({ track(true, 0, { item(2, 6, false) }), target }, { split_failure = 2 })
  expect_items(target, { { -4, -2 }, { 0, 2 }, { 2, 10 } })
  equal(state.deletes, 0, "no audio deleted on any split failure")
  equal(state.undo_begin, 1, "partial edit undo entry")
  message_contains(state, "undo")
end)

test("thrown split errors restore UI refresh and close the undo block", function()
  local target = track(false, 0, { item(0, 10, true) })
  local state = run({ track(true, 0, { item(2, 6, false) }), target }, { split_error = 2 })
  expect_items(target, { { 0, 2 }, { 2, 10 } })
  equal(state.deletes, 0, "deletions after thrown split error")
  message_contains(state, "Injected split failure")
  message_contains(state, "undo")
end)

test("a failed deletion stops further deletion and reports partial changes", function()
  local target = track(false, 0, { item(0, 10, true) })
  local state = run({ track(true, 0, { item(2, 4, false), item(6, 8, false) }), target },
    { delete_failure = 2 })
  equal(state.deletes, 2, "stop at failed deletion")
  expect_items(target, { { 2, 4 }, { 4, 6 }, { 6, 8 }, { 8, 10 } })
  message_contains(state, "delet")
  message_contains(state, "undo")
end)

test("an unexpected error during selection still balances cleanup", function()
  local target = track(false, 0, { item(0, 10, true) })
  local state = run({ track(true, 0, { item(2, 6, false) }), target }, { selection_error = true })
  equal(state.deletes, 0, "deletions after selection failure")
  message_contains(state, "Injected selection failure")
  message_contains(state, "undo")
end)

test("decimal rounding does not split touching reference spans", function()
  local left = item(0.1, 0.8, false)
  left.length = 0.7
  local reference = track(true, 0, { left, item(0.8, 1.0, false) })
  local target = track(false, 0, { item(0, 1.2, true) })
  local state = run({ reference, target })
  expect_items(target, { { 0.1, 1.0 } })
  equal(#state.splits, 2, "only the two outer boundaries are cut")
end)

test("decimal rounding at an existing target edge is a no-op", function()
  local reference_item = item(0.1, 0.8, false)
  reference_item.length = 0.7
  local target = track(false, 0, { item(0.1, 0.8, true) })
  local state = run({ track(true, 0, { reference_item }), target })
  expect_items(target, { { 0.1, 0.8 } })
  expect_no_undo(state)
end)

test("a real sub-microsecond reference gap remains a gap", function()
  local reference = track(true, 0, { item(0, 1, false), item(1.0000001, 2, false) })
  local target = track(false, 0, { item(-1, 3, true) })
  local state = run({ reference, target })
  expect_items(target, { { 0, 1 }, { 1.0000001, 2 } })
  equal(#state.splits, 4, "both gap boundaries are retained")
end)

local failures = 0
for _, case in ipairs(tests) do
  local ok, failure = pcall(case.body)
  if ok then
    print("PASS " .. case.name)
  else
    failures = failures + 1
    io.stderr:write("FAIL " .. case.name .. "\n" .. tostring(failure) .. "\n")
  end
end
_G.reaper = nil
assert(failures == 0, failures .. " split test(s) failed")
print(#tests .. " split tests passed")
