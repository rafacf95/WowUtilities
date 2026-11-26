-- ============================================================
--  ClassColors.lua
--  Provedor de cores de classe.
--  Responsabilidade única: dizer qual é a cor de uma classe e
--  embrulhar texto com o escape de cor do WoW.
-- ============================================================

local _, ns = ...

local ClassColors = {}
ns.ClassColors = ClassColors

-- Fallback usado quando RAID_CLASS_COLORS não tem a classe.
-- Inclui classes que o Forever (base Classic) não tem; não causa problema.
local FALLBACK = {
    WARRIOR     = { r = 0.78, g = 0.61, b = 0.43 },
    PALADIN     = { r = 0.96, g = 0.55, b = 0.73 },
    HUNTER      = { r = 0.67, g = 0.83, b = 0.45 },
    ROGUE       = { r = 1.00, g = 0.96, b = 0.41 },
    PRIEST      = { r = 1.00, g = 1.00, b = 1.00 },
    DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
    SHAMAN      = { r = 0.00, g = 0.44, b = 0.87 },
    MAGE        = { r = 0.41, g = 0.80, b = 0.94 },
    WARLOCK     = { r = 0.58, g = 0.51, b = 0.79 },
    MONK        = { r = 0.00, g = 1.00, b = 0.60 },
    DRUID       = { r = 1.00, g = 0.49, b = 0.04 },
    DEMONHUNTER = { r = 0.64, g = 0.19, b = 0.79 },
    EVOKER      = { r = 0.20, g = 0.58, b = 0.50 },
}

local function ToHex(c)
    return string.format("%02x%02x%02x",
        math.floor(c.r * 255 + 0.5),
        math.floor(c.g * 255 + 0.5),
        math.floor(c.b * 255 + 0.5))
end

--- Retorna a tabela {r,g,b} da classe ou nil.
function ClassColors:Get(classFile)
    if type(classFile) ~= "string" then return nil end
    return (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]) or FALLBACK[classFile]
end

--- Embrulha o texto com a cor da classe. Se a classe for desconhecida,
--- devolve o texto inalterado (falha graciosa).
function ClassColors:Wrap(text, classFile)
    local color = self:Get(classFile)
    if not color then return text end
    return "|cff" .. ToHex(color) .. text .. "|r"
end
