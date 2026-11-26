-- ============================================================
--  CharacterSlots.lua
--  Infraestrutura compartilhada dos recursos que desenham algo sobre os
--  botões de equipamento da janela de personagem (item level, encantamentos).
--  Cuida de: lista de botões, gancho em PaperDollItemSlotButton_Update,
--  OnShow da janela, eventos de equipamento (agrupados num único
--  redesenho), mudanças de configuração e "só pinta botão visível".
--  Cada recurso (cliente) se registra com:
--    path    = "items.<recurso>"        (config; mudanças redesenham o cliente)
--    enabled = function() -> boolean
--    paint   = function(button, slotID) (slotID nil = botão sem item)
--    clear   = function()               (apaga tudo ao desligar)
-- ============================================================

local _, ns = ...

local Slots = {}
ns.CharacterSlots = Slots

local COALESCE_SECONDS = 0.1
local EVENTS = { "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED", "GET_ITEM_INFO_RECEIVED", "PLAYER_ENTERING_WORLD" }

Slots.NAMES = {
    "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
    "CharacterChestSlot", "CharacterShirtSlot", "CharacterTabardSlot", "CharacterWristSlot",
    "CharacterHandsSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
    "CharacterFinger0Slot", "CharacterFinger1Slot", "CharacterTrinket0Slot", "CharacterTrinket1Slot",
    "CharacterMainHandSlot", "CharacterSecondaryHandSlot", "CharacterRangedSlot",
}
local IS_SLOT = {}
for _, name in ipairs(Slots.NAMES) do IS_SLOT[name] = true end

local clients = {}
local installed, queued

--- Erros do nosso código vão ao tratador de erros sem quebrar a janela da Blizzard.
local function Guard(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and geterrorhandler then geterrorhandler()(err) end
end

local function Visible(frame)
    local fn = frame.IsVisible
    if type(fn) ~= "function" then fn = frame.IsShown end
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn, frame)
    return ok and value == true
end

--- Número do slot de equipamento do botão (nil se não tiver).
local function SlotID(button)
    local id = type(button.GetID) == "function" and ns.SafeCall(button.GetID, button) or nil
    if type(id) == "number" and id > 0 then return id end
end

local function ButtonName(button)
    if type(button) ~= "table" or type(button.GetName) ~= "function" then return nil end
    return ns.SafeCall(button.GetName, button)
end

local function PaintButton(client, button)
    if type(button) ~= "table" or not client.enabled() or not Visible(button) then return end
    client.paint(button, SlotID(button))
end

function Slots:PaintAll(client)
    if not client.enabled() then client.clear() return end
    for _, name in ipairs(Slots.NAMES) do
        local button = rawget(_G, name)
        if type(button) == "table" then Guard(PaintButton, client, button) end
    end
end

local function PaintEveryone()
    for _, client in ipairs(clients) do Guard(Slots.PaintAll, Slots, client) end
end

--- Agrupa vários pedidos seguidos num único redesenho.
local function Queue()
    if queued then return end
    queued = true
    local function Run() queued = false; PaintEveryone() end
    if C_Timer and C_Timer.After then C_Timer.After(COALESCE_SECONDS, Run) else Run() end
end

local function Install()
    if installed then return end
    installed = true
    -- A Blizzard redesenha cada slot por aqui (recebe o botão)
    if type(rawget(_G, "PaperDollItemSlotButton_Update")) == "function" then
        hooksecurefunc("PaperDollItemSlotButton_Update", function(button)
            if not IS_SLOT[ButtonName(button) or ""] then return end
            for _, client in ipairs(clients) do Guard(PaintButton, client, button) end
        end)
    end
    local items = rawget(_G, "PaperDollItemsFrame")
    if type(items) == "table" and type(items.HookScript) == "function" then
        items:HookScript("OnShow", function() Queue() end)
    end
    Queue()
end

local events = CreateFrame("Frame")
for _, name in ipairs(EVENTS) do pcall(events.RegisterEvent, events, name) end
events:SetScript("OnEvent", function(_, event, unit)
    if not installed then return end
    if event == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then return end
    Queue()
end)

ns.Bus:Subscribe("READY", Install)

ns.Bus:Subscribe("CONFIG_CHANGED", function(path)
    if not installed or type(path) ~= "string" then return end
    for _, client in ipairs(clients) do
        if path == "items" or path == client.path or path:sub(1, #client.path + 1) == client.path .. "." then
            Guard(Slots.PaintAll, Slots, client)
        end
    end
end)

--- Registra um recurso que desenha sobre os botões.
function Slots:Register(client)
    clients[#clients + 1] = client
end

function Slots:IsInstalled() return installed == true end
