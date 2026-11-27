-- ============================================================
--  CharacterItemLevel.lua
--  Mostra o item level dos itens equipados sobre os botões de
--  equipamento da janela de personagem e, se ligado, da janela de
--  inspeção (com o mesmo visual). A infraestrutura (botões, ganchos,
--  eventos, visibilidade) é do ns.CharacterSlots / ns.InspectSlots; o
--  texto é do pintor compartilhado (ns.LevelText). Munição, camisa e
--  tabardo ficam sem número pela regra do ns.ItemLevel.
-- ============================================================

local _, ns = ...

local Module = {}
ns.CharacterItemLevel = Module

local function Fn(name)
    local fn = rawget(_G, name)
    return type(fn) == "function" and fn or nil
end

local function NoOp() end

--- Registra o item level num conjunto de botões, com um pintor próprio.
local function Attach(set, painter, enabled)
    set:Register({
        path = "items.characterLevel",
        enabled = enabled,
        paint = function(button, id, unit)
            local level, quality
            if id then
                local link = ns.SafeCall(Fn("GetInventoryItemLink") or NoOp, unit, id)
                level = ns.ItemLevel:Level(link)
                if level then
                    quality = ns.SafeCall(Fn("GetInventoryItemQuality") or NoOp, unit, id)
                end
            end
            painter:Apply(button, level, quality)
        end,
        clear = function() painter:ClearAll() end,
    })
end

local character = ns.LevelText.Create("characterLevel")
Attach(ns.CharacterSlots, character, function() return character:Enabled() end)

local inspect = ns.LevelText.Create("characterLevel", "wuinspectLevel")
Attach(ns.InspectSlots, inspect, function()
    return inspect:Enabled() and ns.Config:Get("items.characterLevel.inspect") == true
end)

function Module:IsInstalled() return ns.CharacterSlots:IsInstalled() end
