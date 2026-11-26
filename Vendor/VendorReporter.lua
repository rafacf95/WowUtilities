-- ============================================================
--  VendorReporter.lua
--  Mostra no chat o que o VendorTracker mediu. Duas saídas
--  independentes, escolhidas na configuração:
--    onClose        — resumo ao fechar o vendedor (com saldo)
--    perTransaction — mensagem após cada compra/venda/reparo; mudanças
--                     seguidas (ex.: vender lixo) viram uma linha só
-- ============================================================

local _, ns = ...
local L = ns.L

local Reporter = {}
ns.VendorReporter = Reporter

local COALESCE_SECONDS = 0.3
local GREEN, RED = "|cff33ff33", "|cffff5555"

local pending         -- acumulado ainda não impresso (modo por transação)
local flushScheduled = false

local function Cfg(key) return ns.Config:Get("vendor." .. key) end

local function Signed(amount)
    local sign, color = "+", GREEN
    if amount < 0 then sign, color = "-", RED end
    return color .. sign .. "|r" .. ns.MoneyFormat:Coins(amount)
end

--- Monta a linha de uma sessão. Só entram as categorias com valor;
--- o saldo aparece quando há mais de uma (com uma só seria repetição).
function Reporter:Line(session, withNet)
    local parts = {}
    if session.sold > 0 then parts[#parts + 1] = L["Sold"] .. " " .. Signed(session.sold) end
    if session.bought > 0 then parts[#parts + 1] = L["Bought"] .. " " .. Signed(-session.bought) end
    if session.repair > 0 then parts[#parts + 1] = L["Repair"] .. " " .. Signed(-session.repair) end

    if #parts == 0 then return nil end
    if withNet and #parts > 1 then parts[#parts + 1] = L["Net"] .. " " .. Signed(session:Net()) end
    return table.concat(parts, " | ")
end

local function Print(text)
    print("|cff66ccffWowUtilities|r — " .. L["Vendor"] .. ": " .. text)
end

local function Flush()
    flushScheduled = false
    local session = pending
    pending = nil
    if not session then return end
    local line = Reporter:Line(session, false)
    if line then Print(line) end
end

local function OnChange(category, amount)
    if not Cfg("enabled") or not Cfg("perTransaction") then return end
    pending = pending or ns.VendorSession.New()
    pending:Add(category, amount)

    if flushScheduled then return end
    flushScheduled = true
    if C_Timer and C_Timer.After then
        C_Timer.After(COALESCE_SECONDS, Flush)
    else
        Flush()
    end
end

local function OnClosed(session)
    Flush() -- o que sobrou do modo por transação sai antes do resumo
    if not session or not Cfg("enabled") or not Cfg("onClose") then return end

    local line = Reporter:Line(session, true)
    if line then
        Print(line)
    elseif Cfg("showZero") then
        Print(L["No changes"])
    end
end

ns.Bus:Subscribe("VENDOR_CHANGE", OnChange)
ns.Bus:Subscribe("VENDOR_CLOSED", OnClosed)
