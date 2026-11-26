-- ============================================================
--  DebugEnchants.lua
--  /wu debug enchants
--  Diagnóstico para o futuro indicador de encantamentos na janela de
--  personagem: o ID de encantamento de cada item equipado (no link), se
--  a tooltip entrega a linha "Enchanted: ..." (por API moderna e por
--  tooltip de leitura), e as profissões do personagem (anéis só podem
--  ser encantados por Encantadores). Só lê; não altera nada. Report
--  monta as linhas (testável sem o jogo); o comando abre a janela de
--  texto copiável.
-- ============================================================

local _, ns = ...

local Enchants = {}
ns.DebugEnchants = Enchants

local Show = ns.Debug.Show

local SCAN_NAME = "WowUtilitiesEnchantScan"
local MAX_LINES = 40

local SLOTS = {
    { 1, "Head" }, { 2, "Neck" }, { 3, "Shoulder" }, { 4, "Shirt" }, { 5, "Chest" }, { 6, "Waist" },
    { 7, "Legs" }, { 8, "Feet" }, { 9, "Wrist" }, { 10, "Hands" }, { 11, "Finger 1" }, { 12, "Finger 2" },
    { 13, "Trinket 1" }, { 14, "Trinket 2" }, { 15, "Back" }, { 16, "Main hand" }, { 17, "Off hand" },
    { 18, "Ranged/relic" }, { 19, "Tabard" },
}

local API_CHECKS = {
    { "GetInventoryItemLink",            { "GetInventoryItemLink" } },
    { "C_TooltipInfo.GetInventoryItem",  { "C_TooltipInfo", "GetInventoryItem" } },
    { "TooltipUtil.SurfaceArgs",         { "TooltipUtil", "SurfaceArgs" } },
    { "GetProfessions",                  { "GetProfessions" } },
    { "GetProfessionInfo",               { "GetProfessionInfo" } },
    { "GetNumSkillLines",                { "GetNumSkillLines" } },
    { "GetSkillLineInfo",                { "GetSkillLineInfo" } },
    { "C_TradeSkillUI.GetAllProfessionTradeSkillLines", { "C_TradeSkillUI", "GetAllProfessionTradeSkillLines" } },
    { "IsPlayerSpell",                   { "IsPlayerSpell" } },
    { "C_Item.GetItemGem (gems)",        { "C_Item", "GetItemGem" } },
}

local function Resolve(path)
    local value = _G
    for _, key in ipairs(path) do
        if type(value) ~= "table" then return nil end
        value = rawget(value, key)
    end
    return value
end

local function Call(fn, ...)
    if not fn then return end
    return ns.SafeCall(fn, ...)
end

--- Padrão Lua que casa a linha de encantamento, a partir da frase do jogo
--- ("Enchanted: %s" já traduzida). Devolve nil se a frase não existir.
local function EnchantPattern()
    local phrase = rawget(_G, "ENCHANTED_TOOLTIP_LINE")
    if type(phrase) ~= "string" or not phrase:find("%%s") then return nil, phrase end
    local escaped = phrase:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    escaped = escaped:gsub("%%s", "(.+)")
    return "^" .. escaped .. "$", phrase
end

--- ID de encantamento do link: "item:ID:ENCHANT:...". nil = não conseguiu ler; 0 = sem encantamento.
local function EnchantID(link)
    local id = type(link) == "string" and link:match("item:%-?%d+:(%-?%d*)")
    if id == nil then return nil end
    return tonumber(id) or 0
end

--- Linhas de texto da tooltip pela API moderna (C_TooltipInfo).
local function ModernLines(slotID)
    local fn = Resolve({ "C_TooltipInfo", "GetInventoryItem" })
    if not fn then return nil, "API missing" end
    local data = Call(fn, "player", slotID)
    if type(data) ~= "table" then return nil, "no data" end
    local surface = Resolve({ "TooltipUtil", "SurfaceArgs" })
    if surface then Call(surface, data) end
    local lines = {}
    if type(data.lines) == "table" then
        for _, line in ipairs(data.lines) do
            if type(line) == "table" then
                if surface then Call(surface, line) end
                if type(line.leftText) == "string" then lines[#lines + 1] = line.leftText end
            end
        end
    end
    return lines
end

local scanner
--- Linhas de texto pela tooltip de leitura (escondida), a técnica clássica.
local function ScanLines(slotID)
    if type(rawget(_G, "CreateFrame")) ~= "function" then return nil, "no CreateFrame" end
    if not scanner then
        local ok, frame = pcall(CreateFrame, "GameTooltip", SCAN_NAME, nil, "GameTooltipTemplate")
        if not ok or type(frame) ~= "table" then return nil, "could not create the scan tooltip" end
        scanner = frame
    end
    local ok, err = pcall(function()
        scanner:SetOwner(UIParent, "ANCHOR_NONE")
        scanner:ClearLines()
        scanner:SetInventoryItem("player", slotID)
    end)
    if not ok then return nil, "SetInventoryItem failed: " .. tostring(err) end
    local lines = {}
    local count = Call(scanner.NumLines, scanner)
    for i = 1, math.min(type(count) == "number" and count or 0, MAX_LINES) do
        local region = rawget(_G, SCAN_NAME .. "TextLeft" .. i)
        local text = type(region) == "table" and Call(region.GetText, region) or nil
        if type(text) == "string" then lines[#lines + 1] = text end
    end
    return lines
end

local function FindEnchant(lines, pattern)
    if not lines or not pattern then return nil end
    for _, text in ipairs(lines) do
        local name = text:match(pattern)
        if name then return name end
    end
end

local function Environment(add)
    local version, build, _, toc = ns.SafeCall(GetBuildInfo)
    add(string.format("Game version: %s (build %s, interface %s)",
        Show(version), Show(build), Show(toc)))
    local pattern, phrase = EnchantPattern()
    add("ENCHANTED_TOOLTIP_LINE = " .. Show(phrase) .. " | pattern: " .. Show(pattern))
    local classLocal, classToken = Call(Resolve({ "UnitClass" }), "player")
    add(string.format("Class: %s (%s) | level %s", Show(classLocal), Show(classToken), Show((Call(Resolve({ "UnitLevel" }), "player")))))
end

local function ApiPresence(add)
    add("")
    add("== API presence ==")
    for _, check in ipairs(API_CHECKS) do
        add(string.format("  %-52s %s", check[1], type(Resolve(check[2])) == "function" and "yes" or "MISSING"))
    end
end

local function Professions(add)
    add("")
    add("== Professions ==")
    local list = {}
    local getProfessions = Resolve({ "GetProfessions" })
    local getInfo = Resolve({ "GetProfessionInfo" })
    if getProfessions and getInfo then
        local a, b, c, d, e = Call(getProfessions)
        for _, index in ipairs({ a or false, b or false, c or false, d or false, e or false }) do
            if index then
                local name, _, rank, _, _, _, skillLine = Call(getInfo, index)
                list[#list + 1] = string.format("  [GetProfessions] %s | rank %s | skillLine %s", Show(name), Show(rank), Show(skillLine))
            end
        end
    end
    local numLines, getLine = Resolve({ "GetNumSkillLines" }), Resolve({ "GetSkillLineInfo" })
    if numLines and getLine then
        local count = Call(numLines)
        for i = 1, math.min(type(count) == "number" and count or 0, 60) do
            local name, isHeader, _, rank = Call(getLine, i)
            if name and not isHeader and (name:lower():find("enchant") or name:lower():find("encant")) then
                list[#list + 1] = string.format("  [GetSkillLineInfo #%d] %s | rank %s", i, Show(name), Show(rank))
            end
        end
        list[#list + 1] = "  skill lines scanned: " .. Show(count) .. " (only names containing 'enchant'/'encant' are listed)"
    end
    if #list == 0 then add("  (no professions API returned data)") end
    for _, line in ipairs(list) do add(line) end
end

local function Slots(add)
    add("")
    add("== Equipped items ==")
    local pattern = EnchantPattern()
    local getLink = Resolve({ "GetInventoryItemLink" })
    local equipped = 0
    for _, entry in ipairs(SLOTS) do
        local slotID, label = entry[1], entry[2]
        local link = Call(getLink, "player", slotID)
        if type(link) ~= "string" then
            add(string.format("  %2d %-13s empty", slotID, label))
        else
            equipped = equipped + 1
            local modern, modernWhy = ModernLines(slotID)
            local scanned, scanWhy = ScanLines(slotID)
            local m = FindEnchant(modern, pattern)
            local s = FindEnchant(scanned, pattern)
            add(string.format("  %2d %-13s enchantID %s | modern: %s | scan: %s",
                slotID, label, Show(EnchantID(link)),
                modern and string.format("%d lines, enchant %s", #modern, Show(m)) or tostring(modernWhy),
                scanned and string.format("%d lines, enchant %s", #scanned, Show(s)) or tostring(scanWhy)))
        end
    end
    add("Equipped slots: " .. equipped)
end

--- Monta o relatório como lista de linhas.
function Enchants:Report()
    local lines = {}
    local function add(text) lines[#lines + 1] = text end
    add("WowUtilities enchant debug (read-only; nothing is changed)")
    Environment(add)
    ApiPresence(add)
    Professions(add)
    Slots(add)
    return lines
end

ns.Debug:Register("enchants", function()
    local ok, lines = pcall(Enchants.Report, Enchants)
    if not ok then lines = { "WowUtilities enchant debug failed: " .. tostring(lines) } end
    ns.Debug:Output("WowUtilities debug — enchants", lines)
end)
