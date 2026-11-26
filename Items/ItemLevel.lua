-- ============================================================
--  ItemLevel.lua
--  Serviço compartilhado: item level e qualidade de um item a partir
--  do link, e a regra de "o que é equipamento". Quem precisa do nível
--  (seletor de trinkets, bolsas) pergunta aqui, então a regra e o
--  acesso à API (moderna ou antiga, Adapter) ficam num lugar só.
--  Só lê; nunca altera itens.
-- ============================================================

local _, ns = ...

local ItemLevel = {}
ns.ItemLevel = ItemLevel

local EMPTY = {} -- marca "não é equipamento" no cache

-- Posições de equipamento que não mostram nível (não são "equipamento"
-- no sentido de poder ser comparado): o jogo devolve INVTYPE_NON_EQUIP_IGNORE
-- para o que não se equipa (não string vazia), e bolsas, aljavas, munição,
-- camisa e tabardo só têm nível 1.
local IGNORED = {
    INVTYPE_NON_EQUIP_IGNORE = true, INVTYPE_BAG = true, INVTYPE_QUIVER = true,
    INVTYPE_AMMO = true, INVTYPE_BODY = true, INVTYPE_TABARD = true,
}

local CACHE_LIMIT = 800
local cache, size = {}, 0

local function Fn(space, name)
    local t = rawget(_G, space)
    if type(t) == "table" and type(t[name]) == "function" then return t[name] end
    local g = rawget(_G, name)
    if type(g) == "function" then return g end
end

local function Call(fn, ...)
    if not fn then return end
    return ns.SafeCall(fn, ...)
end

--- True se o tipo de equipamento (equipLoc) conta como equipamento.
function ItemLevel:IsEquipLoc(equipLoc)
    return type(equipLoc) == "string" and equipLoc ~= "" and not IGNORED[equipLoc]
end

--- Item level do link, ou nil se não for equipamento / se ainda não estiver no cache do jogo.
--- Só guarda respostas definitivas (nível que ainda não carregou não é guardado).
function ItemLevel:Level(link)
    if type(link) ~= "string" then return nil end
    local hit = cache[link]
    if hit == EMPTY then return nil end
    if hit then return hit end

    local _, _, _, equipLoc = Call(Fn("C_Item", "GetItemInfoInstant"), link)
    if equipLoc == nil then return nil end -- ainda sem informação: tenta de novo depois
    local level
    if self:IsEquipLoc(equipLoc) then
        level = Call(Fn("C_Item", "GetDetailedItemLevelInfo"), link)
        if type(level) ~= "number" then return nil end
    end

    if size >= CACHE_LIMIT then cache, size = {}, 0 end
    cache[link] = level or EMPTY
    size = size + 1
    return level
end

--- r, g, b da qualidade (cinza/branco/verde/azul/roxo/laranja...).
function ItemLevel:QualityColor(quality)
    local colors = rawget(_G, "ITEM_QUALITY_COLORS")
    local c = type(colors) == "table" and colors[quality]
    if type(c) == "table" then return c.r, c.g, c.b end
    return 1, 1, 1
end

function ItemLevel:Clear()
    cache, size = {}, 0
end
