-- ============================================================
--  Debug.lua
--  /wu debug [unit]       — mostra o que cada API devolve para a unit.
--  /wu debug <subsistema> — diagnósticos registrados por outros arquivos
--                           (ex.: "wardrobe").
--  Os relatórios abrem numa janela de texto para copiar e colar.
--  Fora do fluxo normal do addon. Só em inglês.
-- ============================================================

local _, ns = ...

local Debug = {}
ns.Debug = Debug

local subcommands = {}

--- Registra /wu debug <nome> [argumento].
function Debug:Register(name, fn)
    subcommands[name:lower()] = fn
end

function Debug.Show(value)
    if ns.IsSecret(value) then return "<secret>" end
    return tostring(value)
end

--- Entrega o relatório (lista de linhas) à janela de texto copiável.
function Debug:Output(title, lines)
    ns.TextWindow:Show(title, table.concat(lines, "\n"))
end

local Show = Debug.Show

local function Row(label, ...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = Show((select(i, ...))) end
    return string.format("%s = %s", label, table.concat(parts, " | "))
end

local function Dump(unit)
    local lines = {}
    if not UnitExists(unit) then
        lines[1] = "WowUtilities: unit '" .. unit .. "' does not exist."
        Debug:Output("WowUtilities debug", lines)
        return
    end
    local guid = ns.SafeCall(UnitGUID, unit)
    lines[#lines + 1] = "WowUtilities debug — unit: " .. unit .. ""
    lines[#lines + 1] = Row("UnitName", ns.SafeCall(UnitName, unit))
    lines[#lines + 1] = Row("UnitFullName", ns.SafeCall(UnitFullName, unit))
    lines[#lines + 1] = Row("UnitPVPName", ns.SafeCall(UnitPVPName, unit))
    lines[#lines + 1] = Row("GetUnitName(unit,true)", ns.SafeCall(GetUnitName, unit, true))
    lines[#lines + 1] = Row("GetPlayerInfoByGUID (name, second name)", select(6, ns.SafeCall(GetPlayerInfoByGUID, guid)))
    lines[#lines + 1] = Row("UnitFactionGroup", ns.SafeCall(UnitFactionGroup, unit))
    lines[#lines + 1] = Row("UnitIsVisible", ns.SafeCall(UnitIsVisible, unit))
    lines[#lines + 1] = Row("Resolved", ns.NameResolver:Display(unit))
    Debug:Output("WowUtilities debug — " .. unit, lines)
end

ns.Commands:Register("debug", function(arg)
    local sub, rest = arg:match("^(%S+)%s*(.-)$")
    local handler = sub and subcommands[sub:lower()]
    if handler then
        handler(rest)
    else
        Dump(arg ~= "" and arg or "target")
    end
end, "shows what the APIs return for a unit (/wu debug party2) or a subsystem (/wu debug wardrobe, /wu debug trinkets, /wu debug bags, /wu debug character, /wu debug enchants, /wu debug editmode, /wu debug anchors, /wu debug ui)")
