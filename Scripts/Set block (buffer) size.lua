--@author Souk21
--@description Set block/buffer size
--@version 1.08
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

-- To use a custom block size:
-- Enter a custom block size below, between the quotation marks
local custom_size = ""

-- Size will be, in order of precedence:
-- custom_size if set
-- filename if ends with a number
-- menu if filename ends with "(menu)"
-- else prompt for size

if reaper.JS_Window_Find == nil then
  reaper.ShowMessageBox("You can get download it from ReaPack", "This script needs js_ReaScriptAPI to be installed", 0)
  return
end

local prompt = false
local size = ""
if custom_size ~= "" then
  size = custom_size
else
  local script_name = ({ reaper.get_action_context() })[2]:match("([^/\\_]+)%.lua$") -- Get filename without the extension
  local filename_size = script_name:match("%d*$")                                    -- Matches digits at the end of filename
  if filename_size ~= "" then
    size = filename_size
  else
    local menu = script_name:match("%(menu%)$") == "(menu)"
    if menu then
      local retval, current_size = reaper.GetAudioDeviceInfo("BSIZE", "")
      if retval then current_size = tonumber(current_size) end
      local menu_items = {
        { "#Block size|", nil },
      }

      local buff = 8
      local current_added = false

      for i = 0, 8 do
        buff = buff * 2
        if retval and not current_added and current_size < buff then
          table.insert(menu_items, { "!" .. tostring(current_size), tostring(current_size) })
          current_added = true
        end
        if current_size ~= buff then
          table.insert(menu_items, { tostring(buff), tostring(buff) })
        end
      end
      if retval and not current_added and current_size >= buff then
        table.insert(menu_items, { "!" .. tostring(current_size), tostring(current_size) })
        current_added = true
      end
      table.insert(menu_items, { "|Custom...", nil })
      local menu = ""
      for i = 1, #menu_items do
        menu = menu .. menu_items[i][1] .. "|"
      end
      -- Credits to amagalma for the menu code
      local title = "hidden" .. reaper.genGuid()
      gfx.init(title, 0, 0, 0, 0, 0)
      local hwnd = reaper.JS_Window_Find(title, true)
      if hwnd then
        reaper.JS_Window_Show(hwnd, "HIDE")
      end
      gfx.x, gfx.y = gfx.mouse_x - 55, gfx.mouse_y - 100
      local selection = gfx.showmenu(menu)
      gfx.quit()
      if selection == 0 then
        return
      elseif selection == #menu_items then
        prompt = true
      elseif selection ~= 0 then
        size = menu_items[selection][2]
      end
    else
      prompt = true
    end
  end
end

if prompt then
  local retval
  retval, size = reaper.GetUserInputs("Set block size", 1, "Block size", "")
  if not retval then return end
end

reaper.Main_OnCommand(1016, 0)  -- Transport: Stop
reaper.Main_OnCommand(40099, 0) -- Open audio device preferences
local window = reaper.JS_Window_Find("REAPER Preferences", true)

if window ~= nil then
  local hwnd_asio
  local hwnd_other
  local use_asio = true
  local arr = reaper.new_array({}, 255)
  local count = reaper.JS_Window_ArrayAllChild(window, arr)
  local adr = arr.table()

  for j = 1, #adr do
    local hwnd = reaper.JS_Window_HandleFromAddress(adr[j])
    local id = reaper.JS_Window_GetLong(hwnd, "ID")
    if id == 1008 then
      hwnd_asio = hwnd
    end
    if id == 1009 then
      hwnd_other = hwnd
    end
    if id == 1000 then
      local protocol = reaper.JS_Window_GetTitle(hwnd)
      if protocol == "WaveOut"
          or protocol == "DirectSound"
          or protocol == "WDM Kernel Streaming (Windows XP)"
          or protocol == "WASAPI (Windows 7/8/10/Vista)"
          or protocol == "Dummy Audio" then
        use_asio = false
      end
    end
    if id == 1043 or id == 1045 then -- "Request block size" checkbox (1043 is osx, 1045 is win)
      reaper.JS_WindowMessage_Send(hwnd, "BM_SETCHECK", 0x1, 0, 0, 0)
    end
  end

  if use_asio then
    reaper.JS_Window_SetTitle(hwnd_asio, size)
  else
    reaper.JS_Window_SetTitle(hwnd_other, size)
  end
  reaper.JS_WindowMessage_Send(window, "WM_COMMAND", 1144, 0, 0, 0) -- Apply
  reaper.JS_Window_Destroy(window)                                  -- Close window
end
