-- ============================================================
--  Commands.lua
--  Registro de comandos de chat (/wu). Open/Closed: cada módulo
--  registra seus próprios subcomandos, sem editar este arquivo.
-- ============================================================

local _, ns = ...
local L = ns.L

local Commands = {}
ns.Commands = Commands

local handlers, helps, default = {}, {}, nil

--- Registra /wu <nome> [argumento].
function Commands:Register(name, fn, help)
    handlers[name] = fn
    helps[#helps + 1] = { name = name, help = help }
end

--- Ação de "/wu" sem argumentos (abre a janela de configuração).
function Commands:SetDefault(fn)
    default = fn
end

local function PrintHelp()
    print("|cff66ccff" .. L["WowUtilities — commands:"] .. "|r")
    print("  " .. L["/wu — opens the settings"])
    for _, h in ipairs(helps) do
        print("  /wu " .. h.name .. (h.help and (" — " .. h.help) or ""))
    end
end

SLASH_WOWUTILITIES1 = "/wu"
SLASH_WOWUTILITIES2 = "/wowutilities"
SlashCmdList["WOWUTILITIES"] = function(msg)
    local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" then
        if default then default() else PrintHelp() end
    elseif handlers[cmd] then
        handlers[cmd](arg)
    else
        PrintHelp()
    end
end
