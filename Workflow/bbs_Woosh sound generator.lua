-- @description Generate sound effects using the Woosh AI model via its API.
-- @version 3.0
-- @author bbs
-- @about
--   # Woosh Sound Generator
--   Generate sound effects from text descriptions using Sony's Woosh AI model.
--   Requires:
--   - ReaImGui extension installed in REAPER (via ReaPack)
--   - curl (pre-installed on macOS, Linux, and Windows 10+)
--
--   Features:
--   - Zero-dependency setup: auto-installs uv, downloads Woosh, weights
--   - No git, gh, or unzip required — only curl + tar (system-provided)
--   - Auto-starts and stops the API server
--   - Text prompt input with adjustable generation parameters
--   - Inserts generated audio at cursor position or start of time selection
--   - Remembers settings between sessions
--   - Resume interrupted downloads

-- ── Dependency check & ImGui loader ─────────────────────────────────────────
if not reaper.ImGui_GetBuiltinPath then
  reaper.ShowMessageBox(
    "This script requires the ReaImGui extension (v0.10+).\n\n"
    .. "To install:\n"
    .. "1. Install ReaPack if you haven't: https://reapack.com\n"
    .. "2. In REAPER: Extensions > ReaPack > Import repositories...\n"
    .. "3. Add: https://github.com/ReaTeam/Extensions/raw/master/index.xml\n"
    .. "4. Extensions > ReaPack > Browse packages > search 'ReaImGui'\n"
    .. "5. Install and RESTART REAPER.",
    "Woosh: Missing Dependency", 0
  )
  return
end

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.10'

-- ── Constants ───────────────────────────────────────────────────────────────
local SECTION     = "bbs_WooshSoundGen"
local IS_WIN      = reaper.GetOS():match("Win")
local HOME        = IS_WIN and os.getenv("USERPROFILE") or os.getenv("HOME")
local SEP         = IS_WIN and "\\" or "/"
local WOOSH_DIR   = HOME .. SEP .. "Woosh"
local TMP_DIR     = (IS_WIN and os.getenv("TEMP") or "/tmp") .. SEP .. "woosh_reaper" .. SEP
local MODELS      = { "Woosh-DFlow", "Woosh-Flow" }
local SAMPLERS    = { "heun", "cfgpp" }
local SCHEDULERS  = { "karras", "linear", "sigmoid", "cosine" }
local SERVER_PORT = 8000
local WOOSH_TAG   = "v1.0.0"
local WOOSH_REPO_URL  = "https://github.com/SonyResearch/Woosh"
local WOOSH_RELEASE_URL = "https://github.com/SonyResearch/Woosh/releases/download/" .. WOOSH_TAG

-- ── Platform binary paths (absolute — immune to REAPER's stale PATH) ────────
local CURL_BIN, TAR_BIN, UV_BIN
if IS_WIN then
  CURL_BIN = "C:\\Windows\\System32\\curl.exe"
  TAR_BIN  = "C:\\Windows\\System32\\tar.exe"
  UV_BIN   = HOME .. "\\.local\\bin\\uv.exe"
else
  CURL_BIN = "/usr/bin/curl"
  TAR_BIN  = "/usr/bin/tar"
  UV_BIN   = HOME .. "/.local/bin/uv"
end

-- ── Unzip availability (cached once at startup) ─────────────────────────────
local HAS_UNZIP = false
if not IS_WIN then
  local _h = io.popen('command -v unzip >/dev/null 2>&1 && echo yes')
  if _h then
    HAS_UNZIP = (_h:read("*a") or ""):match("yes") ~= nil
    _h:close()
  end
end

-- ── Weight assets to download (T2A only, skip V2A models) ───────────────────
local WEIGHT_ASSETS = {
  {
    name = "Woosh-AE.zip",
    url  = WOOSH_RELEASE_URL .. "/Woosh-AE.zip",
    size = 822991075,
    sha256 = "d6f77e3792ee43c21da580f39d6576e0da3e4b46b949223259adf36036c1f9af",
  },
  {
    name = "Woosh-CLAP.zip",
    url  = WOOSH_RELEASE_URL .. "/Woosh-CLAP.zip",
    size = 1620013482,
    sha256 = "fa2cd7cfedae45fde39b5dc81bc6c9a40d721d0c9d422a954b60d69584177f62",
  },
  {
    name = "Woosh-DFlow.zip",
    url  = WOOSH_RELEASE_URL .. "/Woosh-DFlow.zip",
    size = 1281505601,
    sha256 = "26cfe732500e3952c58aaaf433d29d75b46d42afe5e52f49430d6093eabfdb04",
  },
  {
    name = "Woosh-Flow.zip",
    url  = WOOSH_RELEASE_URL .. "/Woosh-Flow.zip",
    size = 1253883744,
    sha256 = "f748c70972798ca09f98fe49e505e700ccfe4d38b3b12b955a06cb89aa0e024c",
  },
  {
    name = "TextConditionerA.zip",
    url  = WOOSH_RELEASE_URL .. "/TextConditionerA.zip",
    size = 1297121262,
    sha256 = "68a777b9ac28aa5daf6017b21af9a3659de75074ea14dac65f5231a42c375193",
  },
}

-- ── Persisted state helpers ─────────────────────────────────────────────────
local function get_state(key, default)
  local v = reaper.GetExtState(SECTION, key)
  return v ~= "" and v or default
end

local function save(key, val)
  reaper.SetExtState(SECTION, key, tostring(val), true)
end

-- ── File system helpers ─────────────────────────────────────────────────────
local function ensure_dir(path)
  reaper.RecursiveCreateDirectory(path, 0)
end

local function file_exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

local function file_size(path)
  local f = io.open(path, "rb")
  if not f then return 0 end
  local sz = f:seek("end")
  f:close()
  return sz
end

local function dir_exists(path)
  if IS_WIN then
    local ok, _, code = os.rename(path .. "\\.", path .. "\\.")
    return ok or code == 13
  else
    -- os.rename to self: true (Linux) or EINVAL/22 (macOS) for existing dirs
    -- Avoids shell injection that io.popen('test -d "' .. path .. '"') would allow
    local ok, _, code = os.rename(path, path)
    return ok or code == 13 or code == 22
  end
end

local function read_file_contents(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

local function bin_exists(path)
  return file_exists(path)
end

-- ── Shell helpers ───────────────────────────────────────────────────────────
local function bg_exec(cmd, log_path)
  local done_path = log_path .. ".done"
  local full_cmd
  if IS_WIN then
    -- Write a .bat file to avoid cmd /C "..." nested-quote breakage on paths with spaces
    local bat_path = log_path .. "_run.bat"
    local bf = io.open(bat_path, "w")
    if bf then
      bf:write("@echo off\r\n")
      bf:write(string.format('(%s) > "%s" 2>&1\r\n', cmd, log_path))
      bf:write(string.format('echo done > "%s"\r\n', done_path))
      bf:write(string.format('del /Q "%s"\r\n', bat_path))
      bf:close()
    end
    full_cmd = string.format('start /B "" "%s"', bat_path)
  else
    full_cmd = string.format(
      '((%s) > "%s" 2>&1; echo done > "%s") &',
      cmd, log_path, done_path
    )
  end
  os.execute(full_cmd)
  return done_path
end

local function format_size(bytes)
  if bytes >= 1073741824 then
    return string.format("%.1f GB", bytes / 1073741824)
  elseif bytes >= 1048576 then
    return string.format("%.0f MB", bytes / 1048576)
  else
    return string.format("%.0f KB", bytes / 1024)
  end
end

-- ── Setup state ─────────────────────────────────────────────────────────────
-- Phases: idle, prereqs, downloading_repo, installing, downloading_weights, extracting, ready, error
local setup_phase       = "idle"
local setup_log         = ""
local setup_log_path    = TMP_DIR .. "setup_log.txt"
local setup_done_path   = nil
local setup_gpu_mode    = get_state("gpu_mode", "cpu")
local setup_error       = nil
local setup_start_time  = 0
local dl_asset_idx      = 0   -- current weight asset index (set to 1 before first use)

-- ── Server state ────────────────────────────────────────────────────────────
local server_pid_file   = TMP_DIR .. "woosh_server.pid"
local server_log_path   = TMP_DIR .. "woosh_server.log"
local server_running    = false
local server_starting   = false
local server_start_time = 0

-- ── Generation state ────────────────────────────────────────────────────────
local ctx = ImGui.CreateContext("Woosh Sound Generator")

local server_url     = "http://localhost:" .. SERVER_PORT
local prompt         = get_state("prompt", "")
local cfg            = tonumber(get_state("cfg", "3.0")) or 3.0
local guidance_scale = tonumber(get_state("guidance_scale", "7.5")) or 7.5
local num_steps      = math.floor(tonumber(get_state("num_steps", "5")) or 5)
local model_idx      = math.max(0, math.min(#MODELS - 1,     tonumber(get_state("model_idx",     "0")) or 0))
local sampler_idx    = math.max(0, math.min(#SAMPLERS - 1,   tonumber(get_state("sampler_idx",   "0")) or 0))
local scheduler_idx  = math.max(0, math.min(#SCHEDULERS - 1, tonumber(get_state("scheduler_idx", "0")) or 0))
local seed_str       = get_state("seed", "-1")
local insert_on_new  = get_state("insert_new_track", "0") == "1"

local generating     = false
local status_msg     = ""
local status_color   = 0x999999FF
local gen_start_time = 0
local output_path    = nil
local done_marker    = nil

-- ── JSON helpers ────────────────────────────────────────────────────────────
local function escape_json(s)
  s = s:gsub('\\', '\\\\')
  s = s:gsub('"',  '\\"')
  s = s:gsub('\n', '\\n')
  s = s:gsub('\r', '\\r')
  s = s:gsub('\t', '\\t')
  -- Escape remaining ASCII control characters U+0000–U+001F (excl. \n \r \t)
  s = s:gsub('[\x00-\x08\x0B\x0C\x0E-\x1F]', function(c)
    return string.format('\\u%04x', c:byte())
  end)
  return s
end

-- ── Set status with color ───────────────────────────────────────────────────
local function set_status(msg, color)
  status_msg   = msg
  status_color = color or 0x999999FF
end

-- ── Check Woosh installation status ─────────────────────────────────────────
local function check_install_status()
  local has_api = file_exists(WOOSH_DIR .. SEP .. "api" .. SEP .. "api_server.py")
  local has_venv = dir_exists(WOOSH_DIR .. SEP .. ".venv")
  local has_checkpoints = dir_exists(WOOSH_DIR .. SEP .. "checkpoints" .. SEP .. "Woosh-DFlow")
    and dir_exists(WOOSH_DIR .. SEP .. "checkpoints" .. SEP .. "Woosh-AE")
    and dir_exists(WOOSH_DIR .. SEP .. "checkpoints" .. SEP .. "Woosh-CLAP")
    and dir_exists(WOOSH_DIR .. SEP .. "checkpoints" .. SEP .. "Woosh-Flow")
    and dir_exists(WOOSH_DIR .. SEP .. "checkpoints" .. SEP .. "TextConditionerA")
  -- Verify no zip files remain (extraction not complete)
  if has_checkpoints then
    for _, asset in ipairs(WEIGHT_ASSETS) do
      local zip_path = WOOSH_DIR .. SEP .. asset.name
      if file_exists(zip_path) then
        has_checkpoints = false
        break
      end
    end
  end
  return {
    repo = has_api,
    checkpoints = has_checkpoints,
    api = has_api,
    venv = has_venv,
    ready = has_api and has_checkpoints and has_venv,
  }
end

-- ── Prerequisite: auto-install uv ───────────────────────────────────────────
local function start_uv_install()
  setup_phase = "prereqs"
  setup_error = nil
  setup_start_time = reaper.time_precise()
  ensure_dir(TMP_DIR)
  setup_log = "Installing uv (Python package manager)...\n"

  local cmd
  if IS_WIN then
    cmd = string.format(
      'powershell -ExecutionPolicy ByPass -NoProfile -Command "irm https://astral.sh/uv/install.ps1 | iex"'
    )
  else
    cmd = string.format(
      '"%s" -LsSf https://astral.sh/uv/install.sh | sh',
      CURL_BIN
    )
  end
  setup_done_path = bg_exec(cmd, setup_log_path)
end

-- ── Setup: download repo tarball ────────────────────────────────────────────
local function start_setup_download_repo()
  -- If repo already exists (api file present), skip
  if file_exists(WOOSH_DIR .. SEP .. "api" .. SEP .. "api_server.py") then
    return true -- signal caller to move to next phase
  end
  setup_phase = "downloading_repo"
  setup_error = nil
  setup_start_time = reaper.time_precise()
  ensure_dir(TMP_DIR)
  setup_log = "Downloading Woosh repository...\n"

  local tarball_url = WOOSH_REPO_URL .. "/archive/refs/tags/" .. WOOSH_TAG .. ".tar.gz"
  local tarball_path = TMP_DIR .. "woosh_repo.tar.gz"

  local cmd
  if IS_WIN then
    -- Download, extract, rename extracted folder to WOOSH_DIR
    cmd = string.format(
      '"%s" -L -o "%s" "%s"'
      .. ' && "%s" -xzf "%s" -C "%s"'
      .. ' && ren "%s\\Woosh-%s" "%s"'
      .. ' && del "%s"',
      CURL_BIN, tarball_path, tarball_url,
      TAR_BIN, tarball_path, HOME,
      HOME, WOOSH_TAG:sub(2), "Woosh",
      tarball_path
    )
  else
    -- The tarball extracts to Woosh-<tag_without_v>/
    cmd = string.format(
      '"%s" -L -o "%s" "%s"'
      .. ' && "%s" -xzf "%s" -C "%s"'
      .. ' && mv "%s/Woosh-%s" "%s"'
      .. ' && rm -f "%s"',
      CURL_BIN, tarball_path, tarball_url,
      TAR_BIN, tarball_path, HOME,
      HOME, WOOSH_TAG:sub(2), WOOSH_DIR,
      tarball_path
    )
  end
  setup_done_path = bg_exec(cmd, setup_log_path)
  return false
end

-- ── Setup: install dependencies via uv ──────────────────────────────────────
local function start_setup_install()
  setup_phase = "installing"
  setup_error = nil
  setup_start_time = reaper.time_precise()
  ensure_dir(TMP_DIR)
  setup_log = "Installing Python dependencies via uv...\n"

  local extra = setup_gpu_mode == "cuda" and "cuda" or "cpu"
  local cmd
  if IS_WIN then
    cmd = string.format(
      'cd /d "%s" && "%s" sync --extra %s',
      WOOSH_DIR, UV_BIN, extra
    )
  else
    cmd = string.format(
      'cd "%s" && "%s" sync --extra %s',
      WOOSH_DIR, UV_BIN, extra
    )
  end
  setup_done_path = bg_exec(cmd, setup_log_path)
end

-- ── Setup: download weight assets one by one ────────────────────────────────
local function start_download_next_weight()
  if dl_asset_idx < 1 then dl_asset_idx = 1 end
  -- Find the next weight that needs downloading
  while dl_asset_idx <= #WEIGHT_ASSETS do
    local asset = WEIGHT_ASSETS[dl_asset_idx]
    local zip_path = WOOSH_DIR .. SEP .. asset.name
    local checkpoint_name = asset.name:gsub("%.zip$", "")
    local checkpoint_dir = WOOSH_DIR .. SEP .. "checkpoints" .. SEP .. checkpoint_name

    -- Skip if already extracted
    if dir_exists(checkpoint_dir) and not file_exists(zip_path) then
      dl_asset_idx = dl_asset_idx + 1
    else
      break
    end
  end

  if dl_asset_idx > #WEIGHT_ASSETS then
    -- All weights downloaded and extracted
    setup_phase = "ready"
    return
  end

  setup_phase = "downloading_weights"
  setup_error = nil
  setup_start_time = reaper.time_precise()
  ensure_dir(TMP_DIR)

  local asset = WEIGHT_ASSETS[dl_asset_idx]
  local zip_path = WOOSH_DIR .. SEP .. asset.name
  setup_log = string.format("Downloading %s (%s) [%d/%d]...\n",
    asset.name, format_size(asset.size), dl_asset_idx, #WEIGHT_ASSETS)

  -- Download with resume support, then extract, then remove zip
  local extract_cmd
  if IS_WIN then
    extract_cmd = string.format(
      '"%s" -L -C - -o "%s" "%s"'
      .. ' && "%s" -xf "%s" -C "%s"'
      .. ' && del "%s"',
      CURL_BIN, zip_path, asset.url,
      TAR_BIN, zip_path, WOOSH_DIR,
      zip_path
    )
  else
    -- macOS and Linux: use unzip (pre-installed on macOS, common on Linux)
    -- Fallback: use Python via uv if unzip is missing
    if HAS_UNZIP then
      extract_cmd = string.format(
        '"%s" -L -C - -o "%s" "%s"'
        .. ' && unzip -o "%s" -d "%s"'
        .. ' && rm -f "%s"',
        CURL_BIN, zip_path, asset.url,
        zip_path, WOOSH_DIR,
        zip_path
      )
    else
      -- Fallback: use Python's zipfile module via uv
      extract_cmd = string.format(
        '"%s" -L -C - -o "%s" "%s"'
        .. ' && "%s" run python -c "'
        .. "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])"
        .. '" "%s" "%s"'
        .. ' && rm -f "%s"',
        CURL_BIN, zip_path, asset.url,
        UV_BIN, zip_path, WOOSH_DIR,
        zip_path
      )
    end
  end

  setup_done_path = bg_exec(extract_cmd, setup_log_path)
end

-- ── Poll setup progress ────────────────────────────────────────────────────
local function poll_setup()
  if setup_phase == "idle" or setup_phase == "ready" or setup_phase == "error" then return end
  if not setup_done_path then return end
  if not file_exists(setup_done_path) then
    local content = read_file_contents(setup_log_path)
    if content then setup_log = content end
    return
  end

  local content = read_file_contents(setup_log_path)
  if content then setup_log = content end
  os.remove(setup_done_path)
  setup_done_path = nil

  if setup_phase == "prereqs" then
    -- Verify uv was installed
    if not bin_exists(UV_BIN) then
      setup_phase = "error"
      setup_error = "Failed to install uv. Check the log below.\n"
        .. "You can install it manually: https://docs.astral.sh/uv/getting-started/installation/"
      return
    end
    -- uv installed, proceed to download repo
    setup_phase = "idle"
    setup_log = setup_log .. "\nuv installed successfully!\n"
    -- Immediately start next phase
    local skip = start_setup_download_repo()
    if skip then start_setup_install() end
    return

  elseif setup_phase == "downloading_repo" then
    if file_exists(WOOSH_DIR .. SEP .. "api" .. SEP .. "api_server.py") then
      start_setup_install()
    else
      setup_phase = "error"
      setup_error = "Repository download failed. Check the log below."
    end

  elseif setup_phase == "installing" then
    if dir_exists(WOOSH_DIR .. SEP .. ".venv") then
      -- Start downloading weights
      dl_asset_idx = 1
      start_download_next_weight()
    else
      setup_phase = "error"
      setup_error = "Dependency install failed. Check the log below."
    end

  elseif setup_phase == "downloading_weights" then
    local asset = WEIGHT_ASSETS[dl_asset_idx]
    local checkpoint_name = asset.name:gsub("%.zip$", "")
    local checkpoint_dir = WOOSH_DIR .. SEP .. "checkpoints" .. SEP .. checkpoint_name

    if dir_exists(checkpoint_dir) then
      dl_asset_idx = dl_asset_idx + 1
      start_download_next_weight()
    else
      setup_phase = "error"
      setup_error = string.format(
        "Failed to download/extract %s. Check the log below.", asset.name
      )
    end
  end
end

-- ── Server management ───────────────────────────────────────────────────────
local function is_server_responding()
  local check_cmd
  if IS_WIN then
    check_cmd = string.format(
      '"%s" -s -o NUL -w "%%%%{http_code}" --connect-timeout 1 "%s/docs" 2>NUL',
      CURL_BIN, server_url
    )
  else
    check_cmd = string.format(
      '"%s" -s -o /dev/null -w "%%{http_code}" --connect-timeout 1 "%s/docs" 2>/dev/null',
      CURL_BIN, server_url
    )
  end
  local h = io.popen(check_cmd)
  if not h then return false end
  local code = h:read("*a") or ""
  h:close()
  return code:match("200") ~= nil
end

local function start_server()
  if server_running or server_starting then return end
  ensure_dir(TMP_DIR)
  server_starting = true
  server_start_time = reaper.time_precise()

  if IS_WIN then
    local cmd = string.format(
      'cd /d "%s" && "%s" run uvicorn api.api_server:app --host 0.0.0.0 --port %d',
      WOOSH_DIR, UV_BIN, SERVER_PORT
    )
    local bat_path = TMP_DIR .. "start_server.bat"
    local bf = io.open(bat_path, "w")
    if bf then
      bf:write("@echo off\r\n")
      bf:write(string.format('(%s) > "%s" 2>&1\r\n', cmd, server_log_path))
      bf:close()
    end
    os.execute(string.format('start /B "" "%s"', bat_path))
  else
    local cmd = string.format(
      'cd "%s" && "%s" run uvicorn api.api_server:app --host 0.0.0.0 --port %d > "%s" 2>&1 & echo $! > "%s"',
      WOOSH_DIR, UV_BIN, SERVER_PORT, server_log_path, server_pid_file
    )
    os.execute(cmd)
  end
end

local function stop_server()
  if IS_WIN then
    os.execute(string.format(
      'for /f "tokens=5" %%%%a in (\'netstat -aon ^| find ":%d"\') do taskkill /PID %%%%a /F 2>NUL',
      SERVER_PORT
    ))
  else
    local pid = read_file_contents(server_pid_file)
    if pid then
      pid = pid:match("%d+")
      if pid then
        os.execute("kill " .. pid .. " 2>/dev/null")
      end
    end
    os.execute(string.format("lsof -ti:%d | xargs kill 2>/dev/null", SERVER_PORT))
  end
  if file_exists(server_pid_file) then os.remove(server_pid_file) end
  server_running = false
  server_starting = false
end

local server_check_last = 0

local function poll_server()
  local now = reaper.time_precise()
  if now - server_check_last < 2.0 then return end
  server_check_last = now

  if server_starting then
    if is_server_responding() then
      server_running = true
      server_starting = false
      set_status("Server ready. Enter a prompt and generate!", 0x66FF66FF)
    elseif now - server_start_time > 120 then
      server_starting = false
      set_status("Server failed to start after 120s. Check log.", 0xFF4444FF)
    end
  elseif server_running then
    if not is_server_responding() then
      server_running = false
      set_status("Server stopped unexpectedly.", 0xFF4444FF)
    end
  end
end

-- ── Insert audio into REAPER ────────────────────────────────────────────────
local function insert_audio(filepath)
  local ts_start, ts_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local has_time_sel = (ts_end - ts_start) > 0.001
  local insert_pos = has_time_sel and ts_start or reaper.GetCursorPosition()
  local desired_len = has_time_sel and (ts_end - ts_start) or nil

  reaper.SetEditCurPos(insert_pos, false, false)

  if insert_on_new or reaper.CountSelectedTracks(0) == 0 then
    local idx = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(idx, true)
    local track = reaper.GetTrack(0, idx)
    reaper.SetOnlyTrackSelected(track)
    reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "Woosh", true)
  end

  reaper.Undo_BeginBlock()
  reaper.InsertMedia(filepath, 0)

  if desired_len then
    local item = reaper.GetSelectedMediaItem(0, 0)
    if item then
      local src_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      if desired_len < src_len then
        reaper.SetMediaItemInfo_Value(item, "D_LENGTH", desired_len)
        reaper.UpdateArrange()
      end
    end
  end

  reaper.Undo_EndBlock("Woosh: Insert generated sound effect", -1)
end

-- ── Save all settings ───────────────────────────────────────────────────────
local function save_settings()
  save("prompt",          prompt)
  save("cfg",             cfg)
  save("guidance_scale",  guidance_scale)
  save("num_steps",       num_steps)
  save("model_idx",       model_idx)
  save("sampler_idx",     sampler_idx)
  save("scheduler_idx",   scheduler_idx)
  save("seed",            seed_str)
  save("insert_new_track", insert_on_new and "1" or "0")
  save("gpu_mode",        setup_gpu_mode)
end

-- ── Start generation ────────────────────────────────────────────────────────
local function start_generate()
  if generating then return end
  if not server_running then
    set_status("Server is not running yet.", 0xFF6666FF)
    return
  end
  if prompt == "" then
    set_status("Please enter a prompt.", 0xFF6666FF)
    return
  end

  ensure_dir(TMP_DIR)

  local ts = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
  output_path = TMP_DIR .. "gen_" .. ts .. ".flac"
  done_marker = TMP_DIR .. "gen_" .. ts .. ".done"
  local json_path = TMP_DIR .. "gen_" .. ts .. ".json"
  local http_code_path = TMP_DIR .. "gen_" .. ts .. ".http"

  local use_seed = tonumber(seed_str) or -1
  if use_seed < 0 then use_seed = math.random(0, 2147483647) end

  local json = string.format(
    '{"version":"0.1","token":"string","args":'
    .. '{"model":"%s",'
    .. '"prompt":"%s",'
    .. '"cfg":%g,'
    .. '"sampler":"%s",'
    .. '"num_steps":%d,'
    .. '"sigma_min":0.0001,'
    .. '"sigma_max":80,'
    .. '"rho":7,'
    .. '"S_churn":1,'
    .. '"S_min":0,'
    .. '"S_noise":1,'
    .. '"guidance_scale":%g,'
    .. '"noise_scheduler":"%s",'
    .. '"seed":%d}}',
    MODELS[model_idx + 1],
    escape_json(prompt),
    cfg,
    SAMPLERS[sampler_idx + 1],
    num_steps,
    guidance_scale,
    SCHEDULERS[scheduler_idx + 1],
    use_seed
  )

  local jf = io.open(json_path, "w")
  if not jf then
    set_status("Error: Cannot write temp file", 0xFF4444FF)
    return
  end
  jf:write(json)
  jf:close()

  local curl_cmd
  if IS_WIN then
    curl_cmd = string.format(
      'start /B cmd /C ""%s" -s -f -X POST "%s/generate" '
      .. '-H "Content-Type: application/json" '
      .. '-d @"%s" -o "%s" -w "%%%%{http_code}" > "%s" 2>NUL '
      .. '& echo done > "%s""',
      CURL_BIN, server_url, json_path, output_path, http_code_path, done_marker
    )
  else
    curl_cmd = string.format(
      '("%s" -s -f -X POST "%s/generate" '
      .. '-H "Content-Type: application/json" '
      .. '-d @"%s" -o "%s" -w "%%{http_code}" > "%s" 2>/dev/null; '
      .. 'echo done > "%s") &',
      CURL_BIN, server_url, json_path, output_path, http_code_path, done_marker
    )
  end

  os.execute(curl_cmd)
  generating = true
  gen_start_time = reaper.time_precise()
  set_status("Generating...", 0xFFCC44FF)
  save_settings()
end

-- ── Poll for generation completion ──────────────────────────────────────────
local function poll_generation()
  if not generating then return end
  if not file_exists(done_marker) then return end

  os.remove(done_marker)

  local elapsed = reaper.time_precise() - gen_start_time

  if file_exists(output_path) and file_size(output_path) > 100 then
    insert_audio(output_path)
    set_status(
      string.format("Done! Inserted audio. (%.1fs)", elapsed),
      0x66FF66FF
    )
  else
    local hcp = output_path:gsub("%.flac$", ".http")
    local code = ""
    local hf = io.open(hcp, "r")
    if hf then
      code = (hf:read("*a") or ""):match("%d+") or ""
      hf:close()
    end
    if code ~= "" and code ~= "200" then
      set_status("Error: Server returned HTTP " .. code, 0xFF4444FF)
    else
      set_status("Error: No audio received. Is the server running?", 0xFF4444FF)
    end
  end

  generating = false
end

-- ── ImGui helpers ───────────────────────────────────────────────────────────
local function tooltip(text)
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, text)
  end
end

local function combo_from_table(label, current_idx, items)
  local items_str = table.concat(items, "\0") .. "\0"
  local rv, new_idx = ImGui.Combo(ctx, label, current_idx, items_str)
  return rv, new_idx
end

-- ── Setup UI ────────────────────────────────────────────────────────────────
local function draw_setup_ui()
  local status = check_install_status()

  ImGui.TextColored(ctx, 0xFFCC44FF, "Woosh Setup")
  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)

  ImGui.TextWrapped(ctx,
    "Woosh needs to be set up before first use. "
    .. "This will download the repository, install dependencies, "
    .. "and download model weights (~6 GB total).")

  ImGui.Spacing(ctx)
  ImGui.Text(ctx, string.format("Install location: %s", WOOSH_DIR))

  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)

  -- Prerequisites (minimal — just check curl exists)
  local has_curl = bin_exists(CURL_BIN)
  local has_uv = bin_exists(UV_BIN)

  local is_busy = setup_phase ~= "idle" and setup_phase ~= "ready" and setup_phase ~= "error"

  ImGui.Text(ctx, "Prerequisites:")
  if has_curl then
    ImGui.TextColored(ctx, 0x66FF66FF, "  [OK]  curl")
  else
    ImGui.TextColored(ctx, 0xFF4444FF, "  [MISSING]  curl")
    ImGui.SameLine(ctx)
    ImGui.TextColored(ctx, 0x999999FF, " -- requires Windows 10+ or install manually")
  end
  if has_uv then
    ImGui.TextColored(ctx, 0x66FF66FF, "  [OK]  uv (Python manager)")
  else
    ImGui.TextColored(ctx, 0xFFCC44FF, "  [auto]  uv (will be installed automatically)")
  end

  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)

  -- Progress steps
  local function step_icon(done)
    return done and "[done]" or "[    ]"
  end

  ImGui.Text(ctx, "Installation steps:")
  ImGui.TextColored(ctx, status.repo and 0x66FF66FF or 0x777777FF,
    "  " .. step_icon(status.repo) .. "  Download repository")
  ImGui.TextColored(ctx, status.venv and 0x66FF66FF or 0x777777FF,
    "  " .. step_icon(status.venv) .. "  Install dependencies")
  ImGui.TextColored(ctx, status.checkpoints and 0x66FF66FF or 0x777777FF,
    "  " .. step_icon(status.checkpoints) .. "  Download model weights")

  ImGui.Spacing(ctx)

  -- GPU mode
  ImGui.Text(ctx, "Compute mode:")
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "CPU", setup_gpu_mode == "cpu") then
    setup_gpu_mode = "cpu"
    save("gpu_mode", "cpu")
  end
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "CUDA (NVIDIA GPU)", setup_gpu_mode == "cuda") then
    setup_gpu_mode = "cuda"
    save("gpu_mode", "cuda")
  end

  ImGui.Spacing(ctx)

  -- Action button
  if is_busy then
    ImGui.BeginDisabled(ctx)
  end

  if status.ready then
    ImGui.TextColored(ctx, 0x66FF66FF, "Setup complete!")
  elseif not has_curl then
    ImGui.TextColored(ctx, 0xFF6666FF,
      "curl not found. Please update to Windows 10+ or install curl manually.")
  else
    if ImGui.Button(ctx, "Install Woosh", -1, 32) then
      -- Start the pipeline: uv install (if needed) -> repo download -> deps -> weights
      if not has_uv then
        start_uv_install()
      else
        local skip = start_setup_download_repo()
        if skip then start_setup_install() end
      end
    end
  end

  if is_busy then
    ImGui.EndDisabled(ctx)
  end

  -- Phase indicator
  if is_busy then
    ImGui.Spacing(ctx)
    local phase_labels = {
      prereqs = "Installing uv...",
      downloading_repo = "Downloading repository...",
      installing = "Installing dependencies (may take a few minutes)...",
      downloading_weights = string.format("Downloading weights [%d/%d]...",
        math.min(dl_asset_idx, #WEIGHT_ASSETS), #WEIGHT_ASSETS),
    }
    local dots = string.rep(".", math.floor(reaper.time_precise() * 2) % 4)
    ImGui.TextColored(ctx, 0xFFCC44FF, (phase_labels[setup_phase] or setup_phase) .. dots)
    local elapsed = reaper.time_precise() - setup_start_time
    ImGui.SameLine(ctx)
    ImGui.TextColored(ctx, 0x999999FF, string.format("(%.0fs)", elapsed))
  end

  -- Error
  if setup_phase == "error" and setup_error then
    ImGui.Spacing(ctx)
    ImGui.TextColored(ctx, 0xFF4444FF, setup_error)
    ImGui.Spacing(ctx)
    if ImGui.Button(ctx, "Retry", 80, 0) then
      setup_phase = "idle"
      setup_error = nil
    end
  end

  -- Log
  if setup_log ~= "" then
    ImGui.Spacing(ctx)
    ImGui.Separator(ctx)
    ImGui.Spacing(ctx)
    ImGui.Text(ctx, "Log output:")
    local lines = {}
    for line in setup_log:gmatch("[^\n]+") do
      lines[#lines + 1] = line
    end
    local start_i = math.max(1, #lines - 19)
    local trimmed = {}
    for i = start_i, #lines do
      trimmed[#trimmed + 1] = lines[i]
    end
    ImGui.InputTextMultiline(ctx, "##setup_log", table.concat(trimmed, "\n"),
      -1, 120, ImGui.InputTextFlags_ReadOnly)
  end

  -- Never declare ready while a setup phase is actively running
  local is_actively_running = setup_phase ~= "idle" and setup_phase ~= "ready" and setup_phase ~= "error"
  return status.ready and not is_actively_running
end

-- ── Generator UI ────────────────────────────────────────────────────────────
local function draw_generator_ui()
  -- Server status
  if server_running then
    ImGui.TextColored(ctx, 0x66FF66FF, "Server: Running")
  elseif server_starting then
    local dots = string.rep(".", math.floor(reaper.time_precise() * 2) % 4)
    ImGui.TextColored(ctx, 0xFFCC44FF, "Server: Starting" .. dots)
    local elapsed = reaper.time_precise() - server_start_time
    ImGui.SameLine(ctx)
    ImGui.TextColored(ctx, 0x999999FF, string.format("(%.0fs)", elapsed))
  else
    ImGui.TextColored(ctx, 0xFF4444FF, "Server: Not running")
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, "Start Server") then
      start_server()
    end
  end

  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)

  -- Prompt
  ImGui.Text(ctx, "Prompt")
  ImGui.SetNextItemWidth(ctx, -1)
  local rv_p, new_p = ImGui.InputTextMultiline(ctx, "##prompt", prompt, -1, 80)
  if rv_p then prompt = new_p end

  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)

  -- Parameters
  if ImGui.TreeNodeEx(ctx, "Parameters", ImGui.TreeNodeFlags_DefaultOpen) then
    local w = -ImGui.GetFontSize(ctx) * 10
    ImGui.SetNextItemWidth(ctx, w)
    local rv_model, new_model = combo_from_table("Model", model_idx, MODELS)
    if rv_model then model_idx = new_model end
    tooltip("Woosh-DFlow: fast distilled model (fewer steps). Woosh-Flow: original model (adaptive steps, higher quality)")

    ImGui.SetNextItemWidth(ctx, w)
    local rv_cfg, new_cfg = ImGui.SliderDouble(ctx, "CFG", cfg, 0.0, 10.0, "%.1f")
    if rv_cfg then cfg = new_cfg end
    tooltip("Classifier-free guidance strength for the diffusion model")

    ImGui.SetNextItemWidth(ctx, w)
    local rv_gs, new_gs = ImGui.SliderDouble(ctx, "Guidance Scale", guidance_scale, 0.0, 20.0, "%.1f")
    if rv_gs then guidance_scale = new_gs end
    tooltip("Text guidance scale -- higher values follow the prompt more closely")

    ImGui.SetNextItemWidth(ctx, w)
    local rv_ns, new_ns = ImGui.SliderInt(ctx, "Steps", num_steps, 1, 100)
    if rv_ns then num_steps = new_ns end
    tooltip("Number of diffusion steps -- more steps = higher quality but slower")

    ImGui.SetNextItemWidth(ctx, w)
    local rv_samp, new_samp = combo_from_table("Sampler", sampler_idx, SAMPLERS)
    if rv_samp then sampler_idx = new_samp end

    ImGui.SetNextItemWidth(ctx, w)
    local rv_sched, new_sched = combo_from_table("Noise Scheduler", scheduler_idx, SCHEDULERS)
    if rv_sched then scheduler_idx = new_sched end

    ImGui.SetNextItemWidth(ctx, w)
    local rv_seed, new_seed = ImGui.InputText(ctx, "Seed (-1 = random)", seed_str)
    if rv_seed then seed_str = new_seed end
    tooltip("Set a specific seed for reproducible results, or -1 for random")

    ImGui.TreePop(ctx)
  end

  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)

  -- Options
  local rv_nt, new_nt = ImGui.Checkbox(ctx, "Insert on new track", insert_on_new)
  if rv_nt then insert_on_new = new_nt end
  tooltip("Always create a new track for each generated sound")

  local ts_start, ts_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local has_ts = (ts_end - ts_start) > 0.001
  if has_ts then
    ImGui.SameLine(ctx, 0, 20)
    ImGui.TextColored(ctx, 0x88CCFFFF,
      string.format("Time sel: %.2fs - %.2fs", ts_start, ts_end))
  end

  ImGui.Spacing(ctx)
  ImGui.Spacing(ctx)

  -- Generate button
  local was_generating = generating
  local btn_disabled = was_generating or not server_running
  if btn_disabled then
    ImGui.BeginDisabled(ctx)
  end

  if ImGui.Button(ctx, "Generate", -1, 32) then
    start_generate()
  end

  if not was_generating and server_running then
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Enter)
       and ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl) then
      start_generate()
    end
  end

  if btn_disabled then
    ImGui.EndDisabled(ctx)
  end

  ImGui.Spacing(ctx)

  -- Status
  if status_msg ~= "" then
    ImGui.TextColored(ctx, status_color, status_msg)
  end

  if generating then
    local elapsed = reaper.time_precise() - gen_start_time
    if status_msg ~= "" then ImGui.SameLine(ctx) end
    ImGui.TextColored(ctx, 0xFFCC44FF,
      string.format(" (%.0fs elapsed)", elapsed))
  end

  -- Insert position hint
  ImGui.Spacing(ctx)
  local pos_label
  if has_ts then
    pos_label = string.format("Will insert at time selection start (%.2fs)", ts_start)
  else
    pos_label = string.format("Will insert at cursor (%.2fs)", reaper.GetCursorPosition())
  end
  ImGui.TextColored(ctx, 0x777777FF, pos_label)
end

-- ── Determine initial mode ──────────────────────────────────────────────────
local install_status = check_install_status()
local show_setup = not install_status.ready
local server_auto_started = false

-- ── Main loop ───────────────────────────────────────────────────────────────
local function loop()
  ImGui.SetNextWindowSize(ctx, 480, 560, ImGui.Cond_FirstUseEver)

  local visible, open = ImGui.Begin(ctx, "Woosh Sound Generator", true,
    ImGui.WindowFlags_NoCollapse)

  if visible then
    if show_setup then
      local ready = draw_setup_ui()
      if ready then
        show_setup = false
      end
    else
      if not server_auto_started then
        server_auto_started = true
        if not server_running and not server_starting then
          start_server()
          set_status("Starting server...", 0xFFCC44FF)
        end
      end
      draw_generator_ui()
    end

    ImGui.End(ctx)
  end

  poll_setup()
  poll_generation()
  poll_server()

  if open then
    reaper.defer(loop)
  else
    stop_server()
    save_settings()
  end
end

ensure_dir(TMP_DIR)
reaper.defer(loop)
