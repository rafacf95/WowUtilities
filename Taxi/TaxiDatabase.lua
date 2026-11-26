-- ============================================================
--  TaxiDatabase.lua
--  Armazena os tempos de voo medidos (SavedVariables, compartilhado
--  entre personagens). Chave: "Origem|Destino" (nomes dos nós).
--  Responsabilidade única: persistência e consulta dos tempos.
-- ============================================================

local _, ns = ...

local Database = {}
ns.TaxiDatabase = Database

local MAX_WEIGHT = 9 -- média móvel: a medição nova pesa 1/(n+1), n <= 9

-- Os nomes dos nós mudam com o idioma do cliente, então cada idioma tem o
-- seu próprio conjunto: ns.db.taxiTimes[idioma]["Origem|Destino"].
local function Store()
    if not ns.db then return nil end
    ns.db.taxiTimes = ns.db.taxiTimes or {}
    local bucket = ns.db.taxiTimes[ns.locale]
    if not bucket then
        bucket = {}
        ns.db.taxiTimes[ns.locale] = bucket
    end
    return bucket
end

--- Versão antiga guardava tudo num único nível; move para o idioma atual.
function Database:Migrate()
    local times = ns.db and ns.db.taxiTimes
    if not times then return end
    local _, first = next(times)
    if type(first) == "table" and first.seconds ~= nil then
        ns.db.taxiTimes = { [ns.locale] = times }
    end
end

ns.Bus:Subscribe("READY", function() Database:Migrate() end)

local function Key(from, to)
    return from .. "|" .. to
end

--- Entrada { seconds, count, hops, dist, updated } ou nil.
function Database:Get(from, to)
    local store = Store()
    return store and store[Key(from, to)] or nil
end

--- Registra uma medição, combinando com as anteriores (média móvel).
function Database:Record(from, to, seconds, hops, dist)
    local store = Store()
    if not store then return end

    local key = Key(from, to)
    local entry = store[key]
    if entry then
        local weight = math.min(entry.count or 1, MAX_WEIGHT)
        entry.seconds = (entry.seconds * weight + seconds) / (weight + 1)
        entry.count = (entry.count or 1) + 1
    else
        entry = { seconds = seconds, count = 1 }
        store[key] = entry
    end
    entry.hops = hops
    entry.dist = dist
    entry.updated = time and time() or 0
end

--- Segundos por unidade de distância (calibrado só com voos diretos
--- medidos). nil se ainda não houver nenhum.
function Database:SecondsPerUnit()
    local store = Store()
    if not store then return nil end
    local totalSeconds, totalDist = 0, 0
    for _, entry in pairs(store) do
        if entry.hops == 1 and entry.dist and entry.dist > 0 then
            totalSeconds = totalSeconds + entry.seconds
            totalDist = totalDist + entry.dist
        end
    end
    if totalDist <= 0 then return nil end
    return totalSeconds / totalDist
end

function Database:Count()
    local store = Store()
    local n = 0
    if store then for _ in pairs(store) do n = n + 1 end end
    return n
end

--- Itera sobre todas as entradas: fn(from, to, entry).
function Database:Each(fn)
    local store = Store()
    if not store then return end
    for key, entry in pairs(store) do
        local from, to = key:match("^(.-)|(.*)$")
        if from then fn(from, to, entry) end
    end
end

function Database:Clear()
    if not ns.db then return end
    ns.db.taxiTimes = ns.db.taxiTimes or {}
    ns.db.taxiTimes[ns.locale] = {}
end
