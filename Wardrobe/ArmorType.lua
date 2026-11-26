-- ============================================================
--  ArmorType.lua
--  Descobre o tipo de armadura (tecido, couro, malha, placa) de uma
--  aparência de transmog. A API não oferece isso: o tipo vem dos itens
--  que têm a aparência (C_Item.GetItemInfoInstant, dado local, sem
--  esperar o servidor). Só os itens COLETADOS contam (cai em todas as
--  fontes quando nada foi coletado). Cache por aparência, limpo quando
--  a coleção muda (ver WardrobeIntegration).
-- ============================================================

local _, ns = ...

local ArmorType = {}
ns.ArmorType = ArmorType

local ARMOR_CLASS = 4 -- Enum.ItemClass.Armor
local SUBCLASS_TO_TYPE = { [1] = "cloth", [2] = "leather", [3] = "mail", [4] = "plate", [5] = "cosmetic" }

-- Categorias de transmog que são peças de armadura (as demais não têm tipo)
local ARMOR_CATEGORY_NAMES = { "Head", "Shoulder", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet" }
local ARMOR_CATEGORY_FALLBACK = { 1, 2, 4, 7, 8, 9, 10, 11 }

local cache = {} -- [visualID] = { cloth = true, ... } | false (tipo desconhecido)

function ArmorType:IsArmorCategory(category)
    if type(category) ~= "number" then return false end
    local enum = Enum and Enum.TransmogCollectionType
    if enum then
        for _, name in ipairs(ARMOR_CATEGORY_NAMES) do
            if enum[name] == category then return true end
        end
        return false
    end
    for _, id in ipairs(ARMOR_CATEGORY_FALLBACK) do
        if id == category then return true end
    end
    return false
end

local function TypeOfItem(itemID)
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not fn or not itemID then return nil end
    local _, _, _, _, _, classID, subClassID = ns.SafeCall(fn, itemID)
    if classID ~= ARMOR_CLASS then return nil end
    return SUBCLASS_TO_TYPE[subClassID]
end

local function ItemIDFromSource(api, source)
    if type(source) == "table" then return source.itemID end
    if api.GetSourceItemID then return (ns.SafeCall(api.GetSourceItemID, source)) end
    if api.GetSourceInfo then
        local info = ns.SafeCall(api.GetSourceInfo, source)
        return type(info) == "table" and info.itemID or nil
    end
end

-- Estratégias para achar os itens de uma aparência (a primeira que der resultado vence).
-- O Wardrobe só libera a aparência para o tipo do item que foi COLETADO: um item
-- de placa e um de malha podem dividir a aparência, mas coletar um não libera o outro.
local strategies = {
    -- 1. Itens já coletados pelo jogador
    function(visualID, category)
        local api = C_TransmogCollection
        if type(api) ~= "table" or not api.GetAppearanceSources then return nil end
        local sources = ns.SafeCall(api.GetAppearanceSources, visualID, category)
        if type(sources) ~= "table" then return nil end
        local ids = {}
        for _, source in ipairs(sources) do
            if type(source) == "table" and source.isCollected ~= false then ids[#ids + 1] = source.itemID end
        end
        return ids
    end,
    -- 2. Aparência ainda não coletada: todas as fontes (tipos em que dá para obtê-la)
    function(visualID)
        local api = C_TransmogCollection
        if type(api) ~= "table" or not api.GetAllAppearanceSources then return nil end
        local sources = ns.SafeCall(api.GetAllAppearanceSources, visualID)
        if type(sources) ~= "table" then return nil end
        local ids = {}
        for _, source in ipairs(sources) do
            ids[#ids + 1] = ItemIDFromSource(api, source)
        end
        return ids
    end,
}

local function Classify(itemIDs)
    local types, any = {}, false
    for _, itemID in pairs(itemIDs) do
        local kind = TypeOfItem(itemID)
        if kind then types[kind] = true; any = true end
    end
    return any and types or nil
end

--- Conjunto de tipos da aparência ({ mail = true, ... }) ou nil se desconhecido.
function ArmorType:Of(visualID, category)
    if visualID == nil then return nil end
    local cached = cache[visualID]
    if cached ~= nil then return cached or nil end

    for _, strategy in ipairs(strategies) do
        local ids = strategy(visualID, category)
        local types = ids and Classify(ids)
        if types then
            cache[visualID] = types
            return types
        end
    end
    cache[visualID] = false
    return nil
end

function ArmorType:Clear()
    cache = {}
end
