-- ============================================================
--  TaxiEstimator.lua
--  Estima a duração de uma viagem. Cadeia de estratégias, da mais
--  confiável para a menos; a primeira que responder vence.
--    1. Medida      — esta rota exata já foi voada.
--    2. Composta    — soma de trechos medidos (rota com paradas).
--    3. Distância   — trechos sem medição estimados pela distância,
--                     calibrada só com voos reais (nunca inventamos
--                     uma velocidade).
--  Retorna (segundos, tipo) com tipo "measured" ou "estimate".
-- ============================================================

local _, ns = ...

local Estimator = {}
ns.TaxiEstimator = Estimator

local DB = function() return ns.TaxiDatabase end

local strategies = {
    -- 1. Medida
    function(trip)
        local entry = DB():Get(trip.fromName, trip.toName)
        if entry then return entry.seconds, "measured" end
    end,

    -- 2. Composta (só faz sentido com mais de um trecho)
    function(trip)
        if #trip.hops < 2 then return end
        local sum = 0
        for _, hop in ipairs(trip.hops) do
            local entry = DB():Get(hop.fromName, hop.toName)
            if not entry then return end
            sum = sum + entry.seconds
        end
        return sum, "estimate"
    end,

    -- 3. Distância
    function(trip)
        local k = DB():SecondsPerUnit()
        if not k then return end
        local sum = 0
        for _, hop in ipairs(trip.hops) do
            local entry = DB():Get(hop.fromName, hop.toName)
            sum = sum + (entry and entry.seconds or hop.dist * k)
        end
        if sum <= 0 then return end
        return sum, "estimate"
    end,
}

--- Estima uma viagem já montada (ver TaxiCompat:BuildTrip).
function Estimator:ForTrip(trip)
    for _, strategy in ipairs(strategies) do
        local seconds, kind = strategy(trip)
        if seconds then return seconds, kind end
    end
end

--- Estima a viagem do nó atual até `destIndex`.
function Estimator:ForNode(destIndex)
    local trip = ns.TaxiCompat:BuildTrip(destIndex)
    if not trip then return end
    return self:ForTrip(trip)
end
