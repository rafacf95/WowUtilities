-- ============================================================
--  ArmorFilter.lua
--  Filtra uma lista de aparências por tipo de armadura. Função pura
--  sobre a lista: não conhece a interface da Blizzard (isso é da
--  WardrobeIntegration).
-- ============================================================

local _, ns = ...
local L = ns.L

local Filter = {}
ns.ArmorFilter = Filter

Filter.ALL = "all"

--- Opções do dropdown, na ordem de exibição.
Filter.OPTIONS = {
    { id = "all",      label = L["All armor types"] },
    { id = "cloth",    label = L["Cloth"] },
    { id = "leather",  label = L["Leather"] },
    { id = "mail",     label = L["Mail"] },
    { id = "plate",    label = L["Plate"] },
    { id = "cosmetic", label = L["Cosmetic"] },
}

local function IsKnownOption(id)
    for _, option in ipairs(Filter.OPTIONS) do
        if option.id == id then return true end
    end
    return false
end

--- Devolve a lista filtrada (nova) ou a própria lista quando não há o que filtrar.
--- list = { { visualID, isHideVisual, ... }, ... }
function Filter:Apply(list, category, typeId)
    if typeId == Filter.ALL or not IsKnownOption(typeId) then return list end
    if not ns.ArmorType:IsArmorCategory(category) then return list end

    local result = {}
    for _, entry in ipairs(list) do
        if entry.isHideVisual then
            result[#result + 1] = entry -- "esconder item" não tem tipo: sempre aparece
        else
            local types = ns.ArmorType:Of(entry.visualID, category)
            if types and types[typeId] then result[#result + 1] = entry end
        end
    end
    return result
end
