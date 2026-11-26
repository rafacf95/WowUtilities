-- ============================================================
--  CharacterItemLevel.lua
--  Mostra o item level dos itens equipados sobre os botões de
--  equipamento da janela de personagem. Só a janela do próprio
--  jogador (a inspeção fica de fora). A infraestrutura (botões,
--  ganchos, eventos, visibilidade) é do ns.CharacterSlots; o texto é do
--  pintor compartilhado (ns.LevelText). Munição, camisa e tabardo ficam
--  sem número pela regra do ns.ItemLevel.
-- ============================================================

local _, ns = ...

local Module = {}
ns.CharacterItemLevel = Module

local Painter = ns.LevelText.Create("characterLevel")

local function Fn(name)
    local fn = rawget(_G, name)
    return type(fn) == "function" and fn or nil
end

--- Escreve (ou apaga) o nível do item equipado num botão de slot.
local function Paint(button, id)
    local level, quality
    if id then
        local link = ns.SafeCall(Fn("GetInventoryItemLink") or function() end, "player", id)
        level = ns.ItemLevel:Level(link)
        if level then
            quality = ns.SafeCall(Fn("GetInventoryItemQuality") or function() end, "player", id)
        end
    end
    Painter:Apply(button, level, quality)
end

ns.CharacterSlots:Register({
    path = "items.characterLevel",
    enabled = function() return Painter:Enabled() end,
    paint = Paint,
    clear = function() Painter:ClearAll() end,
})

function Module:IsInstalled() return ns.CharacterSlots:IsInstalled() end
