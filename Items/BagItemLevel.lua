-- ============================================================
--  BagItemLevel.lua
--  Mostra o item level dos equipamentos sobre os ícones das bolsas
--  padrão do jogo (ContainerFrame1..N e a bolsa combinada). Não toca
--  nas bolsas de addons de terceiros.
--  Estrutura:
--    * Enumerators (Strategy): como achar os botões de item de um frame
--      (pool EnumerateValidItems; lista Items);
--    * Painter: escreve o número num texto próprio de cada botão;
--    * gatilhos (Observer): gancho no UpdateItems de cada frame, OnShow
--      e eventos de bolsa, tudo agrupado num único redesenho;
--    * só redesenha frames realmente visíveis (IsVisible, não IsShown).
-- ============================================================

local _, ns = ...

local Module = {}
ns.BagItemLevel = Module

local COALESCE_SECONDS = 0.1
local MAX_FRAMES = 13 -- NUM_CONTAINER_FRAMES do jogo
local COMBINED = "ContainerFrameCombinedBags"
local EVENTS = { "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD", "GET_ITEM_INFO_RECEIVED" }

local hooked, queued = {}, false
local Painter = ns.LevelText.Create("itemLevel")

local function Cfg(key) return ns.Config:Get("items.itemLevel." .. key) end

--- Erros do nosso código vão ao tratador de erros sem quebrar a janela da Blizzard.
local function Guard(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and geterrorhandler then geterrorhandler()(err) end
end

-- ----------------------------------------------------------------
-- Enumeradores de botões (Strategy)
-- ----------------------------------------------------------------

--- O pool do frame: EnumerateValidItems() devolve o botão como chave
--- (pairs de um conjunto) ou como valor (ipairs); aceita os dois.
local function FromPool(frame, out)
    if type(frame.EnumerateValidItems) ~= "function" then return false end
    local ok, iter, state, init = pcall(frame.EnumerateValidItems, frame)
    if not ok or type(iter) ~= "function" then return false end
    local count = 0
    local ok2 = pcall(function()
        for first, second in iter, state, init do
            local button = type(first) == "table" and first or second
            if type(button) == "table" then out[#out + 1] = button; count = count + 1 end
            if count >= 400 then break end
        end
    end)
    return ok2 and count > 0
end

--- A lista frame.Items (bolsas individuais).
local function FromList(frame, out)
    local list = frame.Items
    if type(list) ~= "table" then return false end
    local count = 0
    for _, button in ipairs(list) do
        if type(button) == "table" then out[#out + 1] = button; count = count + 1 end
    end
    return count > 0
end

local ENUMERATORS = { FromPool, FromList }

local function Buttons(frame)
    local out = {}
    for _, strategy in ipairs(ENUMERATORS) do
        if strategy(frame, out) then break end
    end
    return out
end

-- ----------------------------------------------------------------
-- Frames de bolsa
-- ----------------------------------------------------------------

local function BagFrames()
    local list = {}
    local combined = rawget(_G, COMBINED)
    if type(combined) == "table" then list[#list + 1] = combined end
    for i = 1, MAX_FRAMES do
        local frame = rawget(_G, "ContainerFrame" .. i)
        if type(frame) == "table" then list[#list + 1] = frame end
    end
    return list
end

local function Visible(frame)
    local fn = frame.IsVisible
    if type(fn) ~= "function" then fn = frame.IsShown end
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn, frame)
    return ok and value == true
end

-- ----------------------------------------------------------------
-- Texto (Painter)
-- ----------------------------------------------------------------

local function Slot(button)
    local bag, slot
    if type(button.GetBagID) == "function" then bag = ns.SafeCall(button.GetBagID, button) end
    if type(button.GetID) == "function" then slot = ns.SafeCall(button.GetID, button) end
    if type(bag) ~= "number" and type(button.GetParent) == "function" then
        local parent = ns.SafeCall(button.GetParent, button)
        if type(parent) == "table" and type(parent.GetBagID) == "function" then
            bag = ns.SafeCall(parent.GetBagID, parent)
        end
    end
    if type(bag) == "number" and type(slot) == "number" then return bag, slot end
end

local function Fn(space, name)
    local t = rawget(_G, space)
    if type(t) == "table" and type(t[name]) == "function" then return t[name] end
end

--- Escreve (ou apaga) o nível de um botão.
local function PaintButton(button)
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

local function PaintFrame(frame)
    if not Cfg("enabled") or not Visible(frame) then return end
    for _, button in ipairs(Buttons(frame)) do Guard(PaintButton, button) end
end

local function PaintAll()
    if not Cfg("enabled") then Painter:ClearAll() return end
    for _, frame in ipairs(BagFrames()) do Guard(PaintFrame, frame) end
end

--- Agrupa vários pedidos seguidos num único redesenho.
local HookAll -- definido abaixo

local function Queue()
    if queued then return end
    queued = true
    local function Run() queued = false; HookAll(); PaintAll() end
    if C_Timer and C_Timer.After then C_Timer.After(COALESCE_SECONDS, Run) else Run() end
end

-- ----------------------------------------------------------------
-- Instalação
-- ----------------------------------------------------------------

local function HookFrame(frame)
    if hooked[frame] then return end
    hooked[frame] = true
    -- A Blizzard redesenha os botões em UpdateItems (Update em versões antigas)
    local method = type(frame.UpdateItems) == "function" and "UpdateItems"
        or (type(frame.Update) == "function" and "Update")
    if method then
        hooksecurefunc(frame, method, function(self) Guard(PaintFrame, self) end)
    end
    if type(frame.HookScript) == "function" then
        frame:HookScript("OnShow", function(self) Guard(PaintFrame, self) end)
    end
end

function HookAll()
    for _, frame in ipairs(BagFrames()) do Guard(HookFrame, frame) end
end

local installed
local function Install()
    if installed then return end
    installed = true
    HookAll()
    -- Frames criados depois (bolsas extras) também recebem o gancho
    if type(rawget(_G, "ContainerFrame_GenerateFrame")) == "function" then
        hooksecurefunc("ContainerFrame_GenerateFrame", function() Guard(HookAll); Queue() end)
    end
    Queue()
end

local events = CreateFrame("Frame")
for _, name in ipairs(EVENTS) do pcall(events.RegisterEvent, events, name) end
events:SetScript("OnEvent", function(_, event)
    if not installed then return end
    Queue()
end)

ns.Bus:Subscribe("READY", Install)

ns.Bus:Subscribe("CONFIG_CHANGED", function(path)
    if path == "items" or (path and path:find("^items%.itemLevel")) then
        if installed then PaintAll() end
    end
end)

function Module:IsInstalled() return installed == true end
