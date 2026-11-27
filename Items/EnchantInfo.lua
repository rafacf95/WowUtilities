-- ============================================================
--  EnchantInfo.lua
--  Serviço: o item de um slot equipado está encantado? Com qual
--  encantamento? E esse slot aceita encantamento? Só lê.
--    * encantado = o campo de encantamento do link do item ("item:ID:ENCHANT:...")
--      é diferente de zero;
--    * nome = a linha "Enchanted: ..." da tooltip (frase do jogo, já traduzida),
--      pela API moderna e, na falta dela, por uma tooltip de leitura;
--    * regra dos slots: uma tabela só (ENCHANTABLE) mais as exceções por
--      tipo de item (armas, escudo, anéis de Encantador).
-- ============================================================

local _, ns = ...

local EnchantInfo = {}
ns.EnchantInfo = EnchantInfo

local ENCHANTING_SKILL_LINE = 333 -- independe do idioma
local SCAN_NAME = "WowUtilitiesEnchantInfoScan"
local CACHE_LIMIT = 200

-- Slots que aceitam encantamento sempre (pescoço também no Forever)
local ENCHANTABLE = {
    [1] = true, [2] = true, [3] = true, [5] = true, [7] = true, [8] = true,
    [9] = true, [10] = true, [15] = true,
}
local RING_SLOTS = { [11] = true, [12] = true }
local MAIN_HAND, OFF_HAND = 16, 17

local MAIN_HAND_LOCS = {
    INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
}
local OFF_HAND_LOCS = {
    INVTYPE_SHIELD = true, INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_WEAPONMAINHAND = true,
}
local WEAPON_CLASS, FISHING_POLE = 2, 20

local names, size = {}, 0

local function Fn(space, name)
    local t = space and rawget(_G, space)
    if type(t) == "table" and type(t[name]) == "function" then return t[name] end
    local g = rawget(_G, name)
    if type(g) == "function" then return g end
end

local function Call(fn, ...)
    if not fn then return end
    return ns.SafeCall(fn, ...)
end

--- ID do encantamento no link: número (0 = sem encantamento) ou nil se não conseguiu ler.
function EnchantInfo:Id(link)
    if type(link) ~= "string" then return nil end
    local id = link:match("item:%-?%d+:(%-?%d*)")
    if id == nil then return nil end
    return tonumber(id) or 0
end

--- Padrão que casa a linha de encantamento, a partir da frase do jogo.
local function Pattern()
    local phrase = rawget(_G, "ENCHANTED_TOOLTIP_LINE")
    if type(phrase) ~= "string" or not phrase:find("%%s") then return nil end
    local escaped = phrase:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    escaped = escaped:gsub("%%s", "(.+)")
    return "^" .. escaped .. "$"
end

local function ModernTexts(unit, slotID)
    local data = Call(Fn("C_TooltipInfo", "GetInventoryItem"), unit, slotID)
    if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    local texts = {}
    for _, line in ipairs(data.lines) do
        if type(line) == "table" and type(line.leftText) == "string" then texts[#texts + 1] = line.leftText end
    end
    return texts
end

local scanner
local function ScanTexts(unit, slotID)
    if type(rawget(_G, "CreateFrame")) ~= "function" then return nil end
    if not scanner then
        local ok, frame = pcall(CreateFrame, "GameTooltip", SCAN_NAME, nil, "GameTooltipTemplate")
        if not ok or type(frame) ~= "table" then return nil end
        scanner = frame
    end
    local ok = pcall(function()
        scanner:SetOwner(UIParent, "ANCHOR_NONE")
        scanner:ClearLines()
        scanner:SetInventoryItem(unit, slotID)
    end)
    if not ok then return nil end
    local texts = {}
    local count = Call(scanner.NumLines, scanner)
    for i = 1, math.min(type(count) == "number" and count or 0, 40) do
        local region = rawget(_G, SCAN_NAME .. "TextLeft" .. i)
        local text = type(region) == "table" and Call(region.GetText, region) or nil
        if type(text) == "string" then texts[#texts + 1] = text end
    end
    return texts
end

local function FindName(texts, pattern)
    if not texts then return nil end
    for _, text in ipairs(texts) do
        local name = text:match(pattern)
        if name then return name end
    end
end

--- Nome do encantamento do item do slot da unidade (nil se a tooltip não entregou).
function EnchantInfo:Name(slotID, link, unit)
    unit = unit or "player"
    local hit = names[link]
    if hit then return hit end
    local pattern = Pattern()
    if not pattern then return nil end
    local name = FindName(ModernTexts(unit, slotID), pattern) or FindName(ScanTexts(unit, slotID), pattern)
    if name then
        if size >= CACHE_LIMIT then names, size = {}, 0 end
        names[link] = name
        size = size + 1
    end
    return name
end

--- O personagem tem a profissão Encantamento?
function EnchantInfo:IsEnchanter()
    local list = { Call(Fn(nil, "GetProfessions")) }
    local info = Fn(nil, "GetProfessionInfo")
    if not info then return false end
    for i = 1, 5 do
        local index = list[i]
        if type(index) == "number" then
            local _, _, _, _, _, _, skillLine = Call(info, index)
            if skillLine == ENCHANTING_SKILL_LINE then return true end
        end
    end
    return false
end

--- Este slot, com este item, aceita encantamento?
--- opts.countRings: anéis só contam se ligado e o personagem for Encantador.
--- opts.anyRing: anéis contam sem olhar a profissão (de outro jogador não dá para saber).
function EnchantInfo:Enchantable(slotID, link, opts)
    if ENCHANTABLE[slotID] then return true end
    if RING_SLOTS[slotID] then
        if opts == nil or opts.countRings ~= true then return false end
        return opts.anyRing == true or self:IsEnchanter()
    end
    if slotID ~= MAIN_HAND and slotID ~= OFF_HAND then return false end
    local _, _, _, equipLoc, _, classID, subClassID = Call(Fn("C_Item", "GetItemInfoInstant"), link)
    if type(equipLoc) ~= "string" then return false end
    if slotID == MAIN_HAND then
        return MAIN_HAND_LOCS[equipLoc] == true and not (classID == WEAPON_CLASS and subClassID == FISHING_POLE)
    end
    return OFF_HAND_LOCS[equipLoc] == true
end

--- Estado do item equipado da unidade (padrão "player"): nil (slot vazio /
--- não aceita encantamento), "missing", ou "enchanted", nome (nome pode ser nil).
function EnchantInfo:Status(slotID, opts, unit)
    unit = unit or "player"
    local link = Call(Fn(nil, "GetInventoryItemLink"), unit, slotID)
    if type(link) ~= "string" then return nil end
    local id = self:Id(link)
    if id == nil then return nil end
    if id ~= 0 then return "enchanted", self:Name(slotID, link, unit) end
    if self:Enchantable(slotID, link, opts) then return "missing" end
    return nil
end
