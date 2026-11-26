-- ============================================================
--  DebugTrinkets.lua
--  /wu debug trinkets
--  Diagnóstico para o futuro seletor de trinkets: quais APIs de bolsa,
--  equipamento e item existem neste cliente, o que está nos slots
--  13/14, e quais itens das bolsas são trinkets. Só lê; não equipa,
--  não move e não altera nada. Report monta as linhas (testável sem o
--  jogo); o comando abre a janela de texto copiável.
-- ============================================================

local _, ns = ...

local Trinkets = {}
ns.DebugTrinkets = Trinkets

local Show = ns.Debug.Show

local SLOTS = { 13, 14 } -- INVSLOT_TRINKET1 / INVSLOT_TRINKET2
local TRINKET_LOC = "INVTYPE_TRINKET"
local LIST_LIMIT = 40

-- { rótulo, caminho } de funções que o seletor poderá usar
local API_CHECKS = {
    { "C_Container.GetContainerNumSlots",   { "C_Container", "GetContainerNumSlots" } },
    { "C_Container.GetContainerItemInfo",   { "C_Container", "GetContainerItemInfo" } },
    { "C_Container.GetContainerItemLink",   { "C_Container", "GetContainerItemLink" } },
    { "C_Container.PickupContainerItem",    { "C_Container", "PickupContainerItem" } },
    { "C_Container.UseContainerItem",       { "C_Container", "UseContainerItem" } },
    { "GetContainerNumSlots (legacy)",      { "GetContainerNumSlots" } },
    { "GetContainerItemLink (legacy)",      { "GetContainerItemLink" } },
    { "PickupContainerItem (legacy)",       { "PickupContainerItem" } },
    { "EquipItemByName",                    { "EquipItemByName" } },
    { "PickupInventoryItem",                { "PickupInventoryItem" } },
    { "GetInventoryItemLink",               { "GetInventoryItemLink" } },
    { "GetInventoryItemID",                 { "GetInventoryItemID" } },
    { "GetInventoryItemTexture",            { "GetInventoryItemTexture" } },
    { "GetInventoryItemCooldown",           { "GetInventoryItemCooldown" } },
    { "C_Container.GetContainerItemCooldown", { "C_Container", "GetContainerItemCooldown" } },
    { "GetContainerItemCooldown (legacy)",  { "GetContainerItemCooldown" } },
    { "C_Item.GetItemInfoInstant",          { "C_Item", "GetItemInfoInstant" } },
    { "GetItemInfoInstant (legacy)",        { "GetItemInfoInstant" } },
    { "C_Item.GetItemInfo",                 { "C_Item", "GetItemInfo" } },
    { "GetItemInfo (legacy)",               { "GetItemInfo" } },
    { "C_Item.GetDetailedItemLevelInfo",    { "C_Item", "GetDetailedItemLevelInfo" } },
    { "GetDetailedItemLevelInfo (legacy)",  { "GetDetailedItemLevelInfo" } },
    { "C_Item.IsEquippableItem",            { "C_Item", "IsEquippableItem" } },
    { "IsEquippableItem (legacy)",          { "IsEquippableItem" } },
    { "InCombatLockdown",                   { "InCombatLockdown" } },
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

-- Cada estratégia devolve (valor, nome da fonte) ou nada

local function NumSlots(bag)
    local fn = First(Resolve({ "C_Container", "GetContainerNumSlots" }), Resolve({ "GetContainerNumSlots" }))
    local n = Call(fn, bag)
    return type(n) == "number" and n or 0
end

local function ItemLink(bag, slot)
    local modern = Resolve({ "C_Container", "GetContainerItemLink" })
    if modern then
        local link = Call(modern, bag, slot)
        if type(link) == "string" then return link, "C_Container.GetContainerItemLink" end
    end
    local info = Call(Resolve({ "C_Container", "GetContainerItemInfo" }), bag, slot)
    if type(info) == "table" and type(info.hyperlink) == "string" then
        return info.hyperlink, "C_Container.GetContainerItemInfo.hyperlink"
    end
    local legacy = Resolve({ "GetContainerItemLink" })
    if legacy then
        local link = Call(legacy, bag, slot)
        if type(link) == "string" then return link, "GetContainerItemLink" end
    end
end

--- itemID, tipo, subtipo, equipLoc do item (sem precisar estar no cache).
local function InstantInfo(link)
    local fn = First(Resolve({ "C_Item", "GetItemInfoInstant" }), Resolve({ "GetItemInfoInstant" }))
    return Call(fn, link)
end

local function ItemName(link)
    local fn = First(Resolve({ "C_Item", "GetItemInfo" }), Resolve({ "GetItemInfo" }))
    local name, _, quality = Call(fn, link)
    return name, quality
end

local function ItemLevel(link)
    local fn = First(Resolve({ "C_Item", "GetDetailedItemLevelInfo" }), Resolve({ "GetDetailedItemLevelInfo" }))
    return (Call(fn, link))
end

local function LastBag()
    local n = rawget(_G, "NUM_BAG_SLOTS")
    return type(n) == "number" and n or 4
end

local function Environment(add)
    local version, build, _, toc = ns.SafeCall(GetBuildInfo)
    add(string.format("Game version: %s (build %s, interface %s)",
        Show(version), Show(build), Show(toc)))
    add("InCombatLockdown = " .. Show(Call(Resolve({ "InCombatLockdown" }))))
    add("NUM_BAG_SLOTS = " .. Show(rawget(_G, "NUM_BAG_SLOTS")))
end

local function ApiPresence(add)
    add("")
    add("== API presence ==")
    for _, check in ipairs(API_CHECKS) do
        add(string.format("  %-38s %s", check[1], type(Resolve(check[2])) == "function" and "yes" or "MISSING"))
    end
end

local function Equipped(add)
    add("")
    add("== Equipped trinket slots ==")
    for _, slot in ipairs(SLOTS) do
        local link = Call(Resolve({ "GetInventoryItemLink" }), "player", slot)
        if type(link) ~= "string" then
            add(string.format("  slot %d: empty (link = %s)", slot, Show(link)))
        else
            local itemID = InstantInfo(link)
            local name, quality = ItemName(link)
            local start, duration, enable = Call(Resolve({ "GetInventoryItemCooldown" }), "player", slot)
            add(string.format("  slot %d: %s | itemID %s | quality %s | ilvl %s | texture %s",
                slot, Show(name), Show(itemID), Show(quality), Show(ItemLevel(link)),
                Show(Call(Resolve({ "GetInventoryItemTexture" }), "player", slot))))
            add(string.format("          cooldown start %s duration %s enable %s",
                Show(start), Show(duration), Show(enable)))
        end
    end
end

local function Bags(add)
    add("")
    add("== Bags ==")
    local scanned, nameless, sources, found = 0, 0, {}, {}
    local sizes = {}
    for bag = 0, LastBag() do
        local size = NumSlots(bag)
        sizes[#sizes + 1] = string.format("bag %d: %d", bag, size)
        for slot = 1, size do
            local link, source = ItemLink(bag, slot)
            if link then
                scanned = scanned + 1
                sources[source] = true
                local itemID, _, _, equipLoc = InstantInfo(link)
                if equipLoc == nil then nameless = nameless + 1 end
                if equipLoc == TRINKET_LOC then
                    found[#found + 1] = { bag = bag, slot = slot, link = link, itemID = itemID }
                end
            end
        end
    end
    add("Slots per bag: " .. table.concat(sizes, ", "))
    local used = {}
    for source in pairs(sources) do used[#used + 1] = source end
    table.sort(used)
    add("Items scanned: " .. scanned .. " | link source: " .. (#used > 0 and table.concat(used, ", ") or "none"))
    add("Items without equip location info: " .. nameless)
    add("Trinkets found in bags: " .. #found)
    for i, t in ipairs(found) do
        if i > LIST_LIMIT then
            add("  ... " .. (#found - LIST_LIMIT) .. " more not listed")
            break
        end
        local name, quality = ItemName(t.link)
        add(string.format("  bag %d slot %d: %s | itemID %s | quality %s | ilvl %s",
            t.bag, t.slot, Show(name), Show(t.itemID), Show(quality), Show(ItemLevel(t.link))))
        local cdFn = First(Resolve({ "C_Container", "GetContainerItemCooldown" }), Resolve({ "GetContainerItemCooldown" }))
        local start, duration, enable = Call(cdFn, t.bag, t.slot)
        add(string.format("          cooldown start %s duration %s enable %s",
            Show(start), Show(duration), Show(enable)))
    end
end

--- Monta o relatório como lista de linhas.
function Trinkets:Report()
    local lines = {}
    local function add(text) lines[#lines + 1] = text end
    add("WowUtilities trinket debug (read-only; nothing is equipped or moved)")
    Environment(add)
    ApiPresence(add)
    Equipped(add)
    Bags(add)
    return lines
end

ns.Debug:Register("trinkets", function()
    local ok, lines = pcall(Trinkets.Report, Trinkets)
    if not ok then lines = { "WowUtilities trinket debug failed: " .. tostring(lines) } end
    ns.Debug:Output("WowUtilities debug — trinkets", lines)
end)
