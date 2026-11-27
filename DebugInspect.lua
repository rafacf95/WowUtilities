-- ============================================================
--  DebugInspect.lua
--  /wu debug inspect [unit]
--  Diagnóstico para o futuro item level e indicador de encantamentos na
--  janela de inspeção: se a Blizzard_InspectUI carregou, quais botões de
--  slot existem (nomes, GetID), quais funções de redesenho existem
--  (candidatas a gancho), qual unidade a janela guarda, se o evento
--  INSPECT_READY chegou e, para cada slot da unidade inspecionada, o
--  link, o ID de encantamento, a linha "Enchanted: ..." da tooltip (API
--  moderna e tooltip de leitura) e o item level. Só lê; não altera nada
--  (o único efeito é ouvir INSPECT_READY para contar quando chegou).
--  Report monta as linhas (testável sem o jogo); o comando abre a
--  janela de texto copiável.
-- ============================================================

local _, ns = ...

local Inspect = {}
ns.DebugInspect = Inspect

local Show = ns.Debug.Show

local SCAN_NAME = "WowUtilitiesInspectScan"
local MAX_LINES = 40
local MAX_FIELDS = 30
local INSPECT_ADDON = "Blizzard_InspectUI"

-- { slotID, rótulo, sufixo do botão (Inspect<sufixo>) }
local SLOTS = {
    { 1, "Head", "HeadSlot" }, { 2, "Neck", "NeckSlot" }, { 3, "Shoulder", "ShoulderSlot" },
    { 4, "Shirt", "ShirtSlot" }, { 5, "Chest", "ChestSlot" }, { 6, "Waist", "WaistSlot" },
    { 7, "Legs", "LegsSlot" }, { 8, "Feet", "FeetSlot" }, { 9, "Wrist", "WristSlot" },
    { 10, "Hands", "HandsSlot" }, { 11, "Finger 1", "Finger0Slot" }, { 12, "Finger 2", "Finger1Slot" },
    { 13, "Trinket 1", "Trinket0Slot" }, { 14, "Trinket 2", "Trinket1Slot" }, { 15, "Back", "BackSlot" },
    { 16, "Main hand", "MainHandSlot" }, { 17, "Off hand", "SecondaryHandSlot" },
    { 18, "Ranged/relic", "RangedSlot" }, { 19, "Tabard", "TabardSlot" },
}

local API_CHECKS = {
    { "NotifyInspect",                          { "NotifyInspect" } },
    { "CanInspect",                             { "CanInspect" } },
    { "ClearInspectPlayer",                     { "ClearInspectPlayer" } },
    { "InspectUnit",                            { "InspectUnit" } },
    { "CheckInteractDistance",                  { "CheckInteractDistance" } },
    { "GetInventoryItemLink",                   { "GetInventoryItemLink" } },
    { "GetInventoryItemID",                     { "GetInventoryItemID" } },
    { "GetInventoryItemQuality",                { "GetInventoryItemQuality" } },
    { "C_TooltipInfo.GetInventoryItem",         { "C_TooltipInfo", "GetInventoryItem" } },
    { "C_Item.GetItemInfoInstant",              { "C_Item", "GetItemInfoInstant" } },
    { "C_Item.GetItemInfo",                     { "C_Item", "GetItemInfo" } },
    { "C_Item.GetDetailedItemLevelInfo",        { "C_Item", "GetDetailedItemLevelInfo" } },
    { "C_PaperDollInfo.GetInspectItemLevel",    { "C_PaperDollInfo", "GetInspectItemLevel" } },
    { "GetInspectSpecialization",               { "GetInspectSpecialization" } },
    { "C_AddOns.IsAddOnLoaded",                 { "C_AddOns", "IsAddOnLoaded" } },
    { "C_AddOns.LoadAddOn",                     { "C_AddOns", "LoadAddOn" } },
    -- funções globais da janela de inspeção (candidatas a gancho)
    { "InspectFrame_LoadUI",                    { "InspectFrame_LoadUI" } },
    { "InspectFrame_Show",                      { "InspectFrame_Show" } },
    { "InspectFrame_UnitChanged",               { "InspectFrame_UnitChanged" } },
    { "InspectFrame_OnEvent",                   { "InspectFrame_OnEvent" } },
    { "InspectPaperDollFrame_OnShow",           { "InspectPaperDollFrame_OnShow" } },
    { "InspectPaperDollFrame_OnEvent",          { "InspectPaperDollFrame_OnEvent" } },
    { "InspectPaperDollFrame_UpdateButtons",    { "InspectPaperDollFrame_UpdateButtons" } },
    { "InspectPaperDollFrame_SetLevel",         { "InspectPaperDollFrame_SetLevel" } },
    { "InspectPaperDollItemSlotButton_Update",  { "InspectPaperDollItemSlotButton_Update" } },
    { "InspectPaperDollItemSlotButton_OnLoad",  { "InspectPaperDollItemSlotButton_OnLoad" } },
    { "InspectPaperDollItemSlotButton_OnEvent", { "InspectPaperDollItemSlotButton_OnEvent" } },
}

local WINDOWS = {
    "InspectFrame", "InspectPaperDollFrame", "InspectPaperDollItemsFrame", "InspectModelFrame",
    "InspectModelScene", "InspectLevelText", "InspectPVPFrame", "InspectTalentFrame", "InspectGuildFrame",
    "InspectFrameTab1", "InspectFrameTab2", "InspectFrameTab3",
}

-- Quantas vezes INSPECT_READY chegou desde o carregamento (só para o relatório).
local ready = { count = 0 }

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

local function Now()
    local fn = rawget(_G, "GetTime")
    return type(fn) == "function" and fn() or 0
end

do
    local listener = CreateFrame("Frame")
    if pcall(listener.RegisterEvent, listener, "INSPECT_READY") then
        ready.valid = true
        listener:SetScript("OnEvent", function(_, _, guid)
            ready.count = ready.count + 1
            ready.guid = guid
            ready.time = Now()
        end)
    end
end

local function Limited(list)
    local out = {}
    for i = 1, math.min(#list, MAX_FIELDS) do out[i] = list[i] end
    local text = #out > 0 and table.concat(out, ", ") or "(none)"
    if #list > MAX_FIELDS then text = text .. ", ... +" .. (#list - MAX_FIELDS) end
    return text
end

--- Campos de um frame: tabelas, funções e valores simples (para achar o campo da unidade).
local function Fields(frame)
    local tables, funcs, values = {}, {}, {}
    local ok = pcall(function()
        for key, value in pairs(frame) do
            if type(key) == "string" then
                local kind = type(value)
                if kind == "table" then
                    tables[#tables + 1] = key
                elseif kind == "function" then
                    funcs[#funcs + 1] = key
                elseif kind == "string" or kind == "number" or kind == "boolean" then
                    values[#values + 1] = key .. "=" .. Show(value)
                end
            end
        end
    end)
    if not ok then return { "(could not read fields)" }, {}, {} end
    table.sort(tables); table.sort(funcs); table.sort(values)
    return tables, funcs, values
end

local function EnchantPattern()
    local phrase = rawget(_G, "ENCHANTED_TOOLTIP_LINE")
    if type(phrase) ~= "string" or not phrase:find("%%s") then return nil, phrase end
    local escaped = phrase:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    escaped = escaped:gsub("%%s", "(.+)")
    return "^" .. escaped .. "$", phrase
end

local function LinkParts(link)
    if type(link) ~= "string" then return nil end
    local itemID, enchant = link:match("item:(%-?%d+):(%-?%d*)")
    local name = link:match("|h%[(.-)%]|h")
    return tonumber(itemID), itemID and (tonumber(enchant) or 0) or nil, name
end

local function ModernLines(unit, slotID)
    local fn = Resolve({ "C_TooltipInfo", "GetInventoryItem" })
    if not fn then return nil, "API missing" end
    local data = Call(fn, unit, slotID)
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
local function ScanLines(unit, slotID)
    if not scanner then
        local ok, frame = pcall(CreateFrame, "GameTooltip", SCAN_NAME, nil, "GameTooltipTemplate")
        if not ok or type(frame) ~= "table" then return nil, "could not create the scan tooltip" end
        scanner = frame
    end
    local ok, err = pcall(function()
        scanner:SetOwner(UIParent, "ANCHOR_NONE")
        scanner:ClearLines()
        scanner:SetInventoryItem(unit, slotID)
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

--- Unidade a inspecionar: a pedida, senão a que a janela guarda, senão "target".
local function PickUnit(arg)
    if type(arg) == "string" and arg ~= "" then return arg, "argument" end
    local frame = rawget(_G, "InspectFrame")
    local unit = type(frame) == "table" and rawget(frame, "unit") or nil
    if type(unit) == "string" and unit ~= "" then return unit, "InspectFrame.unit" end
    return "target", "default"
end

local function Environment(add)
    local version, build, _, toc = ns.SafeCall(GetBuildInfo)
    add(string.format("Game version: %s (build %s, interface %s)", Show(version), Show(build), Show(toc)))
    local _, phrase = EnchantPattern()
    add("ENCHANTED_TOOLTIP_LINE = " .. Show(phrase))
    for _, name in ipairs({ "ElvUI", "Inspectionator", "Examiner", "TinyInspect", "iLvLrReborn" }) do
        if rawget(_G, name) ~= nil then add("  third-party addon detected: " .. name) end
    end
end

local function AddonState(add)
    add("")
    add("== " .. INSPECT_ADDON .. " ==")
    local loaded = Call(First(Resolve({ "C_AddOns", "IsAddOnLoaded" }), Resolve({ "IsAddOnLoaded" })), INSPECT_ADDON)
    add("  IsAddOnLoaded: " .. Show(loaded))
    local name, _, _, loadable, reason = Call(First(Resolve({ "C_AddOns", "GetAddOnInfo" }), Resolve({ "GetAddOnInfo" })), INSPECT_ADDON)
    add(string.format("  GetAddOnInfo: name %s | loadable %s | reason %s", Show(name), Show(loadable), Show(reason)))
    local lod = Call(First(Resolve({ "C_AddOns", "IsAddOnLoadOnDemand" }), Resolve({ "IsAddOnLoadOnDemand" })), INSPECT_ADDON)
    add("  IsAddOnLoadOnDemand: " .. Show(lod))
    if ready.valid then
        local ago = ready.time and string.format("%.1fs ago", Now() - ready.time) or "never"
        add(string.format("  INSPECT_READY: valid | received %d time(s) | last guid %s | %s",
            ready.count, Show(ready.guid), ago))
    else
        add("  INSPECT_READY: could not register (event may not exist)")
    end
end

local function ApiPresence(add)
    add("")
    add("== API presence ==")
    for _, check in ipairs(API_CHECKS) do
        add(string.format("  %-42s %s", check[1], type(Resolve(check[2])) == "function" and "yes" or "MISSING"))
    end
    for _, name in ipairs({ "InspectPaperDollItemSlotButtonMixin", "InspectFrameMixin", "PaperDollItemSlotButtonMixin" }) do
        add(string.format("  %-42s %s", name, type(rawget(_G, name)) == "table" and "yes" or "MISSING"))
    end
end

local function Windows(add)
    add("")
    add("== Windows ==")
    for _, name in ipairs(WINDOWS) do
        local frame = rawget(_G, name)
        if type(frame) ~= "table" then
            add(string.format("  %-28s absent", name))
        else
            add(string.format("  %-28s IsShown %s | IsVisible %s | objectType %s",
                name, Show(Method(frame, "IsShown")), Show(Method(frame, "IsVisible")), Show(Method(frame, "GetObjectType"))))
        end
    end
    local frame = rawget(_G, "InspectFrame")
    if type(frame) == "table" then
        local tables, funcs, values = Fields(frame)
        add("InspectFrame values: " .. Limited(values))
        add("InspectFrame table fields: " .. Limited(tables))
        add("InspectFrame functions: " .. Limited(funcs))
    end
end

local function UnitInfo(add, unit, source)
    add("")
    add(string.format("== Unit: %s (from %s) ==", unit, source))
    add("  UnitExists " .. Show((Call(Resolve({ "UnitExists" }), unit))) ..
        " | UnitIsPlayer " .. Show((Call(Resolve({ "UnitIsPlayer" }), unit))) ..
        " | UnitIsUnit(player) " .. Show((Call(Resolve({ "UnitIsUnit" }), unit, "player"))))
    add("  UnitName " .. Show((Call(Resolve({ "UnitName" }), unit))) ..
        " | UnitGUID " .. Show((Call(Resolve({ "UnitGUID" }), unit))))
    local classLocal, classToken = Call(Resolve({ "UnitClass" }), unit)
    add(string.format("  UnitClass %s (%s) | UnitLevel %s", Show(classLocal), Show(classToken),
        Show((Call(Resolve({ "UnitLevel" }), unit)))))
    add("  CanInspect " .. Show((Call(Resolve({ "CanInspect" }), unit))) ..
        " | CheckInteractDistance(1) " .. Show((Call(Resolve({ "CheckInteractDistance" }), unit, 1))))
    local avg = Call(Resolve({ "C_PaperDollInfo", "GetInspectItemLevel" }), unit)
    add("  C_PaperDollInfo.GetInspectItemLevel " .. Show(avg))
end

local function SlotButton(slot)
    return rawget(_G, "Inspect" .. slot[3])
end

local function Buttons(add)
    add("")
    add("== Inspect slot buttons ==")
    local found, first = 0, nil
    for _, slot in ipairs(SLOTS) do
        local name = "Inspect" .. slot[3]
        local button = SlotButton(slot)
        if type(button) ~= "table" then
            add(string.format("  %-28s absent", name))
        else
            found = found + 1
            first = first or button
            local point, relative, relPoint, x, y = Method(button, "GetPoint", 1)
            local relName = type(relative) == "table" and Method(relative, "GetName") or relative
            add(string.format("  %-28s GetID %s (expected %d) | visible %s | size %sx%s | point %s %s %s %s,%s",
                name, Show(Method(button, "GetID")), slot[1], Show(Method(button, "IsVisible")),
                Show(Method(button, "GetWidth")), Show(Method(button, "GetHeight")),
                Show(point), Show(relName), Show(relPoint), Show(x), Show(y)))
        end
    end
    add(string.format("Slot buttons found: %d of %d", found, #SLOTS))
    if first then
        local tables, funcs, values = Fields(first)
        add("First button values: " .. Limited(values))
        add("First button table fields: " .. Limited(tables))
        add("First button functions: " .. Limited(funcs))
    end
end

local function Items(add, unit)
    add("")
    add("== Items of " .. unit .. " ==")
    local pattern = EnchantPattern()
    local getLink = Resolve({ "GetInventoryItemLink" })
    local getInfo = First(Resolve({ "C_Item", "GetItemInfo" }), Resolve({ "GetItemInfo" }))
    local getInstant = First(Resolve({ "C_Item", "GetItemInfoInstant" }), Resolve({ "GetItemInfoInstant" }))
    local getLevel = First(Resolve({ "C_Item", "GetDetailedItemLevelInfo" }), Resolve({ "GetDetailedItemLevelInfo" }))
    local equipped, named, enchanted = 0, 0, 0
    for _, slot in ipairs(SLOTS) do
        local slotID, label = slot[1], slot[2]
        local link = Call(getLink, unit, slotID)
        local id = Call(Resolve({ "GetInventoryItemID" }), unit, slotID)
        if type(link) ~= "string" then
            add(string.format("  %2d %-13s no link | GetInventoryItemID %s", slotID, label, Show(id)))
        else
            equipped = equipped + 1
            local itemID, enchantID, linkName = LinkParts(link)
            if linkName and linkName ~= "" then named = named + 1 end
            if enchantID and enchantID ~= 0 then enchanted = enchanted + 1 end
            local _, _, _, equipLoc = Call(getInstant, link)
            local infoName, _, quality = Call(getInfo, link)
            local level = Call(getLevel, link)
            local modern, modernWhy = ModernLines(unit, slotID)
            local scanned, scanWhy = ScanLines(unit, slotID)
            add(string.format("  %2d %-13s item %s (GetInventoryItemID %s) | name in link %s | GetItemInfo %s | %s | quality %s | ilvl %s",
                slotID, label, Show(itemID), Show(id), Show(linkName), Show(infoName), Show(equipLoc), Show(quality), Show(level)))
            add(string.format("      enchantID %s | modern: %s | scan: %s",
                Show(enchantID),
                modern and string.format("%d lines, enchant %s", #modern, Show(FindEnchant(modern, pattern))) or tostring(modernWhy),
                scanned and string.format("%d lines, enchant %s", #scanned, Show(FindEnchant(scanned, pattern))) or tostring(scanWhy)))
        end
    end
    add(string.format("Slots with link: %d | with name in link: %d | with enchantID: %d", equipped, named, enchanted))
end

--- Monta o relatório como lista de linhas.
function Inspect:Report(arg)
    local lines = {}
    local function add(text) lines[#lines + 1] = text end
    local unit, source = PickUnit(arg)
    add("WowUtilities inspect debug (read-only; nothing is changed)")
    add("Run it with the Inspect window open on another player (twice: right away and after a few seconds).")
    Environment(add)
    AddonState(add)
    ApiPresence(add)
    Windows(add)
    UnitInfo(add, unit, source)
    Buttons(add)
    Items(add, unit)
    return lines
end

ns.Debug:Register("inspect", function(arg)
    local ok, lines = pcall(Inspect.Report, Inspect, arg)
    if not ok then lines = { "WowUtilities inspect debug failed: " .. tostring(lines) } end
    ns.Debug:Output("WowUtilities debug — inspect", lines)
end)
