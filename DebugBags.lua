-- ============================================================
--  DebugBags.lua
--  /wu debug bags
--  Diagnóstico para o futuro módulo de item level nas bolsas: como a
--  interface de bolsas deste cliente é montada (frames, botões de item,
--  funções que a Blizzard usa para redesenhar), quais APIs existem e
--  o item level de alguns equipamentos reais. Só lê; não altera nada.
--  Report monta as linhas (testável sem o jogo); o comando abre a
--  janela de texto copiável.
-- ============================================================

local _, ns = ...

local Bags = {}
ns.DebugBags = Bags

local Show = ns.Debug.Show

local MAX_FRAMES = 6        -- ContainerFrame1..N inspecionados
local MAX_BUTTONS = 4       -- botões de exemplo por frame
local MAX_FIELDS = 24       -- campos listados por frame
local MAX_SAMPLES = 12      -- equipamentos de exemplo
local COMBINED = "ContainerFrameCombinedBags"

local API_CHECKS = {
    { "C_Container.GetContainerNumSlots",    { "C_Container", "GetContainerNumSlots" } },
    { "C_Container.GetContainerItemInfo",    { "C_Container", "GetContainerItemInfo" } },
    { "C_Container.GetContainerItemLink",    { "C_Container", "GetContainerItemLink" } },
    { "C_Item.GetItemInfoInstant",           { "C_Item", "GetItemInfoInstant" } },
    { "C_Item.GetItemInfo",                  { "C_Item", "GetItemInfo" } },
    { "C_Item.GetDetailedItemLevelInfo",     { "C_Item", "GetDetailedItemLevelInfo" } },
    { "GetDetailedItemLevelInfo (legacy)",   { "GetDetailedItemLevelInfo" } },
    { "GetItemInfoInstant (legacy)",         { "GetItemInfoInstant" } },
    { "GetContainerItemLink (legacy)",       { "GetContainerItemLink" } },
    -- funções globais que a Blizzard usa para redesenhar bolsas (candidatas a gancho)
    { "ContainerFrame_Update",               { "ContainerFrame_Update" } },
    { "ContainerFrame_UpdateAll",            { "ContainerFrame_UpdateAll" } },
    { "ContainerFrame_UpdateItemLevel",      { "ContainerFrame_UpdateItemLevel" } },
    { "ContainerFrame_GenerateFrame",        { "ContainerFrame_GenerateFrame" } },
    { "ContainerFrameItemButton_UpdateItemUpgradeIcon", { "ContainerFrameItemButton_UpdateItemUpgradeIcon" } },
    { "OpenAllBags",                         { "OpenAllBags" } },
    { "ToggleAllBags",                       { "ToggleAllBags" } },
    { "BankFrame_ShowPanel",                 { "BankFrame_ShowPanel" } },
}

-- Mixins/templates (existência e métodos)
local MIXINS = {
    { "ContainerFrameMixin",                 { "Update", "UpdateItems", "UpdateName", "GetBagID", "EnumerateValidItems", "Init" } },
    { "ContainerFrameCombinedBagsMixin",     { "Update", "UpdateItems", "EnumerateValidItems" } },
    { "ContainerFrameItemButtonMixin",       { "GetBagID", "GetSlotAndBagID", "UpdateItemContextMatching", "SetItemButtonQuality" } },
    { "ItemButtonMixin",                     { "SetItem", "GetItemInfo" } },
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

--- Chama um método do frame de forma segura; nil se não existir.
local function Method(obj, name, ...)
    if type(obj) ~= "table" then return end
    local fn = obj[name]
    if type(fn) ~= "function" then return end
    return ns.SafeCall(fn, obj, ...)
end

local function Environment(add)
    local version, build, _, toc = ns.SafeCall(GetBuildInfo)
    add(string.format("Game version: %s (build %s, interface %s)",
        Show(version), Show(build), Show(toc)))
    add("NUM_BAG_SLOTS = " .. Show(rawget(_G, "NUM_BAG_SLOTS"))
        .. " | NUM_BANKBAGSLOTS = " .. Show(rawget(_G, "NUM_BANKBAGSLOTS")))
    for _, name in ipairs({ "ElvUI", "Bagnon", "Baganator", "AdiBags", "ArkInventory", "BetterBags", "LiteBag" }) do
        if rawget(_G, name) ~= nil then add("  third-party bag/UI addon detected: " .. name) end
    end
end

local function ApiPresence(add)
    add("")
    add("== API presence ==")
    for _, check in ipairs(API_CHECKS) do
        add(string.format("  %-52s %s", check[1], type(Resolve(check[2])) == "function" and "yes" or "MISSING"))
    end
    add("")
    add("== Mixins ==")
    for _, mixin in ipairs(MIXINS) do
        local t = Resolve({ mixin[1] })
        if type(t) ~= "table" then
            add(string.format("  %-34s MISSING", mixin[1]))
        else
            local have = {}
            for _, method in ipairs(mixin[2]) do
                if type(t[method]) == "function" then have[#have + 1] = method end
            end
            add(string.format("  %-34s yes | methods: %s", mixin[1], #have > 0 and table.concat(have, ", ") or "(none of the expected)"))
        end
    end
end

--- Campos interessantes de um frame: tabelas e funções de nome relevante.
local function Fields(frame)
    local tables, funcs = {}, {}
    local ok = pcall(function()
        for key, value in pairs(frame) do
            if type(key) == "string" then
                if type(value) == "table" then tables[#tables + 1] = key
                elseif type(value) == "function" and key:find("Update") or (type(value) == "function" and key:find("Item")) then
                    funcs[#funcs + 1] = key
                end
            end
        end
    end)
    table.sort(tables); table.sort(funcs)
    if not ok then return { "(could not read fields)" }, {} end
    return tables, funcs
end

local function Limited(list)
    local out = {}
    for i = 1, math.min(#list, MAX_FIELDS) do out[i] = list[i] end
    local text = #out > 0 and table.concat(out, ", ") or "(none)"
    if #list > MAX_FIELDS then text = text .. ", ... +" .. (#list - MAX_FIELDS) end
    return text
end

local function DescribeButton(add, button, label)
    if type(button) ~= "table" then add("    " .. label .. ": " .. Show(button)); return end
    local bagID = Method(button, "GetBagID")
    local slotID = Method(button, "GetID")
    local parent = Method(button, "GetParent")
    local parentName = type(parent) == "table" and Method(parent, "GetName")
    add(string.format("    %s: name %s | GetBagID %s | GetID %s | parent %s | shown %s",
        label, Show(Method(button, "GetName")), Show(bagID), Show(slotID), Show(parentName),
        Show(Method(button, "IsShown"))))
    add(string.format("        icon %s | Count %s | ItemLevel %s | IconBorder %s | JunkIcon %s",
        Show(type(button.icon) == "table" or type(button.Icon) == "table"),
        Show(type(button.Count) == "table" or type(button.count) == "table"),
        Show(type(button.ItemLevel) == "table" or type(button.itemLevel) == "table"),
        Show(type(button.IconBorder) == "table"), Show(type(button.JunkIcon) == "table")))
end

--- Primeiros botões de um frame: tenta Items, EnumerateValidItems e nomes clássicos.
local function SampleButtons(add, frame, frameName)
    local shown = 0
    if type(frame.Items) == "table" then
        add("    frame.Items: " .. #frame.Items .. " entries")
        for i = 1, #frame.Items do
            if shown >= MAX_BUTTONS then break end
            shown = shown + 1
            DescribeButton(add, frame.Items[i], "Items[" .. i .. "]")
        end
    end
    if shown < MAX_BUTTONS and type(frame.EnumerateValidItems) == "function" then
        local ok, iter, state, init = pcall(frame.EnumerateValidItems, frame)
        if ok and type(iter) == "function" then
            local count = 0
            for _, button in iter, state, init do
                count = count + 1
                if shown < MAX_BUTTONS then
                    shown = shown + 1
                    DescribeButton(add, button, "EnumerateValidItems#" .. count)
                end
                if count >= 200 then break end
            end
            add("    EnumerateValidItems yielded " .. count .. " button(s)")
        else
            add("    EnumerateValidItems: call failed")
        end
    end
    if shown == 0 then
        for i = 1, MAX_BUTTONS do
            local button = rawget(_G, frameName .. "Item" .. i)
            if button then DescribeButton(add, button, frameName .. "Item" .. i) end
        end
    end
end

local function DescribeFrame(add, name)
    local frame = rawget(_G, name)
    if type(frame) ~= "table" then
        add(string.format("  %s: absent", name))
        return
    end
    add(string.format("  %s: IsShown %s | IsVisible %s | GetID %s | GetBagID %s | size %s | objectType %s",
        name, Show(Method(frame, "IsShown")), Show(Method(frame, "IsVisible")),
        Show(Method(frame, "GetID")), Show(Method(frame, "GetBagID")),
        Show(frame.size), Show(Method(frame, "GetObjectType"))))
    local tables, funcs = Fields(frame)
    add("    table fields: " .. Limited(tables))
    add("    Update/Item functions: " .. Limited(funcs))
    SampleButtons(add, frame, name)
end

local function Frames(add)
    add("")
    add("== Bag frames ==")
    DescribeFrame(add, COMBINED)
    local container = rawget(_G, "ContainerFrameContainer")
    add("  ContainerFrameContainer: " .. (type(container) == "table" and "present" or "absent")
        .. (type(container) == "table" and type(container.ContainerFrames) == "table"
            and (" | ContainerFrames: " .. #container.ContainerFrames) or ""))
    for i = 1, MAX_FRAMES do DescribeFrame(add, "ContainerFrame" .. i) end
    DescribeFrame(add, "BankFrame")
    DescribeFrame(add, "BankSlotsFrame")
    local backpackSetting = Call(Resolve({ "GetCVar" }), "combinedBags")
    add("  CVar combinedBags = " .. Show(backpackSetting))
end

local function Slots(add)
    add("")
    add("== Bag slots and item level samples ==")
    local numFn = First(Resolve({ "C_Container", "GetContainerNumSlots" }), Resolve({ "GetContainerNumSlots" }))
    local linkFn = First(Resolve({ "C_Container", "GetContainerItemLink" }), Resolve({ "GetContainerItemLink" }))
    local instant = First(Resolve({ "C_Item", "GetItemInfoInstant" }), Resolve({ "GetItemInfoInstant" }))
    local levelFn = First(Resolve({ "C_Item", "GetDetailedItemLevelInfo" }), Resolve({ "GetDetailedItemLevelInfo" }))
    local infoFn = First(Resolve({ "C_Item", "GetItemInfo" }), Resolve({ "GetItemInfo" }))
    local last = rawget(_G, "NUM_BAG_SLOTS")
    last = type(last) == "number" and last or 4
    local sizes, samples, equippable, total = {}, {}, 0, 0
    for bag = 0, last do
        local size = Call(numFn, bag)
        size = type(size) == "number" and size or 0
        sizes[#sizes + 1] = string.format("bag %d: %d", bag, size)
        for slot = 1, size do
            local link = Call(linkFn, bag, slot)
            if type(link) == "string" then
                total = total + 1
                local _, _, _, equipLoc = Call(instant, link)
                if type(equipLoc) == "string" and equipLoc ~= "" then
                    equippable = equippable + 1
                    if #samples < MAX_SAMPLES then
                        local name, _, quality = Call(infoFn, link)
                        samples[#samples + 1] = string.format(
                            "  bag %d slot %d: %s | %s | quality %s | ilvl %s",
                            bag, slot, Show(name), equipLoc, Show(quality), Show((Call(levelFn, link))))
                    end
                end
            end
        end
    end
    add("Slots per bag: " .. table.concat(sizes, ", "))
    add(string.format("Items: %d | with an equip location: %d", total, equippable))
    for _, line in ipairs(samples) do add(line) end
    if equippable > #samples then add("  ... " .. (equippable - #samples) .. " more not listed") end
end

--- Monta o relatório como lista de linhas.
function Bags:Report()
    local lines = {}
    local function add(text) lines[#lines + 1] = text end
    add("WowUtilities bag debug (read-only; nothing is changed)")
    Environment(add)
    ApiPresence(add)
    Frames(add)
    Slots(add)
    return lines
end

ns.Debug:Register("bags", function()
    local ok, lines = pcall(Bags.Report, Bags)
    if not ok then lines = { "WowUtilities bag debug failed: " .. tostring(lines) } end
    ns.Debug:Output("WowUtilities debug — bags", lines)
end)
