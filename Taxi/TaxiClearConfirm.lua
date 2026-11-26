-- ============================================================
--  TaxiClearConfirm.lua
--  Pede confirmação antes de apagar os tempos de voo gravados.
--  Único caminho para apagar: o botão da janela /wu e o comando
--  "/wu taxi clear" chamam ns.TaxiClearConfirm:Request(), então a
--  regra (e o texto) vivem num lugar só.
--  O jogador precisa digitar a palavra que o jogo usa para apagar itens
--  (DELETE_ITEM_CONFIRM_STRING, já traduzida pelo cliente); o botão
--  fica travado até o texto bater. Sem caixa de texto no cliente, cai
--  na confirmação simples (Apagar/Cancelar).
--  Modo de teste (dryRun): mostra exatamente a mesma janela, mas
--  confirmar não apaga nada — serve para validar o fluxo sem risco.
-- ============================================================

local _, ns = ...
local L = ns.L

local Confirm = {}
ns.TaxiClearConfirm = Confirm

local REAL, TEST = "WOWUTILITIES_CLEAR_TAXI", "WOWUTILITIES_CLEAR_TAXI_TEST"

local function Say(text)
    print("|cff66ccffWowUtilities|r: " .. text)
end

local FALLBACK_WORD = "DELETE"

--- Palavra de confirmação: a mesma da janela de apagar item.
local function Word()
    local word = rawget(_G, "DELETE_ITEM_CONFIRM_STRING")
    if type(word) == "string" and word:match("%S") then return word end
    return FALLBACK_WORD
end

local function Matches(text)
    if type(text) ~= "string" then return false end
    return text:match("^%s*(.-)%s*$"):lower() == Word():lower()
end

-- Os frames de popup mudaram de campos entre versões do cliente; cada
-- busca tenta os nomes conhecidos e devolve nil se nenhum existir.
local function Pick(dialog, ...)
    for i = 1, select("#", ...) do
        local value = dialog[select(i, ...)]
        if type(value) == "table" then return value end
    end
end

local function Button1(dialog)
    local direct = Pick(dialog, "button1", "Button1")
    if direct then return direct end
    local container = Pick(dialog, "ButtonContainer")
    return container and Pick(container, "Button1", "button1")
end

local function EditBox(dialog)
    return Pick(dialog, "editBox", "EditBox")
end

local function OnAccept(dialog, data)
    -- Defesa extra: com caixa de texto, só apaga se a palavra estiver certa
    local box = type(dialog) == "table" and EditBox(dialog)
    if box and not Matches(box:GetText()) then return end

    data = data or {}
    local count = ns.TaxiDatabase:Count()
    if data.dryRun then
        Say(string.format(L["Test: nothing was deleted (%d route(s) kept)."], count))
        return
    end
    ns.TaxiDatabase:Clear()
    Say(L["Flight times deleted."])
    if type(data.onDone) == "function" then data.onDone() end
end

local function OnShow(dialog)
    local box, button = EditBox(dialog), Button1(dialog)
    if not box then return end -- sem caixa de texto: confirmação simples
    box:SetText("")
    if button then button:Disable() end
end

local function OnTextChanged(box)
    local button = Button1(box:GetParent())
    if not button then return end
    if Matches(box:GetText()) then button:Enable() else button:Disable() end
end

local function OnEnterPressed(box)
    local dialog = box:GetParent()
    if not Matches(box:GetText()) then return end
    OnAccept(dialog, dialog.data)
    dialog:Hide()
end

local function OnEscapePressed(box)
    box:GetParent():Hide()
end

local registered
local function Register()
    if registered or type(StaticPopupDialogs) ~= "table" then return registered end
    local function Dialog(text)
        return {
            text = text .. "\n\n" .. L["Type %s to confirm."],
            button1 = L["Delete"],
            button2 = CANCEL or "Cancel",
            hasEditBox = 1,
            maxLetters = 32,
            OnAccept = OnAccept,
            OnShow = OnShow,
            EditBoxOnTextChanged = OnTextChanged,
            EditBoxOnEnterPressed = OnEnterPressed,
            EditBoxOnEscapePressed = OnEscapePressed,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3, -- evita conflito com popups da interface
        }
    end
    StaticPopupDialogs[REAL] = Dialog(L["Delete all %d recorded flight route(s)? This cannot be undone."])
    StaticPopupDialogs[TEST] = Dialog(L["[TEST] Delete all %d recorded flight route(s)? Nothing will actually be deleted."])
    registered = true
    return true
end

--- Pede a confirmação. opts.dryRun = só testa (nada é apagado);
--- opts.onDone() roda depois de apagar de verdade.
function Confirm:Request(opts)
    opts = opts or {}
    local count = ns.TaxiDatabase:Count()
    if count == 0 and not opts.dryRun then
        Say(L["No recorded routes to delete."])
        return false
    end
    if not Register() or type(StaticPopup_Show) ~= "function" then
        -- Sem como confirmar, nunca apaga: falha para o lado seguro.
        Say(L["Could not open the confirmation window; nothing was deleted."])
        return false
    end
    StaticPopup_Show(opts.dryRun and TEST or REAL, count, Word(), { dryRun = opts.dryRun, onDone = opts.onDone })
    return true
end
