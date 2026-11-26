-- ============================================================
--  ConfigWindow.lua
--  Janela de configuração aberta por /wu, no estilo do painel de Opções
--  da Blizzard: moldura de metal, lista de categorias à esquerda (grupos
--  de UI/ConfigPages.lua), página à direita com título, "Defaults" e
--  rolagem, rodapé com versão/licença e "Close". A janela é nossa (não o
--  painel da Blizzard) para poder ser arrastada enquanto o jogador posiciona
--  as barras; a posição fica salva. Só monta a interface; as páginas vêm do
--  PageBuilder e gravam na Config.
-- ============================================================

local _, ns = ...
local L = ns.L

local Window = {}
ns.ConfigWindow = Window

local Skin = ns.Skin

local WIDTH, HEIGHT = 800, 600
local LIST_WIDTH = 190
local INSET_TOP, INSET_SIDE, FOOTER_HEIGHT = 30, 14, 44
local CONTENT_LEFT = INSET_SIDE + LIST_WIDTH + 12
local SCROLLBAR_ROOM = 24
local HEADER_HEIGHT = 44
local CATEGORY_HEIGHT, GROUP_HEIGHT, GROUP_GAP = 20, 30, 18
local GROUP_ATLASES = { "Options_CategoryHeader_1", "Options_CategoryHeader_2" }
local FALLBACK_AUTHOR = "rafacf95"
local COPYRIGHT_YEAR = 2026
local RESET_POPUP = "WOWUTILITIES_RESET_PAGE"

local frame, title, current
local pages, buttons = {}, {}   -- [id] = { def, scroll, page } | [id] = botão da lista

-- ----------------------------------------------------------------
-- Travas do Edit Mode
-- ----------------------------------------------------------------

local function Locked(path)
    return ns.Positioner.IsEditedInEditMode(path) and not ns.Config:Get("ui.allowWindowEdit")
end

-- ----------------------------------------------------------------
-- Posição salva
-- ----------------------------------------------------------------

local function RestorePosition()
    local saved = ns.db and ns.db.ui and ns.db.ui.window
    frame:ClearAllPoints()
    if type(saved) == "table" and saved.point then
        frame:SetPoint(saved.point, UIParent, saved.relPoint or saved.point, saved.x or 0, saved.y or 0)
    else
        frame:SetPoint("CENTER")
    end
end

local function SavePosition()
    if not (ns.db and ns.db.ui) then return end
    local point, _, relPoint, x, y = frame:GetPoint(1)
    if point then ns.db.ui.window = { point = point, relPoint = relPoint, x = x, y = y } end
end

-- ----------------------------------------------------------------
-- "Defaults" da página (com confirmação)
-- ----------------------------------------------------------------

local function ResetPage(def)
    for _, section in ipairs(def.sections) do ns.Config:ResetSection(section) end
    Window:Refresh()
end

local function RegisterResetPopup()
    if type(StaticPopupDialogs) ~= "table" or StaticPopupDialogs[RESET_POPUP] then return end
    StaticPopupDialogs[RESET_POPUP] = {
        text = L["Restore the default settings of \"%s\"?"],
        button1 = ACCEPT or "Accept",
        button2 = CANCEL or "Cancel",
        OnAccept = function(_, data) if type(data) == "function" then data() end end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

local function AskReset()
    local entry = current and pages[current]
    if not entry then return end
    RegisterResetPopup()
    if type(StaticPopup_Show) == "function" and StaticPopupDialogs[RESET_POPUP] then
        StaticPopup_Show(RESET_POPUP, entry.def.title, nil, function() ResetPage(entry.def) end)
    else
        ResetPage(entry.def)
    end
end

-- ----------------------------------------------------------------
-- Lista de categorias (à esquerda)
-- ----------------------------------------------------------------

local function StyleButton(button, selected)
    local font = selected and rawget(_G, "GameFontHighlight") or rawget(_G, "GameFontNormal")
    if font then button.Label:SetFontObject(font) end
    if button.Active then button.Active:SetShown(selected) end
end

local function CategoryButton(parent, def, y)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(LIST_WIDTH, CATEGORY_HEIGHT)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    button.Active = Skin.AtlasTexture(button, "BACKGROUND", "Options_List_Active")
    if button.Active then
        button.Active:SetPoint("LEFT")
        button.Active:SetSize(LIST_WIDTH - 8, CATEGORY_HEIGHT + 1)
    end
    local hover = Skin.AtlasTexture(button, "HIGHLIGHT", "Options_List_Hover")
    if hover then
        hover:SetPoint("LEFT")
        hover:SetSize(LIST_WIDTH - 8, CATEGORY_HEIGHT + 1)
    end
    button.Label = Skin.Text(button, def.title, "GameFontNormal")
    button.Label:SetPoint("LEFT", button, "LEFT", 24, 0)
    button.def = def
    button:SetScript("OnClick", function() Window:Select(def.id) end)
    StyleButton(button, false)
    return button
end

local function BuildList(list)
    local y = 0
    for index, group in ipairs(ns.ConfigPages.GROUPS) do
        local header = CreateFrame("Frame", nil, list)
        header:SetSize(LIST_WIDTH, GROUP_HEIGHT)
        header:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y)
        local bg = Skin.AtlasTexture(header, "ARTWORK", GROUP_ATLASES[(index - 1) % #GROUP_ATLASES + 1], true)
        if bg then
            bg:SetPoint("TOPLEFT")
            bg:SetWidth(LIST_WIDTH)
        end
        Skin.Text(header, group.title, "GameFontHighlightMedium"):SetPoint("LEFT", header, "LEFT", 12, 0)
        y = y + GROUP_HEIGHT
        for _, def in ipairs(group.pages) do
            buttons[def.id] = CategoryButton(list, def, y)
            y = y + CATEGORY_HEIGHT
        end
        y = y + GROUP_GAP
    end
end

-- ----------------------------------------------------------------
-- Páginas (à direita)
-- ----------------------------------------------------------------

local function BuildPage(area, def)
    local width = WIDTH - CONTENT_LEFT - INSET_SIDE - SCROLLBAR_ROOM
    local scroll, content = Skin.Scroll(area, width)
    scroll:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -HEADER_HEIGHT)
    scroll:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -SCROLLBAR_ROOM, 0)
    scroll:Hide()
    local page = ns.PageBuilder.Build(content, def.rows, { locked = Locked })
    pages[def.id] = { def = def, scroll = scroll, page = page }
end

local function AddonMeta(field)
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if type(get) ~= "function" then return nil end
    local ok, value = pcall(get, "WowUtilities", field)
    if ok and type(value) == "string" and value ~= "" then return value end
end

local function BuildFooter()
    local author = AddonMeta("Author") or FALLBACK_AUTHOR
    local version = AddonMeta("Version") or "?"
    if version:find("^@") then version = "dev" end -- código-fonte: o empacotador ainda não trocou o marcador
    version = version:gsub("^v", "")               -- tag "v4.3.3" -> "4.3.3"

    local top = Skin.Text(frame, string.format(L["WowUtilities v%s · by %s"], version, author), "GameFontHighlightSmall")
    top:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", INSET_SIDE + 4, 24)
    local rights = Skin.Text(frame, string.format(L["© %d %s. All rights reserved."], COPYRIGHT_YEAR, author),
        "GameFontDisableSmall")
    rights:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", INSET_SIDE + 4, 10)

    local close = Skin.Button(frame, L["Close"], 96, function() frame:Hide() end)
    close:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -INSET_SIDE - 2, 12)
end

-- ----------------------------------------------------------------
-- Montagem
-- ----------------------------------------------------------------

local function Build()
    frame = Skin.Window("WowUtilitiesConfig", "WowUtilities", WIDTH, HEIGHT)
    frame:SetFrameStrata("HIGH") -- abaixo do ColorPickerFrame (DIALOG)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    RestorePosition()
    frame:Hide()

    local list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT", frame, "TOPLEFT", INSET_SIDE, -INSET_TOP)
    list:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", INSET_SIDE, FOOTER_HEIGHT)
    list:SetWidth(LIST_WIDTH)
    BuildList(list)

    local area = CreateFrame("Frame", nil, frame)
    area:SetPoint("TOPLEFT", frame, "TOPLEFT", CONTENT_LEFT, -INSET_TOP)
    area:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -INSET_SIDE, FOOTER_HEIGHT)

    title = Skin.Text(area, "", "GameFontHighlightHuge")
    title:SetPoint("TOPLEFT", area, "TOPLEFT", 7, -10)
    local defaults = Skin.Button(area, L["Defaults"], 96, AskReset)
    defaults:SetPoint("TOPRIGHT", area, "TOPRIGHT", -4, -8)
    local divider = Skin.Divider(area)
    divider:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -HEADER_HEIGHT + 4)
    divider:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, -HEADER_HEIGHT + 4)

    for _, group in ipairs(ns.ConfigPages.GROUPS) do
        for _, def in ipairs(group.pages) do BuildPage(area, def) end
    end

    BuildFooter()

    frame:SetScript("OnShow", function() Window:Refresh() end)
    frame:SetScript("OnHide", function()
        ns.FlightCastBar:Preview(false)
        ns.Positioner:SetUnlocked(false)
        if ns.TrinketSelector.positioner then ns.TrinketSelector.positioner:SetUnlocked(false) end
    end)

    tinsert(UISpecialFrames, "WowUtilitiesConfig") -- ESC fecha
    Window:Select(ns.ConfigPages.GROUPS[1].pages[1].id)
end

-- ----------------------------------------------------------------
-- API
-- ----------------------------------------------------------------

--- Mostra a página `id` (ex.: "flight").
function Window:Select(id)
    if not pages[id] then return end
    current = id
    for pageId, entry in pairs(pages) do entry.scroll:SetShown(pageId == id) end
    for pageId, button in pairs(buttons) do StyleButton(button, pageId == id) end
    title:SetText(pages[id].def.title)
    pages[id].page:Refresh()
end

--- Página aberta no momento.
function Window:Current() return current end

--- Controle de uma opção (caminho da configuração ou rótulo de uma caixa avulsa).
function Window:Control(key)
    for _, entry in pairs(pages) do
        local control = entry.page.controls[key]
        if control then return control end
    end
end

function Window:Refresh()
    for _, entry in pairs(pages) do entry.page:Refresh() end
end

function Window:Frame() return frame end

function Window:Toggle()
    if not frame then Build() end
    frame:SetShown(not frame:IsShown())
end

ns.Bus:Subscribe("CONFIG_CHANGED", function()
    if frame and frame:IsShown() then Window:Refresh() end
end)

ns.Commands:SetDefault(function() Window:Toggle() end)
