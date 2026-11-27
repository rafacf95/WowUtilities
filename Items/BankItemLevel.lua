-- ============================================================
--  BankItemLevel.lua
--  Mostra o item level dos equipamentos guardados no banco padrão do
--  jogo. No Forever o banco é o BankPanel (abas de personagem com IDs de
--  bolsa 6..14, confirmado pelo /wu debug bank): os botões vêm do pool
--  (EnumerateValidItems) e cada um diz a bolsa e o espaço por
--  GetBankTabID() e GetContainerSlotID().
--  Visual: o mesmo das bolsas (opções items.itemLevel.*); a opção
--  items.itemLevel.bank liga e desliga só o banco.
--  Gatilhos (Observer): ganchos nas funções do painel que recriam os
--  botões, no Refresh de cada botão, OnShow e eventos de bolsa/banco,
--  agrupados num único redesenho.
-- ============================================================

local _, ns = ...

local Module = {}
ns.BankItemLevel = Module

local COALESCE_SECONDS = 0.1
local PANEL_HOOKS = { "RefreshBankPanel", "GenerateItemSlotsForSelectedTab", "GenerateAndPlaceOnePageOfItemButtons", "SelectTab" }
local EVENTS = {
    "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED", "BANK_TABS_CHANGED",
    "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED",
}

-- Mesmas opções das bolsas; campo próprio no botão para limpar só o banco
local Painter = ns.LevelText.Create("itemLevel", "wuitemLevelBank")
local hookedPanel, hookedButtons, queued, installed = nil, {}, false, false

local function Cfg(key) return ns.Config:Get("items.itemLevel." .. key) end
local function Enabled() return Cfg("enabled") == true and Cfg("bank") == true end

local function Guard(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and geterrorhandler then geterrorhandler()(err) end
end

local function Panel()
    local panel = rawget(_G, "BankPanel")
    if type(panel) ~= "table" then
        local bank = rawget(_G, "BankFrame")
        panel = type(bank) == "table" and rawget(bank, "BankPanel") or nil
    end
    return type(panel) == "table" and panel or nil
end

local function Visible(frame)
    local fn = frame.IsVisible or frame.IsShown
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn, frame)
    return ok and value == true
end

--- Botões do pool: EnumerateValidItems devolve o botão como chave ou como valor.
local function Buttons(panel)
    local out = {}
    if type(panel.EnumerateValidItems) ~= "function" then return out end
    local ok, iter, state, init = pcall(panel.EnumerateValidItems, panel)
    if not ok or type(iter) ~= "function" then return out end
    pcall(function()
        for first, second in iter, state, init do
            local button = type(first) == "table" and first or second
            if type(button) == "table" then out[#out + 1] = button end
            if #out >= 400 then break end
        end
    end)
    return out
end

--- Bolsa e espaço do botão (GetBankTabID/GetContainerSlotID; GetBagID/GetID como reserva).
local function Slot(button)
    local function Number(name)
        if type(button[name]) ~= "function" then return nil end
        local value = ns.SafeCall(button[name], button)
        return type(value) == "number" and value or nil
    end
    local bag = Number("GetBankTabID") or Number("GetBagID")
    local slot = Number("GetContainerSlotID") or Number("GetID")
    if bag and slot and slot > 0 then return bag, slot end
end

local function Fn(space, name)
    local t = rawget(_G, space)
    if type(t) == "table" and type(t[name]) == "function" then return t[name] end
end

local function PaintButton(button)
    if not Enabled() then Painter:Clear(button) return end
    local bag, slot = Slot(button)
    local level, quality
    if bag then
        local link = ns.SafeCall(Fn("C_Container", "GetContainerItemLink") or function() end, bag, slot)
        level = ns.ItemLevel:Level(link)
        if level then
            local info = ns.SafeCall(Fn("C_Container", "GetContainerItemInfo") or function() end, bag, slot)
            quality = type(info) == "table" and info.quality or nil
        end
    end
    Painter:Apply(button, level, quality)
end

--- Cada botão redesenhado pela Blizzard (item movido) é repintado na hora.
local function HookButton(button)
    if hookedButtons[button] or type(button.Refresh) ~= "function" then return end
    hookedButtons[button] = true
    hooksecurefunc(button, "Refresh", function(self) Guard(PaintButton, self) end)
end

local function PaintAll()
    if not Enabled() then Painter:ClearAll() return end
    local panel = Panel()
    if not (panel and Visible(panel)) then return end
    for _, button in ipairs(Buttons(panel)) do
        Guard(HookButton, button)
        Guard(PaintButton, button)
    end
end

local HookPanel -- definido abaixo

local function Queue()
    if queued then return end
    queued = true
    local function Run() queued = false; Guard(HookPanel); PaintAll() end
    if C_Timer and C_Timer.After then C_Timer.After(COALESCE_SECONDS, Run) else Run() end
end

--- O painel pode nascer depois do login: liga os ganchos na primeira vez que existir.
function HookPanel()
    local panel = Panel()
    if not panel or hookedPanel == panel then return end
    hookedPanel = panel
    for _, method in ipairs(PANEL_HOOKS) do
        if type(panel[method]) == "function" then hooksecurefunc(panel, method, Queue) end
    end
    if type(panel.HookScript) == "function" then panel:HookScript("OnShow", Queue) end
end

local events = CreateFrame("Frame")
for _, name in ipairs(EVENTS) do pcall(events.RegisterEvent, events, name) end
events:SetScript("OnEvent", function()
    if installed then Queue() end
end)

ns.Bus:Subscribe("READY", function()
    installed = true
    Guard(HookPanel)
end)

ns.Bus:Subscribe("CONFIG_CHANGED", function(path)
    if installed and (path == "items" or (path and path:find("^items%.itemLevel"))) then PaintAll() end
end)

function Module:IsInstalled() return installed end
