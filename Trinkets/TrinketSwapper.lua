-- ============================================================
--  TrinketSwapper.lua
--  Equipa um trinket das bolsas num slot escolhido (13 ou 14).
--  Estratégias, da mais direta para a alternativa:
--    1. Nativa — EquipItemByName(item, slot), se o cliente tiver.
--    2. Cursor — pega o item da bolsa, solta no slot e devolve o
--                trinket antigo ao espaço que ficou vazio.
--  Nunca age em combate e nunca deixa um item preso no cursor.
--  Devolve (true) ou (false, motivo).
-- ============================================================

local _, ns = ...
local L = ns.L

local Swapper = {}
ns.TrinketSwapper = Swapper

local Fn = function(...) return ns.TrinketScanner.Fn(...) end
local VERIFY_DELAY = 1.0

local function CursorHasItem()
    local fn = Fn(nil, "CursorHasItem")
    if not fn then return false end
    local ok, has = pcall(fn)
    return ok and has and true or false
end

local function ClearCursor()
    local fn = Fn(nil, "ClearCursor")
    if fn then pcall(fn) end
end

local function InCombat()
    local fn = Fn(nil, "InCombatLockdown")
    if not fn then return false end
    local ok, value = pcall(fn)
    return ok and value and true or false
end

-- ----------------------------------------------------------------
-- Estratégias: devolvem (true) ou (false, motivo); nil = indisponível
-- ----------------------------------------------------------------

local strategies = {
    -- 1. Nativa
    {
        name = "native",
        run = function(entry, slot)
            local fn = Fn("C_Item", "EquipItemByName")
            if not fn then return nil end
            local ok = pcall(fn, entry.link, slot)
            if ok then return true end
            return false, "failed"
        end,
    },

    -- 2. Cursor
    {
        name = "cursor",
        run = function(entry, slot)
            local pickupBag = Fn("C_Container", "PickupContainerItem")
            local pickupSlot = Fn(nil, "PickupInventoryItem")
            if not (pickupBag and pickupSlot) then return nil end

            ClearCursor()
            if CursorHasItem() then return false, "cursor" end

            local ok = pcall(pickupBag, entry.bag, entry.slot)
            if not ok or not CursorHasItem() then
                ClearCursor()
                return false, "failed"
            end

            ok = pcall(pickupSlot, slot)
            if not ok then
                ClearCursor()
                return false, "failed"
            end

            -- O trinket antigo (se havia) está no cursor: volta ao espaço vago
            if CursorHasItem() then
                pcall(pickupBag, entry.bag, entry.slot)
            end
            if CursorHasItem() then
                ClearCursor()
                return false, "failed"
            end
            return true
        end,
    },
}

local MESSAGES = {
    combat = L["Cannot swap trinkets in combat."],
    moved  = L["That item is no longer in that bag slot."],
    cursor = L["Your cursor is holding an item; put it down and try again."],
    failed = L["The swap could not be completed; check your bags."],
    unconfirmed = L["The game did not confirm the trinket swap."],
}

local function Say(reason)
    print("|cff66ccffWowUtilities|r: " .. (MESSAGES[reason] or MESSAGES.failed))
end

--- Confere (um instante depois) se o item chegou ao slot.
local function Verify(entry, slot)
    if ns.TrinketScanner:EquippedID(slot) ~= entry.itemID then Say("unconfirmed") end
end

--- Equipa `entry` (item de TrinketScanner:Trinkets) no slot 13 ou 14.
function Swapper:Equip(entry, slot)
    if type(entry) ~= "table" or (slot ~= 13 and slot ~= 14) then return false, "failed" end

    if InCombat() then Say("combat"); return false, "combat" end
    if not ns.TrinketScanner:StillThere(entry) then Say("moved"); return false, "moved" end

    for _, strategy in ipairs(strategies) do
        local ok, reason = strategy.run(entry, slot)
        if ok ~= nil then
            if ok then
                if C_Timer and C_Timer.After then C_Timer.After(VERIFY_DELAY, function() Verify(entry, slot) end) end
                return true, strategy.name
            end
            Say(reason)
            return false, reason
        end
    end
    Say("failed")
    return false, "failed"
end
