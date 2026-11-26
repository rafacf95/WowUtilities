-- ============================================================
--  TaxiCommand.lua
--  /wu taxi         — lista os tempos de voo gravados
--  /wu taxi clear   — apaga todos (pede confirmação)
-- ============================================================

local _, ns = ...
local L = ns.L

ns.Commands:Register("taxi", function(arg)
    local db = ns.TaxiDatabase
    if arg == "clear" then
        ns.TaxiClearConfirm:Request()
        return
    end

    local rows = {}
    db:Each(function(from, to, entry)
        rows[#rows + 1] = { from = from, to = to, entry = entry }
    end)
    table.sort(rows, function(a, b)
        return (a.from .. a.to) < (b.from .. b.to)
    end)

    print("|cff66ccffWowUtilities|r: " .. string.format(L["%d route(s) recorded."], #rows))
    for i, row in ipairs(rows) do
        if i > 20 then
            print("  " .. string.format(L["... and %d more."], #rows - 20))
            break
        end
        print("  " .. string.format(L["%s → %s: %s (%dx, %d leg(s))"], row.from, row.to,
            ns.FormatTime(row.entry.seconds), row.entry.count or 1, row.entry.hops or 1))
    end
end, L["lists recorded flight times (\"clear\" deletes)"])
