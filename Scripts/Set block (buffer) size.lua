--@author Souk21
--@description Set block/buffer size
--@version 1.14
--@changelog
--   Fix last update
--@metapackage
--@provides
--   [main] . > souk21_Set block (buffer) size (menu).lua
--   [main] . > souk21_Set block (buffer) size (prompt).lua
--   [main] . > souk21_Set block (buffer) size to 16.lua
--   [main] . > souk21_Set block (buffer) size to 32.lua
--   [main] . > souk21_Set block (buffer) size to 64.lua
--   [main] . > souk21_Set block (buffer) size to 128.lua
--   [main] . > souk21_Set block (buffer) size to 256.lua
--   [main] . > souk21_Set block (buffer) size to 512.lua
--   [main] . > souk21_Set block (buffer) size to 1024.lua
--   [main] . > souk21_Set block (buffer) size to 2048.lua
--   [main] . > souk21_Set block (buffer) size to 4096.lua
--   [main] . > souk21_Double block (buffer) size.lua
--   [main] . > souk21_Halve block (buffer) size.lua
--   [main] . > souk21_Set limits for double and halve block (buffer) size.lua

-- To use a custom block size:
-- Enter a custom block size below, between the quotation marks
local custom_size = ""

local function get_limits()
  local min = 16
  if reaper.HasExtState("Souk21", "MinBlockSize") then
    min = tonumber(reaper.GetExtState("Souk21", "MinBlockSize"))
  end
  local max = 4096
  if reaper.HasExtState("Souk21", "MaxBlockSize") then
    max = tonumber(reaper.GetExtState("Souk21", "MaxBlockSize"))
  end
  return min, max
end

-- Size will be, in order of precedence:
-- custom_size if set
-- filename if ends with a number
-- double/halve if filename starts with this
-- menu if filename ends with "(menu)"
-- else prompt for size

-- This function parses the filename to get the selected block size (or prompt/menu for it)
local function get_selected_size(filename)
  local current_size = 0.;
  local current_size_is_known, current_size_str = reaper.GetAudioDeviceInfo("BSIZE")
  if current_size_is_known then current_size = tonumber(current_size_str) end
  local prompt = false
  local selected_size = ""
  local filename_size = filename:match("%d*$") -- Matches digits at the end of filename
  if filename_size ~= "" then
    selected_size = filename_size
  elseif filename:match("souk21_Double") or filename:match("souk21_Halve") then
    local min, max = get_limits()
    local desired_size = 0
    if filename:match("souk21_Double") then
      desired_size = current_size * 2
    else
      desired_size = current_size / 2
    end
    selected_size = tostring(math.min(max, math.max(min, desired_size)))
  elseif filename:match("%(menu%)$") then
    local menu = "#Block size|"
    local menu_sizes = {}
    local buffer_size = 8
    local current_added = false
    for _ = 0, 8 do
      buffer_size = buffer_size * 2
      if current_size_is_known and not current_added and current_size < buffer_size then
        menu = menu .. "!" .. tostring(current_size) .. "|"
        table.insert(menu_sizes, current_size)
        current_added = true
      end
      if buffer_size ~= current_size then
        menu = menu .. tostring(buffer_size) .. "|"
        table.insert(menu_sizes, buffer_size)
      end
    end
    if current_size_is_known and not current_added and current_size >= buffer_size then
      menu = menu .. "!" .. tostring(current_size) .. "|"
      table.insert(menu_sizes, current_size)
      current_added = true
    end
    menu = menu .. "|Custom..."
    table.insert(menu_sizes, -1)
    --Reaper versions are decimal
    local version = tonumber(reaper.GetAppVersion():match("^[%d%.]+"))
    --Versions before 6.82 don't support gfx.showmenu without gfx.init on Windows
    local needs_gfx = version < 6.82
    if needs_gfx then
      local gfx_title = "Souk21_SetBlockSizeMenu"
      gfx.init(gfx_title, 0, 0)
      local gfx_hwnd = reaper.JS_Window_Find(gfx_title, true)
      if gfx_hwnd then
        reaper.JS_Window_Show(gfx_hwnd, "HIDE")
      end
      gfx.x = gfx.mouse_x
      gfx.y = gfx.mouse_y
    end
    local selection = gfx.showmenu(menu)
    if needs_gfx then
      gfx.quit()
    end
    if selection == 0 then return end
    selected_size = menu_sizes[selection - 1]
    prompt = selected_size == -1
  else
    prompt = true
  end

  if prompt then
    local retval
    retval, selected_size = reaper.GetUserInputs("Set block size", 1, "Block size", "")
    if not retval then return end
  end

  return selected_size
end

if reaper.JS_Window_Find == nil then
  reaper.ShowMessageBox(
    "This script needs js_ReaScriptAPI to be installed.\nYou can download it from ReaPack in the next window",
    "Missing dependency", 0)
  reaper.ReaPack_BrowsePackages("js_ReaScriptAPI")
  return
end

-- Filename without the extension
local filename = ({ reaper.get_action_context() })[2]:match("([^/\\]+)%.lua$")
if filename == nil then return end
if filename:match("^souk21_Set limits") then
  local min, max = get_limits()
  local placeholder = min .. "," .. max
  local ret, ret_csv = reaper.GetUserInputs("Set limits for \"double/halve block (buffer) size\"", 2, "Minimum,Maximum",
    placeholder)
  if not ret then return end
  local min, max = ret_csv:match("([^,]+),([^,]+)")
  if min == nil or max == nil then return end
  reaper.SetExtState("Souk21", "MinBlockSize", min, true)
  reaper.SetExtState("Souk21", "MaxBlockSize", max, true)
  return
end
local selected_size = ""
if custom_size ~= "" then
  selected_size = custom_size
else
  selected_size = get_selected_size(filename)
end
if selected_size == nil or selected_size == "" then return end

reaper.Main_OnCommand(1016, 0)  -- Transport: Stop
reaper.Main_OnCommand(40099, 0) -- Open audio device preferences
local preferences_title = reaper.LocalizeString("REAPER Preferences", "DLG_128", 0)
local window = reaper.JS_Window_Find(preferences_title, true)

if window == nil then return end

local hwnd_asio
local hwnd_other
local use_asio = true
local arr = reaper.new_array({}, 255)
reaper.JS_Window_ArrayAllChild(window, arr)
local addresses = arr.table()

for i = 1, #addresses do
  local hwnd = reaper.JS_Window_HandleFromAddress(addresses[i])
  local id = reaper.JS_Window_GetLong(hwnd, "ID")
  if id == 1008 then
    hwnd_asio = hwnd
  elseif id == 1009 then
    hwnd_other = hwnd
  elseif id == 1000 then
    local protocol = reaper.JS_Window_GetTitle(hwnd)
    if protocol == "WaveOut"
        or protocol == "DirectSound"
        or protocol:find("WDM Kernel Streaming")
        or protocol:find("WASAPI")
        or protocol == "Dummy Audio" then
      use_asio = false
    end
  elseif id == 1043 or id == 1045 then -- "Request block size" checkbox (1043 is osx, 1045 is win)
    reaper.JS_WindowMessage_Send(hwnd, "BM_SETCHECK", 0x1, 0, 0, 0)
  end
end

if use_asio then
  reaper.JS_Window_SetTitle(hwnd_asio, selected_size)
else
  reaper.JS_Window_SetTitle(hwnd_other, selected_size)
end
reaper.JS_WindowMessage_Send(window, "WM_COMMAND", 1144, 0, 0, 0) -- Apply
reaper.JS_Window_Destroy(window)
