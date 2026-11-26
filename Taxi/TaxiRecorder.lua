-- ============================================================
--  TaxiRecorder.lua
--  Cronometra os voos reais e grava o resultado no banco.
--  Publica no Bus:
--    FLIGHT_START(destino, segundosEsperados, tipo)
--    FLIGHT_END(concluido, segundosReais)
--  Responsabilidade única: observar o voo. Não desenha nada.
-- ============================================================

local _, ns = ...

local Recorder = {}
ns.TaxiRecorder = Recorder

local MIN_SECONDS = 5      -- abaixo disso, descarta (clique errado, desconexão)
local START_CHECK_DELAY = 0.3

local pending -- viagem escolhida no mapa, ainda não iniciada
local flight  -- viagem em andamento

local function Start()
    flight, pending = pending, nil
    flight.startedAt = GetTime()
    ns.Bus:Fire("FLIGHT_START", flight.toName, flight.expected, flight.kind)
end

local function Finish()
    local f = flight
    flight = nil
    local duration = GetTime() - f.startedAt
    local completed = not f.aborted and duration >= MIN_SECONDS
    if completed then
        ns.TaxiDatabase:Record(f.fromName, f.toName, duration, #f.hops, f.dist)
    end
    ns.Bus:Fire("FLIGHT_END", completed, duration)
end

local function OnTakeTaxiNode(destIndex)
    local trip = ns.TaxiCompat:BuildTrip(destIndex)
    if not trip then pending = nil return end
    trip.expected, trip.kind = ns.TaxiEstimator:ForTrip(trip)
    pending = trip
end

function Recorder:IsFlying()
    return flight ~= nil
end

ns.Bus:Subscribe("READY", function()
    if type(TakeTaxiNode) == "function" then
        hooksecurefunc("TakeTaxiNode", function(index) pcall(OnTakeTaxiNode, index) end)
    end
    -- Pouso antecipado: o voo termina no próximo nó, então não é uma medição válida
    if type(TaxiRequestEarlyLanding) == "function" then
        hooksecurefunc("TaxiRequestEarlyLanding", function()
            if flight then flight.aborted = true end
        end)
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_CONTROL_LOST")
    frame:RegisterEvent("PLAYER_CONTROL_GAINED")
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_CONTROL_LOST" then
            if not pending then return end
            -- PLAYER_CONTROL_LOST também ocorre por medo, etc.: confirma que é voo
            C_Timer.After(START_CHECK_DELAY, function()
                if pending and UnitOnTaxi("player") then Start() else pending = nil end
            end)
        elseif flight then
            Finish()
        else
            pending = nil
        end
    end)
end)
