-- ============================================================
--  TextWindow.lua
--  Janela com um texto longo já selecionado, para copiar (Ctrl+C) e
--  colar fora do jogo, como num .txt. O WoW não permite escrever na
--  área de transferência; a caixa de texto selecionada é o caminho.
--  Responsabilidade única: exibir texto. Quem gera o texto é outro.
-- ============================================================

local _, ns = ...
local L = ns.L

local TextWindow = {}
ns.TextWindow = TextWindow

local W = ns.Widgets
local frame, edit, shownText

--- Tira os escapes do chat (cores, texturas, links) deixando só o texto.
function TextWindow.Plain(text)
    text = tostring(text or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|T.-|t", ""):gsub("|H.-|h(.-)|h", "%1")
    return text
end

local function SelectAll()
    if not edit then return end
    edit:SetFocus()
    edit:HighlightText()
end

local function Build()
    frame = W.NewFrame(UIParent, "WowUtilitiesTextWindow")
    frame:SetSize(640, 440)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    W.Backdrop(frame, { 0.06, 0.06, 0.08, 0.97 }, { 0.5, 0.5, 0.55, 1 })
    frame:Hide()

    frame.title = W.Label(frame, "", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", 14, -12)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    local hint = W.Label(frame, L["Select all and press Ctrl+C to copy"], "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 14, -38)

    local scroll = CreateFrame("ScrollFrame", "WowUtilitiesTextWindowScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -58)
    scroll:SetPoint("BOTTOMRIGHT", -34, 46)

    edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal or GameFontHighlight)
    edit:SetWidth(580)
    scroll:SetScrollChild(edit)

    -- Só leitura na prática: qualquer digitação volta ao texto original.
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput and shownText and self:GetText() ~= shownText then
            self:SetText(shownText)
            self:HighlightText()
        end
    end)
    edit:SetScript("OnEscapePressed", function() frame:Hide() end)

    local selectAll = W.Button(frame, L["Select all"], 130, SelectAll)
    selectAll:SetPoint("BOTTOMLEFT", 14, 12)
    local closeButton = W.Button(frame, L["Close"], 100, function() frame:Hide() end)
    closeButton:SetPoint("BOTTOMRIGHT", -14, 12)

    frame:SetScript("OnShow", SelectAll)
    tinsert(UISpecialFrames, "WowUtilitiesTextWindow") -- ESC fecha
end

--- Abre a janela com `text` (escapes de chat removidos) já selecionado.
function TextWindow:Show(title, text)
    if not frame then Build() end
    shownText = TextWindow.Plain(text)
    frame.title:SetText(title or "")
    edit:SetText(shownText)
    frame:Show()
    SelectAll()
    -- O layout só termina no quadro seguinte; repete a seleção então.
    if C_Timer and C_Timer.After then C_Timer.After(0, SelectAll) end
end
