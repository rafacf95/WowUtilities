-- ============================================================
--  DebugCharacter.lua
--  /wu debug character
--  Diagnóstico para o futuro módulo de item level na janela de
--  personagem: quais botões de equipamento existem, seus números de
--  slot, funções de redesenho disponíveis e o nível lido de cada item
--  equipado. Só lê; não altera nada. Report monta as linhas (testável
--  sem o jogo); o comando abre a janela de texto copiável.
-- ============================================================

local _, ns = ...

local Character = {}
ns.DebugCharacter = Character

local Show = ns.Debug.Show

local MAX_FIELDS = 24

-- { nome do botão, nome do slot para GetInventorySlotInfo }
local SLOT_BUTTONS = {
    { "CharacterHeadSlot", "HeadSlot" }, { "CharacterNeckSlot", "NeckSlot" },
    { "CharacterShoulderSlot", "ShoulderSlot" }, { "CharacterBackSlot", "BackSlot" },
    { "CharacterChestSlot", "ChestSlot" }, { "CharacterShirtSlot", "ShirtSlot" },
    { "CharacterTabardSlot", "TabardSlot" }, { "CharacterWristSlot", "WristSlot" },
    { "CharacterHandsSlot", "HandsSlot" }, { "CharacterWaistSlot", "WaistSlot" },
    { "CharacterLegsSlot", "LegsSlot" }, { "CharacterFeetSlot", "FeetSlot" },
    { "CharacterFinger0Slot", "Finger0Slot" }, { "CharacterFinger1Slot", "Finger1Slot" },
    { "CharacterTrinket0Slot", "Trinket0Slot" }, { "CharacterTrinket1Slot", "Trinket1Slot" },
    { "CharacterMainHandSlot", "MainHandSlot" }, { "CharacterSecondaryHandSlot", "SecondaryHandSlot" },
    { "CharacterRangedSlot", "RangedSlot" }, { "CharacterAmmoSlot", "AmmoSlot" },
}

local API_CHECKS = {
    { "GetInventoryItemLink",             { "GetInventoryItemLink" } },
    { "GetInventoryItemID",               { "GetInventoryItemID" } },
    { "GetInventoryItemQuality",          { "GetInventoryItemQuality" } },
    { "GetInventorySlotInfo",             { "GetInventorySlotInfo" } },
    { "GetAverageItemLevel",              { "GetAverageItemLevel" } },
    { "C_Item.GetItemInfoInstant",        { "C_Item", "GetItemInfoInstant" } },
    { "C_Item.GetItemInfo",               { "C_Item", "GetItemInfo" } },
    { "C_Item.GetDetailedItemLevelInfo",  { "C_Item", "GetDetailedItemLevelInfo" } },
    -- funções globais que a Blizzard usa para redesenhar os slots (candidatas a gancho)
    { "PaperDollItemSlotButton_Update",   { "PaperDollItemSlotButton_Update" } },
    { "PaperDollFrame_UpdateStats",       { "PaperDollFrame_UpdateStats" } },
    { "PaperDollFrame_SetItemLevel",      { "PaperDollFrame_SetItemLevel" } },
    { "CharacterFrame_ShowSubFrame",      { "CharacterFrame_ShowSubFrame" } },
    { "ToggleCharacter",                  { "ToggleCharacter" } },
}

local function Resolve(path)
    local value = _G
    for _, key in ipairs(path) do
        if type(value) ~= "table" then return nil end
        value = rawget(value, key)
    end
    return value
end

local function First(...)
    for i = 1, select("#", ...) do
        local fn = select(i, ...)
        if type(fn) == "function" then return fn end
    end
end

local function Call(fn, ...)
    if not fn then return end
    return ns.SafeCall(fn, ...)
end

local function Method(obj, name, ...)
    if type(obj) ~= "table" then return end
    local fn = obj[name]
    if type(fn) ~= "function" then return end
    return ns.SafeCall(fn, obj, ...)
end

local function Limited(list)
    local out = {}
    for i = 1, math.min(#list, MAX_FIELDS) do out[i] = list[i] end
    local text = #out > 0 and table.concat(out, ", ") or "(none)"
    if #list > MAX_FIELDS then text = text .. ", ... +" .. (#list - MAX_FIELDS) end
    return text
end

--- Campos de um frame: tabelas e funções com "Update"/"Item" no nome.
local function Fields(frame)
    local tables, funcs = {}, {}
    local ok = pcall(function()
        for key, value in pairs(frame) do
            if type(key) == "string" then
                if type(value) == "table" then
                    tables[#tables + 1] = key
                elseif type(value) == "function" and (key:find("Update") or key:find("Item")) then
                    funcs[#funcs + 1] = key
                end
            end
        end
    end)
    table.sort(tables); table.sort(funcs)
    if not ok then return { "(could not read fields)" }, {} end
    return tables, funcs
end

local function Environment(add)
    local version, build, _, toc = ns.SafeCall(GetBuildInfo)
    add(string.format("Game version: %s (build %s, interface %s)",
        Show(version), Show(build), Show(toc)))
    for _, name in ipairs({ "ElvUI", "Bagnon", "Cork", "DejaCharacterStats", "CharacterStatsClassic", "Inspectionator" }) do
        if rawget(_G, name) ~= nil then add("  third-party UI addon detected: " .. name) end
    end
end

local function ApiPresence(add)
    add("")
    add("== API presence ==")
    for _, check in ipairs(API_CHECKS) do
        add(string.format("  %-38s %s", check[1], type(Resolve(check[2])) == "function" and "yes" or "MISSING"))
    end
    local mixin = Resolve({ "PaperDollItemSlotButtonMixin" })
    add("  PaperDollItemSlotButtonMixin           " .. (type(mixin) == "table" and "yes" or "MISSING"))
    local average, equipped = Call(Resolve({ "GetAverageItemLevel" }))
    add(string.format("  GetAverageItemLevel() -> overall %s | equipped %s", Show(average), Show(equipped)))
end

local function Windows(add)
    add("")
    add("== Windows ==")
    for _, name in ipairs({ "CharacterFrame", "PaperDollFrame", "PaperDollItemsFrame", "CharacterModelFrame", "CharacterModelScene", "InspectFrame" }) do
        local frame = rawget(_G, name)
        if type(frame) ~= "table" then
            add(string.format("  %-22s absent", name))
        else
            add(string.format("  %-22s IsShown %s | IsVisible %s | objectType %s",
                name, Show(Method(frame, "IsShown")), Show(Method(frame, "IsVisible")), Show(Method(frame, "GetObjectType"))))
        end
    end
end

local function SlotItem(slotID)
    local link = Call(Resolve({ "GetInventoryItemLink" }), "player", slotID)
    if type(link) ~= "string" then return nil end
    local _, _, _, equipLoc = Call(First(Resolve({ "C_Item", "GetItemInfoInstant" }), Resolve({ "GetItemInfoInstant" })), link)
    local name, _, quality = Call(First(Resolve({ "C_Item", "GetItemInfo" }), Resolve({ "GetItemInfo" })), link)
    local ilvl = Call(First(Resolve({ "C_Item", "GetDetailedItemLevelInfo" }), Resolve({ "GetDetailedItemLevelInfo" })), link)
    return { name = name, quality = quality, equipLoc = equipLoc, ilvl = ilvl }
end

local function Slots(add)
    add("")
    add("== Equipment slot buttons ==")
    local found, first = 0, nil
    for _, entry in ipairs(SLOT_BUTTONS) do
        local name, slotName = entry[1], entry[2]
        local button = rawget(_G, name)
        if type(button) ~= "table" then
            add(string.format("  %-28s absent", name))
        else
            found = found + 1
            first = first or button
            local id = Method(button, "GetID")
            local expected = Call(Resolve({ "GetInventorySlotInfo" }), slotName)
            local item = type(id) == "number" and SlotItem(id) or nil
            add(string.format("  %-28s GetID %s (GetInventorySlotInfo %s) | visible %s | size %sx%s",
                name, Show(id), Show(expected), Show(Method(button, "IsVisible")),
                Show(Method(button, "GetWidth")), Show(Method(button, "GetHeight"))))
            add(string.format("      icon %s | Count %s | IconBorder %s | ignoreTexture %s | cooldown %s | item: %s",
                Show(type(button.icon) == "table" or type(button.Icon) == "table"),
                Show(type(button.Count) == "table"), Show(type(button.IconBorder) == "table"),
                Show(type(button.ignoreTexture) == "table"), Show(type(button.cooldown) == "table" or type(button.Cooldown) == "table"),
                item and string.format("%s | %s | quality %s | ilvl %s", Show(item.name), Show(item.equipLoc), Show(item.quality), Show(item.ilvl)) or "empty"))
        end
    end
    add(string.format("Slot buttons found: %d of %d", found, #SLOT_BUTTONS))
    if first then
        local tables, funcs = Fields(first)
        add("First button table fields: " .. Limited(tables))
        add("First button Update/Item functions: " .. Limited(funcs))
    end
end

--- Monta o relatório como lista de linhas.
function Character:Report()
    local lines = {}
    local function add(text) lines[#lines + 1] = text end
    add("WowUtilities character debug (read-only; nothing is changed)")
    Environment(add)
    ApiPresence(add)
    Windows(add)
    Slots(add)
    return lines
end

ns.Debug:Register("character", function()
    local ok, lines = pcall(Character.Report, Character)
    if not ok then lines = { "WowUtilities character debug failed: " .. tostring(lines) } end
    ns.Debug:Output("WowUtilities debug — character", lines)
end)
