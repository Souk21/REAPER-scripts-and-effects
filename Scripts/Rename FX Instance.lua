--@author Souk21
--@description Rename FX Instance
--@version 1.0
if reaper.CF_GetFocusedFXChain == nil or reaper.JS_WindowMessage_Send == nil then
  reaper.ShowMessageBox("This script requires SWS and JS_API", "Missing dependency", 0)
  return
end
local fx_chain = reaper.CF_GetFocusedFXChain()
reaper.JS_WindowMessage_Send(fx_chain, "WM_COMMAND", 40562, 0, 0, 0)
