-- ============================================================
--  TaxiCompat.lua
--  Camada de compatibilidade do mapa de voo (WoW Forever).
--  Único arquivo que toca nas APIs de taxi e nos frames do mapa de
--  voo. O resto do addon só enxerga "trips" (viagens) e callbacks.
-- ============================================================

local _, ns = ...

local Compat = {}
ns.TaxiCompat = Compat

-- ----------------------------------------------------------------
-- Leitura dos nós
-- ----------------------------------------------------------------

function Compat:NumNodes()
    return ns.SafeCall(NumTaxiNodes) or 0
end

function Compat:NodeName(index)
    local name = ns.SafeCall(TaxiNodeName, index)
    return type(name) == "string" and name or nil
end

--- "CURRENT", "REACHABLE", "DISTANT" ou "NONE".
function Compat:NodeType(index)
    return (ns.SafeCall(TaxiNodeGetType, index))
end

--- Posição normalizada (0..1) do nó no mapa de voo.
function Compat:NodePosition(index)
    local x, y = ns.SafeCall(TaxiNodePosition, index)
    return x, y
end

--- Índice do nó onde o jogador está (mestre de voo atual).
function Compat:CurrentNode()
    for i = 1, self:NumNodes() do
        if self:NodeType(i) == "CURRENT" then return i end
    end
end

--- Trechos da rota até `destIndex`: lista de { from = slot, to = slot }.
function Compat:Hops(destIndex)
    local hops = {}
    local count = ns.SafeCall(GetNumRoutes, destIndex) or 0
    for hop = 1, count do
        local from = ns.SafeCall(TaxiGetNodeSlot, destIndex, hop, true)
        local to = ns.SafeCall(TaxiGetNodeSlot, destIndex, hop, false)
        if not from or not to then return {} end -- dado incompleto
        hops[#hops + 1] = { from = from, to = to }
    end
    return hops
end

local function Distance(self, a, b)
    local ax, ay = self:NodePosition(a)
    local bx, by = self:NodePosition(b)
    if not (ax and ay and bx and by) then return 0 end
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

--- Monta a viagem até `destIndex`:
--- { fromName, toName, dist, hops = { {fromName, toName, dist}, ... } }
--- Devolve nil se faltarem nomes (dados ainda não carregados).
function Compat:BuildTrip(destIndex)
    local current = self:CurrentNode()
    if not current or not destIndex then return nil end

    local rawHops = self:Hops(destIndex)
    if #rawHops == 0 then rawHops = { { from = current, to = destIndex } } end

    local trip = { fromName = self:NodeName(current), toName = self:NodeName(destIndex),
                   dist = 0, hops = {} }
    if not trip.fromName or not trip.toName then return nil end

    for _, hop in ipairs(rawHops) do
        local fromName, toName = self:NodeName(hop.from), self:NodeName(hop.to)
        if not fromName or not toName then return nil end
        local dist = Distance(self, hop.from, hop.to)
        trip.hops[#trip.hops + 1] = { fromName = fromName, toName = toName, dist = dist }
        trip.dist = trip.dist + dist
    end
    return trip
end

-- ----------------------------------------------------------------
-- Hover nos destinos do mapa de voo
-- Cada cliente exibe o mapa de um jeito; tentamos os dois.
--   callback(nodeIndex)  -- chamado depois de a Blizzard montar a tooltip
-- ----------------------------------------------------------------

function Compat:InstallNodeHoverHook(callback)
    local function Safe(index)
        if index then pcall(callback, index) end
    end

    -- Estilo clássico: botões TaxiButtonN com ID = índice do nó
    if type(TaxiNodeOnButtonEnter) == "function" then
        hooksecurefunc("TaxiNodeOnButtonEnter", function(button)
            Safe(button and button:GetID())
        end)
    end

    -- Estilo moderno: pins do FlightMapFrame (carregado sob demanda)
    local function HookPins()
        local mixin = FlightMap_FlightPointPinMixin
        if not mixin or mixin.__wuHooked then return end
        if type(mixin.OnMouseEnter) ~= "function" then return end
        mixin.__wuHooked = true
        hooksecurefunc(mixin, "OnMouseEnter", function(pin)
            local data = pin and pin.taxiNodeData
            Safe(data and data.slotIndex)
        end)
    end

    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_FlightMap") then
        HookPins()
    else
        local watcher = CreateFrame("Frame")
        watcher:RegisterEvent("ADDON_LOADED")
        watcher:SetScript("OnEvent", function(self, _, name)
            if name == "Blizzard_FlightMap" then
                HookPins()
                self:UnregisterEvent("ADDON_LOADED")
            end
        end)
        HookPins() -- caso já esteja disponível
    end
end
