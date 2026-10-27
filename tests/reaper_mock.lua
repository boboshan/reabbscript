-- A small in-memory REAPER boundary. Tests execute the real action files.
local Mock = {}

function Mock.new()
  local state = {
    tracks = {}, messages = {}, markers = {}, undo = 0, undo_count = 0,
    refresh = 0, clipboard = "", input = nil, ext = {}, mutations = 0,
  }
  function state:add_track(name, selected, depth)
    local track = { name = name, selected = selected or false, depth = depth or 0, items = {}, color = 0 }
    self.tracks[#self.tracks + 1] = track
    return track
  end
  function state:add_item(track, pos, len, take, selected)
    local item = {
      track = track, pos = pos, len = len, selected = selected ~= false, group = 0, lock = 0,
      take = take == false and nil or (take or { name = "take", offset = 0, rate = 1 }),
    }
    if take == false then item.take = nil end
    track.items[#track.items + 1] = item
    return item
  end
  local function tracks(selected)
    local result = {}
    for _, track in ipairs(state.tracks) do
      if not selected or track.selected then result[#result + 1] = track end
    end
    return result
  end
  local function items(selected)
    local result = {}
    for _, track in ipairs(state.tracks) do
      for _, item in ipairs(track.items) do
        if not selected or item.selected then result[#result + 1] = item end
      end
    end
    return result
  end
  local function mutate()
    state.mutations = state.mutations + 1
    if state.fail_at and state.mutations == state.fail_at then error("injected API failure") end
  end
  local api = {
    CountTracks = function() return #state.tracks end,
    GetTrack = function(_, i) return state.tracks[i + 1] end,
    CountSelectedTracks = function() return #tracks(true) end,
    GetSelectedTrack = function(_, i) return tracks(true)[i + 1] end,
    GetTrackName = function(track) return true, track.name end,
    GetTrackColor = function(track) return track.color end,
    CountMediaItems = function() return #items(false) end,
    GetMediaItem = function(_, i) return items(false)[i + 1] end,
    CountSelectedMediaItems = function() return #items(true) end,
    GetSelectedMediaItem = function(_, i) return items(true)[i + 1] end,
    CountTrackMediaItems = function(track) return #track.items end,
    GetTrackMediaItem = function(track, i) return track.items[i + 1] end,
    GetMediaItemTrack = function(item) return item.track end,
    GetActiveTake = function(item) return item.take end,
    GetTakeName = function(take) return take.name end,
    GetMediaItemInfo_Value = function(item, key)
      local names = { D_POSITION = "pos", D_LENGTH = "len", I_GROUPID = "group", C_LOCK = "lock" }
      return item[names[key]] or 0
    end,
    GetMediaItemTakeInfo_Value = function(take, key)
      if key == "D_STARTOFFS" then return take.offset or 0 end
      if key == "D_PLAYRATE" then return take.rate or 1 end
      return 0
    end,
    GetTakeNumStretchMarkers = function(take) return take.stretch or 0 end,
    GetMediaTrackInfo_Value = function(track, key)
      if key == "I_FOLDERDEPTH" then return track.depth end
      if key == "IP_TRACKNUMBER" then
        for i, candidate in ipairs(state.tracks) do if candidate == track then return i end end
      end
      return 0
    end,
    SetMediaTrackInfo_Value = function(track, key, value)
      mutate()
      assert(key == "I_FOLDERDEPTH", key)
      track.depth = value
      return true
    end,
    SetMediaItemInfo_Value = function(item, key, value)
      mutate()
      assert(key == "D_POSITION", key)
      item.pos = value
      return true
    end,
    GetSetMediaTrackInfo_String = function(track, key, value, set)
      assert(key == "P_NAME")
      if set then mutate(); track.name = value end
      return true, track.name
    end,
    GetSetMediaItemTakeInfo_String = function(take, key, value, set)
      assert(key == "P_NAME")
      if set then mutate(); take.name = value end
      return true, take.name
    end,
    CSurf_TrackToID = function(track)
      for i, candidate in ipairs(state.tracks) do if candidate == track then return i end end
    end,
    InsertTrackAtIndex = function(index)
      mutate()
      table.insert(state.tracks, index + 1, { name = "", selected = false, depth = 0, items = {}, color = 0 })
    end,
    MoveMediaItemToTrack = function(item, track)
      mutate()
      for i, candidate in ipairs(item.track.items) do
        if candidate == item then table.remove(item.track.items, i); break end
      end
      item.track = track
      track.items[#track.items + 1] = item
      return true
    end,
    SetTakeMarker = function(take, _, name, pos)
      mutate()
      state.markers[#state.markers + 1] = { take = take, name = name, pos = pos }
      return #state.markers - 1
    end,
    AddProjectMarker = function(_, region, pos, tail, name)
      mutate()
      state.markers[#state.markers + 1] = { region = region, pos = pos, tail = tail, name = name }
      return #state.markers - 1
    end,
    AddProjectMarker2 = function(_, region, pos, tail, name, _, color)
      mutate()
      state.markers[#state.markers + 1] = { region = region, pos = pos, tail = tail, name = name, color = color }
      return #state.markers - 1
    end,
    CF_GetClipboard = function() return state.clipboard end,
    CF_SetClipboard = function(text) state.clipboard = text end,
    SNM_CreateFastString = function() return {} end,
    CF_GetClipboardBig = function() return state.clipboard end,
    SNM_DeleteFastString = function() end,
    ShowMessageBox = function(message, title) state.messages[#state.messages + 1] = { message, title }; return 0 end,
    GetUserInputs = function() return state.input ~= nil, state.input end,
    GetExtState = function(section, key) return state.ext[section .. "/" .. key] or "" end,
    SetExtState = function(section, key, value) state.ext[section .. "/" .. key] = value end,
    Undo_BeginBlock = function() state.undo = state.undo + 1; state.undo_count = state.undo_count + 1 end,
    Undo_EndBlock = function() state.undo = state.undo - 1 end,
    PreventUIRefresh = function(delta) state.refresh = state.refresh + delta end,
    UpdateArrange = function() end,
    TrackList_AdjustWindows = function() end,
    defer = function() end,
  }
  api.Undo_BeginBlock2 = api.Undo_BeginBlock
  api.Undo_EndBlock2 = api.Undo_EndBlock
  api.APIExists = function(name) return api[name] ~= nil end
  state.api = api
  function state:run(path)
    local env = setmetatable({ reaper = self.api }, { __index = _G })
    assert(loadfile(path, "t", env))()
    assert(self.undo == 0, "undo block left open")
    assert(self.refresh == 0, "UI refresh left suspended")
  end
  return state
end

return Mock
