-- ============================================================
--  NameResolver.lua
--  Descobre o nome completo do jogador (título + nome + segundo nome).
--  Chain of Responsibility: cada "fonte" tenta devolver (nome, segundo);
--  as fontes são consultadas em ordem até o nome estar completo.
--  Para jogadores distantes, UnitName pode vir incompleto, então há
--  fontes alternativas (ex.: pelo GUID).
-- ============================================================

local _, ns = ...

local NameResolver = {}
ns.NameResolver = NameResolver

--- Devolve o valor se for string legível e útil; senão nil.
local function Valid(v)
    if type(v) ~= "string" or ns.IsSecret(v) then return nil end
    if v == "" or v == UNKNOWNOBJECT then return nil end
    return v
end

-- Cada fonte recebe a unit e devolve (nome, segundoNome). No Forever o
-- segundo nome NÃO é realm, mas as APIs o expõem no mesmo retorno.
local sources = {
    function(unit)
        local name, second = ns.SafeCall(UnitFullName, unit)
        return name, second
    end,
    function(unit)
        local name, second = ns.SafeCall(UnitName, unit)
        return name, second
    end,
    function(unit)
        -- GetPlayerInfoByGUID funciona com dados em cache, mesmo se o
        -- jogador estiver fora do alcance de visão.
        local guid = ns.SafeCall(UnitGUID, unit)
        if not Valid(guid) then return end
        local _, _, _, _, _, name, second = ns.SafeCall(GetPlayerInfoByGUID, guid)
        return name, second
    end,
}

--- Retorna (primeiroNome, segundoNome). Qualquer um pode ser nil.
--- No WoW Forever o personagem tem um segundo nome, sempre procurado.
function NameResolver:Resolve(unit)
    local first, second
    for _, source in ipairs(sources) do
        local n, s = source(unit)
        first = first or Valid(n)
        second = second or Valid(s)
        if first and second then break end
    end
    return first, second
end

--- Nome para exibição: mantém o título do jogador (UnitPVPName) e injeta o
--- segundo nome logo após o primeiro, seja o título prefixo ou sufixo.
function NameResolver:Display(unit)
    local first, second = self:Resolve(unit)
    local pvp = Valid(ns.SafeCall(UnitPVPName, unit))

    local full = first
    if first and second then full = first .. " " .. second end

    if not pvp then return full end
    if not first or not second then return pvp end
    if pvp:find(second, 1, true) then return pvp end -- já completo

    local s, e = pvp:find(first, 1, true)
    if not s then return full end
    return pvp:sub(1, s - 1) .. full .. pvp:sub(e + 1)
end
