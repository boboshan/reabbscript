local Mock = dofile("tests/reaper_mock.lua")
local passed, failed = 0, 0
local function equal(actual, expected)
  assert(actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end
local function test(name, body)
  local ok, err = pcall(body)
  if ok then passed = passed + 1 else failed = failed + 1 end
  print((ok and "PASS " or "FAIL ") .. name .. (ok and "" or ": " .. tostring(err)))
end

test("CRLF and interior blank lines do not shift track names", function()
  local s = Mock.new()
  for i = 1, 4 do s:add_track("old" .. i, true) end
  s.clipboard = "Kick\r\n\r\nSnare\r\n"
  s:run("Clipboard/bbs_Rename selected tracks from clipboard.lua")
  equal(s.tracks[1].name, "Kick")
  equal(s.tracks[2].name, "")
  equal(s.tracks[3].name, "Snare")
  equal(s.tracks[4].name, "old4")
end)

test("take copy and paste skip items without an active take consistently", function()
  local s = Mock.new()
  local tr = s:add_track("Track", true)
  local a = s:add_item(tr, 0, 1, { name = "A" })
  s:add_item(tr, 1, 1, false)
  local b = s:add_item(tr, 2, 1, { name = "B" })
  s:run("Clipboard/bbs_Copy selected take names to clipboard.lua")
  equal(s.clipboard, "A\nB")
  a.take.name, b.take.name = "oldA", "oldB"
  s:run("Clipboard/bbs_Rename selected takes from clipboard.lua")
  equal(a.take.name, "A")
  equal(b.take.name, "B")
end)

test("copy and paste preserve empty final track names and raw unnamed tracks", function()
  local s = Mock.new()
  local a = s:add_track("A", true)
  local b = s:add_track("", true)
  s.api.GetTrackName = function(track) return true, track.name == "" and "Track 2" or track.name end
  s:run("Clipboard/bbs_Copy selected track names to clipboard.lua")
  a.name, b.name = "changed A", "changed B"
  s:run("Clipboard/bbs_Rename selected tracks from clipboard.lua")
  equal(a.name, "A")
  equal(b.name, "")
end)

test("single blank clipboard line clears just one selected name", function()
  local s = Mock.new()
  s:add_track("A", true)
  s:add_track("B", true)
  s.clipboard = "\r\n"
  s:run("Clipboard/bbs_Rename selected tracks from clipboard.lua")
  equal(s.tracks[1].name, "")
  equal(s.tracks[2].name, "B")
end)

test("clipboard dependency failure is explained without a Lua crash", function()
  for _, path in ipairs({
    "Clipboard/bbs_Copy selected take names to clipboard.lua",
    "Clipboard/bbs_Copy selected track names to clipboard.lua",
    "Clipboard/bbs_Rename selected takes from clipboard.lua",
    "Clipboard/bbs_Rename selected tracks from clipboard.lua",
    "Workflow/bbs_Generate Osu mania chart from items.lua",
  }) do
    local s = Mock.new()
    local tr = s:add_track("1", true)
    s:add_item(tr, 0, 1, { name = "1,0" })
    s.api.CF_SetClipboard, s.api.CF_GetClipboard = nil, nil
    s.api.SNM_CreateFastString, s.api.CF_GetClipboardBig = nil, nil
    s:run(path)
    equal(s.undo_count, 0)
    assert(#s.messages > 0)
  end
end)

test("clipboard renaming releases undo and refresh after an API error", function()
  local s = Mock.new()
  s:add_track("A", true)
  s:add_track("B", true)
  s.clipboard, s.fail_at = "one\ntwo", 2
  s:run("Clipboard/bbs_Rename selected tracks from clipboard.lua")
  assert(#s.messages > 0)
  equal(s.tracks[1].name, "one")
end)

for _, edge in ipairs({ "start", "end" }) do
  test(edge .. " take marker includes source offset and rate", function()
    local s = Mock.new()
    local tr = s:add_track("track")
    s:add_item(tr, 10, 4, { name = "take", offset = 3, rate = 2 })
    s.input = "Marker,0.5,t"
    s:run("Markers/bbs_Add take marker at selected items " .. edge .. ".lua")
    equal(#s.markers, 1)
    equal(s.markers[1].pos, edge == "start" and 4 or 12)
  end)

  test(edge .. " project marker accepts blank name and trims marker type", function()
    local s = Mock.new()
    s:add_item(s:add_track("track"), 10, 4)
    s.input = ",-0.5, P "
    s:run("Markers/bbs_Add take marker at selected items " .. edge .. ".lua")
    equal(#s.markers, 1)
    equal(s.markers[1].name, "")
    equal(s.markers[1].pos, edge == "start" and 9.5 or 13.5)
  end)

  test(edge .. " marker rejects malformed numbers before editing", function()
    for _, input in ipairs({ "mark,wrong,t", "mark,1e999,t", "mark,0,typo" }) do
      local s = Mock.new()
      s:add_item(s:add_track("track"), 0, 1)
      s.input = input
      s:run("Markers/bbs_Add take marker at selected items " .. edge .. ".lua")
      equal(#s.markers, 0)
      equal(s.undo_count, 0)
    end
  end)

  test(edge .. " take marker skips warped takes instead of placing a wrong marker", function()
    local s = Mock.new()
    s:add_item(s:add_track("track"), 10, 4, { name = "take", stretch = 2 })
    s.input = "Marker,0,t"
    s:run("Markers/bbs_Add take marker at selected items " .. edge .. ".lua")
    equal(#s.markers, 0)
    equal(s.undo_count, 0)
    assert(#s.messages > 0)
  end)
end

test("regions correctly span items entirely before project zero", function()
  local s = Mock.new()
  local tr = s:add_track("negative", true)
  tr.color = 0x123456
  s:add_item(tr, -5, 2)
  s:add_item(tr, -2, 1)
  s:run("Markers/bbs_Create region for items on each selected track.lua")
  equal(s.markers[1].pos, -5)
  equal(s.markers[1].tail, -1)
  equal(s.markers[1].color, 0x1123456)
end)

test("empty selected tracks do not produce undo entries", function()
  local s = Mock.new()
  s:add_track("empty", true)
  s:run("Markers/bbs_Create region for items on each selected track.lua")
  equal(s.undo_count, 0)
end)

test("moving items off a folder's last child preserves folder membership", function()
  local s = Mock.new()
  s:add_track("folder", false, 1)
  local source = s:add_track("last child", false, -1)
  local a = s:add_item(source, 0, 1, { name = "A" })
  local b = s:add_item(source, 2, 1, { name = "B" })
  local outside = s:add_track("outside")
  s:run("Items Editing/bbs_Move selected items to new tracks by name.lua")
  equal(source.depth, 0)
  equal(s.tracks[3].name, "A")
  equal(s.tracks[4].name, "B")
  equal(s.tracks[4].depth, -1)
  equal(s.tracks[5], outside)
  equal(a.track, s.tracks[3])
  equal(b.track, s.tracks[4])
end)

test("move skips locked items without making empty tracks", function()
  local s = Mock.new()
  local tr = s:add_track("track")
  local item = s:add_item(tr, 0, 1)
  item.lock = 1
  s:run("Items Editing/bbs_Move selected items to new tracks by name.lua")
  equal(#s.tracks, 1)
  equal(s.undo_count, 0)
end)

test("reposition rejects invalid numeric and mode inputs without saving them", function()
  for _, input in ipairs({ "x,1,1,end,1", "0,1,1,typo,1", "0,1,1,end,1.5", "0,1,1e999,end,1" }) do
    local s = Mock.new()
    local tr = s:add_track("track")
    s:add_item(tr, 1, 1)
    s:add_item(tr, 5, 1)
    s.input = input
    s:run("Items Editing/bbs_Reposition items with curved gap.lua")
    equal(s.undo_count, 0)
    equal(next(s.ext), nil)
  end
end)

test("reposition keeps grouped relative offsets and anchors first batch", function()
  local s = Mock.new()
  local a_track, b_track = s:add_track("A"), s:add_track("B")
  local a = s:add_item(a_track, 2, 2)
  local b = s:add_item(a_track, 10, 1)
  local c = s:add_item(b_track, 11, 3)
  b.group, c.group = 7, 7
  s.input = "0.5,0.5,1,end,1"
  s:run("Items Editing/bbs_Reposition items with curved gap.lua")
  equal(a.pos, 2)
  equal(b.pos, 4.5)
  equal(c.pos, 5.5)
  equal(s.undo_count, 1)
end)

test("reposition refuses a locked selection without partially moving groups", function()
  local s = Mock.new()
  local tr = s:add_track("track")
  s:add_item(tr, 0, 1)
  local item = s:add_item(tr, 4, 1)
  item.lock = 1
  s.input = "1,1,1,end,1"
  s:run("Items Editing/bbs_Reposition items with curved gap.lua")
  equal(item.pos, 4)
  equal(s.undo_count, 0)
end)

test("osu export rejects malformed names and orders simultaneous columns", function()
  local s = Mock.new()
  local invalid = s:add_track("4")
  s:add_item(invalid, 0, 1, { name = "prefix1,0suffix" })
  local right = s:add_track("4")
  local left = s:add_track("1")
  s:add_item(right, 2, 1, { name = "1,0" })
  s:add_item(left, 2, 0.5, { name = "128,0" })
  s:run("Workflow/bbs_Generate Osu mania chart from items.lua")
  equal(s.clipboard, "[HitObjects]\n64,192,2000,128,0,2500:0:0:0:0:\n448,192,2000,1,0,0:0:0:0:")
end)

test("all editing actions release undo and refresh on API failure", function()
  for _, path in ipairs({
    "Clipboard/bbs_Rename selected takes from clipboard.lua",
    "Markers/bbs_Add take marker at selected items start.lua",
    "Markers/bbs_Add take marker at selected items end.lua",
    "Markers/bbs_Create region for items on each selected track.lua",
    "Items Editing/bbs_Move selected items to new tracks by name.lua",
    "Items Editing/bbs_Reposition items with curved gap.lua",
  }) do
    local s = Mock.new()
    local tr = s:add_track("track", true)
    s:add_item(tr, 0, 1)
    s:add_item(tr, 5, 1)
    s.input = path:find("Reposition", 1, true) and "1,1,1,end,1" or "marker,0,t"
    s.clipboard, s.fail_at = "one\ntwo", 1
    s:run(path)
    equal(s.undo_count, 1)
    assert(#s.messages > 0)
  end
end)

test("start-mode curved spacing reaches both endpoints with unequal item lengths", function()
  local s = Mock.new()
  local tr = s:add_track("track")
  local a = s:add_item(tr, 10, 4)
  local b = s:add_item(tr, 20, 2)
  local c = s:add_item(tr, 30, 8)
  local d = s:add_item(tr, 40, 1)
  s.input = "1,5,2,start,1"
  s:run("Items Editing/bbs_Reposition items with curved gap.lua")
  equal(a.pos, 10)
  equal(b.pos, 11)
  equal(c.pos, 13)
  equal(d.pos, 18)
end)

test("osu export rejects out of range hitsounds", function()
  local s = Mock.new()
  s:add_item(s:add_track("1"), 0, 1, { name = "1,999" })
  s.clipboard = "unchanged"
  s:run("Workflow/bbs_Generate Osu mania chart from items.lua")
  equal(s.clipboard, "unchanged")
end)

print(string.format("Actions: %d passed, %d failed", passed, failed))
assert(failed == 0, "action regression failures")
