-- ============================================================
--  FactionColors.lua
--  Provedor de cores de facção.
--  Responsabilidade única: cor de uma facção e escape de cor.
-- ============================================================

local _, ns = ...

local FactionColors = {}
ns.FactionColors = FactionColors

-- Chaves = valor "inglês" devolvido por UnitFactionGroup.
local HEX = {
    Horde    = "ff2020", -- vermelho
    Alliance = "3380ff", -- azul
}

--- Embrulha o texto com a cor da facção. Facção sem cor definida
--- (ex.: "Neutral") devolve o texto inalterado.
function FactionColors:Wrap(text, faction)
    local hex = HEX[faction]
    if not hex then return text end
    return "|cff" .. hex .. text .. "|r"
end

function FactionColors:Has(faction)
    return HEX[faction] ~= nil
end
