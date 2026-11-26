-- ============================================================
--  UnitResolver.lua
--  Traduz uma tooltip em informações sobre o jogador.
--  Responsabilidade única: ler dados de unit de forma segura.
--  Nenhuma chamada aqui pode propagar erro nem valor secreto.
-- ============================================================

local _, ns = ...

local UnitResolver = {}
ns.UnitResolver = UnitResolver

--- Obtém o token da unit (ex.: "mouseover") a partir da tooltip.
--- Retorna nil em contextos sem unit (SetWorldCursor, itens, etc.).
function UnitResolver:GetUnit(tooltip)
    -- GetUnit retorna (nome, unit). Só a unit interessa; o nome pode vir
    -- como secret e não deve invalidar o resultado.
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    if not ok or ns.IsSecret(unit) then return nil end
    if type(unit) ~= "string" or unit == "" then return nil end
    return unit
end

--- Monta o "perfil" do jogador usado pelos decorators.
--- Retorna nil se a unit não for um jogador legível.
function UnitResolver:Describe(unit)
    if not ns.Safe(UnitIsPlayer, unit) then return nil end

    local className, classFile = ns.Safe(UnitClass, unit)
    if type(classFile) ~= "string" then return nil end

    -- Título + nome (+ segundo nome no Forever). Pode ser nil para jogadores
    -- distantes sem dados; nesse caso a linha original da tooltip é preservada.
    local displayName = ns.NameResolver:Display(unit)

    -- Facção: english = "Horde"/"Alliance"; localized = texto exibido na tooltip
    local faction, factionName = ns.Safe(UnitFactionGroup, unit)
    if type(faction) ~= "string" then faction = nil end
    if type(factionName) ~= "string" then factionName = nil end

    return {
        faction     = faction,
        factionName = factionName,
        unit        = unit,
        className   = type(className) == "string" and className or nil,
        classFile   = classFile,
        displayName = displayName,
    }
end
