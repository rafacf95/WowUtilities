-- ============================================================
--  CharacterSlots.lua
--  Infraestrutura compartilhada dos recursos que desenham algo sobre os
--  botões de equipamento (item level, encantamentos). Há dois conjuntos
--  de botões, criados pela mesma fábrica (NewSet):
--    * ns.CharacterSlots = janela de personagem (unidade "player");
--    * ns.InspectSlots   = janela de inspeção (Blizzard_InspectUI, que só
--      carrega na primeira inspeção; unidade = InspectFrame.unit).
--  Cada conjunto cuida de: lista de botões, gancho na função da Blizzard
--  que redesenha um slot, OnShow da janela, eventos (agrupados num único
--  redesenho), mudanças de configuração e "só pinta botão visível".
--  Cada recurso (cliente) se registra num conjunto com:
--    path    = "items.<recurso>"              (config; mudanças redesenham o cliente)
--    enabled = function() -> boolean
--    paint   = function(button, slotID, unit) (slotID nil = botão sem item)
--    clear   = function()                     (apaga tudo ao desligar)
-- ============================================================

local _, ns = ...

local COALESCE_SECONDS = 0.1
local INSPECT_ADDON = "Blizzard_InspectUI"

local SLOT_SUFFIXES = {
    "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "ShirtSlot", "TabardSlot", "WristSlot",
    "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot",
    "MainHandSlot", "SecondaryHandSlot", "RangedSlot",
}

local function Names(prefix)
    local list = {}
    for i, suffix in ipairs(SLOT_SUFFIXES) do list[i] = prefix .. suffix end
    return list
end

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

--- Cria um conjunto de botões. def:
---   names   = lista de nomes globais dos botões
---   hook    = nome da função global da Blizzard que redesenha um slot (recebe o botão)
---   frame   = nome do frame que contém os botões (OnShow redesenha)
---   unit    = function() -> unidade dona dos itens
---   events  = lista de eventos que redesenham
---   accept  = function(set, event, ...) -> boolean (filtra os eventos)
---   addon   = addon da Blizzard que cria os botões (instala quando ele carregar)
local function NewSet(def)
    local set = { NAMES = def.names }
    local isSlot = {}
    for _, name in ipairs(def.names) do isSlot[name] = true end
    local clients = {}
    local installed, queued

    function set:Unit() return def.unit() end

    local function PaintButton(client, button)
        if type(button) ~= "table" or not client.enabled() or not Visible(button) then return end
        client.paint(button, SlotID(button), set:Unit())
    end

    function set:PaintAll(client)
        if not client.enabled() then client.clear() return end
        for _, name in ipairs(def.names) do
            local button = rawget(_G, name)
            if type(button) == "table" then Guard(PaintButton, client, button) end
        end
    end

    local function PaintEveryone()
        for _, client in ipairs(clients) do Guard(set.PaintAll, set, client) end
    end

    --- Agrupa vários pedidos seguidos num único redesenho.
    function set:Queue()
        if queued or not installed then return end
        queued = true
        local function Run() queued = false; PaintEveryone() end
        if C_Timer and C_Timer.After then C_Timer.After(COALESCE_SECONDS, Run) else Run() end
    end

    local function Install()
        local hasHook = type(rawget(_G, def.hook)) == "function"
        local items = rawget(_G, def.frame)
        if installed or (not hasHook and type(items) ~= "table") then return end -- janela ainda não existe
        installed = true
        if hasHook then
            hooksecurefunc(def.hook, function(button)
                if not isSlot[ButtonName(button) or ""] then return end
                for _, client in ipairs(clients) do Guard(PaintButton, client, button) end
            end)
        end
        if type(items) == "table" and type(items.HookScript) == "function" then
            items:HookScript("OnShow", function() set:Queue() end)
        end
        set:Queue()
    end

    local events = CreateFrame("Frame")
    for _, name in ipairs(def.events) do pcall(events.RegisterEvent, events, name) end
    if def.addon then pcall(events.RegisterEvent, events, "ADDON_LOADED") end
    events:SetScript("OnEvent", function(_, event, ...)
        if event == "ADDON_LOADED" then
            if ... == def.addon and ns.db then Install() end
            return
        end
        if installed and def.accept(set, event, ...) then set:Queue() end
    end)

    ns.Bus:Subscribe("READY", Install) -- janela já carregada (ou da própria interface)

    ns.Bus:Subscribe("CONFIG_CHANGED", function(path)
        if not installed or type(path) ~= "string" then return end
        for _, client in ipairs(clients) do
            if path == "items" or path == client.path or path:sub(1, #client.path + 1) == client.path .. "." then
                Guard(set.PaintAll, set, client)
            end
        end
    end)

    --- Registra um recurso que desenha sobre os botões.
    function set:Register(client)
        clients[#clients + 1] = client
    end

    function set:IsInstalled() return installed == true end

    return set
end

ns.CharacterSlots = NewSet({
    names = Names("Character"),
    hook = "PaperDollItemSlotButton_Update",
    frame = "PaperDollItemsFrame",
    unit = function() return "player" end,
    events = { "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED", "GET_ITEM_INFO_RECEIVED", "PLAYER_ENTERING_WORLD" },
    accept = function(_, event, unit)
        return event ~= "UNIT_INVENTORY_CHANGED" or unit == "player"
    end,
})

--- Unidade que a janela de inspeção está mostrando.
local function InspectUnit()
    local frame = rawget(_G, "InspectFrame")
    local unit = type(frame) == "table" and rawget(frame, "unit") or nil
    return type(unit) == "string" and unit ~= "" and unit or "target"
end

ns.InspectSlots = NewSet({
    names = Names("Inspect"),
    hook = "InspectPaperDollItemSlotButton_Update",
    frame = "InspectPaperDollItemsFrame",
    unit = InspectUnit,
    addon = INSPECT_ADDON,
    events = { "INSPECT_READY", "GET_ITEM_INFO_RECEIVED", "UNIT_INVENTORY_CHANGED" },
    accept = function(set, event, arg)
        -- outras coisas também pedem inspeção: só interessa o jogador da janela
        if event == "INSPECT_READY" then
            local guid = ns.SafeCall(UnitGUID, set:Unit())
            return guid ~= nil and arg == guid
        end
        if event == "UNIT_INVENTORY_CHANGED" then return arg == set:Unit() end
        return true
    end,
})
