--@author Souk21
--@description Open floating "Recent Projects" menu at mouse position
--@changelog
--   Change script name to have author prefix
--@version 1.2
--@provides
--   [main] . > souk21_Open floating "Recent Projects" menu at mouse position.lua
function msg(str) reaper.ShowConsoleMsg(tostring(str) .. "\n") end

function main()
  if reaper.JS_Mouse_GetState == nil then
    reaper.ShowMessageBox("This script requires JS_API", "Missing dependency", 0)
    return
  end
  local projects = {}
  local _, current_project = reaper.EnumProjects(-1)
  local ini_path = reaper.get_ini_file()
  for line in io.lines(ini_path) do
    local matched = line:match("^recent%d+=(.+)")
    if matched and reaper.file_exists(matched) then
      local path = matched
      local title = matched:match(".+[/\\](.*)")
      local opened = path == current_project
      projects[#projects + 1] = { path, title, opened }
    end
  end

  local menu = "#Hold shift to open in new project tab|"

  for i = #projects, 1, -1 do
    local project_str = projects[i][2]
    if project_str:match("^[#!|<>]") then
      project_str = " " .. project_str
    end
    if projects[i][3] then
      project_str = "!" .. project_str
    end
    menu = menu .. "|" .. project_str
  end

  local result = gfx.showmenu(menu)
  local shift = reaper.JS_Mouse_GetState(8) == 8
  if result < 2 then
    return
  end
  if shift then
    reaper.Main_OnCommand(40859, 0) -- New project tab
  end
  reaper.Main_openProject(projects[#projects - (result - 2)][1])
end

main()
