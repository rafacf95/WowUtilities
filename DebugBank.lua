-- ============================================================
--  DebugBank.lua
--  /wu debug bank   (rode com o banco aberto)
--  Diagnóstico para o item level no banco: como a janela do banco deste
--  cliente é montada (frames, botões de item, abas, funções de
--  atualização), quais IDs de bolsa o banco usa, quais APIs e eventos
--  existem (e quantas vezes cada evento chegou desde o carregamento) e
--  o item level de alguns equipamentos guardados. Só lê; não altera nada
--  (o único efeito é ouvir os eventos para contá-los). Report monta as
--  linhas (testável sem o jogo); o comando abre a janela de texto.
-- ============================================================

local _, ns = ...

local Bank = {}
ns.DebugBank = Bank

local Show = ns.Debug.Show

local MAX_BUTTONS = 4   -- botões de exemplo por frame
local MAX_FIELDS = 30   -- campos listados por frame
local MAX_SAMPLES = 12  -- equipamentos de exemplo
local MAX_GLOBALS = 60  -- funções globais com "Bank" no nome
local MAX_CHILDREN = 40 -- filhos listados por frame

local API_CHECKS = {
    { "C_Container.GetContainerNumSlots",   { "C_Container", "GetContainerNumSlots" } },
    { "C_Container.GetContainerItemLink",   { "C_Container", "GetContainerItemLink" } },
    { "C_Container.GetContainerItemInfo",   { "C_Container", "GetContainerItemInfo" } },
    { "C_Container.GetBagName",             { "C_Container", "GetBagName" } },
    { "GetNumBankSlots",                    { "GetNumBankSlots" } },
    { "IsReagentBankUnlocked",              { "IsReagentBankUnlocked" } },
    { "BankButtonIDToInvSlotID",            { "BankButtonIDToInvSlotID" } },
    { "ReagentBankButtonIDToInvSlotID",     { "ReagentBankButtonIDToInvSlotID" } },
    { "BankFrame_ShowPanel",                { "BankFrame_ShowPanel" } },
    { "BankFrameItemButton_Update",         { "BankFrameItemButton_Update" } },
    { "BankFrameItemButton_UpdateLocked",   { "BankFrameItemButton_UpdateLocked" } },
    { "BankFrame_UpdateCooldown",           { "BankFrame_UpdateCooldown" } },
    { "BankFrameBaseButton_OnLoad",         { "BankFrameBaseButton_OnLoad" } },
    { "UpdateBagSlotStatus",                { "UpdateBagSlotStatus" } },
    { "ContainerFrame_GenerateFrame",       { "ContainerFrame_GenerateFrame" } },
    { "ContainerFrame_Update",              { "ContainerFrame_Update" } },
    { "OpenAllBags",                        { "OpenAllBags" } },
    { "C_Item.GetDetailedItemLevelInfo",    { "C_Item", "GetDetailedItemLevelInfo" } },
}

local MIXINS = {
    { "BankFrameMixin",               { "OnLoad", "OnShow", "OnEvent", "UpdateTabs", "SetTab", "GetActiveBankType" } },
    { "BankPanelMixin",               { "OnShow", "OnEvent", "Refresh", "SelectTab", "GetSelectedTabID", "EnumerateValidItems",
                                        "GenerateItemSlotsForSelectedTab", "RefreshBankPanel", "GetActiveBankType" } },
    { "BankPanelItemButtonMixin",     { "Init", "Refresh", "GetBankTabID", "GetContainerSlotID", "GetBagID", "UpdateVisualsForItem" } },
    { "BankPanelTabMixin",            { "Init", "RefreshVisuals", "IsSelected" } },
    { "ContainerFrameMixin",          { "Update", "UpdateItems", "GetBagID", "EnumerateValidItems", "IsBankBag" } },
    { "ContainerFrameItemButtonMixin", { "GetBagID", "GetSlotAndBagID" } },
}

local FRAMES = {
    "BankFrame", "BankSlotsFrame", "BankPanel", "BankFrameBankPanel", "ReagentBankFrame",
    "AccountBankPanel", "BankFrameMoneyFrame", "BankItemSearchBox",
}

local EVENTS = {
    "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "PLAYERBANKBAGSLOTS_CHANGED",
    "PLAYERREAGENTBANKSLOTS_CHANGED", "REAGENTBANK_PURCHASED", "BANK_TABS_CHANGED",
    "BANK_TAB_SETTINGS_UPDATED", "BANK_BAG_SLOT_FLAGS_UPDATED", "BAG_UPDATE", "BAG_UPDATE_DELAYED",
    "BAG_CONTAINER_UPDATE", "INVENTORY_SEARCH_UPDATE", "ITEM_LOCK_CHANGED", "GET_ITEM_INFO_RECEIVED",
}

-- Contagem dos eventos desde o carregamento: [evento] = { valid, count, last }
local seen = {}

local function Resolve(path)
    local value = _G
    for _, key in ipairs(path) do
        if type(value) ~= "table" then return nil end
        value = rawget(value, key)
    end
    return value
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return end
    return ns.SafeCall(fn, ...)
end

local function Method(obj, name, ...)
    if type(obj) ~= "table" then return end
    local fn = obj[name]
    if type(fn) ~= "function" then return end
    return ns.SafeCall(fn, obj, ...)
end

local function Args(...)
    local parts = {}
    for i = 1, math.min(select("#", ...), 4) do parts[#parts + 1] = Show((select(i, ...))) end
    return table.concat(parts, ", ")
end

do
    local listener = CreateFrame("Frame")
    for _, event in ipairs(EVENTS) do
        seen[event] = { valid = pcall(listener.RegisterEvent, listener, event), count = 0 }
    end
    listener:SetScript("OnEvent", function(_, event, ...)
        local entry = seen[event]
        if not entry then return end
        entry.count = entry.count + 1
        entry.last = Args(...)
    end)
end

local function Sorted(t)
    local keys = {}
    pcall(function() for key in pairs(t) do keys[#keys + 1] = key end end)
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

local function Limited(list, max)
    max = max or MAX_FIELDS
    local out = {}
    for i = 1, math.min(#list, max) do out[i] = tostring(list[i]) end
    local text = #out > 0 and table.concat(out, ", ") or "(none)"
    if #list > max then text = text .. ", ... +" .. (#list - max) end
    return text
end

-- ----------------------------------------------------------------
-- Seções
-- ----------------------------------------------------------------

local function IsOpen()
    for _, name in ipairs({ "BankFrame", "BankPanel" }) do
        if Method(rawget(_G, name), "IsVisible") == true then return true end
    end
    return false
end

local function Environment(add)
    local version, build, _, toc = ns.SafeCall(GetBuildInfo)
    add(string.format("Game version: %s (build %s, interface %s)", Show(version), Show(build), Show(toc)))
    add("Bank window open: " .. (IsOpen() and "yes" or "NO (open the bank and run the command again)"))
    add(string.format("NUM_BAG_SLOTS = %s | NUM_BANKBAGSLOTS = %s | NUM_BANKGENERIC_SLOTS = %s",
        Show(rawget(_G, "NUM_BAG_SLOTS")), Show(rawget(_G, "NUM_BANKBAGSLOTS")), Show(rawget(_G, "NUM_BANKGENERIC_SLOTS"))))
    add(string.format("BANK_CONTAINER = %s | REAGENTBANK_CONTAINER = %s | GetNumBankSlots() %s | IsReagentBankUnlocked() %s",
        Show(rawget(_G, "BANK_CONTAINER")), Show(rawget(_G, "REAGENTBANK_CONTAINER")),
        Show((Call(rawget(_G, "GetNumBankSlots")))), Show((Call(rawget(_G, "IsReagentBankUnlocked"))))))
    for _, name in ipairs({ "ElvUI", "Bagnon", "Baganator", "AdiBags", "ArkInventory", "BetterBags", "LiteBag" }) do
        if rawget(_G, name) ~= nil then add("  third-party bag/UI addon detected: " .. name) end
    end

    for _, enumName in ipairs({ "BagIndex", "BankType" }) do
        local t = Resolve({ "Enum", enumName })
        if type(t) ~= "table" then
            add("Enum." .. enumName .. ": MISSING")
        else
            local parts = {}
            for _, key in ipairs(Sorted(t)) do parts[#parts + 1] = tostring(key) .. "=" .. Show(t[key]) end
            add("Enum." .. enumName .. ": " .. Limited(parts, 40))
        end
    end

    local bankApi = rawget(_G, "C_Bank")
    if type(bankApi) == "table" then
        local fns = {}
        for _, key in ipairs(Sorted(bankApi)) do
            if type(bankApi[key]) == "function" then fns[#fns + 1] = key end
        end
        add("C_Bank functions: " .. Limited(fns, 40))
    else
        add("C_Bank: MISSING")
    end
end

local function ApiPresence(add)
    add("")
    add("== API presence ==")
    for _, check in ipairs(API_CHECKS) do
        add(string.format("  %-40s %s", check[1], type(Resolve(check[2])) == "function" and "yes" or "MISSING"))
    end
    add("")
    add("== Mixins ==")
    for _, mixin in ipairs(MIXINS) do
        local t = rawget(_G, mixin[1])
        if type(t) ~= "table" then
            add(string.format("  %-32s MISSING", mixin[1]))
        else
            local have = {}
            for _, method in ipairs(mixin[2]) do
                if type(t[method]) == "function" then have[#have + 1] = method end
            end
            add(string.format("  %-32s yes | methods: %s", mixin[1], #have > 0 and table.concat(have, ", ") or "(none of the expected)"))
        end
    end
    add("")
    add("== Global functions with \"Bank\" in the name (hook candidates) ==")
    local names = {}
    pcall(function()
        for key, value in pairs(_G) do
            if type(key) == "string" and type(value) == "function" and key:find("Bank") then names[#names + 1] = key end
        end
    end)
    table.sort(names)
    add("  " .. Limited(names, MAX_GLOBALS))
end

local function DescribeButton(add, button, label)
    if type(button) ~= "table" then add("    " .. label .. ": " .. Show(button)); return end
    local parent = Method(button, "GetParent")
    add(string.format("    %s: name %s | type %s | GetBagID %s | GetID %s | GetBankTabID %s | GetContainerSlotID %s | parent %s | shown %s",
        label, Show(Method(button, "GetName")), Show(Method(button, "GetObjectType")),
        Show(Method(button, "GetBagID")), Show(Method(button, "GetID")),
        Show(Method(button, "GetBankTabID")), Show(Method(button, "GetContainerSlotID")),
        Show(type(parent) == "table" and (Method(parent, "GetName") or "(unnamed)") or nil), Show(Method(button, "IsShown"))))
    add(string.format("        fields: bagID %s | slotID %s | isBag %s | icon %s | Count %s | IconBorder %s | UpdateTooltip %s",
        Show(rawget(button, "bagID")), Show(rawget(button, "slotID")), Show(rawget(button, "isBag")),
        Show(type(button.icon) == "table" or type(button.Icon) == "table"),
        Show(type(button.Count) == "table" or type(button.count) == "table"),
        Show(type(button.IconBorder) == "table"), Show(type(button.UpdateTooltip) == "function")))
end

--- Botões de um frame: Items, EnumerateValidItems e os filhos do tipo Button.
local function SampleButtons(add, frame)
    local shown = 0
    if type(rawget(frame, "Items")) == "table" then
        add("    frame.Items: " .. #frame.Items .. " entries")
        for i = 1, math.min(#frame.Items, MAX_BUTTONS) do
            shown = shown + 1
            DescribeButton(add, frame.Items[i], "Items[" .. i .. "]")
        end
    end
    if type(frame.EnumerateValidItems) == "function" then
        local ok, iter, state, init = pcall(frame.EnumerateValidItems, frame)
        if ok and type(iter) == "function" then
            local count = 0
            pcall(function()
                for first, second in iter, state, init do
                    count = count + 1
                    local button = type(first) == "table" and first or second
                    if shown < MAX_BUTTONS then
                        shown = shown + 1
                        DescribeButton(add, button, "EnumerateValidItems#" .. count)
                    end
                    if count >= 400 then break end
                end
            end)
            add("    EnumerateValidItems yielded " .. count .. " button(s)")
        else
            add("    EnumerateValidItems: call failed")
        end
    end
    if type(frame.GetChildren) == "function" then
        local children = { pcall(frame.GetChildren, frame) }
        local buttons, kinds = 0, {}
        if table.remove(children, 1) then
            for i, child in ipairs(children) do
                local kind = Method(child, "GetObjectType") or "?"
                kinds[kind] = (kinds[kind] or 0) + 1
                if kind == "Button" or kind == "ItemButton" or kind == "CheckButton" then
                    buttons = buttons + 1
                    if shown < MAX_BUTTONS then
                        shown = shown + 1
                        DescribeButton(add, child, "child#" .. i)
                    end
                end
                if i >= 400 then break end
            end
        end
        local parts = {}
        for _, kind in ipairs(Sorted(kinds)) do parts[#parts + 1] = kind .. " " .. kinds[kind] end
        add("    children: " .. #children .. " (" .. Limited(parts, MAX_CHILDREN) .. ")")
    end
end

local function Fields(frame)
    local tables, funcs, values = {}, {}, {}
    pcall(function()
        for key, value in pairs(frame) do
            if type(key) == "string" then
                local kind = type(value)
                if kind == "table" then tables[#tables + 1] = key
                elseif kind == "function" then funcs[#funcs + 1] = key
                elseif kind == "number" or kind == "string" or kind == "boolean" then
                    values[#values + 1] = key .. "=" .. Show(value)
                end
            end
        end
    end)
    table.sort(tables); table.sort(funcs); table.sort(values)
    return tables, funcs, values
end

local function DescribeFrame(add, name, frame)
    frame = frame or rawget(_G, name)
    if type(frame) ~= "table" then
        add(string.format("  %s: absent", name))
        return
    end
    add(string.format("  %s: IsShown %s | IsVisible %s | GetID %s | GetBagID %s | objectType %s | size %sx%s",
        name, Show(Method(frame, "IsShown")), Show(Method(frame, "IsVisible")),
        Show(Method(frame, "GetID")), Show(Method(frame, "GetBagID")), Show(Method(frame, "GetObjectType")),
        Show(Method(frame, "GetWidth")), Show(Method(frame, "GetHeight"))))
    local tables, funcs, values = Fields(frame)
    add("    table fields: " .. Limited(tables))
    add("    functions: " .. Limited(funcs))
    add("    values: " .. Limited(values))
    SampleButtons(add, frame)
end

local function Frames(add)
    add("")
    add("== Bank frames ==")
    for _, name in ipairs(FRAMES) do DescribeFrame(add, name) end
    local bank = rawget(_G, "BankFrame")
    if type(bank) == "table" then
        for _, key in ipairs({ "BankPanel", "AccountBankPanel", "ReagentBankFrame", "TabSystem" }) do
            local sub = rawget(bank, key)
            if type(sub) == "table" and sub ~= rawget(_G, key) then DescribeFrame(add, "BankFrame." .. key, sub) end
        end
        add(string.format("  BankFrame.selectedTab %s | activeTabIndex %s | GetActiveBankType %s",
            Show(rawget(bank, "selectedTab")), Show(rawget(bank, "activeTabIndex")), Show(Method(bank, "GetActiveBankType"))))
    end
    local tabs = {}
    for i = 1, 6 do
        local tab = rawget(_G, "BankFrameTab" .. i)
        if type(tab) == "table" then
            tabs[#tabs + 1] = string.format("BankFrameTab%d (shown %s, text %s)", i,
                Show(Method(tab, "IsShown")), Show(Method(tab, "GetText")))
        end
    end
    add("  tabs: " .. (#tabs > 0 and table.concat(tabs, "; ") or "(no BankFrameTabN)"))
    local named = {}
    for i = 1, 40 do
        if rawget(_G, "BankFrameItem" .. i) then named[#named + 1] = i end
    end
    add("  BankFrameItemN globals: " .. (#named > 0 and (#named .. " (first " .. named[1] .. ", last " .. named[#named] .. ")") or "none"))
    if #named > 0 then DescribeButton(add, rawget(_G, "BankFrameItem" .. named[1]), "BankFrameItem" .. named[1]) end

    add("")
    add("== Container frames showing bank bags ==")
    local any = false
    for i = 1, 13 do
        local frame = rawget(_G, "ContainerFrame" .. i)
        if type(frame) == "table" and Method(frame, "IsShown") == true then
            any = true
            add(string.format("  ContainerFrame%d: GetID %s | GetBagID %s | IsBankBag %s",
                i, Show(Method(frame, "GetID")), Show(Method(frame, "GetBagID")), Show(Method(frame, "IsBankBag"))))
        end
    end
    if not any then add("  (no ContainerFrame shown)") end
end

--- IDs de bolsa candidatos: constantes antigas, Enum.BagIndex com "Bank" e abas do C_Bank.
local function CandidateBags()
    local ids, set = {}, {}
    local function Add(id, label)
        if type(id) == "number" and not set[id] then
            set[id] = label
            ids[#ids + 1] = id
        elseif type(id) == "number" then
            set[id] = set[id] .. ", " .. label
        end
    end
    Add(rawget(_G, "BANK_CONTAINER") or -1, "BANK_CONTAINER")
    Add(rawget(_G, "REAGENTBANK_CONTAINER") or -3, "REAGENTBANK_CONTAINER")
    local first = (type(rawget(_G, "NUM_BAG_SLOTS")) == "number" and NUM_BAG_SLOTS or 4) + 1
    local count = type(rawget(_G, "NUM_BANKBAGSLOTS")) == "number" and NUM_BANKBAGSLOTS or 7
    for i = 0, count - 1 do Add(first + i, "bank bag " .. (i + 1)) end
    local index = Resolve({ "Enum", "BagIndex" })
    if type(index) == "table" then
        for _, key in ipairs(Sorted(index)) do
            if tostring(key):find("Bank") then Add(index[key], "Enum.BagIndex." .. tostring(key)) end
        end
    end
    local fetch = Resolve({ "C_Bank", "FetchPurchasedBankTabIDs" })
    local bankType = Resolve({ "Enum", "BankType", "Character" })
    if fetch and bankType ~= nil then
        local tabs = Call(fetch, bankType)
        if type(tabs) == "table" then
            for i, id in ipairs(tabs) do Add(id, "C_Bank tab " .. i) end
        end
    end
    table.sort(ids)
    return ids, set
end

local function Containers(add)
    add("")
    add("== Bank containers and item level samples ==")
    local numFn = Resolve({ "C_Container", "GetContainerNumSlots" }) or rawget(_G, "GetContainerNumSlots")
    local linkFn = Resolve({ "C_Container", "GetContainerItemLink" }) or rawget(_G, "GetContainerItemLink")
    local nameFn = Resolve({ "C_Container", "GetBagName" })
    local instant = Resolve({ "C_Item", "GetItemInfoInstant" }) or rawget(_G, "GetItemInfoInstant")
    local ids, labels = CandidateBags()
    local samples, total, equippable = {}, 0, 0
    for _, bag in ipairs(ids) do
        local size = Call(numFn, bag)
        size = type(size) == "number" and size or 0
        local items = 0
        for slot = 1, size do
            local link = Call(linkFn, bag, slot)
            if type(link) == "string" then
                items = items + 1
                local _, _, _, equipLoc = Call(instant, link)
                if type(equipLoc) == "string" and equipLoc ~= "" then
                    equippable = equippable + 1
                    if #samples < MAX_SAMPLES then
                        samples[#samples + 1] = string.format("  bag %d slot %d: %s | %s | ilvl %s",
                            bag, slot, link, equipLoc, Show(ns.ItemLevel:Level(link)))
                    end
                end
            end
        end
        total = total + items
        add(string.format("  bag %3d (%s): %d slots, %d items, name %s", bag, labels[bag], size, items,
            Show((Call(nameFn, bag)))))
    end
    add(string.format("Items: %d | with an equip location: %d", total, equippable))
    for _, line in ipairs(samples) do add(line) end
    if equippable > #samples then add("  ... " .. (equippable - #samples) .. " more not listed") end
end

local function Events(add)
    add("")
    add("== Events (since load: count | last args) ==")
    for _, event in ipairs(EVENTS) do
        local e = seen[event]
        if e.valid then
            add(string.format("  %-32s %d | %s", event, e.count, Show(e.last)))
        else
            add(string.format("  %-32s could not register", event))
        end
    end
end

--- Monta o relatório como lista de linhas.
function Bank:Report()
    local lines = {}
    local function add(text) lines[#lines + 1] = text end
    add("WowUtilities bank debug (read-only; nothing is changed)")
    for _, section in ipairs({ Environment, ApiPresence, Frames, Containers, Events }) do
        local ok, err = pcall(section, add)
        if not ok then add("  (section error: " .. tostring(err) .. ")") end
    end
    return lines
end

ns.Debug:Register("bank", function()
    local ok, lines = pcall(Bank.Report, Bank)
    if not ok then lines = { "WowUtilities bank debug failed: " .. tostring(lines) } end
    ns.Debug:Output("WowUtilities debug — bank", lines)
end)
