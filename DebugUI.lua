-- ============================================================
--  DebugUI.lua
--  /wu debug ui — o que o cliente oferece para imitar o visual do painel
--  de Opções da Blizzard na janela /wu:
--    * a estrutura do próprio painel (SettingsPanel): moldura, fundo,
--      lista de categorias, linhas de controles, fontes e atlas usados;
--    * quais templates candidatos existem (cada um é criado escondido,
--      dentro de um frame invisível, e listado com as peças que tem);
--    * quais atlas e fontes candidatos existem.
--  Para o relatório mais útil, abra antes o painel de Opções (Esc > Opções)
--  na página Gameplay > Controls. Só lê; os frames de teste ficam escondidos.
--  Report monta as linhas (testável sem o jogo); o comando abre a janela de
--  texto copiável.
-- ============================================================

local _, ns = ...

local UI = {}
ns.DebugUI = UI

local Show = ns.Debug.Show

local MAX_LINES = 900       -- teto do relatório inteiro
local MAX_DEPTH = 5         -- profundidade da árvore do painel
local MAX_CHILDREN = 30     -- filhos por nó da árvore
local MAX_KEYS = 24         -- peças listadas por template

-- Templates candidatos: { tipo de frame, nome do template }
local TEMPLATES = {
    -- Molduras de janela
    { "Frame", "SettingsFrameTemplate" }, { "Frame", "ButtonFrameTemplate" },
    { "Frame", "PortraitFrameTemplate" }, { "Frame", "PortraitFrameFlatTemplate" },
    { "Frame", "BasicFrameTemplate" }, { "Frame", "BasicFrameTemplateWithInset" },
    { "Frame", "DefaultPanelTemplate" }, { "Frame", "DefaultPanelFlatTemplate" },
    { "Frame", "DialogBorderTemplate" }, { "Frame", "DialogBorderDarkTemplate" },
    { "Frame", "DialogBorderTranslucentTemplate" }, { "Frame", "UIPanelDialogTemplate" },
    { "Frame", "InsetFrameTemplate" }, { "Frame", "TooltipBackdropTemplate" },
    { "Frame", "NineSlicePanelTemplate" },
    -- Lista de categorias e cabeçalhos
    { "Button", "SettingsCategoryListButtonTemplate" }, { "Frame", "SettingsCategoryListHeaderTemplate" },
    { "Frame", "SettingsListSectionHeaderTemplate" }, { "Frame", "SettingsListElementTemplate" },
    -- Caixas de seleção
    { "CheckButton", "SettingsCheckboxTemplate" }, { "CheckButton", "UICheckButtonTemplate" },
    { "CheckButton", "InterfaceOptionsCheckButtonTemplate" }, { "CheckButton", "ChatConfigCheckButtonTemplate" },
    -- Sliders
    { "Frame", "MinimalSliderWithSteppersTemplate" }, { "Slider", "OptionsSliderTemplate" },
    { "Slider", "UISliderTemplate" }, { "Slider", "UISliderTemplateWithLabels" },
    { "Slider", "MinimalSliderTemplate" },
    -- Menus de seleção
    { "DropdownButton", "WowStyle1DropdownTemplate" }, { "DropdownButton", "WowStyle2DropdownTemplate" },
    { "Frame", "SettingsDropdownWithButtonsTemplate" }, { "Frame", "UIDropDownMenuTemplate" },
    -- Botões
    { "Button", "UIPanelButtonTemplate" }, { "Button", "SharedButtonTemplate" },
    { "Button", "SharedButtonSmallTemplate" }, { "Button", "SharedButtonLargeTemplate" },
    { "Button", "SharedGoldRedButtonTemplate" }, { "Button", "SharedGoldRedButtonSmallTemplate" },
    { "Button", "UIPanelDynamicResizeButtonTemplate" }, { "Button", "UIMenuButtonStretchTemplate" },
    { "Button", "UIPanelCloseButton" }, { "Button", "UIPanelCloseButtonNoScripts" },
    { "Button", "UIPanelSquareButton" },
    -- Cor
    { "Button", "ColorSwatchTemplate" }, { "Frame", "ColorSwatchTemplate" },
    -- Rolagem
    { "ScrollFrame", "UIPanelScrollFrameTemplate" }, { "ScrollFrame", "ScrollFrameTemplate" },
    { "Frame", "WowScrollBoxList" }, { "Frame", "WowScrollBox" }, { "EventFrame", "MinimalScrollBar" },
    -- Abas e texto
    { "Button", "PanelTopTabButtonTemplate" }, { "Button", "PanelTabButtonTemplate" },
    { "EditBox", "InputBoxTemplate" }, { "EditBox", "SearchBoxTemplate" },
}

-- Atlas candidatos (os que o painel usa aparecem também na árvore do painel)
local ATLASES = {
    "Options_List_Active", "Options_List_Hover", "Options_CategoryHeader_1", "Options_CategoryHeader_2",
    "Options_HorizontalDivider", "Options_InnerFrame", "Options_ListExpand_Right", "Options_ListExpand_Down",
    "checkbox-minimal", "checkmark-minimal", "checkbox-minimal-disabled", "checkmark-minimal-disabled",
    "Minimal_SliderBar_Button", "Minimal_SliderBar_Left", "Minimal_SliderBar_Right", "Minimal_SliderBar_Middle",
    "Minimal_SliderBar_Button_Left", "Minimal_SliderBar_Button_Right",
    "common-dropdown-a-button", "common-dropdown-a-button-hover", "common-dropdown-a-button-open",
    "128-RedButton-Up", "128-RedButton-Down", "128-RedButton-Highlight",
    "RedButton-Exit", "RedButton-exit-pressed", "UI-Frame-DiamondMetal-Header-CornerLeft",
    "minimal-scrollbar-track-top", "minimal-scrollbar-thumb-top",
}

-- Fontes candidatas
local FONTS = {
    "GameFontNormal", "GameFontNormalLarge", "GameFontNormalLarge2", "GameFontNormalHuge",
    "GameFontHighlight", "GameFontHighlightLarge", "GameFontHighlightMedium", "GameFontHighlightHuge",
    "GameFontNormalMed3", "GameFontHighlightMed2", "GameFontNormalSmall", "GameFontHighlightSmall",
    "GameFontDisable", "GameFontDisableSmall", "Game15Font_Shadow", "Game18Font", "Game20Font",
    "Game24Font", "SystemFont_Huge1", "SystemFont_Large", "SystemFont_Med1", "SystemFont_Shadow_Large",
}

-- Mixins e utilitários que indicam o sistema de menus/sliders/cor do cliente
local GLOBALS = {
    "SettingsPanel", "InterfaceOptionsFrame", "VideoOptionsFrame", "Settings", "MenuUtil", "Menu",
    "MinimalSliderWithSteppersMixin", "SettingsCheckboxMixin", "SettingsCategoryListButtonMixin",
    "ColorSwatchMixin", "ScrollUtil", "CreateScrollBoxListLinearView", "NineSliceUtil",
    "UIDropDownMenu_Initialize", "ButtonFrameTemplate_HidePortrait", "PanelTemplates_SetNumTabs",
}

local function Method(obj, name, ...)
    if type(obj) ~= "table" then return end
    local fn = obj[name]
    if type(fn) ~= "function" then return end
    return ns.SafeCall(fn, obj, ...)
end

local function IsRegion(value)
    return type(value) == "table" and type(value.GetObjectType) == "function"
end

local function Round(n)
    if type(n) ~= "number" then return n end
    return math.floor(n + 0.5)
end

local function Short(text, size)
    text = tostring(text)
    if #text > size then return text:sub(1, size) .. "..." end
    return text
end

--- Uma linha descrevendo a região: tipo, tamanho, visibilidade e o que
--- importa para copiar o visual (atlas/textura, fonte e texto, layout do NineSlice).
local function Describe(region)
    local kind = Show(Method(region, "GetObjectType"))
    local w, h = Method(region, "GetSize")
    local parts = { kind, string.format("%sx%s", Show(Round(w)), Show(Round(h))) }
    if Method(region, "IsShown") == false then parts[#parts + 1] = "hidden" end
    if kind == "Texture" then
        local atlas = Method(region, "GetAtlas")
        if atlas then parts[#parts + 1] = "atlas=" .. Show(atlas) end
        local texture = Method(region, "GetTexture")
        if texture and not atlas then parts[#parts + 1] = "tex=" .. Show(texture) end
        local layer = Method(region, "GetDrawLayer")
        if layer then parts[#parts + 1] = "layer=" .. Show(layer) end
    elseif kind == "FontString" then
        local font = Method(region, "GetFontObject")
        local fontName = font and Method(font, "GetName")
        local path, size = Method(region, "GetFont")
        parts[#parts + 1] = string.format("font=%s(%s)", Show(fontName), Show(Round(size)))
        local text = Method(region, "GetText")
        if type(text) == "string" and text ~= "" then parts[#parts + 1] = "text=\"" .. Short(text, 30) .. "\"" end
        local r, g, b = Method(region, "GetTextColor")
        if type(r) == "number" then
            parts[#parts + 1] = string.format("color=%.2f,%.2f,%.2f", r, g, b)
        end
    end
    if type(region) == "table" and type(rawget(region, "layoutType")) == "string" then
        parts[#parts + 1] = "layoutType=" .. rawget(region, "layoutType")
    end
    return table.concat(parts, " ")
end

--- Filhos e regiões de um frame, com o nome da chave no pai quando houver.
local function Children(frame)
    local list, seen = {}, {}
    if type(frame) ~= "table" then return list end
    local keys = {}
    for key, value in pairs(frame) do
        if type(key) == "string" and IsRegion(value) and value ~= frame and Method(value, "GetParent") == frame then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local value = frame[key]
        if not seen[value] then
            seen[value] = true
            list[#list + 1] = { key = key, region = value }
        end
    end
    for _, getter in ipairs({ "GetRegions", "GetChildren" }) do
        local results = { Method(frame, getter) }
        for _, region in ipairs(results) do
            if IsRegion(region) and not seen[region] then
                seen[region] = true
                list[#list + 1] = { key = Method(region, "GetName") or "?", region = region }
            end
        end
    end
    return list
end

local function Tree(add, frame, label, depth, budget)
    if budget.left <= 0 then return end
    budget.left = budget.left - 1
    add(string.rep("  ", depth) .. label .. ": " .. Describe(frame))
    if depth >= MAX_DEPTH or Method(frame, "GetObjectType") == "Texture"
        or Method(frame, "GetObjectType") == "FontString" then
        return
    end
    local children = Children(frame)
    for i, child in ipairs(children) do
        if i > MAX_CHILDREN then
            add(string.rep("  ", depth + 1) .. "... " .. (#children - MAX_CHILDREN) .. " more")
            break
        end
        Tree(add, child.region, child.key, depth + 1, budget)
    end
end

local function Environment(add)
    local version, build, _, toc = ns.SafeCall(rawget(_G, "GetBuildInfo") or function() end)
    add(string.format("Game version: %s (build %s, interface %s)", Show(version), Show(build), Show(toc)))
    local panel = rawget(_G, "SettingsPanel")
    add(string.format("SettingsPanel: %s | shown %s | movable %s",
        type(panel) == "table" and "present" or "ABSENT", Show(Method(panel, "IsShown")), Show(Method(panel, "IsMovable"))))
    local present = {}
    for _, name in ipairs(GLOBALS) do
        local v = rawget(_G, name)
        present[#present + 1] = name .. "=" .. ((type(v) == "table" or type(v) == "function") and "yes" or "no")
    end
    add("Globals: " .. table.concat(present, " "))
    local picker = rawget(_G, "ColorPickerFrame")
    add("ColorPickerFrame.SetupColorPickerAndShow: " .. Show(type(picker) == "table" and type(picker.SetupColorPickerAndShow) == "function"))
end

local function Panel(add)
    local panel = rawget(_G, "SettingsPanel")
    if type(panel) ~= "table" then
        add("SettingsPanel not found (open Esc > Options once, then run this again).")
        return
    end
    add("-- SettingsPanel tree (open it on Gameplay > Controls before running for the richest output) --")
    Tree(add, panel, "SettingsPanel", 0, { left = 420 })
end

local holder
local function Holder()
    if not holder then
        holder = CreateFrame("Frame", nil, UIParent)
        holder:Hide() -- tudo criado aqui dentro fica invisível
    end
    return holder
end

local function Templates(add)
    add("-- Templates (OK = created; pieces = keys that hold regions) --")
    for _, entry in ipairs(TEMPLATES) do
        local kind, template = entry[1], entry[2]
        local ok, frame = pcall(CreateFrame, kind, nil, Holder(), template)
        if not ok or type(frame) ~= "table" then
            add(string.format("%s (%s): FAIL %s", template, kind, Short(frame, 90)))
        else
            local keys = {}
            for key, value in pairs(frame) do
                if type(key) == "string" and IsRegion(value) and value ~= frame then keys[#keys + 1] = key end
            end
            table.sort(keys)
            local extra = #keys > MAX_KEYS and (" +" .. (#keys - MAX_KEYS)) or ""
            for i = MAX_KEYS + 1, #keys do keys[i] = nil end
            local w, h = Method(frame, "GetSize")
            add(string.format("%s (%s): OK %sx%s pieces: %s%s", template, kind, Show(Round(w)), Show(Round(h)),
                #keys > 0 and table.concat(keys, ",") or "-", extra))
            Method(frame, "Hide")
        end
    end
end

local function Atlases(add)
    local api = rawget(_G, "C_Texture")
    local info = type(api) == "table" and api.GetAtlasInfo
    if type(info) ~= "function" then
        add("Atlases: C_Texture.GetAtlasInfo ABSENT")
        return
    end
    local yes, no = {}, {}
    for _, name in ipairs(ATLASES) do
        local data = ns.SafeCall(info, name)
        if type(data) == "table" then
            yes[#yes + 1] = string.format("%s(%sx%s)", name, Show(data.width), Show(data.height))
        else
            no[#no + 1] = name
        end
    end
    add("Atlases present: " .. (#yes > 0 and table.concat(yes, " ") or "-"))
    add("Atlases absent: " .. (#no > 0 and table.concat(no, " ") or "-"))
end

local function Fonts(add)
    local yes, no = {}, {}
    for _, name in ipairs(FONTS) do
        local font = rawget(_G, name)
        if type(font) == "table" then
            local _, size = Method(font, "GetFont")
            yes[#yes + 1] = string.format("%s(%s)", name, Show(Round(size)))
        else
            no[#no + 1] = name
        end
    end
    add("Fonts present: " .. (#yes > 0 and table.concat(yes, " ") or "-"))
    add("Fonts absent: " .. (#no > 0 and table.concat(no, " ") or "-"))
end

function UI:Report()
    local lines = {}
    local function add(text)
        if #lines < MAX_LINES then lines[#lines + 1] = text
        elseif #lines == MAX_LINES then lines[#lines + 1] = "... report truncated" end
    end
    add("WowUtilities debug — ui (Blizzard look for the /wu window)")
    Environment(add)
    Fonts(add)
    Atlases(add)
    Templates(add)
    Panel(add)
    return lines
end

ns.Debug:Register("ui", function()
    local ok, lines = pcall(UI.Report, UI)
    if not ok then lines = { "WowUtilities ui debug failed: " .. tostring(lines) } end
    ns.Debug:Output("WowUtilities debug — ui", lines)
end)
