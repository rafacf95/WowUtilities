-- ============================================================
--  VendorTracker.lua
--  Observa o jogo e mede quanto gold muda enquanto a janela do
--  vendedor está aberta (diferença simples de saldo).
--  Publica no Bus:
--    VENDOR_CHANGE(categoria, cobre)  — a cada mudança de saldo
--    VENDOR_CLOSED(sessão)            — ao fechar o vendedor
--  Não imprime nada: quem mostra é o VendorReporter.
-- ============================================================

local _, ns = ...

local Tracker = {}
ns.VendorTracker = Tracker

local REPAIR_WINDOW = 1 -- segundos: uma queda de saldo logo após o reparo conta como reparo

local session
local isOpen = false
local lastMoney
local repairAt

local function Money()
    local value = ns.Safe(GetMoney)
    return type(value) == "number" and value or nil
end

local function Enabled()
    return ns.Config:Get("vendor.enabled")
end

local function Close()
    if not isOpen then return end
    isOpen = false
    local finished = session
    session, lastMoney = nil, nil
    ns.Bus:Fire("VENDOR_CLOSED", finished)
end

local function Open()
    if isOpen then Close() end -- trocou direto de vendedor
    if not Enabled() then return end
    isOpen = true
    session = ns.VendorSession.New()
    lastMoney = Money()
end

local function MoneyChanged()
    if not isOpen then return end
    local now = Money()
    if not now then return end
    if lastMoney == nil then lastMoney = now return end

    local delta = now - lastMoney
    lastMoney = now
    if delta == 0 then return end

    local category
    if delta > 0 then
        category = "sold"
    elseif repairAt and (GetTime() - repairAt) <= REPAIR_WINDOW then
        category = "repair"
    else
        category = "bought"
    end

    local amount = math.abs(delta)
    session:Add(category, amount)
    ns.Bus:Fire("VENDOR_CHANGE", category, amount)
end

--- Só serve para separar "reparo" de "compra"; sem ele, vira compra.
local function HookRepair()
    if type(RepairAllItems) ~= "function" then return end
    hooksecurefunc("RepairAllItems", function() repairAt = GetTime() end)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("MERCHANT_CLOSED")
frame:RegisterEvent("PLAYER_MONEY")
frame:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then Open()
    elseif event == "MERCHANT_CLOSED" then Close()
    else MoneyChanged() end
end)

ns.Bus:Subscribe("READY", HookRepair)
