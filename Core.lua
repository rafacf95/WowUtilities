-- ============================================================
--  Core.lua
--  Namespace compartilhado, barramento de eventos (Observer) e
--  helpers de segurança. Sem dependência de nenhum recurso.
-- ============================================================

local ADDON_NAME, ns = ...

ns.name = ADDON_NAME

local unpack = unpack or table.unpack

-- ----------------------------------------------------------------
-- Cliente
-- ----------------------------------------------------------------

-- ----------------------------------------------------------------
-- Segurança ("secret values")
-- ----------------------------------------------------------------

function ns.IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) or false
end

--- pcall que devolve até 3 retornos, descartando erros e valores secretos.
function ns.Safe(fn, ...)
    local ok, a, b, c = pcall(fn, ...)
    if not ok then return end
    if ns.IsSecret(a) or ns.IsSecret(b) or ns.IsSecret(c) then return end
    return a, b, c
end

--- pcall que devolve TODOS os retornos (até 8); valores secretos viram nil.
function ns.SafeCall(fn, ...)
    local r = { pcall(fn, ...) }
    if not r[1] then return end
    for i = 2, 9 do
        if issecretvalue and issecretvalue(r[i]) then r[i] = nil end
    end
    return unpack(r, 2, 9)
end

-- ----------------------------------------------------------------
-- Utilitários
-- ----------------------------------------------------------------

--- 75 -> "1:15"
function ns.FormatTime(seconds)
    seconds = math.max(0, math.floor((seconds or 0) + 0.5))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

--- "Booty Bay, Stranglethorn" -> "Booty Bay": tira a zona (tudo depois da
--- primeira vírgula). Sem vírgula, devolve o nome inteiro.
function ns.PlaceName(nodeName)
    if type(nodeName) ~= "string" then return nil end
    local place = nodeName:match("^([^,]+)")
    place = place and place:match("^%s*(.-)%s*$")
    if place and place ~= "" then return place end
    return nodeName
end

-- ----------------------------------------------------------------
-- Bus de eventos internos (Observer)
-- Desacopla quem produz (gravador de voo, configuração) de quem
-- reage (barra, janela, tooltip).
-- ----------------------------------------------------------------

local Bus = { handlers = {} }
ns.Bus = Bus

function Bus:Subscribe(event, fn)
    local list = self.handlers[event]
    if not list then
        list = {}
        self.handlers[event] = list
    end
    list[#list + 1] = fn
end

function Bus:Fire(event, ...)
    local list = self.handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end
end

-- ----------------------------------------------------------------
-- Bootstrap: inicializa a configuração e avisa os módulos (READY)
-- ----------------------------------------------------------------

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(self, _, loaded)
    if loaded ~= ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")
    ns.Config:Init()
    Bus:Fire("READY")
end)
