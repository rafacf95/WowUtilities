-- ============================================================
--  MoneyFormat.lua
--  Converte cobre em texto ("12g 30s 5c") com os ícones de moeda do
--  jogo quando a API existir (C_CurrencyInfo ou a função global).
-- ============================================================

local _, ns = ...

local Format = {}
ns.MoneyFormat = Format

local COPPER_PER_SILVER, COPPER_PER_GOLD = 100, 10000

--- Texto simples colorido, usado quando o jogo não oferece a API.
local function Manual(copper)
    local gold = math.floor(copper / COPPER_PER_GOLD)
    local silver = math.floor((copper % COPPER_PER_GOLD) / COPPER_PER_SILVER)
    local rest = copper % COPPER_PER_SILVER

    local parts = {}
    if gold > 0 then parts[#parts + 1] = string.format("|cffffd700%dg|r", gold) end
    if silver > 0 then parts[#parts + 1] = string.format("|cffc7c7cf%ds|r", silver) end
    if rest > 0 or #parts == 0 then parts[#parts + 1] = string.format("|cffeda55f%dc|r", rest) end
    return table.concat(parts, " ")
end

--- Cobre (número >= 0) -> texto. Nunca dispara erro.
function Format:Coins(copper)
    copper = math.floor(math.abs(tonumber(copper) or 0))

    local native = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    if native then
        local ok, text = pcall(native, copper)
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    return Manual(copper)
end
