--@author Souk21
--@description Set block/buffer size
--@version 1.09
--@changelog
--   Fix WASAPI and WDL Kernel Streaming with REAPER 7
--   Added "Double" and "Halve" block size
--   Code cleanup
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

-- To use a custom block size:
-- Enter a custom block size below, between the quotation marks
local custom_size = ""

-- Size will be, in order of precedence:
-- custom_size if set
-- filename if ends with a number
-- double/halve if filename starts with this
-- menu if filename ends with "(menu)"
-- else prompt for size

if reaper.JS_Window_Find == nil then
  reaper.ShowMessageBox("You can download it from ReaPack", "This script needs js_ReaScriptAPI to be installed", 0)
  return
end

local current_size = 0.;
local current_size_is_known, current_size_str = reaper.GetAudioDeviceInfo("BSIZE")
if current_size_is_known then current_size = tonumber(current_size_str) end

local prompt = false
local selected_size = ""
if custom_size ~= "" then
  selected_size = custom_size
else
  local script_name = ({ reaper.get_action_context() })[2]:match("([^/\\]+)%.lua$")   -- Get filename without the extension
  local filename_size = script_name:match("%d*$")                                     -- Matches digits at the end of filename
  if filename_size ~= "" then
    selected_size = filename_size
  elseif script_name:match("souk21_Double") then
    selected_size = tostring(current_size * 2)
  elseif script_name:match("souk21_Halve") then
    selected_size = tostring(current_size / 2)
  elseif script_name:match("%(menu%)$") then
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
    local selection = gfx.showmenu(menu)
    if selection == 0 then return end
    selected_size = menu_sizes[selection - 1]
    prompt = selected_size == -1
  else
    prompt = true
  end
end

if prompt then
  local retval
  retval, selected_size = reaper.GetUserInputs("Set block size", 1, "Block size", "")
  if not retval then return end
end

if selected_size == nil or selected_size == "" then return end

reaper.Main_OnCommand(1016, 0)  -- Transport: Stop
reaper.Main_OnCommand(40099, 0) -- Open audio device preferences
local window = reaper.JS_Window_Find("REAPER Preferences", true)

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
  elseif id == 1043 or id == 1045 then   -- "Request block size" checkbox (1043 is osx, 1045 is win)
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
