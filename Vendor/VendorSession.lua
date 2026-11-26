-- ============================================================
--  VendorSession.lua
--  Totais de uma visita a um vendedor (vendido, comprado, reparo).
--  Objeto de valor: não conhece eventos, chat nem configuração.
-- ============================================================

local _, ns = ...

local Session = {}
Session.__index = Session
ns.VendorSession = Session

Session.CATEGORIES = { "sold", "bought", "repair" }

function Session.New()
    return setmetatable({ sold = 0, bought = 0, repair = 0 }, Session)
end

--- amount em cobre, sempre positivo; o sentido vem da categoria.
function Session:Add(category, amount)
    if self[category] == nil or type(self[category]) ~= "number" then return end
    if type(amount) ~= "number" or amount <= 0 then return end
    self[category] = self[category] + amount
end

--- Ganho líquido: negativo quando gastou mais do que vendeu.
function Session:Net()
    return self.sold - self.bought - self.repair
end

function Session:IsEmpty()
    return self.sold == 0 and self.bought == 0 and self.repair == 0
end

function Session:Reset()
    self.sold, self.bought, self.repair = 0, 0, 0
end
