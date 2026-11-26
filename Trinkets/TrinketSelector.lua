-- ============================================================
--  TrinketSelector.lua
--  Seletor de trinkets sempre visível: dois botões (slots 13 e 14) com o
--  trinket equipado; clicar num deles abre uma grade com os trinkets das
--  bolsas, e clicar num item o equipa naquele slot.
--  Só desenha e reage; ler as bolsas é do TrinketScanner e trocar é do
--  TrinketSwapper. A posição é do Positioner (Edit Mode ou arrastar).
-- ============================================================

local _, ns = ...
local L = ns.L

local unpack = unpack or table.unpack

local Selector = {}
ns.TrinketSelector = Selector

local PAD = 8
local MAX_ITEMS = 40
local FLYOUT_OFFSET = 8
local LEAVE_DELAY = 0.8 -- segundos com o mouse fora antes de fechar a grade
local EMPTY_ICON = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket"
local DEFAULT_POSITION = { point = "BOTTOM", relPoint = "BOTTOM", x = -260, y = 140 }

-- Limites das opções numéricas (os mesmos dos controles da janela /wu)
local LIMITS = {
    slotSize = { 40, 28, 64 }, -- padrão, mínimo, máximo
    gap      = { 6, 0, 24 },
    columns  = { 5, 3, 8 },
    itemSize = { 36, 24, 64 }, -- ícones da grade
    itemGap  = { 4, 0, 16 },
}

local frame, flyout, emptyLabel
local slotButtons, itemButtons = {}, {}
local openSlot
local pendingRefresh = false
local inCombat = false

local function Enabled() return ns.Config:Get("trinkets.enabled") end
local function HideInCombat() return ns.Config:Get("trinkets.hideInCombat") == true end
local function ShowItemLevel() return ns.Config:Get("trinkets.showItemLevel") ~= false end

--- Opção numérica da configuração, sempre dentro dos limites.
local function Number(name)
    local default, min, max = unpack(LIMITS[name])
    local value = ns.Config:Get("trinkets." .. name)
    if type(value) ~= "number" then return default end
    return math.floor(math.max(min, math.min(max, value)) + 0.5)
end

-- ----------------------------------------------------------------
-- Disposição (Strategy): onde ficam os botões e para que lado abre a grade.
-- Uma disposição nova é só uma entrada nova aqui.
--   place(i, size, gap)   -> ponto, x, y do botão i
--   extent(size, gap)     -> largura, altura do conjunto
--   anchor(flyout, slot, openRight, openDown) -> ancora a grade ao slot
-- ----------------------------------------------------------------
local LAYOUTS = {
    vertical = {
        place = function(i, size, gap) return "TOPLEFT", 0, -(i - 1) * (size + gap) end,
        extent = function(size, gap) return size, 2 * size + gap end,
        anchor = function(flyout, slot, openRight)
            if openRight then flyout:SetPoint("TOPLEFT", slot, "TOPRIGHT", FLYOUT_OFFSET, 0)
            else flyout:SetPoint("TOPRIGHT", slot, "TOPLEFT", -FLYOUT_OFFSET, 0) end
        end,
    },
    horizontal = {
        place = function(i, size, gap) return "TOPLEFT", (i - 1) * (size + gap), 0 end,
        extent = function(size, gap) return 2 * size + gap, size end,
        anchor = function(flyout, slot, _, openDown)
            if openDown then flyout:SetPoint("TOPLEFT", slot, "BOTTOMLEFT", 0, -FLYOUT_OFFSET)
            else flyout:SetPoint("BOTTOMLEFT", slot, "TOPLEFT", 0, FLYOUT_OFFSET) end
        end,
    },
}
local DEFAULT_ORIENTATION = "vertical"

local function Orientation()
    local value = ns.Config:Get("trinkets.orientation")
    return LAYOUTS[value] and value or DEFAULT_ORIENTATION
end

--- Para que lado a grade tem mais espaço: (abreÀDireita, abreParaBaixo).
--- Sem coordenadas (frame ainda sem posição), abre à direita e para cima.
local function RoomierSide()
    if not frame then return true, false end
    local ok, cx, cy = pcall(frame.GetCenter, frame)
    if not ok or type(cx) ~= "number" or type(cy) ~= "number" then return true, false end
    local scale = frame:GetEffectiveScale()
    local parentScale = UIParent:GetEffectiveScale()
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if type(scale) ~= "number" or type(parentScale) ~= "number"
        or type(width) ~= "number" or type(height) ~= "number" then
        return true, false
    end
    return cx * scale < width * parentScale / 2, cy * scale > height * parentScale / 2
end

local function InCombat()
    local fn = ns.TrinketScanner.Fn(nil, "InCombatLockdown")
    return fn ~= nil and fn() and true or false
end

local function QualityColor(quality)
    local colors = rawget(_G, "ITEM_QUALITY_COLORS")
    local c = type(colors) == "table" and colors[quality or 1]
    if type(c) == "table" and c.r then return c.r, c.g, c.b end
    return 0.62, 0.62, 0.62
end

-- ----------------------------------------------------------------
-- Botão de ícone (usado nos slots e na grade)
-- ----------------------------------------------------------------

local function ApplyCooldown(button, entry)
    local cd = button.cooldown
    if not cd then return end
    pcall(function()
        local active = entry and entry.enable ~= 0 and entry.enable ~= false and entry.enable ~= nil
        if active and type(entry.start) == "number" and (entry.duration or 0) > 0 then
            cd:SetCooldown(entry.start, entry.duration)
        else
            cd:SetCooldown(0, 0)
        end
    end)
end

local function SetEntry(button, entry)
    button.entry = entry
    if entry then
        button.icon:SetTexture(entry.icon)
        button.border:SetColorTexture(QualityColor(entry.quality))
        button.ilvl:SetText((entry.ilvl and ShowItemLevel()) and tostring(entry.ilvl) or "")
    else
        button.icon:SetTexture(EMPTY_ICON)
        button.border:SetColorTexture(0.3, 0.3, 0.3)
        button.ilvl:SetText("")
    end
end

local function NewIconButton(parent, size)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)

    button.border = button:CreateTexture(nil, "BACKGROUND")
    button.border:SetPoint("TOPLEFT", -1, 1)
    button.border:SetPoint("BOTTOMRIGHT", 1, -1)

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()

    button.ilvl = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    button.ilvl:SetPoint("BOTTOMRIGHT", -2, 2)

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.25)

    pcall(function()
        button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        button.cooldown:SetAllPoints()
    end)

    button:SetScript("OnEnter", function(self)
        local entry = self.entry
        if type(entry) ~= "table" or not entry.link or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(entry.link)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    return button
end

-- ----------------------------------------------------------------
-- Grade de trinkets das bolsas
-- ----------------------------------------------------------------

local function CloseFlyout()
    openSlot = nil
    if flyout then flyout:Hide() end
end

local function ItemButton(index)
    local button = itemButtons[index]
    if button then return button end
    button = NewIconButton(flyout, Number("itemSize"))
    button:SetScript("OnClick", function(self)
        local slot = openSlot
        CloseFlyout()
        if slot and type(self.entry) == "table" then ns.TrinketSwapper:Equip(self.entry, slot) end
    end)
    itemButtons[index] = button
    return button
end

local function RefreshFlyout()
    if not (flyout and openSlot) then return end
    local list = ns.TrinketScanner:Trinkets()
    local count = math.min(#list, MAX_ITEMS)
    local COLUMNS = Number("columns")
    local size, gap = Number("itemSize"), Number("itemGap")

    for i = 1, count do
        local button = ItemButton(i)
        SetEntry(button, list[i])
        ApplyCooldown(button, list[i])
        button:SetSize(size, size)
        local row, col = math.floor((i - 1) / COLUMNS), (i - 1) % COLUMNS
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", flyout, "TOPLEFT",
            PAD + col * (size + gap), -(PAD + row * (size + gap)))
        button:Show()
    end
    for i = count + 1, #itemButtons do itemButtons[i]:Hide() end

    emptyLabel:SetShown(count == 0)
    local columns = math.max(1, math.min(COLUMNS, count))
    local rows = math.max(1, math.ceil(count / COLUMNS))
    flyout:SetSize(
        math.max(2 * PAD + columns * size + (columns - 1) * gap, count == 0 and 200 or 0),
        2 * PAD + rows * size + (rows - 1) * gap)
end

local function OpenFlyout(slot)
    if not (frame and frame:IsShown() and Enabled()) or InCombat() then return end
    openSlot = slot
    flyout:ClearAllPoints()
    LAYOUTS[Orientation()].anchor(flyout, slotButtons[slot], RoomierSide())
    flyout.idle = 0
    flyout:Show()
    RefreshFlyout()
end

-- ----------------------------------------------------------------
-- Slots equipados
-- ----------------------------------------------------------------

local function RefreshSlots()
    if not frame then return end
    for slot, button in pairs(slotButtons) do
        local entry = ns.TrinketScanner:Equipped(slot)
        SetEntry(button, entry)
        ApplyCooldown(button, entry)
    end
end

function Selector:Refresh()
    RefreshSlots()
    RefreshFlyout()
end

local function ScheduleRefresh()
    if pendingRefresh then return end
    if not (C_Timer and C_Timer.After) then Selector:Refresh() return end
    pendingRefresh = true
    C_Timer.After(0.05, function()
        pendingRefresh = false
        Selector:Refresh()
    end)
end

-- ----------------------------------------------------------------
-- Construção
-- ----------------------------------------------------------------

local function BuildFlyout()
    -- Moldura de tooltip da Blizzard (com fallback para o fundo simples), via Skin
    flyout = ns.Skin.Panel("WowUtilitiesTrinketFlyout", UIParent)
    flyout:SetFrameStrata("DIALOG")
    flyout:SetClampedToScreen(true)
    flyout:EnableMouse(true)
    flyout:Hide()

    emptyLabel = ns.Widgets.Label(flyout, L["No trinkets in your bags."], "GameFontDisableSmall")
    emptyLabel:SetPoint("CENTER")
    emptyLabel:Hide()

    -- Fecha quando o mouse fica um tempo fora da grade e do seletor
    flyout:SetScript("OnUpdate", function(self, elapsed)
        local over = self:IsMouseOver() or (frame and frame:IsMouseOver())
        if over then self.idle = 0 return end
        self.idle = (self.idle or 0) + elapsed
        if self.idle > LEAVE_DELAY then CloseFlyout() end
    end)
    flyout:SetScript("OnHide", function() openSlot = nil end)
    tinsert(UISpecialFrames, "WowUtilitiesTrinketFlyout") -- ESC fecha
end

local function BuildSlots()
    frame = CreateFrame("Frame", "WowUtilitiesTrinkets", UIParent)
    frame:SetClampedToScreen(true)

    for _, slot in ipairs(ns.TrinketScanner.SLOTS) do
        local button = NewIconButton(frame, Number("slotSize"))
        button:SetScript("OnClick", function()
            if InCombat() then return end
            if openSlot == slot then CloseFlyout() else OpenFlyout(slot) end
        end)
        slotButtons[slot] = button
    end
end

--- Tamanho, espaçamento e disposição dos botões (relida a cada mudança de opção).
local function ApplyLayout()
    if not frame then return end
    local size, gap = Number("slotSize"), Number("gap")
    local layout = LAYOUTS[Orientation()]
    local width, height = layout.extent(size, gap)
    frame:SetSize(width, height)
    for i, slot in ipairs(ns.TrinketScanner.SLOTS) do
        local button = slotButtons[slot]
        local point, x, y = layout.place(i, size, gap)
        button:SetSize(size, size)
        button:ClearAllPoints()
        button:SetPoint(point, frame, point, x, y)
    end
end

local EVENTS = {
    "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED",
    "SPELL_UPDATE_COOLDOWN", "BAG_UPDATE_COOLDOWN",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
}

local function ListenToGame()
    local listener = CreateFrame("Frame")
    for _, event in ipairs(EVENTS) do pcall(listener.RegisterEvent, listener, event) end
    listener:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            inCombat = true
            CloseFlyout()
            Selector:ApplyVisibility()
        elseif event == "PLAYER_REGEN_ENABLED" then
            inCombat = false
            Selector:ApplyVisibility()
            ScheduleRefresh()
        else
            ScheduleRefresh()
        end
    end)
end

--- Mostra/esconde e escurece conforme ligado, em combate e a opção de esconder.
function Selector:ApplyVisibility()
    if not frame then return end
    if not Enabled() or (inCombat and HideInCombat()) then
        CloseFlyout()
        frame:Hide()
        return
    end
    frame:SetAlpha(inCombat and 0.6 or 1)
    frame:Show()
end

local function ApplyConfig()
    if not frame then return end
    CloseFlyout() -- tamanho, colunas ou disposição podem ter mudado
    -- A escala é geral: vale para os botões e para a grade (que é outro frame)
    local scale = ns.Config:Get("trinkets.scale") or 1
    frame:SetScale(scale)
    flyout:SetScale(scale)
    if Selector.positioner then Selector.positioner:Replace(frame) end -- mantém o ponto na tela
    ApplyLayout()
    Selector:ApplyVisibility()
    if frame:IsShown() then Selector:Refresh() end
end

--- Posicionamento próprio (a barra de voo tem o dela).
local function AttachPositioner()
    Selector.positioner = ns.Positioner.New({
        label = L["Trinket selector"] .. " (WowUtilities)",
        default = { point = DEFAULT_POSITION.point, x = DEFAULT_POSITION.x, y = DEFAULT_POSITION.y },
        store = ns.Config:PositionStore("trinketPositions", DEFAULT_POSITION),
        settings = {
            "trinkets.scale",
            { divider = L["Buttons"] },
            "trinkets.orientation", "trinkets.slotSize", "trinkets.gap", "trinkets.hideInCombat",
            { divider = L["Selection grid"] },
            "trinkets.columns", "trinkets.itemSize", "trinkets.itemGap", "trinkets.showItemLevel",
        },
        handles = function()
            local list = {}
            for _, slot in ipairs(ns.TrinketScanner.SLOTS) do list[#list + 1] = slotButtons[slot] end
            return list
        end,
    })
    Selector.positioner:Attach(frame)
end

-- ----------------------------------------------------------------
-- API para o resto do addon e para os testes
-- ----------------------------------------------------------------

function Selector:Open(slot) OpenFlyout(slot) end
function Selector:Close() CloseFlyout() end
function Selector:IsOpen() return openSlot ~= nil end
function Selector:OpenSlot() return openSlot end
function Selector:Frame() return frame end
function Selector:Flyout() return flyout end
function Selector:SlotButton(slot) return slotButtons[slot] end
function Selector:ItemButtons() return itemButtons end

--- Volta o seletor à posição padrão.
function Selector:ResetPosition()
    if not (frame and self.positioner) then return end
    ns.db.trinketPositions = {}
    self.positioner:Replace(frame)
end

ns.Bus:Subscribe("READY", function()
    BuildSlots()
    BuildFlyout()
    AttachPositioner()
    ListenToGame()
    inCombat = InCombat()
    ApplyConfig()
end)

ns.Bus:Subscribe("CONFIG_CHANGED", function(path)
    if path == "trinkets" or path:find("^trinkets%.") then ApplyConfig() end
end)
