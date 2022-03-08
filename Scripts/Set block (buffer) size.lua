--@author Souk21
--@description Set block/buffer size
--@version 1.0
--@metapackage
--@provides
--   [main] . > souk21_Set block (buffer) size (prompt).lua
--   [main] . > souk21_Set block (buffer) size to 64.lua
--   [main] . > souk21_Set block (buffer) size to 128.lua
--   [main] . > souk21_Set block (buffer) size to 256.lua
--   [main] . > souk21_Set block (buffer) size to 512.lua
--   [main] . > souk21_Set block (buffer) size to 1024.lua
--   [main] . > souk21_Set block (buffer) size to 2048.lua

-- To use a custom block size:
-- Enter a custom block size below, between the quotation marks
local custom_size = "" 
--  OR
-- Modify the filename (e.g "Set block size to 1234.lua" will set the size to 1234)
-- The custom size above takes precedence over the filename
-- If custom_size is not set and filename doesn't end with a number, the script will prompt for the size

local cancelled = false
local size = ""
if custom_size ~= "" then
  size = custom_size;
else
  local script_name = ({reaper.get_action_context()})[2]:match("([^/\\_]+)%.lua$") -- Get filename without the extension
  filename_size = script_name:match("%d*$"); -- Matches digits at the end of filename
  if filename_size ~= "" then
    size = filename_size
  else
    local retval;
    retval, size = reaper.GetUserInputs("New block size", 1, "","")
    if not retval then
      cancelled = true;
    end
  end
end

if not cancelled then
  reaper.Main_OnCommand(1016, 0) -- Transport: Stop
  reaper.Main_OnCommand(40099, 0) -- Open audio device preferences
  local window = reaper.JS_Window_Find("REAPER Preferences", true)

  if window ~= nil then
    local block_hwnd_asio
    local block_hwnd_other
    local use_asio = true
    local arr = reaper.new_array({}, 255)
    local count = reaper.JS_Window_ArrayAllChild(window, arr)
    local adr = arr.table()

    for j = 1, #adr do
      local hwnd = reaper.JS_Window_HandleFromAddress(adr[j])
      local title = reaper.JS_Window_GetTitle(hwnd)
      local id = reaper.JS_Window_GetLong(hwnd, "ID")
      if id == 1008 then
        block_hwnd_asio = hwnd;
      end
      if id == 1009 then
        block_hwnd_other = hwnd;
      end
      if id == 1000 then
        local protocol = reaper.JS_Window_GetTitle(hwnd);
        if protocol == "WaveOut" 
        or protocol == "DirectSound" 
        or protocol == "WDM Kernel Streaming (Windows XP)" 
        or protocol == "WASAPI (Windows 7/8/10/Vista)" 
        or protocol == "Dummy Audio" then
          use_asio = false;
        end
      end
    end
    
    if use_asio then
      reaper.JS_Window_SetTitle(block_hwnd_asio, size)
    else
      reaper.JS_Window_SetTitle(block_hwnd_other, size)
    end
    reaper.JS_WindowMessage_Send(window, "WM_COMMAND", 1144, 0, 0, 0) -- Apply
    reaper.JS_Window_Destroy(window) -- Close window
  end
end