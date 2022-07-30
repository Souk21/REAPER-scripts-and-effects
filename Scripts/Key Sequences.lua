--@author Souk21
--@description Key Sequences
--@about Create key sequence shortcuts
--@changelog
--   Reorder actions
--   Edit display name
--   Option to keep sequence open after action
--   Button to remove sequence shortcut
--   Fix some special characters issues, add others
--   Press Enter to validate new sequence / action edit
--   Change 'Key / chord' to 'Key(s)' in popup to avoid confusion
--@version 1.3
--@provides
--   [main] . > souk21_Key Sequences.lua
local font_name = "Verdana"

if reaper.CF_GetCommandText == nil or reaper.ImGui_Begin == nil or reaper.JS_Window_Find == nil then
    reaper.ShowMessageBox("This script requires SWS, ReaImGui and js_ReaScriptAPI.", "Missing dependency", 0)
    return
end

local script_path = reaper.GetResourcePath() .. "/Scripts/Souk21_sequences/"
local prefix = "souk21_sequences_"
local window_title = "Key Sequences"
local ctx = reaper.ImGui_CreateContext(window_title)
local draw_list
local font
if font_name ~= nil then
    font = reaper.ImGui_CreateFont(font_name, 13)
    reaper.ImGui_AttachFont(ctx, font)
end
local FLT_MIN = reaper.ImGui_NumericLimits_Float()
local sections = {
    { name = "Main", id = 0, short_name = "Main" },
    { name = "Main (alt recording)", id = 100, short_name = "Main (alt)" },
    { name = "MIDI Editor", id = 32060, short_name = "Midi Editor" },
    { name = "MIDI Event List Editor", id = 32061, short_name = "Midi Event List" },
    { name = "Media Explorer", id = 32063, short_name = "Media Ex." }
    --It's impossible to send commands to midi inline editor
    --{name= "MIDI Inline Editor", id=32062, short_name="Midi Inline"},
}
local files = {}
local removed = {}
local dirty = {}
local cur_file_idx = 0
local selected_section = 1
local new_seq_name = ""
local new_display_name = ""
local new_exit = false
local new_wants_focus = false
local edit_wants_focus = false
local table_scroll = 0
local first_load = true
local last_dirty_name = ""
local adding = nil
local key_popup_requested = false
local key_popup_opened = false
local did_change_show_after = false
local key_hwnd
local center
local action_popup_requested = false
local action_popup_opened = false
-- -1: not waiting, 0: waiting during new action/key creation, n: waiting during action[n] key/action update/change
local waiting_for_key = -1
local waiting_for_action = -1
local rect_flags = reaper.ImGui_DrawFlags_RoundCornersAll()
local popup_flags = reaper.ImGui_WindowFlags_NoMove() | reaper.ImGui_WindowFlags_AlwaysAutoResize()

-- global colors/styles
local colors = {
    { reaper.ImGui_Col_WindowBg(), 0x202123FF },
    { reaper.ImGui_Col_PopupBg(), 0x202123FF },
    { reaper.ImGui_Col_TitleBgActive(), 0x343434ff },
    { reaper.ImGui_Col_TitleBg(), 0x242424ff },
    { reaper.ImGui_Col_Button(), 0x565656ff },
    { reaper.ImGui_Col_ButtonHovered(), 0x606060ff },
    { reaper.ImGui_Col_ButtonActive(), 0x707070ff },
    { reaper.ImGui_Col_FrameBg(), 0x00000000 },
    { reaper.ImGui_Col_FrameBgHovered(), 0xffffff33 },
    { reaper.ImGui_Col_Header(), 0xFFFFFF00 },
    { reaper.ImGui_Col_HeaderHovered(), 0xFCFCFC00 },
    { reaper.ImGui_Col_HeaderActive(), 0xFFFFFF00 },
    { reaper.ImGui_Col_ChildBg(), 0x2D2D2D00 },
    { reaper.ImGui_Col_ScrollbarBg(), 0xfff00000 },
    { reaper.ImGui_Col_TableRowBgAlt(), 0x00000000 },
    { reaper.ImGui_Col_Text(), 0xffffffcd },
    { reaper.ImGui_Col_ResizeGrip(), 0xffffff33 },
    { reaper.ImGui_Col_ResizeGripHovered(), 0xffffff44 },
    { reaper.ImGui_Col_Border(), 0x606060ff },
}
local styles = {
    --window rounding causes a transparent line to show between title bar and inner window :/
    { reaper.ImGui_StyleVar_WindowRounding(), 7 },
    { reaper.ImGui_StyleVar_WindowPadding(), 10, 10 },
    { reaper.ImGui_StyleVar_WindowBorderSize(), 1 },
    { reaper.ImGui_StyleVar_WindowTitleAlign(), 0.5, 0.5 },
    { reaper.ImGui_StyleVar_FrameBorderSize(), 0 },
    { reaper.ImGui_StyleVar_FrameRounding(), 3 },
    { reaper.ImGui_StyleVar_ScrollbarSize(), 12 },
    { reaper.ImGui_StyleVar_ScrollbarRounding(), 12 },
    { reaper.ImGui_StyleVar_CellPadding(), 3, 5 },
    { reaper.ImGui_StyleVar_ChildRounding(), 3 },
}

function Button(txt, wIn, hIn)
    if hIn == nil then
        hIn = 20
    end
    local ret = false
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), 0xffffff00)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 1)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 0, 0)
    if reaper.ImGui_Button(ctx, txt, wIn, hIn) then
        ret = true
    end
    local w = reaper.ImGui_GetItemRectSize(ctx)
    local x, y = reaper.ImGui_GetItemRectMin(ctx)
    local margin = 2
    w = w - margin * 2
    x = x + margin
    reaper.ImGui_DrawList_AddLine(draw_list, x, y, x + w, y, 0xffffff15, 1)
    reaper.ImGui_PopStyleVar(ctx, 2)
    reaper.ImGui_PopStyleColor(ctx)
    return ret
end

function ArrowButton(wIn, hIn, up, disabled)
    local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
    local btn_name = "##up"
    if not up then btn_name = "##down" end
    local ret = Button(btn_name, wIn, hIn)
    local color = 0xffffffcc
    if disabled then
        color = 0xffffff33
    end
    x = x + 15
    if up then
        y = y + 14
        reaper.ImGui_DrawList_AddTriangleFilled(draw_list, x, y, x - 10, y, x - 5, y - 8, color)
    else
        y = y + 6
        reaper.ImGui_DrawList_AddTriangleFilled(draw_list, x, y, x - 5, y + 8, x - 10, y, color)
    end
    return ret
end

function DeleteButton(name, wIn, hIn)
    if wIn == nil then
        wIn = 20
    end
    if hIn == nil then
        hIn = 20
    end
    local ret = Button(name, wIn, hIn)
    local w = reaper.ImGui_GetItemRectSize(ctx)
    local x, y = reaper.ImGui_GetItemRectMin(ctx)
    x = x + w / 2
    y = y + w / 2
    local size = 4
    reaper.ImGui_DrawList_AddLine(draw_list, x - size, y - size, x + size, y + size, 0xffffffcc, 2)
    reaper.ImGui_DrawList_AddLine(draw_list, x - size, y + size, x + size, y - size, 0xffffffcc, 2)
    return ret
end

function ValidateName(name)
    local black_list = "[^%w _%-.]"
    name = string.gsub(name, black_list, "")
    --remove leading/trailing spaces and '.'
    local matched = false
    local count
    repeat
        matched = false
        name, count = string.gsub(name, "^%s+", "")
        if count > 0 then
            matched = true
        end
        name, count = string.gsub(name, "%s+$", "")
        if count > 0 then
            matched = true
        end
        name, count = string.gsub(name, "^%.+", "")
        if count > 0 then
            matched = true
        end
        name, count = string.gsub(name, "%.+$", "")
        if count > 0 then
            matched = true
        end
    until not matched
    if #name == 0 then
        name = "Invalid"
    end
    for _, file in ipairs(files) do
        while string.lower(file.name) == string.lower(name) do
            name = name .. "2"
        end
    end
    return name
end

--returns nil if not opened / canceled, false if waiting for action, true if got action
function ActionPopup(id, section_id)
    local popup_name = "Action##" .. id
    local action, action_text
    if action_popup_requested then
        action_popup_requested = false
        action_popup_opened = true
        reaper.PromptForAction(1, 0, section_id)
        reaper.ImGui_OpenPopup(ctx, popup_name)
    end
    if not action_popup_opened then return nil end
    local got_action = false ---@type boolean | nil
    reaper.ImGui_SetNextWindowPos(ctx, center[1], center[2], reaper.ImGui_Cond_Appearing(), 0.5, 0.5)
    if reaper.ImGui_BeginPopupModal(ctx, popup_name, nil, popup_flags) then
        local ret = reaper.PromptForAction(0, 0, section_id)
        if ret > 0 then
            action = ret
            action_text = reaper.CF_GetCommandText(section_id, ret)
            got_action = true
            action_popup_opened = false
            reaper.ImGui_CloseCurrentPopup(ctx)
            reaper.PromptForAction(-1, 0, section_id)
        end
        reaper.ImGui_Text(ctx, "Pick an action in the action list")
        MoveCursor(0, 7)
        if ret == -1 or Button("Cancel", -FLT_MIN) then
            action_popup_opened = false
            reaper.ImGui_CloseCurrentPopup(ctx)
            reaper.PromptForAction(-1, 0, section_id)
            got_action = nil
        end
        reaper.ImGui_EndPopup(ctx)
        return got_action, action, action_text
    end
end

--returns nil if not opened, false if waiting for input, true if got input
function KeyPopup(id, own_index)
    local gfx_name = "WaitingForKey"
    local popup_name = "Keyboard" .. id
    local key, key_text, cmd, shift, alt, ctrl
    if key_popup_requested then
        key_popup_requested = false
        key_popup_opened = true
        gfx.init(gfx_name, 0, 0, 0, 0, 0)
        key_hwnd = reaper.JS_Window_Find(gfx_name, true)
        reaper.JS_Window_SetOpacity(key_hwnd, "ALPHA", 0)
        reaper.ImGui_OpenPopup(ctx, popup_name)
    end
    if not key_popup_opened then return nil end
    local got_input = false
    reaper.ImGui_SetNextWindowPos(ctx, center[1], center[2], reaper.ImGui_Cond_Appearing(), 0.5, 0.5)
    if reaper.ImGui_BeginPopupModal(ctx, popup_name, nil, popup_flags) then
        if reaper.JS_Window_GetFocus() ~= key_hwnd then
            gfx.quit()
            reaper.ImGui_CloseCurrentPopup(ctx)
            key_popup_opened = false
        end
        local getchar = gfx.getchar()
        if getchar > 0 then
            key = getchar
            local cap = gfx.mouse_cap
            key_text = ToChar(getchar, cap)
            cmd = cap & 4 == 4
            shift = cap & 8 == 8
            alt = cap & 16 == 16
            ctrl = cap & 32 == 32
            gfx.quit()
            reaper.ImGui_CloseCurrentPopup(ctx)
            key_popup_opened = false
            got_input = true
        elseif getchar == -1 then
            gfx.quit()
            reaper.ImGui_CloseCurrentPopup(ctx)
            key_popup_opened = false
        end
        local text = "Press key(s)"
        local text_size = reaper.ImGui_CalcTextSize(ctx, text)
        local avail_x = reaper.ImGui_GetContentRegionAvail(ctx)
        MoveCursor(avail_x / 2 - text_size / 2, 0)
        reaper.ImGui_Text(ctx, text)
        MoveCursor(0, 7)
        if Button("Cancel", 120, 20) then
            gfx.quit()
            reaper.ImGui_CloseCurrentPopup(ctx)
            key_popup_opened = false
        end
        reaper.ImGui_EndPopup(ctx)
        if got_input then
            local duplicate = false
            local duplicate_name = ""
            for j, action in ipairs(files[cur_file_idx].actions) do
                -- don't check existing action when updating its key
                if own_index == nil or (own_index ~= nil and own_index ~= j) then
                    if math.floor(action.key) == math.floor(key) and action.shift == shift and action.ctrl == ctrl and
                        action.alt == alt and action.cmd == cmd then
                        duplicate = true
                        duplicate_name = action.action_text
                    end
                end
            end
            if duplicate then
                reaper.ShowMessageBox("Key is used by " .. duplicate_name .. "\nPlease pick another one",
                    "Key is already in use"
                    , 0)
                key_popup_requested = true
                return false
            end
            return true, key, key_text, cmd, shift, alt, ctrl
        else return false end
    end
end

function SetDirty(file)
    table.insert(dirty, file)
    last_dirty_name = file.name
end

function ToChar(int, cap)
    local os = reaper.GetOS()
    local is_osx = os == "OSX32" or os == "OSX64" or os == "macOS-arm64"
    local cmd_txt = "Cmd "
    local ctrl_txt = "Ctrl "
    local cmd, ctrl, alt, shift
    if not is_osx then
        cmd_txt = "Ctrl "
        ctrl_txt = "Win "
    end
    local function mods(ignoreshift)
        local ret = ""
        if cmd then ret = cmd_txt end
        if ctrl then ret = ret .. ctrl_txt end
        if alt then ret = ret .. "Alt " end
        if not ignoreshift and shift then ret = ret .. "Shift " end
        return ret
    end

    local keys = {
        [27] = "Esc",
        [32] = "Space",
        [8] = "BckSpace",
        [9] = "Tab",
        [1752132965] = "Home",
        [6647396] = "End",
        [1885824110] = "PgDwn",
        [1885828464] = "PgUp",
        [6909555] = "Ins",
        [6579564] = "Del",
        [13] = "Ret",
        [30064] = "Up",
        [1685026670] = "Down",
        [1818584692] = "Left",
        [1919379572] = "Right",
        [26161] = "F1",
        [26162] = "F2",
        [26163] = "F3",
        [26164] = "F4",
        [26165] = "F5",
        [26166] = "F6",
        [26167] = "F7",
        [26168] = "F8",
        [26169] = "F9",
        [6697264] = "F10",
        [6697265] = "F11",
        [6697266] = "F12"
    }
    if int == 0 then return nil end
    cmd = cap & 4 == 4
    shift = cap & 8 == 8
    alt = cap & 16 == 16
    ctrl = cap & 32 == 32
    if (cmd or ctrl) and int >= 1 and int <= 26 then
        int = int + 96 - 32
        return mods(false) .. utf8.char(int)
    elseif cmd and alt and int >= 257 and int <= 282 then
        int = int - 160 - 32
        return mods(false) .. utf8.char(int)
    elseif alt and int >= 321 and int <= 346 then
        int = int - 256
        return mods(false) .. utf8.char(int)
    elseif keys[int] ~= nil then
        return mods(false) .. keys[int]
    elseif int >= 33 and int <= 255 then
        return mods(true) .. utf8.char(int)
    else
        return mods(false) .. utf8.char(int)
    end
end

function MoveCursor(x, y)
    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + x)
    reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) + y)
end

function ToBool(str)
    if str == "true" then return true else return false end
end

function ToCap(shift, cmd, ctrl, alt)
    local ret = 0
    if cmd then ret = ret + 4 end
    if shift then ret = ret + 8 end
    if alt then ret = ret + 16 end
    if ctrl then ret = ret + 32 end
    return ret
end

function Load()
    local function sectionId(section_str)
        if section_str == "MAIN" then return 1
        elseif section_str == "MALT" then return 2
        elseif section_str == "MIDI" then return 3
        elseif section_str == "EVNT" then return 4
        elseif section_str == "MEXP" then return 5 end
    end

    local function commandPat(section_str)
        if section_str == "MAIN" then return "reaper%.Main_OnCommand%((%d+),0%)"
        elseif section_str == "MALT" then return "reaper%.Main_OnCommand%((%d+),0%)"
        elseif section_str == "MIDI" then return "reaper%.MIDIEditor_OnCommand%(midi_editor,(%d+)%)"
        elseif section_str == "EVNT" then return "reaper%.MIDIEditor_OnCommand%(midi_editor,(%d+)%)"
        elseif section_str == "MEXP" then return "reaper%.JS_Window_OnCommand%(explorerHWND,(%d+)%)" end
    end

    dirty = {}
    files = {}
    -- create directory if it doesn't exist
    reaper.RecursiveCreateDirectory(script_path, 0)
    -- force empty cache
    reaper.EnumerateFiles(script_path, -1)
    local index = 0
    while true do
        local ret = reaper.EnumerateFiles(script_path, index)
        if ret == nil then break end
        if string.sub(ret, 0, #prefix) == prefix then
            table.insert(files, { name = string.sub(ret, #prefix + 1, #ret - 4), path = ret })
        end
        index = index + 1
    end
    for _, file in ipairs(files) do
        local file_io, err = io.open(script_path .. file.path, 'r')
        if file_io == nil then
            reaper.ShowMessageBox(err, "Error loading file")
        else
            local txt = file_io:read("*all")
            file_io:close()
            local section_pat = "--SEC:(%w%w%w%w)"
            local section_str = string.match(txt, section_pat)
            file.section = sectionId(section_str)
            local pat = "if char == (%d+) and shift == (%S+) and cmd == (%S+) and ctrl == (%S+) and alt == (%S+) then%s*"
            pat = pat .. commandPat(section_str)
            pat = pat .. "%s*exit = (%S+)"
            local names_pat = 'gfx.drawstr%("%[.-%] (.-)"%)'
            local names = {}
            for name in string.gmatch(txt, names_pat) do
                table.insert(names, name)
            end
            file.actions = {}
            for key_id, shift, cmd, ctrl, alt, action_id, exit in string.gmatch(txt, pat) do
                shift = ToBool(shift)
                cmd = ToBool(cmd)
                ctrl = ToBool(ctrl)
                alt = ToBool(alt)
                exit = ToBool(exit)
                local new = {
                    key = key_id,
                    action = action_id,
                    shift = shift,
                    cmd = cmd,
                    ctrl = ctrl,
                    alt = alt,
                    exit = exit,
                    key_text = ToChar(tonumber(key_id), ToCap(shift, cmd, ctrl, alt)),
                    action_text = reaper.CF_GetCommandText(sections[file.section].id, action_id),
                    display_name = names[#file.actions + 1]
                }
                table.insert(file.actions, new)
            end
            local show_after_pat = "show_after = (%d%.%d)"
            file.show_after = string.match(txt, show_after_pat)
            local path = script_path .. file.path
            -- get command id by adding it
            -- not efficient, but it feels overkill to include a SHA1 library just to compute the command id
            file.command_id = reaper.AddRemoveReaScript(true, sections[file.section].id, path, true)
        end
    end
    if first_load and #files > 0 then
        cur_file_idx = 1
        first_load = false
    elseif #files > 0 and last_dirty_name ~= "" then
        for i, file in ipairs(files) do
            if file.name == last_dirty_name then
                cur_file_idx = i
            end
        end
    else
        cur_file_idx = 0
    end
    last_dirty_name = ""
end

function Save()
    local function cond(action)
        return "char == " ..
            math.floor(action.key) ..
            " and shift == " ..
            tostring(action.shift) ..
            " and cmd == " ..
            tostring(action.cmd) ..
            " and ctrl == " ..
            tostring(action.ctrl) ..
            " and alt == " ..
            tostring(action.alt)
    end

    local function mainCommands(actions)
        local result = ""
        for _, action in ipairs(actions) do
            result = result .. cond(action) .. [[ then
      reaper.Main_OnCommand(]] .. tostring(action.action) .. [[,0)
      exit = ]] .. tostring(action.exit) .. [[

      time_start = reaper.time_precise()
    elseif ]]
        end
        return result
    end

    local function midiEditorCommands(actions)
        local result = ""
        for _, action in ipairs(actions) do
            result = result .. cond(action) .. [[ then
      reaper.MIDIEditor_OnCommand(midi_editor,]] .. tostring(action.action) .. [[)
      exit = ]] .. tostring(action.exit) .. [[

      time_start = reaper.time_precise()
    elseif ]]
        end
        return result
    end

    local function mediaExplorerCommands(actions)
        local result = ""
        for _, action in ipairs(actions) do
            result = result .. cond(action) .. [[ then
      reaper.JS_Window_OnCommand(explorerHWND,]] .. tostring(action.action) .. [[)
      exit = ]] .. tostring(action.exit) .. [[

      time_start = reaper.time_precise()
    elseif ]]
        end
        return result
    end

    local function commands(file)
        local section = sections[file.section]
        if section.name == "Main" or section.name == "Main (alt recording)" then
            return mainCommands(file.actions)
        elseif section.name == "MIDI Editor" or section.name == "MIDI Event List Editor" then
            return midiEditorCommands(file.actions)
        elseif section.name == "Media Explorer" then
            return mediaExplorerCommands(file.actions)
        else
            return ""
        end
    end

    local function section_setup(file)
        local section = sections[file.section]
        if section.name == "Main" then
            return "\n--SEC:MAIN\n"
        elseif section.name == "MIDI Editor" then
            return "\n--SEC:MIDI\n  midi_editor = reaper.MIDIEditor_GetActive()\n"
        elseif section.name == "Media Explorer" then
            return "\n--SEC:MEXP\n  explorerHWND = reaper.OpenMediaExplorer('', false)\n"
        elseif section.name == "Main (alt recording)" then
            return "\n--SEC:MALT\n"
        elseif section.name == "MIDI Event List Editor" then
            return "\n--SEC:EVNT\n"
        end
    end

    for i, file in ipairs(removed) do
        local path = script_path .. prefix .. file.name .. ".lua"
        local commit = i == #removed
        reaper.AddRemoveReaScript(false, sections[file.section].id, path, commit)
        os.remove(path)
    end
    removed = {}
    for _, file in ipairs(dirty) do
        local longest = ""
        for _, action in ipairs(file.actions) do
            action.hint = string.format("[%s] %s", action.key_text, action.display_name)
            -- replace " with ' to not break code generation
            action.hint = string.gsub(action.hint, '"', "'")
            if #action.hint > #longest then
                longest = action.hint
            end
        end
        local window_name = "KeySequenceListener" .. file.name
        local result = [[
  -- This file is autogenerated, do not modify
  if reaper.JS_Window_Find == nil then
    reaper.ShowMessageBox("This script requires js_ReaScriptAPI", "Missing dependency", 0)
    return
  end
  show_after = ]] .. string.format("%.1f", file.show_after) .. [[
  
  time_start = reaper.time_precise()
  margin = 10
  shown = false
  x, y = reaper.GetMousePosition()
  gfx.setfont(1, "sans-serif", 15)
  gfx.init("]] .. window_name .. [[", 0, 0, 0, 0, 0)
  hwnd = reaper.JS_Window_Find("]] .. window_name .. [[", false)
  reaper.JS_Window_SetStyle(hwnd, "POPUP")
  reaper.JS_Window_SetOpacity(hwnd,"ALPHA", 0)
  exit = false ]] .. section_setup(file) .. [[
  function main()
    gfx.update()
    if not shown and reaper.time_precise() - time_start > show_after then
      reaper.JS_Window_SetOpacity(hwnd,"ALPHA", 1)
      w = gfx.measurestr("]] .. longest .. [[")
      --resize window
      gfx.init("", margin * 2 + w, margin * 2 + gfx.texth * ]] .. #file.actions .. [[, 0, x, y)
      shown = true
    end
    if shown then
      gfx.set(0.15, 0.15, 0.15)
      gfx.rect(0, 0, gfx.w, gfx.h, true)
      gfx.set(1,1,1)
      gfx.x = margin
      gfx.y = margin
    ]]
        for _, action in ipairs(file.actions) do
            result = string.format('%s  gfx.drawstr("%s")\n', result, action.hint)
            result = result .. [[
      gfx.y = gfx.y + gfx.texth
      gfx.x = margin
    ]]
        end
        result = result .. [[end
    cap = gfx.mouse_cap
    cmd = cap & 4 == 4
    shift = cap & 8 == 8
    alt = cap & 16 == 16
    ctrl = cap & 32 == 32
    char = gfx.getchar()
    -- 'var == true' does smell, but it's easier to parse
    if ]] .. commands(file) .. [[ char > 0 then exit = true end
    --stop on unfocus
    if reaper.JS_Window_GetFocus() ~= hwnd then exit = true end
    if exit then gfx.quit() return end
    --stop deferring if window is closed
    if char ~= -1 then reaper.defer(main) end
  end
  
  main()
]]
        local path = script_path .. prefix .. file.name .. ".lua"
        local file_io, err = io.open(path, 'w')
        if file_io == nil then
            reaper.ShowMessageBox(err, "Error loading file")
        else
            file_io, err = file_io:write(result)
            if file_io == nil then
                reaper.ShowMessageBox(err, "Error loading file")
            else
                file_io:close()
                reaper.AddRemoveReaScript(true, sections[file.section].id, path, true)
            end
        end
    end
    dirty = {}
end

function Frame()
    local wants_to_be_removed_id = nil
    local avail_x, avail_y, x, y
    local header_h = 23
    draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    center = { reaper.ImGui_Viewport_GetCenter(reaper.ImGui_GetWindowViewport(ctx)) }
    reaper.ImGui_SetNextFrameWantCaptureKeyboard(ctx, true)

    do
        avail_x = reaper.ImGui_GetContentRegionAvail(ctx)
        if reaper.ImGui_BeginChild(ctx, "L", avail_x * 0.25) then
            avail_x, avail_y = reaper.ImGui_GetContentRegionAvail(ctx)
            x, y = reaper.ImGui_GetCursorScreenPos(ctx)
            reaper.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + avail_x, y + avail_y - 35, 0xffffff14, 3, rect_flags)
            reaper.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + avail_x, y + header_h, 0xffffff12, 3, rect_flags)
            MoveCursor(10, 5)
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_Alpha(), 0.6)
            reaper.ImGui_Text(ctx, "Sequences")
            reaper.ImGui_PopStyleVar(ctx)
            MoveCursor(0, 6)
            if reaper.ImGui_BeginListBox(ctx, "##listL", -FLT_MIN, -35) then
                reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 0, 7)
                for n, v in ipairs(files) do
                    local is_selected = cur_file_idx == n
                    avail_x = reaper.ImGui_GetContentRegionAvail(ctx)
                    x, y = reaper.ImGui_GetCursorScreenPos(ctx)
                    y = y - 3
                    local end_x = x + avail_x
                    if is_selected then
                        reaper.ImGui_DrawList_AddRectFilled(draw_list, x, y, end_x, y + 19, 0xffffff15, 3, rect_flags)
                    elseif reaper.ImGui_IsMouseHoveringRect(ctx, x, y, end_x, y + 19) then
                        reaper.ImGui_DrawList_AddRectFilled(draw_list, x, y, end_x, y + 19, 0xffffff06, 3, rect_flags)
                    end
                    MoveCursor(6, 0)
                    if reaper.ImGui_Selectable(ctx, v.name, is_selected) then
                        cur_file_idx = n
                    end
                    reaper.ImGui_SameLine(ctx)
                    avail_x = reaper.ImGui_GetContentRegionAvail(ctx)
                    local section = sections[v.section].short_name
                    local size = reaper.ImGui_CalcTextSize(ctx, section)
                    MoveCursor(avail_x - size - 6, 0)
                    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_Alpha(), 0.5)
                    reaper.ImGui_Text(ctx, section)
                    reaper.ImGui_PopStyleVar(ctx)
                end
                reaper.ImGui_PopStyleVar(ctx)
                reaper.ImGui_EndListBox(ctx)
            end
            MoveCursor(0, 5)
            x = reaper.ImGui_GetContentRegionAvail(ctx)
            if Button("Add", x / 2.1, 25) then
                new_seq_name = ""
                new_wants_focus = true
                reaper.ImGui_OpenPopup(ctx, "New Sequence")
            end
            reaper.ImGui_SameLine(ctx)

            -- current_idx can change in button so we temp var it
            local began_disabled = false
            if cur_file_idx <= 0 then
                began_disabled = true
                reaper.ImGui_BeginDisabled(ctx, true)
            end
            if Button("Remove", -FLT_MIN, 25) and
                reaper.ShowMessageBox("Are you sure you want to delete " .. files[cur_file_idx].name, "Confirmation", 1)
                == 1 then
                wants_to_be_removed_id = cur_file_idx
            end
            if began_disabled then
                reaper.ImGui_EndDisabled(ctx)
            end
            reaper.ImGui_SetNextWindowPos(ctx, center[1], center[2], reaper.ImGui_Cond_Appearing(), 0.5, 0.5)
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 10, 10)
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 10, 8)
            if reaper.ImGui_BeginPopupModal(ctx, "New Sequence", nil, popup_flags) then
                MoveCursor(0, 15)
                reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_Alpha(), 0.7)
                reaper.ImGui_Text(ctx, "Name")
                reaper.ImGui_PopStyleVar(ctx)
                reaper.ImGui_SameLine(ctx)
                MoveCursor(8, -8)
                if new_wants_focus then
                    reaper.ImGui_SetKeyboardFocusHere(ctx)
                    new_wants_focus = false
                end
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0x333333ff)
                _, new_seq_name = reaper.ImGui_InputText(ctx, "##", new_seq_name)
                MoveCursor(0, 15)
                reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_Alpha(), 0.7)
                reaper.ImGui_Text(ctx, "Section")
                reaper.ImGui_PopStyleVar(ctx)
                reaper.ImGui_SameLine(ctx)
                MoveCursor(0, -8)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), 0xffffff20)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), 0xffffff30)
                if reaper.ImGui_BeginCombo(ctx, "##newSection", sections[selected_section].name) then
                    for i, section in ipairs(sections) do
                        if reaper.ImGui_Selectable(ctx, section.name, i == selected_section) then
                            selected_section = i
                        end
                    end
                    reaper.ImGui_EndCombo(ctx)
                end
                reaper.ImGui_PopStyleColor(ctx, 3)
                MoveCursor(0, 15)

                avail_x = reaper.ImGui_GetContentRegionAvail(ctx)
                if Button("Cancel", avail_x * 0.5) then
                    reaper.ImGui_CloseCurrentPopup(ctx)
                end
                reaper.ImGui_SameLine(ctx)
                if #new_seq_name == 0 then
                    reaper.ImGui_BeginDisabled(ctx, true)
                end
                local enter_pressed = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadEnter())
                enter_pressed = enter_pressed or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter())
                if Button("Ok", -FLT_MIN) or (#new_seq_name ~= 0 and enter_pressed) then
                    new_seq_name = ValidateName(new_seq_name)
                    local new = { name = new_seq_name, actions = {}, section = selected_section, show_after = 1.0 }
                    table.insert(files, new)
                    SetDirty(new)
                    reaper.ImGui_CloseCurrentPopup(ctx)
                end
                if #new_seq_name == 0 then
                    reaper.ImGui_EndDisabled(ctx)
                end
                reaper.ImGui_EndPopup(ctx)
            end
            reaper.ImGui_PopStyleVar(ctx, 2)
            reaper.ImGui_EndChild(ctx)
        end
    end
    reaper.ImGui_SameLine(ctx)

    do
        avail_x, avail_y = reaper.ImGui_GetContentRegionAvail(ctx)
        if cur_file_idx ~= 0 and reaper.ImGui_BeginChild(ctx, "R", avail_x, avail_y, 0) then
            avail_x = reaper.ImGui_GetContentRegionAvail(ctx)
            x, y = reaper.ImGui_GetCursorScreenPos(ctx)
            local end_x = x + avail_x
            reaper.ImGui_DrawList_AddRectFilled(draw_list, x, y, end_x, y + header_h * 1.4, 0xffffff14, 3, rect_flags)
            MoveCursor(6, 10)
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_Alpha(), 0.5)
            reaper.ImGui_Text(ctx, "Show hint after")
            reaper.ImGui_PopStyleVar(ctx)
            reaper.ImGui_SameLine(ctx)
            MoveCursor(-4, -3)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0xffffff2f)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), 0xffffff4f)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(), 0xffffff5f)
            reaper.ImGui_PushItemWidth(ctx, 30)
            local ret, val = reaper.ImGui_DragDouble(ctx, "##show_after", files[cur_file_idx].show_after, .1, 0, 5,
                "%.1fs")
            reaper.ImGui_PopItemWidth(ctx)
            reaper.ImGui_PopStyleColor(ctx, 3)
            if ret then
                files[cur_file_idx].show_after = val
                did_change_show_after = true
            end
            --only register change on mouse up or on finishing keyboard editing
            if not reaper.ImGui_IsItemActive(ctx) and did_change_show_after then
                did_change_show_after = false
                SetDirty(files[cur_file_idx])
            end
            reaper.ImGui_SameLine(ctx)
            avail_x = reaper.ImGui_GetContentRegionAvail(ctx)
            MoveCursor(avail_x - 190, -3)
            if files[cur_file_idx].command_id ~= nil then
                local section_id = sections[files[cur_file_idx].section].id
                local command_id = files[cur_file_idx].command_id
                local ret_desc, shortcut = reaper.JS_Actions_GetShortcutDesc(section_id, command_id, 0)
                if ret_desc then
                    if Button(shortcut, 160) then
                        reaper.JS_Actions_DoShortcutDialog(section_id, command_id, 0)
                    end
                    reaper.ImGui_SameLine(ctx)
                    MoveCursor(-3, -3)
                    if DeleteButton("##deleteShortcut") then
                        reaper.JS_Actions_DeleteShortcut(section_id, command_id, 0)
                    end
                else
                    if Button("Set sequence shortcut", 180) then
                        reaper.JS_Actions_DoShortcutDialog(section_id, command_id, 0)
                    end
                end
            end
            MoveCursor(0, 10)
            avail_x, avail_y = reaper.ImGui_GetContentRegionAvail(ctx)
            x, y = reaper.ImGui_GetCursorScreenPos(ctx)
            local t = table_scroll / header_h
            local action_count = #files[cur_file_idx].actions
            local header_a = math.min(1, math.max(0, 0.05 * (1 - t) + 0 * t))
            local header_col = reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, header_a)
            local padding_table = 0
            if action_count > 0 then
                padding_table = 7
            end

            local table_h = math.min(avail_y - 36, action_count * 30 + header_h + padding_table)
            local table_flags = reaper.ImGui_TableFlags_RowBg() | reaper.ImGui_TableFlags_ScrollY()
            local has_actions = #files[cur_file_idx].actions > 0
            if has_actions and reaper.ImGui_BeginTable(ctx, "table", 3, table_flags, avail_x, table_h) then
                reaper.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + avail_x, y + table_h, 0xffffff14, 3, rect_flags)
                reaper.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + avail_x, y + header_h, header_col, 3, rect_flags)
                table_scroll = reaper.ImGui_GetScrollY(ctx)
                reaper.ImGui_TableSetupColumn(ctx, "", reaper.ImGui_TableColumnFlags_WidthFixed(), 75)
                reaper.ImGui_TableSetupColumn(ctx, " Key", reaper.ImGui_TableColumnFlags_WidthFixed(), 160)
                reaper.ImGui_TableSetupColumn(ctx, " Action", reaper.ImGui_TableColumnFlags_WidthStretch())
                reaper.ImGui_TableNextRow(ctx)
                reaper.ImGui_TableNextColumn(ctx)
                reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_Alpha(), 0.6)
                reaper.ImGui_TableNextColumn(ctx)
                MoveCursor(69, 0)
                reaper.ImGui_Text(ctx, "Key")
                reaper.ImGui_TableNextColumn(ctx)
                MoveCursor(6, 0)
                reaper.ImGui_Text(ctx, "Action")
                reaper.ImGui_PopStyleVar(ctx)
                if action_count > 0 then
                    --don't know why that works but next line pads the top of first row
                    reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx))
                end
                reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 6, 4)
                local cur_file_actions = files[cur_file_idx].actions
                for i, action in ipairs(cur_file_actions) do
                    reaper.ImGui_PushID(ctx, tostring(i))
                    reaper.ImGui_TableNextRow(ctx)
                    reaper.ImGui_TableNextColumn(ctx)
                    MoveCursor(6, 0)
                    local up_disabled = i == 1
                    local down_disabled = i == #files[cur_file_idx].actions
                    if down_disabled then
                        reaper.ImGui_BeginDisabled(ctx)
                    end
                    if ArrowButton(20, 20, false, down_disabled) then
                        cur_file_actions[i], cur_file_actions[i + 1] = cur_file_actions[i + 1], cur_file_actions[i]
                        SetDirty(files[cur_file_idx])
                    end
                    if down_disabled then
                        reaper.ImGui_EndDisabled(ctx)
                    end
                    reaper.ImGui_SameLine(ctx)
                    MoveCursor(-3, 0)
                    if up_disabled then
                        reaper.ImGui_BeginDisabled(ctx)
                    end
                    if ArrowButton(20, 20, true, up_disabled) then
                        cur_file_actions[i - 1], cur_file_actions[i] = cur_file_actions[i], cur_file_actions[i - 1]
                        SetDirty(files[cur_file_idx])
                    end
                    if up_disabled then
                        reaper.ImGui_EndDisabled(ctx)
                    end
                    reaper.ImGui_SameLine(ctx)
                    MoveCursor(-3, 0)
                    if DeleteButton("##deleteAction") then
                        table.remove(files[cur_file_idx].actions, i)
                        SetDirty(files[cur_file_idx])
                    end
                    reaper.ImGui_TableNextColumn(ctx)
                    if Button(action.key_text, -FLT_MIN) then
                        key_popup_requested = true
                        waiting_for_key = i
                    end
                    if waiting_for_key == i then
                        local ret, key, key_text, cmd, shift, alt, ctrl = KeyPopup("##" .. tostring(i), i)
                        if ret == nil then
                            waiting_for_key = -1
                        elseif ret then
                            action.key = key
                            action.key_text = key_text
                            action.cmd = cmd
                            action.shift = shift
                            action.alt = alt
                            action.ctrl = ctrl
                            waiting_for_key = -1
                            SetDirty(files[cur_file_idx])
                        end
                    end

                    reaper.ImGui_TableNextColumn(ctx)
                    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ButtonTextAlign(), 0, 0.5)
                    local btn_text = action.display_name
                    if not action.exit then
                        btn_text = "  " .. btn_text
                    end
                    if action.display_name ~= action.action_text then
                        btn_text = btn_text .. " (" .. action.action_text .. ")"
                    end
                    if Button("  " .. btn_text, -6) then
                        new_display_name = action.display_name
                        new_exit = action.exit
                        edit_wants_focus = true
                        reaper.ImGui_OpenPopup(ctx, "Edit action##" .. tostring(i))
                    end
                    if not action.exit then
                        local x, y = reaper.ImGui_GetItemRectMin(ctx)
                        reaper.ImGui_DrawList_AddCircleFilled(draw_list, x + 9, y + 10, 3, 0xffffffaa, 10)
                    end
                    reaper.ImGui_PopStyleVar(ctx)

                    reaper.ImGui_SetNextWindowPos(ctx, center[1], center[2], reaper.ImGui_Cond_Appearing(), 0.5, 0.5)
                    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 10, 10)
                    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 10, 8)
                    if reaper.ImGui_BeginPopupModal(ctx, "Edit action##" .. tostring(i), nil, popup_flags) then
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0x444444ff)
                        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_Alpha(), 0.7)
                        MoveCursor(3, 16)
                        reaper.ImGui_Text(ctx, "Display Name")
                        reaper.ImGui_PopStyleVar(ctx)
                        reaper.ImGui_SameLine(ctx)
                        MoveCursor(6, -6)
                        if edit_wants_focus then
                            reaper.ImGui_SetKeyboardFocusHere(ctx)
                            edit_wants_focus = false
                        end
                        reaper.ImGui_PushItemWidth(ctx, 300)
                        _, new_display_name = reaper.ImGui_InputText(ctx, "##actionname", new_display_name)
                        reaper.ImGui_PopItemWidth(ctx)
                        reaper.ImGui_SameLine(ctx)
                        MoveCursor(-2, -6)
                        local default_name_disabled = new_display_name == action.action_text
                        if default_name_disabled then
                            reaper.ImGui_BeginDisabled(ctx)
                        end
                        if DeleteButton("##defaultname", 29, 29) then
                            new_display_name = action.action_text
                        end
                        if default_name_disabled then
                            reaper.ImGui_EndDisabled(ctx)
                        end
                        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_Alpha(), 0.7)
                        MoveCursor(3, 0)
                        reaper.ImGui_Text(ctx, "Keep Open")
                        reaper.ImGui_PopStyleVar(ctx)
                        reaper.ImGui_SameLine(ctx)
                        MoveCursor(21, -6)
                        _, new_exit = reaper.ImGui_Checkbox(ctx, "##keepopen", not new_exit)
                        MoveCursor(0, 10)
                        new_exit = not new_exit
                        if Button("Change Action", -FLT_MIN, 30) then
                            if new_display_name == "" then
                                new_display_name = action.action_text
                            end
                            action.display_name = new_display_name
                            action.exit = new_exit
                            SetDirty(files[cur_file_idx])
                            reaper.ImGui_CloseCurrentPopup(ctx)
                            action_popup_requested = true
                            waiting_for_action = i
                        end
                        reaper.ImGui_PopStyleColor(ctx)
                        MoveCursor(0, 6)
                        local avail_x = reaper.ImGui_GetContentRegionAvail(ctx)
                        if Button("Cancel##edit", avail_x / 2.1) then
                            reaper.ImGui_CloseCurrentPopup(ctx)
                        end
                        reaper.ImGui_SameLine(ctx)
                        local enter_pressed = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadEnter())
                        enter_pressed = enter_pressed or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter())
                        if Button("Ok##edit", -FLT_MIN) or enter_pressed then
                            if new_display_name == "" then
                                new_display_name = action.action_text
                            end
                            action.display_name = new_display_name
                            action.exit = new_exit
                            SetDirty(files[cur_file_idx])
                            reaper.ImGui_CloseCurrentPopup(ctx)
                        end
                        reaper.ImGui_EndPopup(ctx)
                    end
                    reaper.ImGui_PopStyleVar(ctx, 2)

                    if waiting_for_action == i then
                        local ret, new_action, new_action_text = ActionPopup(tostring(i),
                            sections[files[cur_file_idx].section].id)
                        if ret == nil then
                            waiting_for_action = -1
                        elseif ret then
                            action.action = new_action
                            action.action_text = new_action_text
                            SetDirty(files[cur_file_idx])
                            waiting_for_action = -1
                        end
                    end
                    reaper.ImGui_PopID(ctx)
                end
                reaper.ImGui_PopStyleVar(ctx)
                reaper.ImGui_EndTable(ctx)
            end
            MoveCursor(0, 6)
            if Button("Add Shortcut", -FLT_MIN, 25) then
                adding = { key_text = "...", action_text = "...", action = -1, key = -1, exit = true,
                    display_name = "..." }
                key_popup_requested = true
                waiting_for_key = 0
            end
            if waiting_for_key == 0 then
                local ret, key, key_text, cmd, shift, alt, ctrl = KeyPopup("##new")
                if ret == nil then
                    waiting_for_key = -1
                elseif ret then
                    adding.key = key
                    adding.key_text = key_text
                    adding.cmd = cmd
                    adding.shift = shift
                    adding.alt = alt
                    adding.ctrl = ctrl
                    waiting_for_key = -1
                    action_popup_requested = true
                    waiting_for_action = 0
                end
            end
            if waiting_for_action == 0 then
                local ret, action, action_text = ActionPopup("new", sections[files[cur_file_idx].section].id)
                if ret == nil then
                    waiting_for_action = -1
                elseif ret then
                    adding.action = action
                    adding.action_text = action_text
                    adding.display_name = action_text
                    table.insert(files[cur_file_idx].actions, adding)
                    SetDirty(files[cur_file_idx])
                    waiting_for_action = -1
                end
            end
            reaper.ImGui_EndChild(ctx)
        end
    end
    if wants_to_be_removed_id ~= nil then
        local removed_file = table.remove(files, wants_to_be_removed_id)
        table.insert(removed, removed_file)
        if #files == 0 then
            last_dirty_name = ""
        elseif wants_to_be_removed_id > #files then
            last_dirty_name = files[#files].name
        else
            last_dirty_name = files[wants_to_be_removed_id].name
        end
    end
end

function Loop()
    local window_flags = reaper.ImGui_WindowFlags_NoCollapse()
    if #dirty > 0 or #removed > 0 then
        --Auto save so flags are not needed
        --(note that it -should- be possible to remove this, add the flag back, and get a correct "save on close" behavior)
        Save()
        Load()
        --window_flags = window_flags | reaper.ImGui_WindowFlags_UnsavedDocument()
    end
    if font_name ~= nil then
        reaper.ImGui_PushFont(ctx, font)
    end
    for _, color in pairs(colors) do
        reaper.ImGui_PushStyleColor(ctx, color[1], color[2])
    end
    for _, style in pairs(styles) do
        reaper.ImGui_PushStyleVar(ctx, style[1], style[2], style[3])
    end
    reaper.ImGui_SetNextWindowSize(ctx, 700, 300, reaper.ImGui_Cond_FirstUseEver())
    --title bar padding
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 10, 8)
    local visible, open = reaper.ImGui_Begin(ctx, window_title, true, window_flags)
    reaper.ImGui_PopStyleVar(ctx)
    if visible then
        Frame()
        reaper.ImGui_End(ctx)
    end
    if font_name ~= nil then
        reaper.ImGui_PopFont(ctx)
    end
    reaper.ImGui_PopStyleVar(ctx, #styles)
    reaper.ImGui_PopStyleColor(ctx, #colors)
    if open then
        reaper.defer(Loop)
    else
        --todo this shouldnt happen, if autosave stay, it can be safely removed
        if #dirty > 0 or #removed > 0 then
            local unsaved_msg = "You have unsaved changes, would you like to save before quitting?"
            local wants_save = reaper.ShowMessageBox(unsaved_msg, "Confirm", 4) == 6
            if wants_save then
                Save()
                Load()
            end
        end
        reaper.ImGui_DestroyContext(ctx)
    end
end

Load()
reaper.defer(Loop)
