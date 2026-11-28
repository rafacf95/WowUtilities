-- ============================================================
--  DebugSwing.lua
--  /wu debug swing        relatório
--  /wu debug swing clear  zera a linha do tempo e as contagens
--  Diagnóstico para as futuras barras de swing timer (mão principal,
--  mão secundária e ataque à distância): velocidade de ataque e se ela
--  vem como valor secreto, armas equipadas, ataque automático ligado,
--  busca por nomes com "swing"/"autoattack"/"autoshot" (globais e frames,
--  funções das APIs C_ e CVars, caso o cliente tenha um swing timer
--  próprio) e uma linha do tempo dos eventos ligados a golpes, com o
--  intervalo entre eles para comparar com a velocidade.
--  NÃO ouve COMBAT_LOG_EVENT_UNFILTERED: no Forever registrar esse evento
--  é ação protegida (ADDON_ACTION_FORBIDDEN, confirmado no jogo); o
--  relatório só diz se as funções do log existem.
--  Só lê; não altera nada (o único efeito é ouvir os eventos).
--  Report monta as linhas (testável sem o jogo); o comando abre a
--  janela de texto copiável.
-- ============================================================

local _, ns = ...

local Swing = {}
ns.DebugSwing = Swing

local Show = ns.Debug.Show

local MAX_TIMELINE = 60 -- entradas guardadas na linha do tempo
local AUTO_ATTACK, AUTO_SHOT, SHOOT = 6603, 75, 5019

local API_CHECKS = {
    { "UnitAttackSpeed",                   { "UnitAttackSpeed" } },
    { "UnitRangedDamage",                  { "UnitRangedDamage" } },
    { "UnitDamage",                        { "UnitDamage" } },
    { "GetMeleeHaste",                     { "GetMeleeHaste" } },
    { "GetRangedHaste",                    { "GetRangedHaste" } },
    { "GetHaste",                          { "GetHaste" } },
    { "IsCurrentSpell",                    { "IsCurrentSpell" } },
    { "IsAutoRepeatSpell",                 { "IsAutoRepeatSpell" } },
    { "C_Spell.IsCurrentSpell",            { "C_Spell", "IsCurrentSpell" } },
    { "C_Spell.IsAutoRepeatSpell",         { "C_Spell", "IsAutoRepeatSpell" } },
    { "C_Spell.GetSpellInfo",              { "C_Spell", "GetSpellInfo" } },
    { "CombatLogGetCurrentEventInfo",      { "CombatLogGetCurrentEventInfo" } },
    { "C_CombatLog.GetCurrentEventInfo",   { "C_CombatLog", "GetCurrentEventInfo" } },
    { "GetTime",                           { "GetTime" } },
    { "GetInventoryItemLink",              { "GetInventoryItemLink" } },
    { "issecretvalue",                     { "issecretvalue" } },
}

local EVENTS = {
    "UNIT_COMBAT", "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT",
    "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL", "UNIT_ATTACK_SPEED", "UNIT_RANGEDDAMAGE",
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_FAILED", "CURRENT_SPELL_CAST_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_TARGET_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED",
}

-- Eventos de unidade: só os do jogador e do alvo entram na linha do tempo
local UNIT_EVENTS = {
    UNIT_COMBAT = true, UNIT_ATTACK_SPEED = true, UNIT_RANGEDDAMAGE = true,
    UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_SUCCEEDED = true, UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_INTERRUPTED = true, UNIT_SPELLCAST_FAILED = true, UNIT_INVENTORY_CHANGED = true,
}

local seen = {}      -- [evento] = { valid, err, count, last }
local timeline = {}  -- { t, text }
local lastSwing = {} -- [chave] = GetTime() do evento anterior (intervalo entre golpes)

local function Resolve(path)
    local value = _G
    for _, key in ipairs(path) do
        if type(value) ~= "table" then return nil end
        value = rawget(value, key)
    end
    return value
end

--- Chama sem SafeCall: devolve "ok", valores crus (podem ser secretos) ou "error", mensagem.
local function Raw(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local r = { pcall(fn, ...) }
    if not r[1] then return "error", tostring(r[2]):sub(1, 120) end
    return "ok", unpack(r, 2, 10)
end

--- Descreve até n valores crus: "1.8 | <secret> | nil".
local function Values(n, ...)
    local parts = {}
    for i = 1, n do parts[i] = Show((select(i, ...))) end
    return table.concat(parts, " | ")
end

local function Now()
    local ok, t = pcall(GetTime)
    return ok and type(t) == "number" and t or 0
end

local function Args(...)
    local parts = {}
    for i = 1, math.min(select("#", ...), 6) do parts[#parts + 1] = Show((select(i, ...))) end
    return table.concat(parts, ", ")
end

local function Add(text)
    timeline[#timeline + 1] = { t = Now(), text = text }
    if #timeline > MAX_TIMELINE then table.remove(timeline, 1) end
end

--- Intervalo desde o evento anterior do mesmo tipo (texto pronto).
local function Interval(key)
    local now, last = Now(), lastSwing[key]
    lastSwing[key] = now
    if not last then return "" end
    return string.format(" | +%.2fs since last %s", now - last, key)
end

local function OnEvent(_, event, ...)
    local entry = seen[event]
    if not entry then return end
    entry.count = entry.count + 1
    entry.last = Args(...)
    local unit = ...
    if UNIT_EVENTS[event] and unit ~= "player" and unit ~= "target" then return end
    local suffix = ""
    if event == "UNIT_COMBAT" then
        -- unit, action, indicator, amount, school: golpes no alvo (WOUND) e no jogador
        suffix = Interval("UNIT_COMBAT " .. tostring(unit))
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player" then
        local spellID = select(3, ...)
        if spellID == AUTO_SHOT or spellID == SHOOT then suffix = Interval("ranged (cast)") end
    end
    Add(event .. " (" .. Args(...) .. ")" .. suffix)
end

do
    local listener = CreateFrame("Frame")
    for _, event in ipairs(EVENTS) do
        local ok, err = pcall(listener.RegisterEvent, listener, event)
        seen[event] = { valid = ok, err = not ok and tostring(err):sub(1, 100) or nil, count = 0 }
    end
    listener:SetScript("OnEvent", OnEvent)
end

-- ----------------------------------------------------------------
-- Seções
-- ----------------------------------------------------------------

local function Environment(add)
    local version, build, _, toc = ns.SafeCall(GetBuildInfo)
    add(string.format("Game version: %s (build %s, interface %s)", Show(version), Show(build), Show(toc)))
    local _, class = ns.SafeCall(UnitClass, "player")
    add(string.format("Class %s | level %s | in combat %s | target %s (can attack %s)",
        Show(class), Show((ns.SafeCall(UnitLevel, "player"))), Show((ns.SafeCall(UnitAffectingCombat, "player"))),
        Show((ns.SafeCall(UnitName, "target"))), Show((ns.SafeCall(UnitCanAttack, "player", "target")))))
    add("Tip: /wu debug swing clear, attack a training dummy for ~20 s (melee; hunters also with Auto Shot), then /wu debug swing.")
    add("COMBAT_LOG_EVENT_UNFILTERED is not listened to: registering it is blocked for addons in this client.")
end

local function ApiPresence(add)
    add("")
    add("== API presence ==")
    for _, check in ipairs(API_CHECKS) do
        add(string.format("  %-34s %s", check[1], type(Resolve(check[2])) == "function" and "yes" or "MISSING"))
    end
    local combatLog = rawget(_G, "C_CombatLog")
    if type(combatLog) == "table" then
        local fns = {}
        pcall(function() for k, v in pairs(combatLog) do if type(v) == "function" then fns[#fns + 1] = tostring(k) end end end)
        table.sort(fns)
        add("  C_CombatLog functions: " .. (#fns > 0 and table.concat(fns, ", ") or "(none)"))
    else
        add("  C_CombatLog: MISSING")
    end
end

-- Termos procurados nos nomes globais, nas APIs C_ e nas CVars (o cliente
-- pode ter um swing timer próprio)
local SEARCH_TERMS = { "swing", "autoattack", "autoshot" }
local MAX_MATCHES = 80

local function Matches(name)
    if type(name) ~= "string" then return false end
    local lower = name:lower()
    for _, term in ipairs(SEARCH_TERMS) do
        if lower:find(term, 1, true) then return true end
    end
    return false
end

--- Descreve um global encontrado: tipo e, se for frame, tipo do objeto e visibilidade.
local function DescribeGlobal(name, value)
    local kind = type(value)
    if kind == "table" and type(value.GetObjectType) == "function" then
        local objectType = ns.SafeCall(value.GetObjectType, value)
        local shown = type(value.IsShown) == "function" and ns.SafeCall(value.IsShown, value)
        return string.format("%s = %s frame (IsShown %s)", name, Show(objectType), Show(shown))
    elseif kind == "table" then
        local fns = {}
        pcall(function() for k, v in pairs(value) do if type(v) == "function" then fns[#fns + 1] = tostring(k) end end end)
        table.sort(fns)
        return string.format("%s = table (%d functions%s)", name, #fns,
            #fns > 0 and (": " .. table.concat(fns, ", ", 1, math.min(#fns, 12))) or "")
    elseif kind == "function" then
        return name .. " = function"
    end
    return string.format("%s = %s %s", name, kind, Show(value))
end

local function Search(add)
    add("")
    add("== Search: names with " .. table.concat(SEARCH_TERMS, " / ") .. " ==")

    -- 1 e 2: frames e variáveis globais
    local globals = {}
    pcall(function()
        for key, value in pairs(_G) do
            if Matches(key) then globals[#globals + 1] = { key, value } end
        end
    end)
    table.sort(globals, function(a, b) return a[1] < b[1] end)
    add(string.format("Globals (%d):", #globals))
    for i = 1, math.min(#globals, MAX_MATCHES) do add("  " .. DescribeGlobal(globals[i][1], globals[i][2])) end
    if #globals > MAX_MATCHES then add("  ... +" .. (#globals - MAX_MATCHES)) end
    if #globals == 0 then add("  (none)") end

    -- 3: funções das APIs C_*
    local apis = {}
    pcall(function()
        for key, value in pairs(_G) do
            if type(key) == "string" and key:find("^C_") and type(value) == "table" then
                for name, fn in pairs(value) do
                    if Matches(name) then apis[#apis + 1] = key .. "." .. tostring(name) .. " (" .. type(fn) .. ")" end
                end
            end
        end
    end)
    table.sort(apis)
    add(string.format("C_ API functions (%d):", #apis))
    for i = 1, math.min(#apis, MAX_MATCHES) do add("  " .. apis[i]) end
    if #apis == 0 then add("  (none)") end

    -- 4: opções de console (CVars e comandos), com o valor atual
    local getAll = Resolve({ "C_Console", "GetAllCommands" }) or rawget(_G, "ConsoleGetAllCommands")
    if not getAll then
        add("Console commands: C_Console.GetAllCommands MISSING")
        return
    end
    local ok, list = pcall(getAll)
    if not ok or type(list) ~= "table" then
        add("Console commands: GetAllCommands failed: " .. Show(list))
        return
    end
    local getCVar = Resolve({ "C_CVar", "GetCVar" }) or rawget(_G, "GetCVar")
    local getDefault = Resolve({ "C_CVar", "GetCVarDefault" }) or rawget(_G, "GetCVarDefault")
    local cvars = {}
    for _, entry in ipairs(list) do
        local command = type(entry) == "table" and entry.command
        if Matches(command) then
            cvars[#cvars + 1] = string.format("%s | value %s | default %s | type %s | help %s", command,
                Show((ns.SafeCall(getCVar or function() end, command))),
                Show((ns.SafeCall(getDefault or function() end, command))),
                Show(entry.commandType), Show(entry.help))
        end
    end
    table.sort(cvars)
    add(string.format("Console commands / CVars (%d of %d):", #cvars, #list))
    for i = 1, math.min(#cvars, MAX_MATCHES) do add("  " .. cvars[i]) end
    if #cvars == 0 then add("  (none)") end
end

local function Speeds(add)
    add("")
    add("== Attack speed (raw values; <secret> = secret value) ==")
    local speed = rawget(_G, "UnitAttackSpeed")
    add("  UnitAttackSpeed(player)        " .. Values(2, select(2, Raw(speed, "player"))) ..
        "   [status " .. (Raw(speed, "player")) .. "]")
    add("  UnitRangedDamage(player)       " .. Values(6, select(2, Raw(rawget(_G, "UnitRangedDamage"), "player"))) ..
        "   (speed, min, max, bonus+, bonus-, percent)")
    add("  UnitDamage(player)             " .. Values(7, select(2, Raw(rawget(_G, "UnitDamage"), "player"))))
    for _, name in ipairs({ "GetMeleeHaste", "GetRangedHaste", "GetHaste" }) do
        add(string.format("  %-30s %s", name .. "()", Values(1, select(2, Raw(rawget(_G, name))))))
    end
    local status, main = Raw(speed, "player")
    if status == "ok" then
        local okMath, err = pcall(function() return main + 0 end)
        add("  arithmetic on main hand speed: " .. (okMath and "ok" or ("ERROR " .. tostring(err):sub(1, 80))))
    end
end

local function Weapons(add)
    add("")
    add("== Weapons ==")
    local instant = Resolve({ "C_Item", "GetItemInfoInstant" }) or rawget(_G, "GetItemInfoInstant")
    for _, slot in ipairs({ { 16, "main hand" }, { 17, "off hand" }, { 18, "ranged" } }) do
        local link = ns.SafeCall(GetInventoryItemLink, "player", slot[1])
        local equipLoc, subType
        if type(link) == "string" and instant then
            local _, _, sub, loc = ns.SafeCall(instant, link)
            equipLoc, subType = loc, sub
        end
        add(string.format("  slot %d (%s): %s | %s | %s", slot[1], slot[2], Show(link), Show(equipLoc), Show(subType)))
    end
end

local function AutoAttack(add)
    add("")
    add("== Auto attack / auto repeat ==")
    for _, spell in ipairs({ { AUTO_ATTACK, "Auto Attack" }, { AUTO_SHOT, "Auto Shot" }, { SHOOT, "Shoot (wand)" } }) do
        add(string.format("  %-14s id %-5d IsCurrentSpell %s | C_Spell.IsCurrentSpell %s | IsAutoRepeatSpell %s | C_Spell.IsAutoRepeatSpell %s",
            spell[2], spell[1],
            Values(1, select(2, Raw(rawget(_G, "IsCurrentSpell"), spell[1]))),
            Values(1, select(2, Raw(Resolve({ "C_Spell", "IsCurrentSpell" }), spell[1]))),
            Values(1, select(2, Raw(rawget(_G, "IsAutoRepeatSpell"), spell[1]))),
            Values(1, select(2, Raw(Resolve({ "C_Spell", "IsAutoRepeatSpell" }), spell[1])))))
    end
end

local function Events(add)
    add("")
    add("== Events (since load or clear: count | last args) ==")
    for _, event in ipairs(EVENTS) do
        local e = seen[event]
        if e.valid then
            add(string.format("  %-30s %d | %s", event, e.count, Show(e.last)))
        else
            add(string.format("  %-30s could not register: %s", event, Show(e.err)))
        end
    end
end

local function Timeline(add)
    add("")
    add(string.format("== Timeline (last %d player/target events; time relative to the last entry) ==", MAX_TIMELINE))
    if #timeline == 0 then add("  (empty)") return end
    local last = timeline[#timeline].t
    for _, entry in ipairs(timeline) do
        add(string.format("  %8.2f  %s", entry.t - last, entry.text))
    end
end

--- Monta o relatório como lista de linhas.
function Swing:Report()
    local lines = {}
    local function add(text) lines[#lines + 1] = text end
    add("WowUtilities swing timer debug (read-only; nothing is changed)")
    for _, section in ipairs({ Environment, ApiPresence, Search, Speeds, Weapons, AutoAttack, Events, Timeline }) do
        local ok, err = pcall(section, add)
        if not ok then add("  (section error: " .. tostring(err) .. ")") end
    end
    return lines
end

--- Zera a linha do tempo e as contagens (para gravar um teste limpo).
function Swing:Clear()
    wipe(timeline)
    wipe(lastSwing)
    for _, entry in pairs(seen) do entry.count = 0; entry.last = nil end
end

ns.Debug:Register("swing", function(arg)
    if type(arg) == "string" and arg:lower() == "clear" then
        Swing:Clear()
        print("|cff66ccffWowUtilities|r swing debug cleared. Attack something, then type /wu debug swing.")
        return
    end
    local ok, lines = pcall(Swing.Report, Swing)
    if not ok then lines = { "WowUtilities swing debug failed: " .. tostring(lines) } end
    ns.Debug:Output("WowUtilities debug — swing", lines)
end)
