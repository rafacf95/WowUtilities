-- ============================================================
--  ResourceBar.lua
--  Barra do recurso do jogador (mana, rage, energy), que acompanha a
--  classe e a forma, com os pontos de combo colados acima ou abaixo
--  (Ladino; Druida na Forma de Felino). Um frame só no Edit Mode: mover
--  e ancorar a barra leva os pontos junto.
--  Responsabilidade: desenhar e decidir quando aparecer. O que ler do
--  jogo é do ns.PowerSource; a posição é de um Positioner próprio (Edit
--  Mode com LibEditMode ou arrastar).
--  O valor do recurso é secreto: vai direto para a StatusBar e para o
--  texto (SetFormattedText), sem contas. Por isso a visibilidade não
--  depende do valor (só de combate e alvo).
-- ============================================================

local _, ns = ...
local L = ns.L

local Bar = {}
ns.ResourceBar = Bar

local Source = ns.PowerSource
local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil
local MAX_POINTS = 10
local DEFAULT_POSITION = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 180 }
local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"

local EVENTS = {
    "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
    "UPDATE_SHAPESHIFT_FORM", "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_ENTERING_WORLD",
}

local frame
local powerType, powerToken
local inCombat, editing, unlocked, previewing = false, false, false, false

local function Cfg(key) return ns.Config:Get("resource." .. key) end

local function ColorOf(key)
    local c = Cfg(key)
    if type(c) ~= "table" then c = ns.Config:Default("resource." .. key) end
    return c.r or 1, c.g or 1, c.b or 1
end

local function FontPath()
    local ok, path = pcall(function() return GameFontHighlight and GameFontHighlight:GetFont() end)
    return (ok and type(path) == "string") and path or FALLBACK_FONT
end

-- ----------------------------------------------------------------
-- Construção
-- ----------------------------------------------------------------

local function Build()
    if frame then return end
    frame = CreateFrame("Frame", "WowUtilitiesResourceBar", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:Hide()

    local main = CreateFrame("Frame", nil, frame, BACKDROP)
    frame.main = main
    local status = CreateFrame("StatusBar", nil, main)
    status:SetMinMaxValues(0, 1)
    status:SetValue(0)
    frame.status = status
    frame.bg = status:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetColorTexture(0, 0, 0, 0.55)
    frame.text = status:CreateFontString(nil, "OVERLAY")
    frame.text:SetPoint("CENTER", status, "CENTER", 0, 0)

    frame.combo = CreateFrame("Frame", nil, frame)
    frame.points = {}
    for i = 1, MAX_POINTS do
        local point = CreateFrame("Frame", nil, frame.combo, BACKDROP)
        point.fill = point:CreateTexture(nil, "ARTWORK")
        point:Hide()
        frame.points[i] = point
    end
    frame:SetScript("OnSizeChanged", function() Bar:LayoutPoints() end)
end

-- ----------------------------------------------------------------
-- Estilo e disposição
-- ----------------------------------------------------------------

--- Cor do preenchimento: a do recurso (padrão do jogo), a da classe ou a escolhida.
function Bar:FillColor()
    local mode = Cfg("colorMode")
    if mode == "class" then
        local _, classFile = ns.SafeCall(UnitClass, "player")
        local c = classFile and ns.ClassColors:Get(classFile)
        if c then return c.r, c.g, c.b end
    elseif mode == "fixed" then
        return ColorOf("fillColor")
    end
    if powerType == nil then powerType, powerToken = Source:PowerType() end
    return Source:Color(powerType, powerToken)
end

--- Borda (estilo do catálogo) em `box`, com `inner` recuado pela espessura.
local function ApplyBorder(box, inner)
    local catalog = ns.StyleCatalog
    local border = catalog:Find(catalog.borders, Cfg("border"))
    local size = 0
    if box.SetBackdrop then
        if border.edgeFile and Cfg("borderSize") > 0 then
            size = Cfg("borderSize")
            local r, g, b = ColorOf("borderColor")
            pcall(box.SetBackdrop, box, { edgeFile = border.edgeFile, edgeSize = size })
            pcall(box.SetBackdropBorderColor, box, r, g, b, 1)
        else
            pcall(box.SetBackdrop, box, nil)
        end
    end
    inner:ClearAllPoints()
    inner:SetPoint("TOPLEFT", box, "TOPLEFT", size, -size)
    inner:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -size, size)
end

local function ShowsCombo()
    return Cfg("comboPoints") == true and Source:HasComboPoints(powerType)
end

--- Distribui os pontos de combo pela largura da barra.
function Bar:LayoutPoints()
    if not frame then return end
    local count = ShowsCombo() and Source:ComboMax() or 0
    local spacing = Cfg("comboSpacing")
    local width = frame:GetWidth()
    if type(width) ~= "number" or width <= 0 then width = Cfg("width") end
    local each = count > 0 and (width - spacing * (count - 1)) / count or 0
    for i, point in ipairs(frame.points) do
        point:ClearAllPoints()
        if i <= count and each > 0 then
            point:SetPoint("TOPLEFT", frame.combo, "TOPLEFT", (i - 1) * (each + spacing), 0)
            point:SetSize(each, Cfg("comboHeight"))
            point:Show()
        else
            point:Hide()
        end
    end
end

local function Layout()
    local combo = ShowsCombo()
    local height, comboHeight, gap = Cfg("height"), Cfg("comboHeight"), Cfg("comboGap")
    frame:SetSize(Cfg("width"), height + (combo and (comboHeight + gap) or 0))
    frame:SetScale(Cfg("scale"))
    if Bar.positioner then Bar.positioner:Replace(frame) end -- a escala mudou: mantém o ponto na tela

    -- Barra e pontos acompanham a largura do frame (inclusive com "ajustar largura")
    local main, holder = frame.main, frame.combo
    local mainEdge, comboEdge = "TOP", "BOTTOM"
    if combo and Cfg("comboPosition") == "above" then mainEdge, comboEdge = "BOTTOM", "TOP" end
    main:ClearAllPoints()
    main:SetPoint(mainEdge .. "LEFT", frame, mainEdge .. "LEFT", 0, 0)
    main:SetPoint(mainEdge .. "RIGHT", frame, mainEdge .. "RIGHT", 0, 0)
    main:SetHeight(height)
    holder:ClearAllPoints()
    holder:SetPoint(comboEdge .. "LEFT", frame, comboEdge .. "LEFT", 0, 0)
    holder:SetPoint(comboEdge .. "RIGHT", frame, comboEdge .. "RIGHT", 0, 0)
    holder:SetHeight(comboHeight)
    holder:SetShown(combo)
    Bar:LayoutPoints()
end

local function ApplyStyle()
    ApplyBorder(frame.main, frame.status)
    frame.status:SetStatusBarTexture(ns.StyleCatalog:TexturePath(Cfg("texture")))
    frame.status:SetStatusBarColor(Bar:FillColor())
    frame.text:SetFont(FontPath(), Cfg("fontSize"), "OUTLINE")
    local texture = ns.StyleCatalog:TexturePath(Cfg("texture"))
    for _, point in ipairs(frame.points) do
        ApplyBorder(point, point.fill)
        point.fill:SetTexture(texture)
    end
end

-- ----------------------------------------------------------------
-- Valores
-- ----------------------------------------------------------------

local function SetBarValue(value)
    local interpolation = rawget(_G, "Enum") and Enum.StatusBarInterpolation
    if Cfg("smooth") and type(interpolation) == "table" and interpolation.ExponentialEaseOut then
        if pcall(frame.status.SetValue, frame.status, value, interpolation.ExponentialEaseOut) then return end
    end
    pcall(frame.status.SetValue, frame.status, value)
end

--- Existe valor? Só por type(): o valor secreto não pode ser comparado (nem com nil).
local function Has(value) return type(value) ~= "nil" end

--- Texto da barra; o valor é secreto, então só passa pelo SetFormattedText.
local function SetText(value, max)
    local mode, text = Cfg("text"), frame.text
    if mode == "value" and Has(value) then
        pcall(text.SetFormattedText, text, "%d", value)
    elseif mode == "both" and Has(value) then
        pcall(text.SetFormattedText, text, "%d / %d", value, max)
    elseif mode == "percent" then
        local percent = Source:Percent(powerType)
        if not Has(percent) or not pcall(text.SetFormattedText, text, "%d%%", percent) then text:SetText("") end
    else
        text:SetText("")
    end
end

local function UpdatePoints()
    if not ShowsCombo() then return end
    local current, count = Source:ComboPoints(), Source:ComboMax()
    local fr, fg, fb = ColorOf("comboColor")
    local er, eg, eb = ColorOf("comboEmptyColor")
    for i = 1, count do
        local fill = frame.points[i].fill
        if i <= current then fill:SetVertexColor(fr, fg, fb) else fill:SetVertexColor(er, eg, eb) end
    end
end

--- Redesenha valor, texto e pontos (chamado a cada mudança de recurso).
function Bar:Update()
    if not (frame and frame:IsShown()) then return end
    local max = Source:Max(powerType) or 1
    local value = Source:Value(powerType)
    frame.status:SetMinMaxValues(0, max)
    if Has(value) then SetBarValue(value) else SetBarValue(0) end
    SetText(value, max)
    UpdatePoints()
end

-- ----------------------------------------------------------------
-- Visibilidade
-- ----------------------------------------------------------------

--- Deve aparecer agora? Sempre que estiver sendo posicionada/pré-visualizada;
--- fora disso, conforme a opção (sempre, em combate, em combate ou com alvo hostil).
function Bar:WantsShown()
    if not Cfg("enabled") then return false end
    if editing or unlocked or previewing then return true end
    local mode = Cfg("visibility")
    if mode == "combat" then return inCombat end
    if mode == "combatOrTarget" then return inCombat or Source:HasHostileTarget() end
    return true
end

local function ApplyVisibility()
    if not frame then return end
    local show = Bar:WantsShown()
    if show ~= frame:IsShown() then frame:SetShown(show) end
end

--- Relê o tipo do recurso (classe/forma) e refaz tudo.
function Bar:Refresh()
    if not frame then return end
    powerType, powerToken = Source:PowerType()
    Layout()
    ApplyStyle()
    ApplyVisibility()
    self:Update()
end

-- ----------------------------------------------------------------
-- Posição, pré-visualização e API
-- ----------------------------------------------------------------

local function AttachPositioner()
    Bar.positioner = ns.Positioner.New({
        label = L["Resource bar"] .. " (WowUtilities)",
        default = { point = DEFAULT_POSITION.point, x = DEFAULT_POSITION.x, y = DEFAULT_POSITION.y },
        store = ns.Config:PositionStore("resourcePositions", DEFAULT_POSITION),
        anchorable = true,
        matchWidthLocks = "resource.width",
        settings = {
            "resource.scale", "resource.width", "resource.height", "resource.visibility",
            "resource.colorMode", "resource.fillColor", "resource.text", "resource.fontSize", "resource.borderSize",
            { divider = L["Combo points"] },
            "resource.comboPoints", "resource.comboPosition", "resource.comboHeight", "resource.comboSpacing",
            "resource.comboGap",
        },
    })
    Bar.positioner:Attach(frame)
end

--- Só no modo arrastar: destrava a barra (ela aparece para ser arrastada).
function Bar:SetUnlocked(flag)
    if not self.positioner then return end
    self.positioner:SetUnlocked(flag)
    unlocked = self.positioner:IsUnlocked()
    self:Refresh()
end

function Bar:IsUnlocked() return unlocked end

--- Mostra a barra fora das condições normais (botão "Pré-visualizar").
function Bar:Preview(flag)
    previewing = flag and true or false
    self:Refresh()
end

function Bar:IsPreviewing() return previewing end

--- Volta a barra à posição padrão (todos os layouts).
function Bar:ResetPosition()
    if not (frame and self.positioner and ns.db) then return end
    ns.db.resourcePositions = {}
    self.positioner:Replace(frame)
end

function Bar:Frame() return frame end

-- ----------------------------------------------------------------
-- Ligações com o jogo e com o resto do addon
-- ----------------------------------------------------------------

local function OnEvent(_, event, unit)
    if not frame then return end
    if event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
        if unit == "player" then Bar:Update() end
    elseif event == "UNIT_DISPLAYPOWER" then
        if unit == "player" then Bar:Refresh() end
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        inCombat = event == "PLAYER_REGEN_DISABLED"
        ApplyVisibility()
        Bar:Update()
    elseif event == "PLAYER_TARGET_CHANGED" then
        ApplyVisibility()
        Bar:Update()
    else -- troca de forma, entrada no mundo
        inCombat = Source:InCombat()
        Bar:Refresh()
    end
end

ns.Bus:Subscribe("READY", function()
    Build()
    AttachPositioner()
    local events = CreateFrame("Frame")
    for _, name in ipairs(EVENTS) do pcall(events.RegisterEvent, events, name) end
    events:SetScript("OnEvent", OnEvent)
    inCombat = Source:InCombat()
    Bar:Refresh()
end)

ns.Bus:Subscribe("CONFIG_CHANGED", function(path)
    if path == "resource" or path:find("^resource%.") then Bar:Refresh() end
end)

-- Edit Mode da Blizzard (LibEditMode). No modo arrastar quem manda é o "Mover barra".
local function SetEditing(flag)
    if not (Bar.positioner and Bar.positioner:Mode() == "editmode") then return end
    editing = flag
    Bar:Refresh()
end
ns.Bus:Subscribe("EDITMODE_ENTER", function() SetEditing(true) end)
ns.Bus:Subscribe("EDITMODE_EXIT", function() SetEditing(false) end)
