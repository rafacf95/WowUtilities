-- ============================================================
--  EnchantAbbreviation.lua
--  Encurta o nome de um encantamento para destacar o valor do bônus:
--    "Weapon Damage +4"  ->  "Dmg +4"   (modo "short")
--    "Weapon Damage +4"  ->  "+4"       (modo "value")
--  As abreviações são dados por idioma (a lista do inglês está aqui; as
--  outras vêm dos arquivos de Locales via ns.RegisterEnchantAbbreviations).
--  Idioma sem lista mantém o nome completo. Texto sem número no modo
--  "value" cai no modo "short".
-- ============================================================

local _, ns = ...

local Abbreviation = {}
ns.EnchantAbbreviation = Abbreviation

Abbreviation.MODES = { "full", "short", "value" }

local ENGLISH = {
    { "All Stats", "All" },
    { "Weapon Damage", "Dmg" },
    { "Mana Regeneration", "Mp5" },
    { "Healing Power", "Heal" },
    { "Attack Power", "AP" },
    { "Spell Damage", "SD" },
    { "Critical Strike", "Crit" },
    { "Resistance", "Res" },
    { "Intellect", "Int" },
    { "Strength", "Str" },
    { "Agility", "Agi" },
    { "Stamina", "Sta" },
    { "Spirit", "Spi" },
    { "Resist", "Res" },
    { "Defense", "Def" },
    { "Health", "HP" },
}

--- Lista do idioma ativo (inglês por padrão), da mais longa para a mais curta.
local function ActiveList()
    local list = ns.enchantAbbreviations and ns.enchantAbbreviations.list
    if not list and ns.locale ~= "enUS" then return {} end
    list = list or ENGLISH
    local sorted = {}
    for i, pair in ipairs(list) do sorted[i] = pair end
    table.sort(sorted, function(a, b) return #a[1] > #b[1] end)
    return sorted
end

local function IsLetter(char)
    return char ~= "" and char:match("%a") ~= nil
end

--- Troca `from` por `to` só onde forma uma palavra inteira (sem letra ASCII colada).
local function ReplaceWord(text, from, to)
    local out, pos = {}, 1
    while true do
        local first, last = text:find(from, pos, true)
        if not first then break end
        local before = first > 1 and text:sub(first - 1, first - 1) or ""
        local after = text:sub(last + 1, last + 1)
        out[#out + 1] = text:sub(pos, first - 1)
        if IsLetter(before) or IsLetter(after) then
            out[#out + 1] = text:sub(first, last)
        else
            out[#out + 1] = to
        end
        pos = last + 1
    end
    out[#out + 1] = text:sub(pos)
    return table.concat(out)
end

local function Short(name)
    for _, pair in ipairs(ActiveList()) do
        name = ReplaceWord(name, pair[1], pair[2])
    end
    return name
end

--- Primeiro valor numérico com sinal/porcentagem ("+4", "+2%", "-3"), ou nil.
local function Value(name)
    return name:match("[%+%-]%d+%%?") or name:match("%d+%%?")
end

--- Nome formatado para o modo: "full", "short" (padrão) ou "value".
function Abbreviation:Format(name, mode)
    if type(name) ~= "string" then return name end
    if mode == "full" then return name end
    if mode == "value" then return Value(name) or Short(name) end
    return Short(name)
end
