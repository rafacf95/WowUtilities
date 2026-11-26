-- ============================================================
--  ConfigWindow.lua
--  Janela de configuração aberta por /wu. Uma aba por recurso.
--  Só monta a interface e grava na Config; não contém regra de
--  negócio. A janela é criada na primeira abertura.
-- ============================================================

local _, ns = ...
local L = ns.L

local Window = {}
ns.ConfigWindow = Window

local W = ns.Widgets

-- Botão de teste da confirmação de "apagar tempos gravados": validado no jogo
-- e desativado. Para reativar, descomente esta linha e o bloco "Botão temporário"
-- na aba Flight (a confirmação em si, Request({ dryRun = true }), continua no código).
-- local SHOW_CLEAR_TEST_BUTTON = true
local frame
local tabButtons, panels, refreshables = {}, {}, {}

-- ----------------------------------------------------------------
-- Helpers de ligação com a configuração
-- ----------------------------------------------------------------

local function Bind(path)
    return function() return ns.Config:Get(path) end,
           function(value) ns.Config:Set(path, value) end
end

--- Opção que o Edit Mode já edita fica só para leitura aqui, a menos que o
--- usuário libere (rota de fuga caso o frame não apareça no Edit Mode).
local function Locked(path)
    return ns.Positioner.IsEditedInEditMode(path) and not ns.Config:Get("ui.allowWindowEdit")
end

--- Cria um widget e o registra para ser relido quando a janela abre.
--- Com `path`, o widget também é travado/destravado conforme Locked(path).
local function Track(widget, path)
    refreshables[#refreshables + 1] = widget
    if path and widget.SetLocked then
        refreshables[#refreshables + 1] = { Refresh = function() widget:SetLocked(Locked(path)) end }
    end
    return widget
end

--- Caixa "Forçar edição" (rota de fuga, uma só configuração para as duas abas);
--- só aparece quando há opções editadas no Edit Mode.
local function ForceEditBox(panel, x, y)
    local box = W.Checkbox(panel, L["Force edit"],
        function() return ns.Config:Get("ui.allowWindowEdit") end,
        function(value) ns.Config:Set("ui.allowWindowEdit", value) end)
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -y)
    Track({ Refresh = function()
        box:SetShown(ns.Positioner.HasEditModeSettings())
        box:Refresh()
    end })
    return box
end

--- Aviso visível só enquanto a opção `path` estiver travada.
local function LockedHint(panel, x, y, path)
    local hint = W.Label(panel, L["Edit these options in Edit Mode."], "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -y)
    Track({ Refresh = function() hint:SetShown(Locked(path)) end })
    return hint
end

local function Checkbox(panel, x, y, text, path)
    local get, set = Bind(path)
    local box = Track(W.Checkbox(panel, text, get, set), path)
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -y)
    return box
end

local function Slider(panel, x, y, text, path, min, max, step, format)
    if min == nil then -- limites vêm da descrição compartilhada (a mesma do Edit Mode)
        local spec = ns.SettingSpecs:Get(path)
        min, max, step, format = spec.min, spec.max, spec.step, spec.format
    end
    local get, set = Bind(path)
    local slider = Track(W.Slider(panel, text, min, max, step, get, set, 200, format), path)
    slider:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -y)
    return slider
end

local function Dropdown(panel, x, y, text, path, items, opts)
    local get, set = Bind(path)
    local dropdown = Track(W.Dropdown(panel, text, items, get, set, 200, opts), path)
    dropdown:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -y)
    return dropdown
end

--- Seletor de cor ligado a um caminho que guarda { r, g, b }.
local function ColorSwatch(panel, x, y, text, path, isDisabled)
    local function get()
        local c = ns.Config:Get(path)
        return c.r, c.g, c.b
    end
    local function set(r, g, b) ns.Config:Set(path, { r = r, g = g, b = b }) end
    local function Disabled() return Locked(path) or (isDisabled and isDisabled()) or false end
    local swatch = Track(W.ColorSwatch(panel, text, get, set, Disabled))
    swatch:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -y)
    return swatch
end

--- Cada linha da lista de texturas mostra a textura na cor atual da barra.
local function TexturePreview(item)
    return item.path, ns.FlightCastBar:FillColor()
end

local function Items(list)
    return function() return list end
end

-- ----------------------------------------------------------------
-- Abas
-- ----------------------------------------------------------------

local function BuildTooltipTab(panel)
    W.Label(panel, L["Colors on player tooltips"], "GameFontNormal"):SetPoint("TOPLEFT", 12, -12)
    Checkbox(panel, 12, 40, L["Name (with title) in class color"], "tooltip.name")
    Checkbox(panel, 12, 68, L["Class and specialization in class color"], "tooltip.class")
    Checkbox(panel, 12, 96, L["Faction (Horde red, Alliance blue)"], "tooltip.faction")

    W.Label(panel, L["Border on NPC tooltips"], "GameFontNormal"):SetPoint("TOPLEFT", 12, -142)
    local function EliteOff() return not ns.Config:Get("tooltip.eliteBorder") end
    local function RareOff() return not ns.Config:Get("tooltip.rareBorder") end
    Checkbox(panel, 12, 170, L["Elite NPCs and world bosses (gold)"], "tooltip.eliteBorder")
    ColorSwatch(panel, 40, 198, L["Border color"], "tooltip.eliteColor", EliteOff)
    Checkbox(panel, 12, 232, L["Rare NPCs (silver)"], "tooltip.rareBorder")
    ColorSwatch(panel, 40, 260, L["Border color"], "tooltip.rareColor", RareOff)
end

local function BuildFlightTab(panel)
    local catalog = ns.StyleCatalog
    local COL1, COL2 = 12, 232

    -- Geral ------------------------------------------------------
    W.Label(panel, L["Flight durations"], "GameFontNormal"):SetPoint("TOPLEFT", 12, -12)
    Checkbox(panel, 12, 36, L["Show duration on the flight map tooltip"], "taxi.tooltip")
    Checkbox(panel, 12, 62, L["Show the flight bar during flights"], "taxi.bar")

    -- Barra de voo -----------------------------------------------
    local separator = panel:CreateTexture(nil, "ARTWORK")
    separator:SetColorTexture(0.4, 0.4, 0.45, 0.8)
    separator:SetHeight(1)
    separator:SetPoint("TOPLEFT", 12, -92)
    separator:SetPoint("TOPRIGHT", -12, -92)
    W.Label(panel, L["Flight bar"], "GameFontNormal"):SetPoint("TOPLEFT", 12, -102)

    LockedHint(panel, 110, 104, "bar.width")
    ForceEditBox(panel, 360, 98)
    local y = 122 -- primeira linha de controles da barra

    Dropdown(panel, COL1, y, L["Texture"], "bar.texture",
        function() return catalog:Textures() end, { preview = TexturePreview })
    Dropdown(panel, COL2, y, L["Border"], "bar.border", Items(catalog.borders))

    Slider(panel, COL1, y + 50, L["Border thickness"], "bar.borderSize")
    ColorSwatch(panel, COL2, y + 54, L["Border color"], "bar.borderColor")

    local function ClassColorOn() return ns.Config:Get("bar.classColor") end
    ColorSwatch(panel, COL1, y + 100, L["Bar color"], "bar.fillColor", ClassColorOn)
    Checkbox(panel, COL1, y + 126, L["Class color"], "bar.classColor")
    Slider(panel, COL2, y + 104, L["Text size"], "bar.fontSize")

    Slider(panel, COL1, y + 166, L["Width"], "bar.width")
    Slider(panel, COL2, y + 166, L["Height"], "bar.height")

    Slider(panel, COL1, y + 216, L["Scale"], "bar.scale")
    Checkbox(panel, COL2, y + 228, L["Drain bar (like a channel)"], "bar.drain")

    -- Posição: Edit Mode quando a LibEditMode existe; senão, arrastar
    if ns.Positioner:Mode() == "editmode" then
        local hint = W.Label(panel,
            string.format(L["Position: Esc > Edit Mode, then drag \"%s\"."], L["Flight bar"]), "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", COL1, -(y + 270))
    else
        local box = W.Checkbox(panel, L["Move bar (drag with the mouse)"],
            function() return ns.Positioner:IsUnlocked() end,
            function(value) ns.Positioner:SetUnlocked(value) end)
        box:SetPoint("TOPLEFT", COL1, -(y + 266))
        Track(box)
        local hint = W.Label(panel,
            L["Install the LibEditMode addon to position via Edit Mode."], "GameFontDisableSmall")
        hint:SetPoint("TOPLEFT", COL1 + 28, -(y + 290))
    end

    local preview = W.Button(panel, L["Preview"], 130, function()
        ns.FlightCastBar:Preview(not ns.FlightCastBar:IsPreviewing())
    end)
    preview:SetPoint("TOPLEFT", COL1, -(y + 320))

    local reset = W.Button(panel, L["Reset to default"], 130, function()
        ns.Config:ResetSection("bar")
        Window:Refresh()
    end)
    reset:SetPoint("TOPLEFT", COL1 + 140, -(y + 320))

    -- Tempos gravados (fim da aba) -------------------------------
    local routesY = y + 360
    local info = W.Label(panel, "", "GameFontHighlight")
    info:SetPoint("TOPLEFT", COL1, -(routesY + 5))

    local clear = W.Button(panel, L["Delete recorded times"], 180, function()
        ns.TaxiClearConfirm:Request({ onDone = function() Window:Refresh() end })
    end)
    clear:SetPoint("TOPLEFT", COL2, -routesY)

    -- Botão temporário (desativado): abre a mesma confirmação sem apagar nada
    -- if SHOW_CLEAR_TEST_BUTTON then
    --     local test = W.Button(panel, L["Test confirmation (deletes nothing)"], 230, function()
    --         ns.TaxiClearConfirm:Request({ dryRun = true })
    --     end)
    --     test:SetPoint("TOPLEFT", COL1, -(routesY + 54))
    -- end

    local note = W.Label(panel, L["Times are measured from your real flights; \"~\" marks an estimate."],
        "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", COL1, -(routesY + 32))

    Track({ Refresh = function()
        info:SetText(string.format(L["Recorded routes: %d"], ns.TaxiDatabase:Count()))
    end })
end

local function BuildVendorTab(panel)
    W.Label(panel, L["Gold spent and earned with vendors"], "GameFontNormal"):SetPoint("TOPLEFT", 12, -12)
    Checkbox(panel, 12, 40, L["Show gold messages when using vendors"], "vendor.enabled")
    Checkbox(panel, 12, 68, L["Summary when closing the vendor"], "vendor.onClose")
    Checkbox(panel, 12, 96, L["Message after each transaction"], "vendor.perTransaction")
    Checkbox(panel, 12, 124, L["Also show when nothing changed"], "vendor.showZero")
end

local function BuildWardrobeTab(panel)
    W.Label(panel, L["Appearance collection"], "GameFontNormal"):SetPoint("TOPLEFT", 12, -12)
    Checkbox(panel, 12, 40, L["Show the armor type filter in the collection window"], "wardrobe.enabled")
    local note = W.Label(panel, L["Adds a dropdown to the Items tab of the Appearances window."], "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", 40, -70)
end

--- Moldura com título, para separar grupos de opções dentro de uma aba.
--- Os controles são criados dentro dela, com coordenadas relativas ao grupo.
local GROUP_X, GROUP_WIDTH = 4, 446

local function Group(panel, y, height, title)
    local group = W.NewFrame(panel)
    group:SetPoint("TOPLEFT", panel, "TOPLEFT", GROUP_X, -y)
    group:SetSize(GROUP_WIDTH, height)
    W.Backdrop(group, { 0.09, 0.09, 0.11, 0.6 }, { 0.35, 0.35, 0.4, 1 })
    W.Label(group, title, "GameFontNormal"):SetPoint("TOPLEFT", 10, -8)
    return group
end

local function BuildTrinketsTab(panel)
    W.Label(panel, L["Trinket selector"], "GameFontNormal"):SetPoint("TOPLEFT", 12, -12)
    LockedHint(panel, 140, 14, "trinkets.scale")
    ForceEditBox(panel, 360, 6)
    Checkbox(panel, 12, 40, L["Show the trinket selector on screen"], "trinkets.enabled")
    W.Label(panel, L["Click a slot to list the trinkets in your bags."], "GameFontDisableSmall"):SetPoint("TOPLEFT", 40, -70)
    W.Label(panel, L["Click one to equip it in that slot (not in combat)."], "GameFontDisableSmall"):SetPoint("TOPLEFT", 40, -86)
    -- Valem para o seletor inteiro (botões e grade), então ficam fora dos grupos
    Checkbox(panel, 12, 106, L["Show item level on icons"], "trinkets.showItemLevel")
    Slider(panel, 232, 100, L["Scale"], "trinkets.scale")


    -- Botões (o seletor na tela) ---------------------------------
    local buttons = Group(panel, 156, 244, L["Buttons"])
    Slider(buttons, 12, 30, L["Button size"], "trinkets.slotSize")
    Slider(buttons, 232, 30, L["Button spacing"], "trinkets.gap")
    Dropdown(buttons, 12, 92, L["Layout"], "trinkets.orientation", Items({
        { id = "vertical",   label = L["Vertical"] },
        { id = "horizontal", label = L["Horizontal"] },
    }))
    Checkbox(buttons, 12, 148, L["Hide the selector in combat"], "trinkets.hideInCombat")

    -- Posição: Edit Mode quando a LibEditMode existe; senão, arrastar
    local positioner = ns.TrinketSelector.positioner
    if positioner and positioner:Mode() == "editmode" then
        W.Label(buttons, string.format(L["Position: Esc > Edit Mode, then drag \"%s\"."], L["Trinket selector"]),
            "GameFontHighlightSmall"):SetPoint("TOPLEFT", 12, -184)
    elseif positioner then
        local box = W.Checkbox(buttons, L["Move selector (drag with the mouse)"],
            function() return positioner:IsUnlocked() end,
            function(value) positioner:SetUnlocked(value) end)
        box:SetPoint("TOPLEFT", 12, -178)
        Track(box)
    end
    local reset = W.Button(buttons, L["Reset position"], 130, function() ns.TrinketSelector:ResetPosition() end)
    reset:SetPoint("TOPLEFT", 12, -212)

    -- Grade de seleção (a caixa que abre ao clicar num botão) ------
    local grid = Group(panel, 410, 152, L["Selection grid"])
    Slider(grid, 12, 30, L["Grid columns"], "trinkets.columns")
    Slider(grid, 232, 30, L["Icon size"], "trinkets.itemSize")
    Slider(grid, 12, 92, L["Icon spacing"], "trinkets.itemGap")
end

--- Bloco de opções de um recurso de "número de item level" (items.<prefix>.*).
--- Cada recurso tem o seu, para ligar e personalizar separadamente.
local function LevelOptions(panel, y, title, prefix, labels)
    local base = "items." .. prefix .. "."
    local group = Group(panel, y, 172, title)
    Checkbox(group, 12, 30, labels.enable, base .. "enabled")

    local function Off() return not ns.Config:Get(base .. "enabled") end
    Dropdown(group, 12, 58, L["Color"], base .. "colorMode", Items({
        { id = "quality", label = L["Item quality"] },
        { id = "fixed",   label = L["Fixed color"] },
    }))
    ColorSwatch(group, 232, 74, L["Text color"], base .. "color", function()
        return Off() or ns.Config:Get(base .. "colorMode") ~= "fixed"
    end)
    Dropdown(group, 12, 108, L["Position on the icon"], base .. "anchor", Items({
        { id = "TOPLEFT",     label = L["Top left"] },
        { id = "TOPRIGHT",    label = L["Top right"] },
        { id = "BOTTOMLEFT",  label = L["Bottom left"] },
        { id = "BOTTOMRIGHT", label = L["Bottom right"] },
    }))
    Slider(group, 232, 108, L["Text size"], base .. "fontSize", 8, 20, 1, "%d")
    W.Label(group, labels.hint, "GameFontDisableSmall"):SetPoint("TOPLEFT", 12, -154)
    return group
end

--- Bloco do indicador de encantamentos da janela de personagem.
local function EnchantOptions(panel, y)
    local base = "items.characterEnchants."
    local group = Group(panel, y, 190, L["Enchants on the character window"])
    Checkbox(group, 12, 30, L["Show which items are enchanted"], base .. "enabled")
    Checkbox(group, 12, 58, L["Also show the enchanted items"], base .. "showEnchanted")
    Checkbox(group, 12, 86, L["Count rings (Enchanting only)"], base .. "countRings")
    local function Off() return not ns.Config:Get(base .. "enabled") end
    ColorSwatch(group, 12, 118, L["Enchanted color"], base .. "enchantedColor", Off)
    ColorSwatch(group, 232, 118, L["No enchant color"], base .. "missingColor", Off)
    Slider(group, 12, 146, L["Text size"], base .. "fontSize", 8, 16, 1, "%d")
    Dropdown(group, 232, 146, L["Enchant name"], base .. "nameMode", Items({
        { id = "full",  label = L["Full name"] },
        { id = "short", label = L["Abbreviated"] },
        { id = "value", label = L["Value only"] },
    }))
    return group
end

local function BuildItemsTab(panel)
    LevelOptions(panel, 8, L["Item level on bags"], "itemLevel", {
        enable = L["Show item level on equipment in your bags"],
        hint = L["Default game bags only. Open your bags to see the change."],
    })
    LevelOptions(panel, 188, L["Item level on the character window"], "characterLevel", {
        enable = L["Show item level on your equipped items"],
        hint = L["Open your character window to see the change."],
    })
    EnchantOptions(panel, 368)
end

-- Rodapé fixo: não pertence a nenhuma aba, então não muda ao trocá-las.
local FOOTER_HEIGHT = 40
local FALLBACK_AUTHOR = "rafacf95"
local COPYRIGHT_YEAR = 2026

local function AddonMeta(field)
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if type(get) ~= "function" then return nil end
    local ok, value = pcall(get, "WowUtilities", field)
    if ok and type(value) == "string" and value ~= "" then return value end
end

local function BuildFooter(parent)
    local author = AddonMeta("Author") or FALLBACK_AUTHOR
    local version = AddonMeta("Version") or "?"
    if version:find("^@") then version = "dev" end -- código-fonte: o empacotador ainda não trocou o marcador
    version = version:gsub("^v", "")               -- tag "v4.3.3" -> "4.3.3"

    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.4, 0.4, 0.45, 0.8)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", 12, FOOTER_HEIGHT)
    line:SetPoint("BOTTOMRIGHT", -12, FOOTER_HEIGHT)

    local top = W.Label(parent, string.format(L["WowUtilities v%s · by %s"], version, author), "GameFontHighlightSmall")
    top:SetPoint("BOTTOM", parent, "BOTTOM", 0, 22)
    local rights = W.Label(parent,
        string.format(L["© %d %s. All rights reserved."], COPYRIGHT_YEAR, author), "GameFontDisableSmall")
    rights:SetPoint("BOTTOM", parent, "BOTTOM", 0, 8)
end

local TABS = {
    { label = L["Tooltip"], build = BuildTooltipTab },
    { label = L["Flight"],  build = BuildFlightTab },
    { label = L["Vendor"],  build = BuildVendorTab },
    { label = L["Wardrobe"], build = BuildWardrobeTab },
    { label = L["Trinkets"], build = BuildTrinketsTab },
    { label = L["Items"],    build = BuildItemsTab },
}

local TAB_WIDTH = 74 -- 6 abas cabem nos 500 px da janela

local function ShowTab(index)
    for i, panel in ipairs(panels) do panel:SetShown(i == index) end
    for i, button in ipairs(tabButtons) do button:SetEnabled(i ~= index) end
end

-- ----------------------------------------------------------------
-- Janela
-- ----------------------------------------------------------------

local function Build()
    frame = W.NewFrame(UIParent, "WowUtilitiesConfig")
    frame:SetSize(500, 692)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH") -- abaixo do ColorPickerFrame (DIALOG)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    W.Backdrop(frame, { 0.06, 0.06, 0.08, 0.96 }, { 0.5, 0.5, 0.55, 1 })
    frame:Hide()

    W.Label(frame, "WowUtilities", "GameFontNormalLarge"):SetPoint("TOPLEFT", 14, -12)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    for i, tab in ipairs(TABS) do
        local button = W.Button(frame, tab.label, TAB_WIDTH, function() ShowTab(i) end)
        button:SetPoint("TOPLEFT", 14 + (i - 1) * (TAB_WIDTH + 4), -42)
        -- Fonte menor: "Guarda-roupa" precisa caber nos 74 px da aba
        pcall(function()
            button:SetNormalFontObject("GameFontNormalSmall")
            button:SetHighlightFontObject("GameFontHighlightSmall")
            button:SetDisabledFontObject("GameFontDisableSmall")
        end)
        tabButtons[i] = button

        local panel = CreateFrame("Frame", nil, frame)
        panel:SetPoint("TOPLEFT", 8, -76)
        panel:SetPoint("BOTTOMRIGHT", -8, FOOTER_HEIGHT + 4)
        panel:Hide()
        panels[i] = panel
        tab.build(panel)
    end

    BuildFooter(frame)

    frame:SetScript("OnShow", function() Window:Refresh() end)
    frame:SetScript("OnHide", function()
        -- Não deixa a barra destravada nem em demonstração ao fechar
        ns.FlightCastBar:Preview(false)
        ns.Positioner:SetUnlocked(false)
        if ns.TrinketSelector.positioner then ns.TrinketSelector.positioner:SetUnlocked(false) end
    end)

    tinsert(UISpecialFrames, "WowUtilitiesConfig") -- ESC fecha
    ShowTab(1)
end

function Window:Refresh()
    for _, widget in ipairs(refreshables) do widget:Refresh() end
end

function Window:Toggle()
    if not frame then Build() end
    frame:SetShown(not frame:IsShown())
end

ns.Bus:Subscribe("CONFIG_CHANGED", function()
    if frame and frame:IsShown() then Window:Refresh() end
end)

ns.Commands:SetDefault(function() Window:Toggle() end)
