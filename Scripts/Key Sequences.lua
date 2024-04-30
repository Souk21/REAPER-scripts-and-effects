--@author Souk21
--@description Key Sequences
--@about Create key sequence shortcuts
--@changelog
--   Upgrade to ReaImGui 0.9
--   Use ReaImGui shims to stay compatible through future ReaImGui releases
--@version 2.3
--@provides
--   [main] . > souk21_Key Sequences.lua

local font_name = "Verdana"
if reaper.CF_GetCommandText == nil or reaper.ImGui_GetBuiltinPath == nil or reaper.JS_Window_Find == nil then
    reaper.ShowMessageBox("This script requires SWS, ReaImGui (min 0.9) and js_ReaScriptAPI.", "Missing dependency", 0)
    return
end

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.9'

local script_path = reaper.GetResourcePath() .. "/Scripts/Souk21_sequences/"
local prefix = "souk21_sequences_"
local imgui_window_name = "Key Sequences"
local default_style_filename = "defaultStyle.data"
local ctx = ImGui.CreateContext(imgui_window_name)
local draw_list
local font
if font_name ~= nil then
    font = ImGui.CreateFont(font_name, 13)
    ImGui.Attach(ctx, font)
end
local FLT_MIN = ImGui.NumericLimits_Float()
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
local new_text = ""
local new_exit = false
local new_hide = false
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
local dragging
local move_request_old
local move_request_new
local preview_opened = false
local default_style = {
    background_color = 0x000000,
    foreground_color = 0xffffff,
    flash_color = 0xff5555,
    hover_color = 0xffaaaa,
    font = "Verdana",
    font_size = 13,
    padding = 20,
    desc_offset = 20,
    line_offset = 5,
    pos_mode = 0,       --0 follow mouse, 1 fixed position
    size_mode = 0,      --0 auto, 1 fixed size
    mouse_h_align = 0,  --0 left, 1 middle, 2 right
    mouse_v_align = 0,  --0 bottom, 1 middle, 2 top
    first_frame = true, --set to false by UI() after first frame
    shown = false,
}
local copied_style
local current_style = nil
local edit_flags = ImGui.WindowFlags_AlwaysAutoResize
local edit_frame_count = -1
local style_help_text = {
    ["None"] = "Press P to open/close preview...",
    ["PosMode"] = "Mouse: spawn at mouse. Fixed: spawn at a fixed position",
    ["MousePos"] = "Anchor for hints window",
    ["FixedPos"] = "Position where hints will spawn",
    ["SizeMode"] = "Auto: size is computed from layout. Fixed: size is fixed",
    ["FixedSize"] = "Size of the hints window",
    ["BG"] = "Background color",
    ["FG"] = "Text color",
    ["Flash"] = "Color on key down / click",
    ["Hover"] = "Color on mouse hover",
    ["Padding"] =
    "Space between window borders and text (In fixed size mode: space between top and left border and text)",
    ["DescOffset"] = "Horizontal space between shortcut key(s) and name",
    ["LineOffset"] = "Vertical space between lines",
    ["Font"] = "Font family, unknown font will result in default font being used",
    ["FontSize"] = "Font size",
}
local action_popup_requested = false
local action_popup_opened = false
-- -1: not waiting, 0: waiting during new action/key creation, n: waiting during action[n] key/action update/change
local waiting_for_key = -1
local waiting_for_action = -1
local rect_flags = ImGui.DrawFlags_RoundCornersAll
local popup_flags = ImGui.WindowFlags_NoMove | ImGui.WindowFlags_AlwaysAutoResize
local main_hwnd = nil

-- global colors/styles
local colors = {
    { ImGui.Col_WindowBg, 0x202123FF },
    { ImGui.Col_PopupBg, 0x202123FF },
    { ImGui.Col_TitleBgActive, 0x343434ff },
    { ImGui.Col_TitleBg, 0x242424ff },
    { ImGui.Col_Button, 0x565656ff },
    { ImGui.Col_ButtonHovered, 0x606060ff },
    { ImGui.Col_ButtonActive, 0x707070ff },
    { ImGui.Col_FrameBg, 0x00000000 },
    { ImGui.Col_FrameBgHovered, 0xffffff33 },
    { ImGui.Col_Header, 0xFFFFFF00 },
    { ImGui.Col_HeaderHovered, 0xFCFCFC00 },
    { ImGui.Col_HeaderActive, 0xFFFFFF00 },
    { ImGui.Col_ChildBg, 0x2D2D2D00 },
    { ImGui.Col_ScrollbarBg, 0xfff00000 },
    { ImGui.Col_TableRowBgAlt, 0x00000000 },
    { ImGui.Col_Text, 0xffffffcd },
    { ImGui.Col_ResizeGrip, 0xffffff33 },
    { ImGui.Col_ResizeGripHovered, 0xffffff44 },
    { ImGui.Col_Border, 0x606060ff },
}
local styles = {
    --window rounding causes a transparent line to show between title bar and inner window :/
    { ImGui.StyleVar_WindowRounding, 7 },
    { ImGui.StyleVar_WindowPadding, 10, 10 },
    { ImGui.StyleVar_WindowBorderSize, 1 },
    { ImGui.StyleVar_WindowTitleAlign, 0.5, 0.5 },
    { ImGui.StyleVar_FrameBorderSize, 0 },
    { ImGui.StyleVar_FrameRounding, 3 },
    { ImGui.StyleVar_ScrollbarSize, 12 },
    { ImGui.StyleVar_ScrollbarRounding, 12 },
    { ImGui.StyleVar_CellPadding, 3, 5 },
    { ImGui.StyleVar_ChildRounding, 3 },
}

function Move(t, old, new)
    table.insert(t, new, table.remove(t, old))
end

function StripComma(str)
    str = tostring(str)
    str = string.gsub(str, ",", "")
    return str
end

function SequencesToCSV()
    local result = "Sequence,Key,Text,Command,Hide,Keep Open\n"
    for _, sequence in ipairs(files) do
        for _, action in ipairs(sequence.actions) do
            if action.text ~= nil then
                result = result .. string.format("%s,,%s,,,\n",
                    StripComma(sequence.name),
                    StripComma(action.text)
                )
            else
                result = result .. string.format("%s,%s,%s,%s,%s,%s\n",
                    StripComma(sequence.name),
                    StripComma(action.key_text),
                    StripComma(action.display_name),
                    StripComma(action.action_text),
                    StripComma(action.hidden),
                    StripComma(not action.exit)
                )
            end
        end
    end
    return result
end

function Button(txt, wIn, hIn, alpha)
    if hIn == nil then
        hIn = 20
    end
    local ret = false
    ImGui.PushStyleColor(ctx, ImGui.Col_Border, 0xffffff00)
    if alpha ~= nil then
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xffffff00 + math.floor(alpha * 255))
    end
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, 1)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 0, 0)
    if ImGui.Button(ctx, txt, wIn, hIn) then
        ret = true
    end
    local w = ImGui.GetItemRectSize(ctx)
    local x, y = ImGui.GetItemRectMin(ctx)
    local margin = 2
    w = w - margin * 2
    x = x + margin
    ImGui.DrawList_AddLine(draw_list, x, y, x + w, y, 0xffffff15, 1)
    ImGui.PopStyleVar(ctx, 2)
    ImGui.PopStyleColor(ctx)
    if alpha ~= nil then
        ImGui.PopStyleColor(ctx)
    end
    return ret
end

function ArrowButton(wIn, hIn, up, disabled)
    local x, y = ImGui.GetCursorScreenPos(ctx)
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
        ImGui.DrawList_AddTriangleFilled(draw_list, x, y, x - 10, y, x - 5, y - 8, color)
    else
        y = y + 6
        ImGui.DrawList_AddTriangleFilled(draw_list, x, y, x - 5, y + 8, x - 10, y, color)
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
    local w = ImGui.GetItemRectSize(ctx)
    local x, y = ImGui.GetItemRectMin(ctx)
    x = x + w / 2
    y = y + w / 2
    local size = 4
    ImGui.DrawList_AddLine(draw_list, x - size, y - size, x + size, y + size, 0xffffffcc, 2)
    ImGui.DrawList_AddLine(draw_list, x - size, y + size, x + size, y - size, 0xffffffcc, 2)
    return ret
end

function DragDouble(label, value, speed, min, max, format)
    local ret, new_value = ImGui.DragDouble(ctx, label, value, speed, min, max, format)
    if ImGui.IsItemHovered(ctx) then
        ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeEW)
    end
    return ret, new_value
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
    while true do
        local found_duplicate = false
        for _, file in ipairs(files) do
            if string.lower(file.name) == string.lower(name) then
                found_duplicate = true
                name = name .. "2"
            end
        end
        if not found_duplicate then
            break
        end
    end
    return name
end

function MatchStyle(str)
    function NumberOrNilIfEmpty(str)
        if str == "" then return nil end
        return tonumber(str)
    end

    -- Using * instead of + for X, Y, W and H so they are optional
    local style_pat =
    "STYLE BG (%S+) FG (%S+) FC (%S+) HOVER (%S+) FNTSZ (%S+) PAD (%S+) DESC (%S+) LINE (%S+) POS (%S+) SIZE (%S+) X (%S*) Y (%S*) W (%S*) H (%S*) MH (%S+) MV (%S+) FONT ([^\n]*)"
    local bg, fg, flash, hover, font_size, padding, desc_offset, line_offset, pos_mode, size_mode, x, y, w, h, mouse_h, mouse_v, font =
        string
        .match(str
        , style_pat)
    if bg == nil then
        return nil
    end
    x = NumberOrNilIfEmpty(x)
    y = NumberOrNilIfEmpty(y)
    w = NumberOrNilIfEmpty(w)
    h = NumberOrNilIfEmpty(h)
    return {
        background_color = tonumber(bg, 16),
        foreground_color = tonumber(fg, 16),
        flash_color = tonumber(flash, 16),
        hover_color = tonumber(hover, 16),
        font = font,
        font_size = tonumber(font_size),
        padding = tonumber(padding),
        desc_offset = tonumber(desc_offset),
        line_offset = tonumber(line_offset),
        pos_mode = tonumber(pos_mode),
        size_mode = tonumber(size_mode),
        pos_x = x,
        pos_y = y,
        width = w,
        height = h,
        mouse_h_align = tonumber(mouse_h),
        mouse_v_align = tonumber(mouse_v),
        first_frame = true,
        shown = false,
    }
end

function Sanitize(str)
    str = string.gsub(str, "\"", "'")
    str = string.gsub(str, "\\", "\\\\")
    return string.gsub(str, "]]", "")
end

function UI(actions, layout, shown, window_name)
    function ToRGB(int)
        local r = ((int >> 16) & 255) / 255.0
        local g = ((int >> 8) & 255) / 255.0
        local b = (int & 255) / 255.0
        return r, g, b
    end

    function SetColor(int)
        local r, g, b = ToRGB(int)
        gfx.set(r, g, b)
    end

    if layout.first_frame then
        --Before doing anything we init window, so gfx_retina is computed, etc
        --We still have first frame work to do later so we don't set first_frame = false
        gfx.init(window_name, 0, 0, 0, 0, 0)
        gfx.ext_retina = 1
        layout.hwnd = reaper.JS_Window_Find(window_name, true)
        reaper.JS_Window_SetStyle(layout.hwnd, "POPUP")
        reaper.JS_Window_SetOpacity(layout.hwnd, "ALPHA", 0)
        reaper.JS_Window_SetFocus(layout.hwnd)
    end

    local longest_key = ""
    local longest_name = ""

    for _, action in ipairs(actions) do
        if not action.hidden then
            if action.text == nil then
                if #action.key_text > #longest_key then
                    longest_key = action.key_text
                end
                if #action.display_name > #longest_name then
                    longest_name = action.display_name
                end
            else
                if #action.text > #longest_name then
                    longest_name = action.text
                end
            end
        end
    end

    local os = reaper.GetOS()
    local is_mac = os == "OSX32" or os == "OSX64" or os == "macOS-arm64"
    local retina_scale = 1
    if is_mac then
        retina_scale = gfx.ext_retina
    end

    local font_size = layout.font_size * gfx.ext_retina
    gfx.setfont(1, layout.font, font_size)
    longest_key = gfx.measurestr(longest_key)
    longest_name = gfx.measurestr(longest_name)

    local nonHiddenActionCount = 0

    for _, action in ipairs(actions) do
        if not action.hidden then
            nonHiddenActionCount = nonHiddenActionCount + 1
        end
    end

    local padding = layout.padding * retina_scale
    local line_offset = layout.line_offset * retina_scale
    local desc_offset = layout.desc_offset * retina_scale
    local desc_position = padding + longest_key + desc_offset
    local height, width
    if layout.height ~= nil then
        height = layout.height * retina_scale
    else
        height = padding * 2 + nonHiddenActionCount * gfx.texth + (nonHiddenActionCount - 1) * line_offset
    end
    if layout.width ~= nil then
        width = layout.width * retina_scale
    else
        width = desc_position + longest_name + padding
    end

    -- On Windows and Linux, screen coordinates are relative to *upper* left corner of the primary display, and the positive Y-axis points downward.
    -- On macOS, screen coordinates are relative to the *bottom* left corner of the primary display, and the positive Y-axis points upward.
    -- On Windows, windows will appear by default at the bottom right of mouse cursor
    -- On macOS, windows will appear by default at the top right of mouse cursor
    if layout.first_frame then
        layout.first_frame = false
        layout.flash_time = nil
        layout.flash_action = nil
        local x, y = reaper.GetMousePosition()
        if is_mac then
            if layout.pos_mode == 0 then
                --Mouse position
                local left = x
                local bot = y
                local right = x + (width / retina_scale)
                local top = y + (height / retina_scale)
                if layout.mouse_h_align == 1 then
                    left = left - (width / retina_scale) / 2
                    right = right - (width / retina_scale) / 2
                elseif layout.mouse_h_align == 2 then
                    left = left - (width / retina_scale)
                    right = right - (width / retina_scale)
                end
                if layout.mouse_v_align == 1 then
                    top = top - (height / retina_scale) / 2
                    bot = bot - (height / retina_scale) / 2
                elseif layout.mouse_v_align == 2 then
                    top = top - (height / retina_scale)
                    bot = bot - (height / retina_scale)
                end

                local screen_left, screen_top, screen_right, screen_bot = reaper.JS_Window_GetViewportFromRect(10, 10, 10
                , 10
                , true)


                if left <= 0 then
                    right = right - left + 1
                    left = 1
                elseif right >= screen_right then
                    left = left - (right - (screen_right - 1))
                    right = screen_right - 1
                end

                if bot <= 0 then
                    top = top - bot
                    bot = 1
                elseif top >= screen_top then
                    bot = bot - (top - (screen_top - 1))
                    top = screen_top - 1
                end

                layout.pos_x = left
                layout.pos_y = bot
            end
        else
            if layout.pos_mode == 0 then
                local left = x
                local top = y
                local right = x + width
                local bot = y + height
                if layout.mouse_v_align == 0 then
                    bot = bot - height
                    top = top - height
                elseif layout.mouse_v_align == 1 then
                    bot = bot - height / 2
                    top = top - height / 2
                end
                if layout.mouse_h_align == 1 then
                    left = left - width / 2
                    right = right - width / 2
                elseif layout.mouse_h_align == 2 then
                    left = left - width
                    right = right - width
                end

                -- credit @nofish
                -- acount for multi-monitor setups
                -- https://forum.cockos.com/showpost.php?p=1883879&postcount=4
                -- use current mouse position for the second (multimonitor) rectangle
                local screen_left, screen_top, screen_right, screen_bot = reaper.my_getViewport(10, 10, 10, 10, x, y,
                    x + 10, y + 10, true)

                if left <= 0 then
                    right = right - left + 1
                    left = 1
                elseif right >= screen_right then
                    left = left - (right - (screen_right - 1))
                    right = screen_right - 1
                end

                if top <= 0 then
                    bot = bot - top + 1
                    top = 1
                elseif bot >= screen_bot then
                    top = top - (bot - (screen_bot - 1))
                    bot = screen_bot - 1
                end

                layout.pos_x = left
                layout.pos_y = top
            end
        end
    end
    local pos_x = layout.pos_x
    local pos_y = layout.pos_y

    local char = gfx.getchar()
    local unmatched = char > 0
    local cap = gfx.mouse_cap
    local mouse_down = cap & 1 == 1
    local clicked = false
    if not layout.mouse_down and mouse_down then
        clicked = true
    end
    layout.mouse_down = mouse_down
    local cmd = cap & 4 == 4
    local shift = cap & 8 == 8
    local alt = cap & 16 == 16
    local ctrl = cap & 32 == 32
    local exit = false
    local command = nil

    if shown then
        if not layout.shown then
            -- Only on first shown frame
            reaper.JS_Window_SetZOrder(layout.hwnd, "TOPMOST")
            reaper.JS_Window_SetOpacity(layout.hwnd, "ALPHA", 1)
            layout.shown = true
        end
        -- an empty string resizes and reposition current gfx window
        gfx.init("", width / retina_scale, height / retina_scale, 0, pos_x, pos_y)
        gfx.update()
        SetColor(layout.background_color)
        gfx.rect(0, 0, width, height, true)
        gfx.y = padding
    end
    local actionDrawn = 1
    for i, action in ipairs(actions) do
        local wasDrawn = false
        if action.text ~= nil then
            gfx.x = desc_position
            SetColor(layout.foreground_color)
            gfx.drawstr(action.text)
            wasDrawn = true
        else
            local key_pressed = char == action.key and action.cmd == cmd and action.shift == shift and
                action.alt == alt
                and
                action.ctrl == ctrl
            if action.hidden then
                if key_pressed then
                    if action.native then
                        command = action.action
                    else
                        command = reaper.NamedCommandLookup(action.action)
                    end
                    if action.exit then
                        exit = true
                    end
                end
            else
                wasDrawn = true
                gfx.x = padding
                local hover_mid = gfx.y + gfx.texth / 2
                local hover_top = math.max(0, hover_mid - line_offset / 2 - gfx.texth / 2)
                local hover_bot = math.min(gfx.h, hover_mid + line_offset / 2 + gfx.texth / 2)
                local is_hover = gfx.mouse_x >= 0 and gfx.mouse_x <= gfx.w and gfx.mouse_y >= hover_top and
                    gfx.mouse_y < hover_bot
                local is_flashing = layout.flash_action == i and reaper.time_precise() - layout.flash_time < 0.1
                if is_flashing then
                    SetColor(layout.flash_color)
                elseif key_pressed or (is_hover and clicked) then
                    SetColor(layout.flash_color)
                    layout.flash_action = i
                    layout.flash_time = reaper.time_precise()
                    if action.native then
                        command = action.action
                    else
                        command = reaper.NamedCommandLookup(action.action)
                    end
                    if action.exit then
                        exit = true
                    end
                elseif is_hover then
                    SetColor(layout.hover_color)
                else
                    SetColor(layout.foreground_color)
                end
                if shown then
                    gfx.drawstr(action.key_text)
                    gfx.x = desc_position
                    gfx.drawstr(action.display_name)
                end
            end
        end
        if wasDrawn then
            if actionDrawn ~= nonHiddenActionCount then
                gfx.y = gfx.y + gfx.texth + line_offset
            end
            actionDrawn = actionDrawn + 1
        end
    end
    if command ~= nil then
        unmatched = false
    end
    return char, command, exit, layout.hwnd, unmatched
end

function ActionInfo(int_id, section_id)
    local native, stable_id, command_text
    command_text = Sanitize(reaper.CF_GetCommandText(section_id, int_id))
    local lookup = reaper.ReverseNamedCommandLookup(int_id)
    if lookup == nil then
        native = true
        stable_id = int_id
    else
        native = false
        stable_id = "_" .. lookup
    end
    return stable_id, native, command_text
end

--returns nil if not opened / canceled, false if waiting for action, true if got action
function ActionPopup(id, section_id)
    local popup_name = "Action##" .. id
    local action, action_text, native
    if action_popup_requested then
        action_popup_requested = false
        action_popup_opened = true
        reaper.PromptForAction(1, 0, section_id)
        ImGui.OpenPopup(ctx, popup_name)
    end
    if not action_popup_opened then return nil end
    local got_action = false ---@type boolean | nil
    ImGui.SetNextWindowPos(ctx, center[1], center[2], ImGui.Cond_Appearing, 0.5, 0.5)
    if ImGui.BeginPopupModal(ctx, popup_name, nil, popup_flags) then
        local ret = reaper.PromptForAction(0, 0, section_id)
        if ret > 0 then
            action, native, action_text = ActionInfo(ret, section_id)
            got_action = true
            action_popup_opened = false
            ImGui.CloseCurrentPopup(ctx)
            reaper.PromptForAction(-1, 0, section_id)
        end
        ImGui.Text(ctx, "Pick an action in the action list")
        MoveCursor(0, 7)
        if Button("Cancel", -FLT_MIN) or ret == -1 then
            action_popup_opened = false
            ImGui.CloseCurrentPopup(ctx)
            reaper.PromptForAction(-1, 0, section_id)
            got_action = nil
        end
        ImGui.EndPopup(ctx)
        return got_action, action, native, action_text
    end
end

function TextPopup(id)
    local ret = nil
    ImGui.SetNextWindowPos(ctx, center[1], center[2], ImGui.Cond_Appearing, 0.5, 0.5)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 10, 10)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 10, 8)
    if ImGui.BeginPopupModal(ctx, id, nil, popup_flags) then
        ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0x444444ff)
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha, 0.7)
        MoveCursor(3, 16)
        ImGui.Text(ctx, "Text")
        ImGui.PopStyleVar(ctx)
        ImGui.SameLine(ctx)
        MoveCursor(6, -6)
        if edit_wants_focus then
            ImGui.SetKeyboardFocusHere(ctx)
            edit_wants_focus = false
        end
        ImGui.PushItemWidth(ctx, 300)
        _, new_text = ImGui.InputText(ctx, "##actionname", new_text)
        ImGui.PopItemWidth(ctx)
        ImGui.PopStyleColor(ctx)
        MoveCursor(0, 6)
        local avail_x = ImGui.GetContentRegionAvail(ctx)
        if Button("Cancel##edit" .. id, avail_x / 2.1) then
            ImGui.CloseCurrentPopup(ctx)
        end
        ImGui.SameLine(ctx)
        local enter_pressed = ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter)
        enter_pressed = enter_pressed or ImGui.IsKeyPressed(ctx, ImGui.Key_Enter)
        if Button("Ok##edit" .. id, -FLT_MIN) or enter_pressed then
            ret = new_text
            ImGui.CloseCurrentPopup(ctx)
        end
        ImGui.EndPopup(ctx)
    end
    ImGui.PopStyleVar(ctx, 2)
    return ret
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
        ImGui.OpenPopup(ctx, popup_name)
    end
    if not key_popup_opened then return nil end
    local got_input = false
    ImGui.SetNextWindowPos(ctx, center[1], center[2], ImGui.Cond_Appearing, 0.5, 0.5)
    if ImGui.BeginPopupModal(ctx, popup_name, nil, popup_flags) then
        if reaper.JS_Window_GetFocus() ~= key_hwnd then
            gfx.quit()
            ImGui.CloseCurrentPopup(ctx)
            key_popup_opened = false
        end
        local getchar = gfx.getchar()
        if getchar > 0 then
            key = getchar
            local cap = gfx.mouse_cap
            key_text = ToKeyText(getchar, cap)
            cmd = cap & 4 == 4
            shift = cap & 8 == 8
            alt = cap & 16 == 16
            ctrl = cap & 32 == 32
            gfx.quit()
            ImGui.CloseCurrentPopup(ctx)
            key_popup_opened = false
            got_input = true
        elseif getchar == -1 then
            gfx.quit()
            ImGui.CloseCurrentPopup(ctx)
            key_popup_opened = false
        end
        local text = "Press key(s)"
        local text_size = ImGui.CalcTextSize(ctx, text)
        local avail_x = ImGui.GetContentRegionAvail(ctx)
        MoveCursor(avail_x / 2 - text_size / 2, 0)
        ImGui.Text(ctx, text)
        MoveCursor(0, 7)
        if Button("Cancel", 120, 20) then
            gfx.quit()
            ImGui.CloseCurrentPopup(ctx)
            key_popup_opened = false
        end
        ImGui.EndPopup(ctx)
        if got_input then
            local duplicate = false
            local duplicate_name = ""
            for j, action in ipairs(files[cur_file_idx].actions) do
                -- skip text "actions"
                if action.text == nil then
                    -- don't check existing action when updating its key
                    if own_index == nil or (own_index ~= nil and own_index ~= j) then
                        if math.floor(action.key) == math.floor(key) and action.shift == shift and action.ctrl == ctrl
                            and
                            action.alt == alt and action.cmd == cmd then
                            duplicate = true
                            duplicate_name = action.action_text
                        end
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
        else
            return false
        end
    end
end

function SetDirty(file)
    table.insert(dirty, file)
    last_dirty_name = file.name
end

function TryUTFChar(int)
    return pcall(function() return utf8.char(int) end)
end

function ToUTFChar(int)
    local utfOffset = 1962934272; -- 'u' << 24
    local OK, char = TryUTFChar(int)
    if OK then
        return char
    end
    OK, char = TryUTFChar(int - utfOffset)
    if OK then
        return char
    end
    return "?"
end

function ToKeyText(int, cap)
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
        return mods(false) .. ToUTFChar(int)
    elseif cmd and alt and int >= 257 and int <= 282 then
        int = int - 160 - 32
        return mods(false) .. ToUTFChar(int)
    elseif alt and int >= 321 and int <= 346 then
        int = int - 256
        return mods(false) .. ToUTFChar(int)
    elseif keys[int] ~= nil then
        return mods(false) .. keys[int]
    elseif int >= 0x41 and int <= 0x5a then
        -- Different treatment for characters in the [A-Z] range so "Shift + " doesn't show up
        return mods(true) .. ToUTFChar(int)
    elseif int >= 33 and int <= 255 then
        return mods(false) .. ToUTFChar(int)
    else
        return mods(false) .. ToUTFChar(int)
    end
end

function MoveCursor(x, y)
    local ox, oy = ImGui.GetCursorPos(ctx)
    ImGui.SetCursorPos(ctx, ox + x, oy + y)
end

function ToBool(str)
    return str == "true"
end

function ToCap(shift, cmd, ctrl, alt)
    local ret = 0
    if cmd then ret = ret + 4 end
    if shift then ret = ret + 8 end
    if alt then ret = ret + 16 end
    if ctrl then ret = ret + 32 end
    return ret
end

-- Get function source, from first line to last line
function FunctionSource(fn)
    local info = debug.getinfo(fn, 'S')
    local line_start = info.linedefined
    local line_end = info.lastlinedefined
    local path = info.source:sub(2)
    local ret = ""
    local i = 1
    for line in io.lines(path) do
        if i >= line_start and i <= line_end then
            ret = ret .. line .. "\n"
        elseif i > line_end then
            break
        end
        i = i + 1
    end
    return ret
end

function Parse_V0(file, txt)
    local function sectionId(section_str)
        if section_str == "MAIN" then
            return 1
        elseif section_str == "MALT" then
            return 2
        elseif section_str == "MIDI" then
            return 3
        elseif section_str == "EVNT" then
            return 4
        elseif section_str == "MEXP" then
            return 5
        end
    end

    local function commandPat(section_str)
        if section_str == "MAIN" then
            return "reaper%.Main_OnCommand%((%d+),0%)"
        elseif section_str == "MALT" then
            return "reaper%.Main_OnCommand%((%d+),0%)"
        elseif section_str == "MIDI" then
            return "reaper%.MIDIEditor_OnCommand%(midi_editor,(%d+)%)"
        elseif section_str == "EVNT" then
            return "reaper%.MIDIEditor_OnCommand%(midi_editor,(%d+)%)"
        elseif section_str == "MEXP" then
            return "reaper%.JS_Window_OnCommand%(explorerHWND,(%d+)%)"
        end
    end

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
        action_id = tonumber(action_id)
        local id, native, command_text = ActionInfo(action_id, sections[file.section].id)
        local new = {
            key = key_id,
            action = id,
            shift = shift,
            cmd = cmd,
            ctrl = ctrl,
            alt = alt,
            exit = exit,
            key_text = ToKeyText(tonumber(key_id), ToCap(shift, cmd, ctrl, alt)),
            action_text = command_text,
            display_name = names[#file.actions + 1],
            native = native
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

function Parse_V1(file, txt)
    local function sectionId(section_str)
        if section_str == "MAIN" then
            return 1
        elseif section_str == "MALT" then
            return 2
        elseif section_str == "MIDI" then
            return 3
        elseif section_str == "EVNT" then
            return 4
        elseif section_str == "MEXP" then
            return 5
        end
    end

    file.actions = {}
    local section_pat = "--SEC:(%w%w%w%w)"
    local section_str = string.match(txt, section_pat)
    file.section = sectionId(section_str)
    local metadata_pat =
    "KEY (%d+) SHIFT (%S+) CMD (%S+) ALT (%S+) CTRL (%S+)%s+NATIVE (%S+)%s+ID (%S+)%s+EXIT (%S+)%s+DISPLAY ([^\n]+)"
    for key, shift, cmd, alt, ctrl, native, id, exit, display in string.gmatch(txt, metadata_pat) do
        key = tonumber(key)
        shift = ToBool(shift)
        cmd = ToBool(cmd)
        alt = ToBool(alt)
        ctrl = ToBool(ctrl)
        native = ToBool(native)
        exit = ToBool(exit)
        local int_id
        if native then
            id = tonumber(id)
            int_id = id
        else
            int_id = reaper.NamedCommandLookup(id)
        end
        local action_text = Sanitize(reaper.CF_GetCommandText(sections[file.section].id, int_id))
        table.insert(file.actions, {
            key = key,
            action = id,
            shift = shift,
            cmd = cmd,
            alt = alt,
            ctrl = ctrl,
            exit = exit,
            display_name = display,
            action_text = action_text,
            native = native,
            key_text = ToKeyText(tonumber(key), ToCap(shift, cmd, ctrl, alt)),
        })
    end
    local show_after_pat = "show_after = (%d%.%d)"
    file.show_after = string.match(txt, show_after_pat)
    local path = script_path .. file.path
    -- get command id by adding it
    -- not efficient, but it feels overkill to include a SHA1 library just to compute the command id
    file.command_id = reaper.AddRemoveReaScript(true, sections[file.section].id, path, true)
end

function Parse_V3(file, txt)
    local function sectionId(section_str)
        if section_str == "MAIN" then
            return 1
        elseif section_str == "MALT" then
            return 2
        elseif section_str == "MIDI" then
            return 3
        elseif section_str == "EVNT" then
            return 4
        elseif section_str == "MEXP" then
            return 5
        end
    end

    file.actions = {}
    local section_pat = "--SEC:(%w%w%w%w)"
    local section_str = string.match(txt, section_pat)
    file.section = sectionId(section_str)
    local action_pat =
    "KEY (%d+) SHIFT (%S+) CMD (%S+) ALT (%S+) CTRL (%S+) NATIVE (%S+) ID (%S+) EXIT (%S+) DISPLAY ([^\n]+)"
    local text_pat = "TEXT ([^\n]*)"
    local found_at_least_one = false
    -- Read line by line, skipping empty lines
    for line in string.gmatch(txt, "[^\r\n]+") do
        local line_used = false
        local key, shift, cmd, alt, ctrl, native, id, exit, display = string.match(line, action_pat)
        if key ~= nil then
            found_at_least_one = true
            key = tonumber(key)
            shift = ToBool(shift)
            cmd = ToBool(cmd)
            alt = ToBool(alt)
            ctrl = ToBool(ctrl)
            native = ToBool(native)
            exit = ToBool(exit)
            local int_id
            if native then
                id = tonumber(id)
                int_id = id
            else
                int_id = reaper.NamedCommandLookup(id)
            end
            local action_text = Sanitize(reaper.CF_GetCommandText(sections[file.section].id, int_id))
            table.insert(file.actions, {
                key = key,
                action = id,
                shift = shift,
                cmd = cmd,
                alt = alt,
                ctrl = ctrl,
                exit = exit,
                display_name = display,
                action_text = action_text,
                native = native,
                key_text = ToKeyText(tonumber(key), ToCap(shift, cmd, ctrl, alt)),
                command_exists = action_text ~= ""
            })
            line_used = true
        end
        if not line_used and file.style == nil then
            local style = MatchStyle(line)
            if style ~= nil then
                file.style = style
                line_used = true
            end
        end
        if not line_used then
            local text = string.match(line, text_pat)
            if text ~= nil then
                found_at_least_one = true
                table.insert(file.actions, { text = text })
                line_used = true
            else
                if found_at_least_one then
                    -- If curent line is not a style, an action or text, we stop parsing metas
                    break
                end
            end
        end
    end
    if file.style == nil then
        file.style = CloneStyle(default_style)
    end
    local show_after_pat = "show_after = (%d%.%d)"
    file.show_after = string.match(txt, show_after_pat)
    local path = script_path .. file.path
    -- get command id by adding it
    -- not efficient, but it feels overkill to include a SHA1 library just to compute the command id
    file.command_id = reaper.AddRemoveReaScript(true, sections[file.section].id, path, true)
end

function Parse_V4(file, txt)
    local function sectionId(section_str)
        if section_str == "MAIN" then
            return 1
        elseif section_str == "MALT" then
            return 2
        elseif section_str == "MIDI" then
            return 3
        elseif section_str == "EVNT" then
            return 4
        elseif section_str == "MEXP" then
            return 5
        end
    end

    file.actions = {}
    local section_pat = "--SEC:(%w%w%w%w)"
    local section_str = string.match(txt, section_pat)
    file.section = sectionId(section_str)
    local action_pat =
    "KEY (%d+) SHIFT (%S+) CMD (%S+) ALT (%S+) CTRL (%S+) NATIVE (%S+) ID (%S+) EXIT (%S+) HIDDEN (%S+) DISPLAY ([^\n]+)"
    local text_pat = "TEXT ([^\n]*)"
    local found_at_least_one = false
    -- Read line by line, skipping empty lines
    for line in string.gmatch(txt, "[^\r\n]+") do
        local line_used = false
        local key, shift, cmd, alt, ctrl, native, id, exit, hidden, display = string.match(line, action_pat)
        if key ~= nil then
            found_at_least_one = true
            key = tonumber(key)
            shift = ToBool(shift)
            cmd = ToBool(cmd)
            alt = ToBool(alt)
            ctrl = ToBool(ctrl)
            native = ToBool(native)
            exit = ToBool(exit)
            hidden = ToBool(hidden)
            local int_id
            if native then
                id = tonumber(id)
                int_id = id
            else
                int_id = reaper.NamedCommandLookup(id)
            end
            local action_text = Sanitize(reaper.CF_GetCommandText(sections[file.section].id, int_id))
            table.insert(file.actions, {
                key = key,
                action = id,
                shift = shift,
                cmd = cmd,
                alt = alt,
                ctrl = ctrl,
                exit = exit,
                display_name = display,
                action_text = action_text,
                native = native,
                key_text = ToKeyText(tonumber(key), ToCap(shift, cmd, ctrl, alt)),
                command_exists = action_text ~= "",
                hidden = hidden
            })
            line_used = true
        end
        if not line_used and file.style == nil then
            local style = MatchStyle(line)
            if style ~= nil then
                file.style = style
                line_used = true
            end
        end
        if not line_used then
            local text = string.match(line, text_pat)
            if text ~= nil then
                found_at_least_one = true
                table.insert(file.actions, { text = text })
                line_used = true
            else
                if found_at_least_one then
                    -- If curent line is not a style, an action or text, we stop parsing metas
                    break
                end
            end
        end
    end
    if file.style == nil then
        file.style = CloneStyle(default_style)
    end
    local show_after_pat = "show_after = (%d%.%d)"
    file.show_after = string.match(txt, show_after_pat)
    local close_on_unmatched_pat = "close_on_unmatched = ([^\n]+)"
    file.close_on_unmatched = ToBool(string.match(txt, close_on_unmatched_pat))
    local path = script_path .. file.path
    -- get command id by adding it
    -- not efficient, but it feels overkill to include a SHA1 library just to compute the command id
    file.command_id = reaper.AddRemoveReaScript(true, sections[file.section].id, path, true)
end

function Load()
    dirty = {}
    files = {}
    -- create directory if it doesn't exist
    reaper.RecursiveCreateDirectory(script_path, 0)
    -- force empty cache
    reaper.EnumerateFiles(script_path, -1)
    local index = 0
    while true do
        local filename = reaper.EnumerateFiles(script_path, index)
        if filename == nil then break end
        if string.sub(filename, 0, #prefix) == prefix then
            table.insert(files, { name = string.sub(filename, #prefix + 1, #filename - 4), path = filename })
        elseif filename == default_style_filename then
            local file_io, err = io.open(script_path .. filename, 'r')
            if file_io == nil then
                reaper.ShowMessageBox(err, "Error loading default style file")
            else
                local txt = file_io:read("*all")
                file_io:close()
                local style = MatchStyle(txt)
                if style ~= nil then
                    default_style = style
                end
            end
        end
        index = index + 1
    end
    local needs_post_upgrade_save = false
    for _, file in ipairs(files) do
        local file_io, err = io.open(script_path .. file.path, 'r')
        if file_io == nil then
            reaper.ShowMessageBox(err, "Error loading file")
        else
            local txt = file_io:read("*all")
            file_io:close()
            local version_pat = "-- VER:(%d+)"
            local version = string.match(txt, version_pat)
            if version == nil then
                version = 0
            else
                version = tonumber(version)
            end
            if version == 0 then
                Parse_V0(file, txt)
                if file.style == nil then
                    file.style = CloneStyle(default_style)
                end
                SetDirty(file)
                needs_post_upgrade_save = true
            elseif version == 1 then
                Parse_V1(file, txt)
                if file.style == nil then
                    file.style = CloneStyle(default_style)
                end
                SetDirty(file)
                needs_post_upgrade_save = true
            elseif version == 2 then
                Parse_V1(file, txt)
                if file.style == nil then
                    file.style = CloneStyle(default_style)
                end
                SetDirty(file)
                needs_post_upgrade_save = true
            elseif version == 3 then
                Parse_V3(file, txt)
                SetDirty(file)
                needs_post_upgrade_save = true
            elseif version == 4 then
                Parse_V4(file, txt)
                SetDirty(file)
                needs_post_upgrade_save = true
            elseif version == 5 then
                Parse_V4(file, txt)
            end
        end
    end
    if needs_post_upgrade_save then
        Save()
        Load()
    end
    table.sort(files, function(a, b) return a.name:upper() < b.name:upper() end)
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

function StyleToString(style)
    local x = ""
    local y = ""
    if style.pos_mode ~= 0 then
        x = string.format("%.1f", style.pos_x)
        y = string.format("%.1f", style.pos_y)
    end
    local w = ""
    local h = ""
    if style.size_mode ~= 0 then
        w = string.format("%.1f", style.width)
        h = string.format("%.1f", style.height)
    end
    return string.format(
        "\nSTYLE BG %x FG %x FC %x HOVER %x FNTSZ %.1f PAD %.1f DESC %.1f LINE %.1f POS %d SIZE %d X %s Y %s W %s H %s MH %d MV %d FONT %s"
        ,
        style.background_color, style.foreground_color,
        style.flash_color, style.hover_color, style.font_size, style.padding, style.desc_offset,
        style.line_offset, style.pos_mode, style.size_mode, x, y, w, h, style.mouse_h_align, style.mouse_v_align,
        style.font)
end

--This function is only made to work for the style table and the actions table
--It doesn't handle having a named table inside a table among other things
function TableSource(table, name, indent, first)
    local result = ""
    local spaces = string.rep("    ", indent)
    local long_spaces = string.rep("    ", indent + 1)
    if name ~= nil then
        result = spaces .. "local " .. name .. " = {\n"
    else
        result = spaces .. "{\n"
    end
    for k, v in pairs(table) do
        if type(v) == "string" then
            if v == '"' then
                v = "\\\""
            end
            v = Sanitize(v)
            result = result .. string.format('%s%s = "%s",\n', long_spaces, k, v)
        elseif type(v) == "number" or type(v) == "boolean" then
            result = result .. long_spaces .. k .. " = " .. tostring(v) .. ",\n"
        elseif type(v) == "table" then
            result = result .. TableSource(v, nil, indent + 1, false)
        end
    end
    result = result .. spaces .. "}"
    if not first then
        result = result .. ",\n"
    else
        result = result .. "\n"
    end
    return result
end

function SaveCurrentStyleToDefaultStyleFile()
    local str = StyleToString(current_style)
    local path = script_path .. default_style_filename
    local file_io, err = io.open(path, 'w')
    if file_io == nil then
        reaper.ShowMessageBox(err, "Error saving default style")
    else
        file_io, err = file_io:write(str)
        if file_io == nil then
            reaper.ShowMessageBox(err, "Error saving default style")
        else
            file_io:close()
        end
    end
    default_style = CloneStyle(current_style)
end

function CloneStyle(style)
    return {
        background_color = style.background_color,
        foreground_color = style.foreground_color,
        flash_color = style.flash_color,
        hover_color = style.hover_color,
        font = style.font,
        font_size = style.font_size,
        padding = style.padding,
        desc_offset = style.desc_offset,
        line_offset = style.line_offset,
        pos_mode = style.pos_mode,
        size_mode = style.size_mode,
        pos_x = style.pos_x,
        pos_y = style.pos_y,
        width = style.width,
        height = style.height,
        mouse_h_align = style.mouse_h_align,
        mouse_v_align = style.mouse_v_align,
        first_frame = true,
        shown = false,
    }
end

function PasteStyleToCurrent(style)
    current_style.background_color = style.background_color
    current_style.foreground_color = style.foreground_color
    current_style.flash_color = style.flash_color
    current_style.hover_color = style.hover_color
    current_style.font = style.font
    current_style.font_size = style.font_size
    current_style.padding = style.padding
    current_style.desc_offset = style.desc_offset
    current_style.line_offset = style.line_offset
    current_style.pos_mode = style.pos_mode
    current_style.size_mode = style.size_mode
    current_style.pos_x = style.pos_x
    current_style.pos_y = style.pos_y
    current_style.width = style.width
    current_style.height = style.height
    current_style.mouse_h_align = style.mouse_h_align
    current_style.mouse_v_align = style.mouse_v_align
end

function Save()
    local function metadata(file)
        local ret = "\n--[["
        ret = ret .. StyleToString(file.style)
        for _, action in ipairs(file.actions) do
            if action.text ~= nil then
                ret = ret .. "\nTEXT " .. action.text
            else
                local hidden = action.hidden or false
                ret = ret .. "\nKEY " .. math.floor(action.key) ..
                    " SHIFT " .. tostring(action.shift) ..
                    " CMD " .. tostring(action.cmd) ..
                    " ALT " .. tostring(action.alt) ..
                    " CTRL " .. tostring(action.ctrl) ..
                    " NATIVE " .. tostring(action.native) ..
                    " ID " .. action.action ..
                    " EXIT " .. tostring(action.exit) ..
                    " HIDDEN " .. tostring(hidden) ..
                    " DISPLAY " .. action.display_name
            end
        end
        return ret .. "\n]]\n"
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
            return "\n--SEC:EVNT\n  midi_editor = reaper.MIDIEditor_GetActive()\n"
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
        local window_name = "KeySequenceListener" .. file.name
        local close_on_unmatched = file.close_on_unmatched or false
        local result = [[
  -- This file is autogenerated, do not modify or move
  -- VER:5]]
            .. metadata(file)
            .. FunctionSource(UI)
            .. TableSource(file.actions, "actions", 0, true)
            .. TableSource(file.style, "style", 0, true)
            .. [[
if reaper.JS_Window_Find == nil then
    reaper.ShowMessageBox("This script requires js_ReaScriptAPI", "Missing dependency", 0)
    return
end

local prev_focus = reaper.JS_Window_GetFocus()
local close_on_unmatched = ]] .. tostring(close_on_unmatched) .. [[

local show_after = ]] .. string.format("%.1f", file.show_after) .. [[

local time_start = reaper.time_precise()
local shown = false]] .. section_setup(file) .. [[
function main()
    if not shown and reaper.time_precise() - time_start > show_after then
        shown = true
    end
    local char, command, exit, hwnd, unmatched = UI(actions, style, shown, "]] .. window_name .. [[")
    if unmatched and close_on_unmatched then
        exit = true
    end
    -- Exit before calling the action if necessary
    if exit then
      gfx.quit()
      reaper.JS_Window_SetFocus(prev_focus)
    end
    if command ~= nil then
        ]]
        local section = sections[file.section]
        if section.name == "Main" or section.name == "Main (alt recording)" then
            result = result .. "reaper.Main_OnCommand(command ,0)"
        elseif section.name == "MIDI Editor" or section.name == "MIDI Event List Editor" then
            result = result .. "reaper.MIDIEditor_OnCommand(midi_editor, command)"
        elseif section.name == "Media Explorer" then
            result = result .. "reaper.JS_Window_OnCommand(explorerHWND, command)"
        else
            reaper.ShowMessageBox("Unknown section")
        end
        result = result .. [[

        if not exit then
            reaper.JS_Window_SetFocus(hwnd)
        end
    end
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
            reaper.ShowMessageBox(err, "Error saving file")
        else
            file_io, err = file_io:write(result)
            if file_io == nil then
                reaper.ShowMessageBox(err, "Error saving file")
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
    draw_list = ImGui.GetWindowDrawList(ctx)
    center = { ImGui.Viewport_GetCenter(ImGui.GetWindowViewport(ctx)) }
    ImGui.SetNextFrameWantCaptureKeyboard(ctx, true)

    do
        avail_x = ImGui.GetContentRegionAvail(ctx)
        if ImGui.BeginChild(ctx, "L", avail_x * 0.25) then
            avail_x, avail_y = ImGui.GetContentRegionAvail(ctx)
            x, y = ImGui.GetCursorScreenPos(ctx)
            ImGui.DrawList_AddRectFilled(draw_list, x, y, x + avail_x, y + avail_y - 35, 0xffffff14, 3, rect_flags)
            ImGui.DrawList_AddRectFilled(draw_list, x, y, x + avail_x, y + header_h, 0xffffff12, 3, rect_flags)
            MoveCursor(10, 5)
            ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha, 0.6)
            ImGui.Text(ctx, "Sequences")
            ImGui.PopStyleVar(ctx)
            MoveCursor(0, 6)
            if ImGui.BeginListBox(ctx, "##listL", -FLT_MIN, -35) then
                ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 0, 7)
                for n, v in ipairs(files) do
                    local is_selected = cur_file_idx == n
                    avail_x = ImGui.GetContentRegionAvail(ctx)
                    x, y = ImGui.GetCursorScreenPos(ctx)
                    y = y - 3
                    local end_x = x + avail_x
                    if is_selected then
                        ImGui.DrawList_AddRectFilled(draw_list, x, y, end_x, y + 19, 0xffffff15, 3, rect_flags)
                    elseif ImGui.IsMouseHoveringRect(ctx, x, y, end_x, y + 19) then
                        ImGui.DrawList_AddRectFilled(draw_list, x, y, end_x, y + 19, 0xffffff06, 3, rect_flags)
                    end
                    MoveCursor(6, 0)
                    if ImGui.Selectable(ctx, v.name, is_selected) then
                        cur_file_idx = n
                    end
                    ImGui.SameLine(ctx)
                    avail_x = ImGui.GetContentRegionAvail(ctx)
                    local section = sections[v.section].short_name
                    local size = ImGui.CalcTextSize(ctx, section)
                    MoveCursor(avail_x - size - 6, 0)
                    ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha, 0.5)
                    ImGui.Text(ctx, section)
                    ImGui.PopStyleVar(ctx)
                end
                ImGui.PopStyleVar(ctx)
                ImGui.EndListBox(ctx)
            end
            MoveCursor(0, 5)
            if Button("...", 25, 25) then
                ImGui.OpenPopup(ctx, "SeqMorePopup")
            end
            if ImGui.BeginPopupContextItem(ctx, "SeqMorePopup") then
                ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, 0xffffff44)
                if ImGui.Selectable(ctx, "Export summary to CSV", false) then
                    reaper.ShowConsoleMsg(SequencesToCSV())
                end
                ImGui.PopStyleColor(ctx)
                ImGui.EndPopup(ctx)
            end
            ImGui.SameLine(ctx)

            x = ImGui.GetContentRegionAvail(ctx)
            if Button("Add", x / 2.15, 25) then
                new_seq_name = ""
                new_wants_focus = true
                ImGui.OpenPopup(ctx, "New Sequence")
            end
            ImGui.SameLine(ctx)

            -- if Button("Rename", x / 3.2, 25) then
            --     local execute = true
            --     local section_id = sections[files[cur_file_idx].section].id
            --     local command_id = files[cur_file_idx].command_id
            --     local ret, shortcut = reaper.JS_Actions_GetShortcutDesc(section_id, command_id, 0)
            --     if ret then
            --         if reaper.ShowMessageBox(string.format("Are you sure you want to rename %s ?\nYour sequence shortcut (%s) will need to be reassigned."
            --             , files[cur_file_idx].name, shortcut), "Confirmation", 1)
            --             ~= 1 then
            --             execute = false
            --         end
            --     end

            --     if execute then
            --         local cur_file = files[cur_file_idx]
            --         local new = { name = "RENAMD", actions = cur_file.actions, section = cur_file.section,
            --             show_after = 1,
            --             style = CloneStyle(cur_file.style) }
            --         table.insert(files, new)
            --         SetDirty(new)
            --         wants_to_be_removed_id = cur_file_idx
            --     end
            -- end
            -- ImGui.SameLine(ctx)

            -- current_idx can change in button so we temp var it
            local began_disabled = false
            if cur_file_idx <= 0 then
                began_disabled = true
                ImGui.BeginDisabled(ctx, true)
            end
            if Button("Remove", -FLT_MIN, 25) and
                reaper.ShowMessageBox("Are you sure you want to delete " .. files[cur_file_idx].name, "Confirmation", 1)
                == 1 then
                wants_to_be_removed_id = cur_file_idx
            end
            if began_disabled then
                ImGui.EndDisabled(ctx)
            end
            ImGui.SetNextWindowPos(ctx, center[1], center[2], ImGui.Cond_Appearing, 0.5, 0.5)
            ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 10, 10)
            ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 10, 8)
            if ImGui.BeginPopupModal(ctx, "New Sequence", nil, popup_flags) then
                MoveCursor(0, 15)
                ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha, 0.7)
                ImGui.Text(ctx, "Name")
                ImGui.PopStyleVar(ctx)
                ImGui.SameLine(ctx)
                MoveCursor(8, -8)
                if new_wants_focus then
                    ImGui.SetKeyboardFocusHere(ctx)
                    new_wants_focus = false
                end
                ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0x333333ff)
                _, new_seq_name = ImGui.InputText(ctx, "##", new_seq_name)
                MoveCursor(0, 15)
                ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha, 0.7)
                ImGui.Text(ctx, "Section")
                ImGui.PopStyleVar(ctx)
                ImGui.SameLine(ctx)
                MoveCursor(0, -8)
                ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, 0xffffff20)
                ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive, 0xffffff30)
                if ImGui.BeginCombo(ctx, "##newSection", sections[selected_section].name) then
                    for i, section in ipairs(sections) do
                        if ImGui.Selectable(ctx, section.name, i == selected_section) then
                            selected_section = i
                        end
                    end
                    ImGui.EndCombo(ctx)
                end
                ImGui.PopStyleColor(ctx, 3)
                MoveCursor(0, 15)

                avail_x = ImGui.GetContentRegionAvail(ctx)
                if Button("Cancel", avail_x * 0.5) then
                    ImGui.CloseCurrentPopup(ctx)
                end
                ImGui.SameLine(ctx)
                if #new_seq_name == 0 then
                    ImGui.BeginDisabled(ctx, true)
                end
                local enter_pressed = ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter)
                enter_pressed = enter_pressed or ImGui.IsKeyPressed(ctx, ImGui.Key_Enter)
                if Button("Ok", -FLT_MIN) or (#new_seq_name ~= 0 and enter_pressed) then
                    new_seq_name = ValidateName(new_seq_name)
                    local new = {
                        name = new_seq_name,
                        actions = {},
                        section = selected_section,
                        show_after = 1.0,
                        style = CloneStyle(default_style)
                    }
                    table.insert(files, new)
                    SetDirty(new)
                    ImGui.CloseCurrentPopup(ctx)
                end
                if #new_seq_name == 0 then
                    ImGui.EndDisabled(ctx)
                end
                ImGui.EndPopup(ctx)
            end
            ImGui.PopStyleVar(ctx, 2)
            ImGui.EndChild(ctx)
        end
    end
    ImGui.SameLine(ctx)
    do
        avail_x, avail_y = ImGui.GetContentRegionAvail(ctx)
        if cur_file_idx ~= 0 and ImGui.BeginChild(ctx, "R", avail_x, avail_y, 0) then
            avail_x = ImGui.GetContentRegionAvail(ctx)
            x, y = ImGui.GetCursorScreenPos(ctx)
            local end_x = x + avail_x
            ImGui.DrawList_AddRectFilled(draw_list, x, y, end_x, y + header_h * 1.4, 0xffffff14, 3, rect_flags)
            ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha, 0.5)
            MoveCursor(6, 9)
            ImGui.Text(ctx, "Show hint after")
            ImGui.PopStyleVar(ctx)
            ImGui.SameLine(ctx)
            MoveCursor(0, -2)
            ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0xffffff2f)
            ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, 0xffffff4f)
            ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, 0xffffff5f)
            ImGui.PushItemWidth(ctx, 30)
            local ret, val = DragDouble("##show_after", files[cur_file_idx].show_after, .1, 0, 5,
                "%.1fs")
            ImGui.PopItemWidth(ctx)
            ImGui.PopStyleColor(ctx, 3)
            if ret then
                files[cur_file_idx].show_after = val
                did_change_show_after = true
            end
            --only register change on mouse up or on finishing keyboard editing
            if not ImGui.IsItemActive(ctx) and did_change_show_after then
                did_change_show_after = false
                SetDirty(files[cur_file_idx])
            end
            ImGui.SameLine(ctx)
            ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha, 0.5)
            MoveCursor(10, -2)
            ImGui.Text(ctx, "Close on unmatched key")
            ImGui.PopStyleVar(ctx)
            ImGui.SameLine(ctx)
            MoveCursor(0, -2)
            ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0xffffff2f)
            ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, 0xffffff4f)
            ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, 0xffffff5f)
            ImGui.PushItemWidth(ctx, 30)
            local ret, val = ImGui.Checkbox(ctx, "##closeUnmatched", files[cur_file_idx].close_on_unmatched)
            if ret then
                files[cur_file_idx].close_on_unmatched = val
                SetDirty(files[cur_file_idx])
            end
            ImGui.PopItemWidth(ctx)
            ImGui.PopStyleColor(ctx, 3)
            ImGui.SameLine(ctx)
            avail_x = ImGui.GetContentRegionAvail(ctx)
            MoveCursor(avail_x - 294, -3)
            ImGui.SetNextWindowPos(ctx, 0, 0, ImGui.Cond_Appearing, 1, 0)
            if edit_frame_count == 0 then
                --Ugly hack. Move window to the side and back at the middle to somehow avoid flickering color popups. Only draw window content after that.
                edit_flags = ImGui.WindowFlags_AlwaysAutoResize
                ImGui.SetNextWindowPos(ctx, center[1], center[2], ImGui.Cond_Always, 0.5, 0.5)
            end
            edit_frame_count = edit_frame_count - 1
            if Button("Edit style", 100) then
                current_style = CloneStyle(files[cur_file_idx].style)
                --store hwnd here because setfocus(find_window("key sequences")) doesn't work for some reason ?
                main_hwnd = reaper.JS_Window_GetFocus()
                edit_frame_count = 2
                edit_flags = ImGui.WindowFlags_NoTitleBar | ImGui.WindowFlags_NoBackground |
                    ImGui.WindowFlags_AlwaysAutoResize
                ImGui.OpenPopup(ctx, "Edit style##" .. tostring(cur_file_idx))
            end

            local shown = edit_frame_count <= 0
            if edit_frame_count == -1 then
                ImGui.SetNextWindowPos(ctx, center[1], center[2], ImGui.Cond_Always, 0.5, 0.5)
            end

            ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 10, 10)
            ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 10, 8)
            if ImGui.BeginPopupModal(ctx, "Edit style##" .. tostring(cur_file_idx), nil, edit_flags) then
                local focus = "None"
                ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, 0x2D2D2Dff)
                local preview_window_name = "SequencePreview"
                ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0xffffff2f)
                ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, 0xffffff4f)
                ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, 0xffffff5f)
                avail_x = ImGui.GetContentRegionAvail(ctx)
                if shown and ImGui.BeginChild(ctx, "LeftPreview", 200, 138) then
                    MoveCursor(100 - ImGui.CalcTextSize(ctx, "Position") / 2, 10)
                    ImGui.Text(ctx, "Position")
                    MoveCursor(20, 5)
                    --Smaller radiobuttons
                    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 5, 5)
                    _, current_style.pos_mode = ImGui.RadioButtonEx(ctx, " Mouse##position",
                        current_style.pos_mode, 0)
                    if ImGui.IsItemHovered(ctx) then
                        focus = "PosMode"
                    end
                    ImGui.SameLine(ctx)
                    MoveCursor(20, 0)
                    _, current_style.pos_mode = ImGui.RadioButtonEx(ctx, "  Fixed##position",
                        current_style.pos_mode,
                        1)
                    if ImGui.IsItemHovered(ctx) then
                        focus = "PosMode"
                    end
                    ImGui.PopStyleVar(ctx, 1)
                    if current_style.pos_mode == 1 then
                        -- Fixed mode
                        MoveCursor(5, 5)
                        ImGui.PushItemWidth(ctx, 190)
                        _, current_style.pos_x = DragDouble("##previewPosX", current_style.pos_x, 1, 0, 2000,
                            "x: %.0fpx")
                        if ImGui.IsItemHovered(ctx) then
                            focus = "FixedPos"
                        end
                        MoveCursor(5, 0)
                        _, current_style.pos_y = DragDouble("##previewPosY", current_style.pos_y, 1, 0, 2000,
                            "y: %.0fpx")
                        if ImGui.IsItemHovered(ctx) then
                            focus = "FixedPos"
                        end
                        ImGui.PopItemWidth(ctx)
                    else
                        -- Mouse mode
                        MoveCursor(5, 5)
                        ImGui.PushItemWidth(ctx, 190)
                        _, current_style.mouse_v_align = ImGui.Combo(ctx, "##VAlign", current_style.mouse_v_align
                            ,
                            "Vertical: Bottom\0Vertical: Middle\0Vertical: Top\0")
                        if ImGui.IsItemHovered(ctx) then
                            focus = "MousePos"
                        end
                        MoveCursor(5, 0)
                        _, current_style.mouse_h_align = ImGui.Combo(ctx, "##HAlign", current_style.mouse_h_align
                            ,
                            "Horizontal: Left\0Horizontal: Middle\0Horizontal: Right\0")
                        if ImGui.IsItemHovered(ctx) then
                            focus = "MousePos"
                        end
                        ImGui.PopItemWidth(ctx)
                    end
                    ImGui.EndChild(ctx)
                end
                ImGui.SameLine(ctx)

                if shown and ImGui.BeginChild(ctx, "MidPreview", 200, 138) then
                    MoveCursor(100 - ImGui.CalcTextSize(ctx, "Size") / 2, 10)
                    ImGui.Text(ctx, "Size")
                    MoveCursor(25, 5)
                    -- small radio buttons
                    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 5, 5)
                    _, current_style.size_mode = ImGui.RadioButtonEx(ctx, "Auto##size", current_style.size_mode, 0)
                    if ImGui.IsItemHovered(ctx) then
                        focus = "SizeMode"
                    end
                    ImGui.SameLine(ctx)
                    MoveCursor(20, 0)
                    _, current_style.size_mode = ImGui.RadioButtonEx(ctx, "Fixed##size", current_style.size_mode,
                        1)
                    ImGui.PopStyleVar(ctx)
                    if ImGui.IsItemHovered(ctx) then
                        focus = "SizeMode"
                    end
                    if current_style.size_mode == 0 then
                        -- Auto
                        current_style.width = nil
                        current_style.height = nil
                    else
                        ImGui.PushItemWidth(ctx, 190)
                        MoveCursor(5, 5)
                        _, current_style.width = DragDouble("##previewWidth", current_style.width, 1, 50, 1000,
                            "Width: %.0fpx")
                        if ImGui.IsItemHovered(ctx) then
                            focus = "FixedSize"
                        end
                        MoveCursor(5, 0)
                        _, current_style.height = DragDouble("##previewHeight", current_style.height, 1, 50, 1000,
                            "Height: %.0fpx")
                        if ImGui.IsItemHovered(ctx) then
                            focus = "FixedSize"
                        end
                        ImGui.PopItemWidth(ctx)
                    end
                    ImGui.EndChild(ctx)
                end
                ImGui.SameLine(ctx)

                if shown and ImGui.BeginChild(ctx, "RightPreview", 200, 138) then
                    MoveCursor(100 - ImGui.CalcTextSize(ctx, "Layout") / 2, 10)
                    ImGui.Text(ctx, "Layout")
                    MoveCursor(0, 10)
                    ImGui.PushItemWidth(ctx, 190)
                    MoveCursor(5, 0)
                    _, current_style.padding = DragDouble("##previewPadding", current_style.padding, .1, 0, 60,
                        "Padding: %.1f")
                    if ImGui.IsItemHovered(ctx) then
                        focus = "Padding"
                    end
                    MoveCursor(5, 0)
                    _, current_style.line_offset = DragDouble("##previewLineOffset", current_style.line_offset, .1, 0,
                        60, "Line offset: %.1f")
                    if ImGui.IsItemHovered(ctx) then
                        focus = "LineOffset"
                    end
                    MoveCursor(5, 0)
                    _, current_style.desc_offset = DragDouble("##previewDescOffset", current_style.desc_offset, .1, 0,
                        60, "Desc offset: %.1f")
                    if ImGui.IsItemHovered(ctx) then
                        focus = "DescOffset"
                    end
                    ImGui.PopItemWidth(ctx)
                    ImGui.EndChild(ctx)
                end

                local font_input_active = false
                if shown then
                    MoveCursor(0, 4)
                end
                if shown and ImGui.BeginChild(ctx, "BottomLeftPreview", 300, 113) then
                    avail_x, avail_y = ImGui.GetContentRegionAvail(ctx)
                    x, y = ImGui.GetCursorScreenPos(ctx)
                    MoveCursor(150 - ImGui.CalcTextSize(ctx, "Font") / 2, 8)
                    ImGui.Text(ctx, "Font")
                    ImGui.PushItemWidth(ctx, 280)
                    MoveCursor(10, 15)
                    _, current_style.font = ImGui.InputText(ctx, "##previewFont", current_style.font)
                    font_input_active = ImGui.IsItemActive(ctx)
                    if ImGui.IsItemHovered(ctx) then
                        focus = "Font"
                    end
                    MoveCursor(10, 2)
                    _, current_style.font_size = DragDouble("##previewFontSize", current_style.font_size, .5, 3, 100,
                        "Font size: %.1f")
                    if ImGui.IsItemHovered(ctx) then
                        focus = "FontSize"
                    end
                    ImGui.PopItemWidth(ctx)
                    ImGui.EndChild(ctx)
                end
                ImGui.SameLine(ctx)

                if shown and ImGui.BeginChild(ctx, "BottomRightPreview", -FLT_MIN, 108) then
                    MoveCursor(150 - ImGui.CalcTextSize(ctx, "Colors") / 2, 10)
                    ImGui.Text(ctx, "Colors")
                    MoveCursor(10, 10)
                    _, current_style.foreground_color = ImGui.ColorEdit3(ctx, "##previewFG",
                        current_style.foreground_color,
                        ImGui.ColorEditFlags_NoInputs)
                    if ImGui.IsItemHovered(ctx) then
                        focus = "FG"
                    end
                    ImGui.SameLine(ctx)
                    ImGui.Text(ctx, "Text")
                    if ImGui.IsItemHovered(ctx) then
                        focus = "FG"
                    end
                    ImGui.SameLine(ctx)
                    MoveCursor(60, 0)
                    _, current_style.hover_color = ImGui.ColorEdit3(ctx, "##previewHover",
                        current_style.hover_color,
                        ImGui.ColorEditFlags_NoInputs)
                    if ImGui.IsItemHovered(ctx) then
                        focus = "Hover"
                    end
                    ImGui.SameLine(ctx)
                    ImGui.Text(ctx, "Hover")
                    if ImGui.IsItemHovered(ctx) then
                        focus = "Hover"
                    end
                    MoveCursor(10, 0)
                    _, current_style.background_color = ImGui.ColorEdit3(ctx, "##previewBG",
                        current_style.background_color,
                        ImGui.ColorEditFlags_NoInputs)
                    if ImGui.IsItemHovered(ctx) then
                        focus = "BG"
                    end
                    ImGui.SameLine(ctx)
                    ImGui.Text(ctx, "Background")
                    if ImGui.IsItemHovered(ctx) then
                        focus = "BG"
                    end
                    ImGui.SameLine(ctx)
                    MoveCursor(20, 0)
                    _, current_style.flash_color = ImGui.ColorEdit3(ctx, "##previewFlash",
                        current_style.flash_color,
                        ImGui.ColorEditFlags_NoInputs)
                    if ImGui.IsItemHovered(ctx) then
                        focus = "Flash"
                    end
                    ImGui.SameLine(ctx)
                    ImGui.Text(ctx, "Flash")
                    if ImGui.IsItemHovered(ctx) then
                        focus = "Flash"
                    end
                    ImGui.EndChild(ctx)
                end

                if shown then
                    MoveCursor(0, 5)
                end
                if shown and ImGui.BeginChild(ctx, "##previewHelp", -FLT_MIN, 30) then
                    MoveCursor(10, 8)
                    ImGui.Text(ctx, style_help_text[focus])
                    ImGui.EndChild(ctx)
                end
                ImGui.PopStyleColor(ctx, 4)

                local quit_from_gfx = false
                if preview_opened then
                    local char, _, _, _, _ = UI(files[cur_file_idx].actions, current_style, true,
                        preview_window_name)
                    if char == 112 then --Pressed P in gfx
                        quit_from_gfx = true
                    end
                end
                if (not font_input_active and ImGui.IsKeyPressed(ctx, ImGui.Key_P)) or quit_from_gfx then
                    if not preview_opened then
                        --reset opened state
                        current_style.first_frame = true
                        current_style.shown = false
                        preview_opened = true
                    else
                        preview_opened = false
                        gfx.quit()
                        reaper.JS_Window_SetFocus(main_hwnd)
                    end
                end

                if shown then
                    MoveCursor(0, 10)
                    if Button("...", 20) then
                        ImGui.OpenPopup(ctx, "MorePopup")
                    end
                    if ImGui.BeginPopupContextItem(ctx, 'MorePopup') then
                        ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, 0xffffff44)
                        if ImGui.Selectable(ctx, "Copy style", false) then
                            copied_style = CloneStyle(current_style)
                        end
                        if copied_style == nil then
                            ImGui.BeginDisabled(ctx)
                        end
                        if ImGui.Selectable(ctx, "Paste style", false) then
                            PasteStyleToCurrent(copied_style)
                        end
                        if copied_style == nil then
                            ImGui.EndDisabled(ctx)
                        end
                        if ImGui.Selectable(ctx, "Reset to defaults", false) then
                            current_style = CloneStyle(default_style)
                        end
                        if ImGui.Selectable(ctx, "Save as default for new sequences", false) then
                            SaveCurrentStyleToDefaultStyleFile()
                        end
                        if ImGui.Selectable(ctx, "Apply to all existing sequences", false) then
                            local msg =
                                "Are you sure you want to apply this style to all existing sequences ?\n This will modify "
                                .. #files .. " sequences."
                            if reaper.ShowMessageBox(msg, "This action is irreversible", 1) == 1 then
                                for _, file in ipairs(files) do
                                    file.style = CloneStyle(current_style)
                                    SetDirty(file)
                                end
                            end
                        end
                        ImGui.PopStyleColor(ctx)
                        ImGui.EndPopup(ctx)
                    end
                    ImGui.SameLine(ctx)
                    avail_x = ImGui.GetContentRegionAvail(ctx)
                    if Button("Cancel", avail_x / 2.1) then
                        if preview_opened then
                            preview_opened = false
                            gfx.quit()
                        end
                        ImGui.CloseCurrentPopup(ctx)
                    end
                    ImGui.SameLine(ctx)
                    if Button("Save", -FLT_MIN) then
                        if preview_opened then
                            preview_opened = false
                            gfx.quit()
                        end
                        files[cur_file_idx].style = CloneStyle(current_style)
                        SetDirty(files[cur_file_idx])
                        ImGui.CloseCurrentPopup(ctx)
                    end
                end
                ImGui.EndPopup(ctx)
            end
            ImGui.PopStyleVar(ctx, 2)
            ImGui.SameLine(ctx)
            MoveCursor(0, -3)
            if files[cur_file_idx].command_id ~= nil then
                local section_id = sections[files[cur_file_idx].section].id
                local command_id = files[cur_file_idx].command_id
                local ret_desc, shortcut = reaper.JS_Actions_GetShortcutDesc(section_id, command_id, 0)
                if ret_desc then
                    if Button(shortcut, 155) then
                        reaper.JS_Actions_DoShortcutDialog(section_id, command_id, 0)
                    end
                    ImGui.SameLine(ctx)
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
            avail_x, avail_y = ImGui.GetContentRegionAvail(ctx)
            x, y = ImGui.GetCursorScreenPos(ctx)
            local t = table_scroll / header_h
            local action_count = #files[cur_file_idx].actions
            local header_a = math.min(1, math.max(0, 0.05 * (1 - t) + 0 * t))
            local header_col = ImGui.ColorConvertDouble4ToU32(1, 1, 1, header_a)
            local padding_table = 0
            if action_count > 0 then
                padding_table = 7
            end

            local table_h = math.min(avail_y - 36, action_count * 30 + header_h + padding_table)
            local table_flags = ImGui.TableFlags_RowBg | ImGui.TableFlags_ScrollY
            local cur_file_actions = files[cur_file_idx].actions
            local has_actions = #cur_file_actions > 0
            if has_actions and ImGui.BeginTable(ctx, "table", 3, table_flags, avail_x, table_h) then
                ImGui.DrawList_AddRectFilled(draw_list, x, y, x + avail_x, y + table_h, 0xffffff14, 3, rect_flags)
                ImGui.DrawList_AddRectFilled(draw_list, x, y, x + avail_x, y + header_h, header_col, 3, rect_flags)
                table_scroll = ImGui.GetScrollY(ctx)
                ImGui.TableSetupColumn(ctx, "", ImGui.TableColumnFlags_WidthFixed, 51)
                ImGui.TableSetupColumn(ctx, "", ImGui.TableColumnFlags_WidthFixed,
                    160)
                ImGui.TableSetupColumn(ctx, "",
                    ImGui.TableColumnFlags_WidthStretch)
                ImGui.TableNextRow(ctx)
                ImGui.TableNextColumn(ctx)
                ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha, 0.6)
                ImGui.TableNextColumn(ctx)
                MoveCursor(69, 0)
                ImGui.Text(ctx, "Key")
                ImGui.TableNextColumn(ctx)
                MoveCursor(6, 0)
                ImGui.Text(ctx, "Action / Text")
                ImGui.PopStyleVar(ctx)
                if action_count > 0 then
                    -- Pad the top of first row
                    ImGui.Dummy(ctx, 0, 0)
                end
                ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 6, 4)
                for i, action in ipairs(cur_file_actions) do
                    local is_text = action.text ~= nil
                    ImGui.PushID(ctx, tostring(i))
                    ImGui.TableNextRow(ctx)
                    ImGui.TableNextColumn(ctx)
                    MoveCursor(6, 0)
                    if dragging ~= nil and i ~= dragging then
                        local is_before_dragged = i < dragging
                        ArrowButton(20, 20, is_before_dragged, false)
                        if ImGui.BeginDragDropTarget(ctx) then
                            local ret, payload = ImGui.AcceptDragDropPayload(ctx, "actiondrag")
                            if ret then
                                payload = tonumber(payload)
                                move_request_old = payload
                                move_request_new = i
                            end
                            ImGui.EndDragDropTarget(ctx)
                        end
                        ImGui.SameLine(ctx)
                    else
                        Button("", 20, 20, 1)
                        if ImGui.IsItemHovered(ctx) then
                            ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
                        end
                        if ImGui.BeginDragDropSource(ctx, ImGui.DragDropFlags_None) then
                            dragging = i
                            ImGui.SetDragDropPayload(ctx, "actiondrag", tostring(i))
                            ImGui.Text(ctx, action.text or action.display_name)
                            ImGui.EndDragDropSource(ctx)
                        end
                        local x, y = ImGui.GetCursorScreenPos(ctx)
                        ImGui.DrawList_AddCircleFilled(draw_list, x + 16, y - 14, 3, 0xffffffff, 10)
                    end
                    ImGui.SameLine(ctx)
                    MoveCursor(-3, 0)
                    if DeleteButton("##deleteAction") then
                        table.remove(files[cur_file_idx].actions, i)
                        SetDirty(files[cur_file_idx])
                    end
                    ImGui.TableNextColumn(ctx)
                    if not is_text and Button(action.key_text, -FLT_MIN) then
                        key_popup_requested = true
                        waiting_for_key = i
                    end
                    if not is_text and waiting_for_key == i then
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

                    ImGui.TableNextColumn(ctx)
                    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ButtonTextAlign, 0, 0.5)
                    if is_text then
                        local btn_text = action.text
                        local alpha = nil
                        if btn_text == "" then
                            alpha = 0.5
                            btn_text = "(Empty)"
                        end
                        if Button("  " .. btn_text, -6, nil, alpha) then
                            ImGui.OpenPopup(ctx, "Edit text##" .. tostring(i))
                            edit_wants_focus = true
                            new_text = action.text
                        end
                    else
                        local btn_text = action.display_name
                        if not action.command_exists then
                            btn_text = "  Command not found (" .. action.display_name .. ")"
                        else
                            if action.display_name ~= action.action_text then
                                btn_text = btn_text .. " (" .. action.action_text .. ")"
                            end
                        end
                        if not action.exit then
                            btn_text = "  " .. btn_text
                        end
                        if action.hidden then
                            btn_text = "  " .. btn_text
                        end
                        if Button("  " .. btn_text, -6) then
                            new_display_name = action.display_name
                            new_exit = action.exit
                            new_hide = action.hidden
                            edit_wants_focus = true
                            ImGui.OpenPopup(ctx, "Edit action##" .. tostring(i))
                        end
                        local x, y = ImGui.GetItemRectMin(ctx)
                        if not action.command_exists then
                            ImGui.DrawList_AddCircleFilled(draw_list, x + 9, y + 10, 3, 0xff2222aa, 10)
                            x = x + 8
                        end
                        if action.hidden then
                            ImGui.DrawList_AddCircleFilled(draw_list, x + 9, y + 10, 3, 0x00aaffaa, 10)
                            x = x + 8
                        end
                        if not action.exit then
                            ImGui.DrawList_AddCircleFilled(draw_list, x + 9, y + 10, 3, 0xffffffaa, 10)
                        end
                    end
                    ImGui.PopStyleVar(ctx)

                    ImGui.SetNextWindowPos(ctx, center[1], center[2], ImGui.Cond_Appearing, 0.5, 0.5)
                    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 10, 10)
                    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 10, 8)
                    if ImGui.BeginPopupModal(ctx, "Edit action##" .. tostring(i), nil, popup_flags) then
                        ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0x444444ff)
                        ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha, 0.7)
                        MoveCursor(3, 16)
                        ImGui.Text(ctx, "Display Name")
                        ImGui.PopStyleVar(ctx)
                        ImGui.SameLine(ctx)
                        MoveCursor(6, -6)
                        if edit_wants_focus then
                            ImGui.SetKeyboardFocusHere(ctx)
                            edit_wants_focus = false
                        end
                        ImGui.PushItemWidth(ctx, 300)
                        _, new_display_name = ImGui.InputText(ctx, "##actionname", new_display_name)
                        ImGui.PopItemWidth(ctx)
                        ImGui.SameLine(ctx)
                        MoveCursor(-2, -6)
                        local default_name_disabled = new_display_name == action.action_text
                        if default_name_disabled then
                            ImGui.BeginDisabled(ctx)
                        end
                        if DeleteButton("##defaultname", 29, 29) then
                            new_display_name = action.action_text
                        end
                        if default_name_disabled then
                            ImGui.EndDisabled(ctx)
                        end
                        ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha, 0.7)
                        MoveCursor(3, 0)
                        ImGui.Text(ctx, "Keep Open")
                        ImGui.PopStyleVar(ctx)
                        ImGui.SameLine(ctx)
                        MoveCursor(21, -6)
                        _, new_exit = ImGui.Checkbox(ctx, "##keepopen", not new_exit)
                        ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha, 0.7)
                        MoveCursor(3, 7)
                        ImGui.Text(ctx, "Hide")
                        ImGui.PopStyleVar(ctx)
                        ImGui.SameLine(ctx)
                        MoveCursor(57, -6)
                        _, new_hide = ImGui.Checkbox(ctx, "##hide", new_hide)
                        MoveCursor(0, 10)
                        new_exit = not new_exit
                        if Button("Change Action", -FLT_MIN, 30) then
                            if new_display_name == "" then
                                new_display_name = action.action_text
                            end
                            action.display_name = Sanitize(new_display_name)
                            action.exit = new_exit
                            action.hidden = new_hide
                            SetDirty(files[cur_file_idx])
                            ImGui.CloseCurrentPopup(ctx)
                            action_popup_requested = true
                            waiting_for_action = i
                        end
                        ImGui.PopStyleColor(ctx)
                        MoveCursor(0, 6)
                        local avail_x = ImGui.GetContentRegionAvail(ctx)
                        if Button("Cancel##edit", avail_x / 2.1) then
                            ImGui.CloseCurrentPopup(ctx)
                        end
                        ImGui.SameLine(ctx)
                        local enter_pressed = ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter)
                        enter_pressed = enter_pressed or ImGui.IsKeyPressed(ctx, ImGui.Key_Enter)
                        if Button("Ok##edit", -FLT_MIN) or enter_pressed then
                            if new_display_name == "" then
                                new_display_name = action.action_text
                            end
                            action.display_name = Sanitize(new_display_name)
                            action.exit = new_exit
                            action.hidden = new_hide
                            SetDirty(files[cur_file_idx])
                            ImGui.CloseCurrentPopup(ctx)
                        end
                        ImGui.EndPopup(ctx)
                    end
                    ImGui.PopStyleVar(ctx, 2)
                    local ret_text = TextPopup("Edit text##" .. tostring(i))
                    if ret_text ~= nil then
                        action.text = Sanitize(ret_text)
                        SetDirty(files[cur_file_idx])
                    end

                    if waiting_for_action == i then
                        local ret, new_action, native, new_action_text = ActionPopup(tostring(i),
                            sections[files[cur_file_idx].section].id)
                        if ret == nil then
                            waiting_for_action = -1
                        elseif ret then
                            if not action.command_exists or action.action_text == action.display_name then
                                action.display_name = new_action_text
                            end
                            action.action = new_action
                            action.action_text = new_action_text
                            action.native = native
                            SetDirty(files[cur_file_idx])
                            waiting_for_action = -1
                        end
                    end
                    ImGui.PopID(ctx)
                end
                ImGui.PopStyleVar(ctx)
                ImGui.EndTable(ctx)
                if not ImGui.IsAnyMouseDown(ctx) then
                    dragging = nil
                end
                if move_request_new ~= nil then
                    Move(cur_file_actions, move_request_old, move_request_new)
                    move_request_new = nil
                    move_request_old = nil
                    SetDirty(files[cur_file_idx])
                end
            end
            local avail_x = ImGui.GetContentRegionAvail(ctx)
            MoveCursor(0, 6)
            if Button("Add Shortcut", avail_x / 2, 25) then
                adding = {
                    key_text = "...",
                    action_text = "...",
                    action = -1,
                    key = -1,
                    exit = true,
                    display_name = "..."
                }
                key_popup_requested = true
                waiting_for_key = 0
            end
            ImGui.SameLine(ctx)
            if Button("Add Text/Separator", -FLT_MIN, 25) then
                new_text = ""
                edit_wants_focus = true
                ImGui.OpenPopup(ctx, "New text")
            end
            local ret_text = TextPopup("New text")
            if ret_text ~= nil then
                table.insert(cur_file_actions, { text = Sanitize(ret_text) })
                SetDirty(files[cur_file_idx])
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
                local ret, action, native, action_text = ActionPopup("new", sections[files[cur_file_idx].section].id)
                if ret == nil then
                    waiting_for_action = -1
                elseif ret then
                    action_text = Sanitize(action_text)
                    adding.action = action
                    adding.action_text = action_text
                    adding.display_name = action_text
                    adding.native = native
                    table.insert(files[cur_file_idx].actions, adding)
                    SetDirty(files[cur_file_idx])
                    waiting_for_action = -1
                end
            end
            ImGui.EndChild(ctx)
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
    local window_flags = ImGui.WindowFlags_NoCollapse
    if #dirty > 0 or #removed > 0 then
        --Auto save so flags are not needed
        --(note that it -should- be possible to remove this, add the flag back, and get a correct "save on close" behavior)
        Save()
        Load()
        --window_flags = window_flags | ImGui.WindowFlags_UnsavedDocument
    end
    if font_name ~= nil then
        ImGui.PushFont(ctx, font)
    end
    for _, color in pairs(colors) do
        ImGui.PushStyleColor(ctx, color[1], color[2])
    end
    for _, style in pairs(styles) do
        ImGui.PushStyleVar(ctx, style[1], style[2], style[3])
    end
    ImGui.SetNextWindowSize(ctx, 700, 300, ImGui.Cond_FirstUseEver)
    --title bar padding
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 10, 8)
    local visible, open = ImGui.Begin(ctx, imgui_window_name, true, window_flags)
    ImGui.PopStyleVar(ctx)
    if visible then
        Frame()
        ImGui.End(ctx)
    end
    if font_name ~= nil then
        ImGui.PopFont(ctx)
    end
    ImGui.PopStyleVar(ctx, #styles)
    ImGui.PopStyleColor(ctx, #colors)
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
    end
end

Load()
reaper.defer(Loop)
