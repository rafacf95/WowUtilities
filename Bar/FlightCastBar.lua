-- ============================================================
--  FlightCastBar.lua
--  Barra no estilo da barra de cast que mostra o tempo do voo.
--  Responsabilidade única: desenhar. Reage ao Bus:
--    FLIGHT_START / FLIGHT_END   — vindos do TaxiRecorder
--    CONFIG_CHANGED("bar...")    — reaplica o estilo
--    EDITMODE_ENTER / EXIT       — pré-visualização para posicionar
--  Posição fica a cargo do Positioner.
-- ============================================================

local _, ns = ...
local L = ns.L

local Bar = {}
ns.FlightCastBar = Bar

local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil
local FADE_SECONDS = 0.4
local PREVIEW_SECONDS = 10

local frame
local run         -- { mode = "flight"|"preview", startedAt, duration, kind, label, finishedAt }
local editMode = false

local function Cfg(key) return ns.Config:Get("bar." .. key) end

-- ----------------------------------------------------------------
-- Construção e estilo
-- ----------------------------------------------------------------

local function Build()
    if frame then return end
    frame = CreateFrame("Frame", "WowUtilitiesFlightBar", UIParent, BACKDROP)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:Hide()

    local status = CreateFrame("StatusBar", nil, frame)
    status:SetMinMaxValues(0, 1)
    status:SetValue(0)
    frame.status = status

    frame.bg = status:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetColorTexture(0, 0, 0, 0.55)

    frame.spark = status:CreateTexture(nil, "OVERLAY")
    frame.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    frame.spark:SetBlendMode("ADD")
    frame.spark:SetWidth(20)

    frame.label = status:CreateFontString(nil, "OVERLAY")
    frame.label:SetPoint("LEFT", status, "LEFT", 6, 0)
    frame.label:SetJustifyH("LEFT")

    frame.timeText = status:CreateFontString(nil, "OVERLAY")
    frame.timeText:SetPoint("RIGHT", status, "RIGHT", -6, 0)
    frame.timeText:SetJustifyH("RIGHT")
    frame.label:SetPoint("RIGHT", frame.timeText, "LEFT", -6, 0)

    frame:SetScript("OnUpdate", function(_, elapsed) Bar:OnUpdate(elapsed) end)
end

local function ColorOf(key)
    local c = Cfg(key)
    if type(c) ~= "table" then c = ns.Config:Default("bar." .. key) end
    return c.r or 1, c.g or 1, c.b or 1
end

--- Cor do preenchimento: a da classe do jogador (se ativado) ou a escolhida.
function Bar:FillColor()
    if Cfg("classColor") then
        local _, classFile = UnitClass("player")
        local c = ns.ClassColors:Get(classFile)
        if c then return c.r, c.g, c.b end
    end
    return ColorOf("fillColor")
end

local function ApplyStyle()
    if not frame then return end
    local catalog = ns.StyleCatalog
    local height = Cfg("height")

    frame:SetSize(Cfg("width"), height)
    frame:SetScale(Cfg("scale"))
    ns.Positioner:Replace(frame) -- a escala mudou: mantém o ponto na tela

    -- Borda
    local border = catalog:Find(catalog.borders, Cfg("border"))
    local size = 0
    if border.edgeFile and frame.SetBackdrop then
        size = Cfg("borderSize")
        if size > 0 then
            local r, g, b = ColorOf("borderColor")
            pcall(frame.SetBackdrop, frame, { edgeFile = border.edgeFile, edgeSize = size })
            pcall(frame.SetBackdropBorderColor, frame, r, g, b, 1)
        else
            pcall(frame.SetBackdrop, frame, nil)
        end
    elseif frame.SetBackdrop then
        pcall(frame.SetBackdrop, frame, nil)
    end

    -- Barra interna, recuada pela espessura da borda
    local status = frame.status
    status:ClearAllPoints()
    status:SetPoint("TOPLEFT", frame, "TOPLEFT", size, -size)
    status:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -size, size)
    status:SetStatusBarTexture(catalog:TexturePath(Cfg("texture")))
    status:SetStatusBarColor(Bar:FillColor())

    -- Fonte (a mesma da interface do jogo, com o tamanho configurado)
    local fontPath = GameFontHighlight and GameFontHighlight:GetFont() or "Fonts\\FRIZQT__.TTF"
    frame.label:SetFont(fontPath, Cfg("fontSize"), "OUTLINE")
    frame.timeText:SetFont(fontPath, Cfg("fontSize"), "OUTLINE")

    frame.spark:SetHeight(height * 2)
end

-- ----------------------------------------------------------------
-- Exibição
-- ----------------------------------------------------------------

local function SetProgress(progress)
    local value = Cfg("drain") and (1 - progress) or progress
    frame.status:SetValue(value)
    frame.spark:ClearAllPoints()
    frame.spark:SetPoint("CENTER", frame.status, "LEFT", value * frame.status:GetWidth(), 0)
    frame.spark:SetShown(progress > 0 and progress < 1)
end

function Bar:OnUpdate()
    if not run then
        if editMode then
            -- Pré-visualização estática enquanto o usuário posiciona a barra
            frame:SetAlpha(1)
            frame.label:SetText(L["Flight bar"])
            frame.timeText:SetText("0:30")
            SetProgress(0.5)
        else
            frame:Hide()
        end
        return
    end

    local now = GetTime()

    if run.finishedAt then
        local t = (now - run.finishedAt) / FADE_SECONDS
        if t >= 1 then
            run = nil
            if not editMode then frame:Hide() end
        else
            frame:SetAlpha(1 - t)
        end
        return
    end

    local elapsed = now - run.startedAt
    if run.mode == "preview" and elapsed >= run.duration then
        run.startedAt, elapsed = now, 0 -- repete a demonstração
    end

    frame:SetAlpha(1)
    frame.label:SetText(run.label)

    if run.duration and run.duration > 0 then
        local prefix = (run.kind == "measured") and "" or "~"
        frame.timeText:SetText(prefix .. ns.FormatTime(math.max(run.duration - elapsed, 0)))
        SetProgress(math.min(elapsed / run.duration, 1))
    else
        -- Sem estimativa: só o tempo decorrido, sem preenchimento
        frame.timeText:SetText(ns.FormatTime(elapsed))
        SetProgress(0)
    end
end

--- Rota com tempo conhecido ou estimado: nome do local, sem a zona.
--- Rota sem nenhum dado: avisa que o tempo está sendo gravado.
local function FlightLabel(destination, duration)
    if duration and duration > 0 then
        return ns.PlaceName(destination) or "?"
    end
    return L["Recording flight time"]
end

function Bar:StartFlight(destination, duration, kind)
    if not ns.Config:Get("taxi.bar") then return end
    Build()
    ApplyStyle()
    run = {
        mode = "flight", startedAt = GetTime(), duration = duration, kind = kind,
        label = FlightLabel(destination, duration),
    }
    frame:SetAlpha(1)
    frame:Show()
end

function Bar:EndFlight(completed)
    if not run or run.mode ~= "flight" then return end
    if completed then SetProgress(1) end
    run.finishedAt = GetTime()
end

--- Liga/desliga a demonstração (botão "Pré-visualizar" da janela).
function Bar:Preview(enabled)
    Build()
    ApplyStyle()
    if enabled then
        run = { mode = "preview", startedAt = GetTime(), duration = PREVIEW_SECONDS,
                kind = "measured", label = L["Example flight"] }
        frame:Show()
    elseif run and run.mode == "preview" then
        run = nil
        if not editMode then frame:Hide() end
    end
end

function Bar:IsPreviewing()
    return run ~= nil and run.mode == "preview"
end

local function SetEditMode(flag)
    editMode = flag
    Build()
    ApplyStyle()
    if flag then frame:Show() elseif not run then frame:Hide() end
end

-- ----------------------------------------------------------------
-- Ligações com o resto do addon
-- ----------------------------------------------------------------

ns.Bus:Subscribe("READY", function()
    Build()
    ApplyStyle()
    ns.Positioner:Attach(frame)
end)

ns.Bus:Subscribe("CONFIG_CHANGED", function(path)
    if path == "bar" or path:find("^bar%.") then ApplyStyle() end
end)

ns.Bus:Subscribe("FLIGHT_START", function(...) Bar:StartFlight(...) end)
ns.Bus:Subscribe("FLIGHT_END", function(...) Bar:EndFlight(...) end)
ns.Bus:Subscribe("EDITMODE_ENTER", function() SetEditMode(true) end)
ns.Bus:Subscribe("EDITMODE_EXIT", function() SetEditMode(false) end)
