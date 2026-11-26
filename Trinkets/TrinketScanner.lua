-- ============================================================
--  TrinketScanner.lua
--  Leitura (nunca altera nada): trinkets nas bolsas e nos slots 13/14.
--  Cada leitura tenta a API moderna (C_Container / C_Item) e, na falta,
--  a global antiga de mesmo nome (Adapter).
-- ============================================================

local _, ns = ...

local Scanner = {}
ns.TrinketScanner = Scanner

Scanner.SLOTS = { 13, 14 } -- INVSLOT_TRINKET1 / INVSLOT_TRINKET2
local TRINKET_LOC = "INVTYPE_TRINKET"

--- Função `name` do espaço `space` (ex.: C_Container) ou a global antiga.
function Scanner.Fn(space, name)
    local t = space and rawget(_G, space)
    if type(t) == "table" and type(t[name]) == "function" then return t[name] end
    local g = rawget(_G, name)
    if type(g) == "function" then return g end
end

local Fn = Scanner.Fn

local function Call(fn, ...)
    if not fn then return end
    return ns.SafeCall(fn, ...)
end

local function LastBag()
    local n = rawget(_G, "NUM_BAG_SLOTS")
    return type(n) == "number" and n or 4
end

--- itemID, tipo, subtipo, equipLoc, ícone (não depende de cache).
local function Instant(link)
    return Call(Fn("C_Item", "GetItemInfoInstant"), link)
end

local function Quality(link, info)
    if type(info) == "table" and type(info.quality) == "number" then return info.quality end
    local _, _, quality = Call(Fn("C_Item", "GetItemInfo"), link)
    return type(quality) == "number" and quality or 1
end

local function ItemLevel(link)
    return ns.ItemLevel:Level(link) -- serviço compartilhado (com cache)
end

local function BagLink(bag, slot)
    local link = Call(Fn("C_Container", "GetContainerItemLink"), bag, slot)
    if type(link) == "string" then return link end
end

local function BagInfo(bag, slot)
    local info = Call(Fn("C_Container", "GetContainerItemInfo"), bag, slot)
    return type(info) == "table" and info or nil
end

local function Describe(link, extra)
    local itemID, _, _, _, icon = Instant(link)
    extra = extra or {}
    extra.link = link
    extra.itemID = itemID
    extra.icon = icon
    extra.ilvl = ItemLevel(link)
    return extra
end

--- Trinkets das bolsas, do maior nível para o menor.
--- Cada item: { bag, slot, link, itemID, icon, quality, ilvl, name, start, duration, enable }.
function Scanner:Trinkets()
    local list = {}
    for bag = 0, LastBag() do
        local size = Call(Fn("C_Container", "GetContainerNumSlots"), bag)
        for slot = 1, (type(size) == "number" and size or 0) do
            local link = BagLink(bag, slot)
            if link then
                local _, _, _, equipLoc = Instant(link)
                if equipLoc == TRINKET_LOC then
                    local info = BagInfo(bag, slot)
                    local entry = Describe(link, { bag = bag, slot = slot, quality = Quality(link, info) })
                    entry.start, entry.duration, entry.enable = Call(Fn("C_Container", "GetContainerItemCooldown"), bag, slot)
                    entry.name = link:match("%[(.-)%]") or tostring(entry.itemID)
                    list[#list + 1] = entry
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if (a.ilvl or 0) ~= (b.ilvl or 0) then return (a.ilvl or 0) > (b.ilvl or 0) end
        return a.name < b.name
    end)
    return list
end

--- O que está no slot (13 ou 14), ou nil se vazio.
--- { slot, link, itemID, icon, quality, ilvl, start, duration, enable }
function Scanner:Equipped(slot)
    local link = Call(Fn(nil, "GetInventoryItemLink"), "player", slot)
    if type(link) ~= "string" then return nil end
    local entry = Describe(link, { slot = slot, quality = Quality(link) })
    local texture = Call(Fn(nil, "GetInventoryItemTexture"), "player", slot)
    if texture then entry.icon = texture end
    entry.start, entry.duration, entry.enable = Call(Fn(nil, "GetInventoryItemCooldown"), "player", slot)
    return entry
end

--- itemID que está no slot agora (para conferir uma troca).
function Scanner:EquippedID(slot)
    local id = Call(Fn(nil, "GetInventoryItemID"), "player", slot)
    return type(id) == "number" and id or nil
end

--- True se o item ainda está onde a leitura anterior o viu.
function Scanner:StillThere(entry)
    return BagLink(entry.bag, entry.slot) == entry.link
end
