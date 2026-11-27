-- ============================================================
--  DebugPower.lua
--  /wu debug power
--  Diagnóstico para a futura barra de recurso (mana, rage, energy, pontos
--  de combo): tipo de recurso atual e forma (druida), valor e máximo de
--  cada tipo, pontos de combo pelos dois caminhos (GetComboPoints e
--  UnitPower), cores do jogo (PowerBarColor), quais APIs e eventos
--  existem (e quantas vezes cada evento chegou desde o carregamento) e
--  os frames de recurso da Blizzard. Só lê; não altera nada (o único
--  efeito é ouvir os eventos para contá-los). Report monta as linhas
--  (testável sem o jogo); o comando abre a janela de texto copiável.
-- ============================================================

local _, ns = ...

local Power = {}
ns.DebugPower = Power

local Show = ns.Debug.Show

local MAX_TYPE = 25 -- tipos de recurso testados: 0..MAX_TYPE

local API_CHECKS = {
    { "UnitPower",                        { "UnitPower" } },
    { "UnitPowerMax",                     { "UnitPowerMax" } },
    { "UnitPowerType",                    { "UnitPowerType" } },
    { "UnitPowerDisplayMod",              { "UnitPowerDisplayMod" } },
    { "UnitPartialPower",                 { "UnitPartialPower" } },
    { "GetComboPoints",                   { "GetComboPoints" } },
    { "GetShapeshiftForm",                { "GetShapeshiftForm" } },
    { "GetShapeshiftFormID",              { "GetShapeshiftFormID" } },
    { "GetShapeshiftFormInfo",            { "GetShapeshiftFormInfo" } },
    { "GetPowerRegen",                    { "GetPowerRegen" } },
    { "GetPowerRegenForPowerType",        { "GetPowerRegenForPowerType" } },
    { "GetManaRegen",                     { "GetManaRegen" } },
    { "GetUnitPowerBarInfo",              { "GetUnitPowerBarInfo" } },
    { "UnitAffectingCombat",              { "UnitAffectingCombat" } },
    { "IsResting",                        { "IsResting" } },
    { "GetSpecialization",                { "GetSpecialization" } },
    { "C_SpecializationInfo.GetSpecialization", { "C_SpecializationInfo", "GetSpecialization" } },
}

local EVENTS = {
    "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
    "UNIT_POWER_POINT_CHARGE", "UNIT_COMBO_POINTS", "PLAYER_TARGET_CHANGED",
    "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED",
}

local FRAMES = {
    "PlayerFrame", "PlayerFrameManaBar", "PlayerFrameAlternateManaBar", "AlternatePowerBar",
    "ComboFrame", "ComboPointPlayerFrame", "RogueComboPointBarFrame", "DruidComboPointBarFrame",
    "ClassNameplateBarRogueDruidFrame", "PersonalResourceDisplayFrame", "PlayerPowerBarAlt",
    "PaladinPowerBarFrame", "TotemFrame",
}

local COLOR_KEYS = { "MANA", "RAGE", "FOCUS", "ENERGY", "COMBO_POINTS", "RUNIC_POWER", "HAPPINESS", 0, 1, 2, 3, 4 }

-- Contagem dos eventos desde o carregamento: [evento] = { valid, count, player, last }
local seen = {}

local function Resolve(path)
    local value = _G
    for _, key in ipairs(path) do
        if type(value) ~= "table" then return nil end
        value = rawget(value, key)
    end
    return value
end

local function Call(fn, ...)
    if not fn then return end
    return ns.SafeCall(fn, ...)
end

local function Method(obj, name, ...)
    if type(obj) ~= "table" then return end
    local fn = obj[name]
    if type(fn) ~= "function" then return end
    return ns.SafeCall(fn, obj, ...)
end

local function Args(...)
    local parts = {}
    for i = 1, math.min(select("#", ...), 4) do parts[#parts + 1] = Show((select(i, ...))) end
    return table.concat(parts, ", ")
end

do
    local listener = CreateFrame("Frame")
    for _, event in ipairs(EVENTS) do
        seen[event] = { valid = pcall(listener.RegisterEvent, listener, event), count = 0, player = 0 }
    end
    listener:SetScript("OnEvent", function(_, event, ...)
        local entry = seen[event]
        if not entry then return end
        entry.count = entry.count + 1
        local unit = ...
        if unit == "player" or (type(unit) ~= "string") then
            entry.player = entry.player + 1
            entry.last = Args(...)
        end
    end)
end

--- Nome do tipo de recurso no Enum.PowerType (ex.: 0 -> "Mana").
local function TypeNames()
    local names = {}
    local enum = Resolve({ "Enum", "PowerType" })
    if type(enum) == "table" then
        for key, value in pairs(enum) do
            if type(value) == "number" then names[value] = names[value] and (names[value] .. "/" .. key) or key end
        end
    end
    return names, type(enum) == "table"
end

local function Environment(add)
    local version, build, _, toc = ns.SafeCall(GetBuildInfo)
    add(string.format("Game version: %s (build %s, interface %s)", Show(version), Show(build), Show(toc)))
    local classLocal, classToken = Call(Resolve({ "UnitClass" }), "player")
    add(string.format("Class: %s (%s) | level %s", Show(classLocal), Show(classToken),
        Show((Call(Resolve({ "UnitLevel" }), "player")))))
    local powerType, token, r, g, b = Call(Resolve({ "UnitPowerType" }), "player")
    add(string.format("UnitPowerType: %s (%s) | alt color %s,%s,%s", Show(powerType), Show(token), Show(r), Show(g), Show(b)))
    add("GetShapeshiftForm " .. Show((Call(Resolve({ "GetShapeshiftForm" })))) ..
        " | GetShapeshiftFormID " .. Show((Call(Resolve({ "GetShapeshiftFormID" })))))
    add("In combat " .. Show((Call(Resolve({ "UnitAffectingCombat" }), "player"))) ..
        " | resting " .. Show((Call(Resolve({ "IsResting" })))) ..
        " | GetPowerRegen " .. Args(Call(Resolve({ "GetPowerRegen" }))))
end

local function ApiPresence(add)
    add("")
    add("== API presence ==")
    for _, check in ipairs(API_CHECKS) do
        add(string.format("  %-42s %s", check[1], type(Resolve(check[2])) == "function" and "yes" or "MISSING"))
    end
end

local function PowerTypes(add)
    add("")
    local names, hasEnum = TypeNames()
    add("== Power types (Enum.PowerType " .. (hasEnum and "present" or "MISSING") .. "; only types with max > 0) ==")
    local power, maxPower = Resolve({ "UnitPower" }), Resolve({ "UnitPowerMax" })
    local listed = 0
    for t = 0, MAX_TYPE do
        local max = Call(maxPower, "player", t)
        if type(max) == "number" and max > 0 then
            listed = listed + 1
            add(string.format("  %2d %-16s %s / %s | unmodified %s / %s", t, names[t] or "?",
                Show((Call(power, "player", t))), Show(max),
                Show((Call(power, "player", t, true))), Show((Call(maxPower, "player", t, true)))))
        end
    end
    add("Types with max > 0: " .. listed)
    local list = {}
    for t = 0, MAX_TYPE do if names[t] then list[#list + 1] = t .. "=" .. names[t] end end
    add("Enum.PowerType: " .. (#list > 0 and table.concat(list, ", ") or "(none)"))
end

local function ComboPoints(add)
    add("")
    add("== Combo points ==")
    local exists = Call(Resolve({ "UnitExists" }), "target")
    add("target exists " .. Show(exists) .. " | UnitCanAttack " ..
        Show((Call(Resolve({ "UnitCanAttack" }), "player", "target"))))
    add("GetComboPoints(player, target) " .. Show((Call(Resolve({ "GetComboPoints" }), "player", "target"))))
    local combo = Resolve({ "Enum", "PowerType", "ComboPoints" })
    local t = type(combo) == "number" and combo or 4
    add(string.format("UnitPower(player, %d) %s | UnitPowerMax %s", t,
        Show((Call(Resolve({ "UnitPower" }), "player", t))), Show((Call(Resolve({ "UnitPowerMax" }), "player", t)))))
    add("UnitPartialPower(player, " .. t .. ") " .. Show((Call(Resolve({ "UnitPartialPower" }), "player", t))))
end

local function Colors(add)
    add("")
    local colors = Resolve({ "PowerBarColor" })
    add("== PowerBarColor " .. (type(colors) == "table" and "present" or "MISSING") .. " ==")
    if type(colors) ~= "table" then return end
    for _, key in ipairs(COLOR_KEYS) do
        local c = colors[key]
        if type(c) == "table" then
            add(string.format("  %-14s %s, %s, %s | atlas %s", tostring(key), Show(c.r), Show(c.g), Show(c.b), Show(c.atlas)))
        else
            add(string.format("  %-14s absent", tostring(key)))
        end
    end
end

local function Events(add)
    add("")
    add("== Events (since load: total | player/no unit | last player args) ==")
    for _, event in ipairs(EVENTS) do
        local e = seen[event]
        if e.valid then
            add(string.format("  %-30s %d | %d | %s", event, e.count, e.player, Show(e.last)))
        else
            add(string.format("  %-30s could not register", event))
        end
    end
end

local function Frames(add)
    add("")
    add("== Blizzard resource frames ==")
    for _, name in ipairs(FRAMES) do
        local frame = rawget(_G, name)
        if type(frame) ~= "table" then
            add(string.format("  %-34s absent", name))
        else
            add(string.format("  %-34s IsShown %s | IsVisible %s | objectType %s | size %sx%s", name,
                Show(Method(frame, "IsShown")), Show(Method(frame, "IsVisible")), Show(Method(frame, "GetObjectType")),
                Show(Method(frame, "GetWidth")), Show(Method(frame, "GetHeight"))))
        end
    end
    local player = rawget(_G, "PlayerFrame")
    if type(player) == "table" then
        local keys = {}
        pcall(function()
            for key, value in pairs(player) do
                if type(key) == "string" and type(value) == "table" and (key:lower():find("mana") or key:lower():find("power")) then
                    keys[#keys + 1] = key
                end
            end
        end)
        table.sort(keys)
        add("PlayerFrame mana/power fields: " .. (#keys > 0 and table.concat(keys, ", ") or "(none)"))
    end
end

--- Descreve um valor cru (sem SafeCall): tipo e se é secreto.
local function Raw(value)
    local secret = ns.IsSecret(value)
    if secret then return "<secret> (type " .. type(value) .. ")" end
    return tostring(value) .. " (type " .. type(value) .. ")"
end

--- pcall que descreve o resultado: "ok -> valor" ou "ERROR msg".
local function Try(fn, ...)
    local ok, a = pcall(fn, ...)
    if not ok then return "ERROR " .. tostring(a):sub(1, 120) end
    return "ok -> " .. Raw(a)
end

--- O recurso vem como valor secreto? O que dá para fazer com ele?
local function Secrets(add)
    add("")
    add("== Secret values ==")
    for _, name in ipairs({ "issecretvalue", "canaccessvalue", "canaccesssecrets", "issecrettable",
                            "UnitPowerPercent", "UnitPowerMissing", "AbbreviateNumbers", "BreakUpLargeNumbers" }) do
        add(string.format("  %-22s %s", name, type(rawget(_G, name)) == "function" and "yes" or "MISSING"))
    end
    add("  C_CurveUtil " .. (type(rawget(_G, "C_CurveUtil")) == "table" and "yes" or "MISSING") ..
        " | CurveConstants " .. (type(rawget(_G, "CurveConstants")) == "table" and "yes" or "MISSING") ..
        " | Enum.StatusBarInterpolation " .. (type(Resolve({ "Enum", "StatusBarInterpolation" })) == "table" and "yes" or "MISSING"))

    local unitPower = Resolve({ "UnitPower" })
    local powerType = Call(Resolve({ "UnitPowerType" }), "player") or 0
    if not unitPower then return end
    local okRaw, raw = pcall(unitPower, "player", powerType)
    local _, rawMax = pcall(Resolve({ "UnitPowerMax" }), "player", powerType)
    add("  raw UnitPower(player, " .. powerType .. ") " .. (okRaw and Raw(raw) or "ERROR") .. " | raw UnitPowerMax " .. Raw(rawMax))
    local _, combo = pcall(unitPower, "player", 4)
    add("  raw UnitPower(player, 4) " .. Raw(combo))
    local _, target = pcall(unitPower, "target")
    add("  raw UnitPower(target) " .. Raw(target))
    local percent = Resolve({ "UnitPowerPercent" })
    if percent then add("  UnitPowerPercent(player) " .. Try(percent, "player", powerType)) end
    local missing = Resolve({ "UnitPowerMissing" })
    if missing then add("  UnitPowerMissing(player) " .. Try(missing, "player", powerType)) end

    add("  math: raw + 0 " .. Try(function() return raw + 0 end) ..
        " | raw > 0 " .. Try(function() return raw > 0 end))
    add("  tostring(raw) " .. Try(tostring, raw) ..
        " | string.format(\"%d\", raw) " .. Try(string.format, "%d", raw))
    local abbreviate = rawget(_G, "AbbreviateNumbers")
    if type(abbreviate) == "function" then add("  AbbreviateNumbers(raw) " .. Try(abbreviate, raw)) end

    -- Widgets escondidos: aceitam o valor secreto?
    local holder = CreateFrame("Frame", nil, UIParent)
    holder:Hide()
    local okBar, bar = pcall(CreateFrame, "StatusBar", nil, holder)
    if okBar and type(bar) == "table" then
        add("  StatusBar:SetMinMaxValues(0, max) " .. Try(bar.SetMinMaxValues, bar, 0, rawMax or 100))
        add("  StatusBar:SetValue(raw) " .. Try(bar.SetValue, bar, raw))
        add("  StatusBar:GetValue() " .. Try(bar.GetValue, bar))
        local interp = Resolve({ "Enum", "StatusBarInterpolation" })
        if type(interp) == "table" then
            local names = {}
            for key, value in pairs(interp) do names[#names + 1] = key .. "=" .. tostring(value) end
            table.sort(names)
            add("  Enum.StatusBarInterpolation: " .. table.concat(names, ", "))
            local smooth = interp.ExponentialEaseOut or interp.Immediate
            add("  StatusBar:SetValue(raw, interpolation) " .. Try(bar.SetValue, bar, raw, smooth))
        end
    else
        add("  StatusBar: could not create")
    end
    local text = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    add("  FontString:SetText(raw) " .. Try(text.SetText, text, raw))
    add("  FontString:SetFormattedText(\"%d / %d\", raw, max) " .. Try(text.SetFormattedText, text, "%d / %d", raw, rawMax or 0))
    add("  FontString:GetText() " .. Try(text.GetText, text))
    if percent then
        local okP, p = pcall(percent, "player", powerType)
        if okP then add("  FontString:SetFormattedText(\"%d%%\", percent) " .. Try(text.SetFormattedText, text, "%d%%", p)) end
    end
end

--- Monta o relatório como lista de linhas.
function Power:Report()
    local lines = {}
    local function add(text) lines[#lines + 1] = text end
    add("WowUtilities power debug (read-only; nothing is changed)")
    add("Best: run it on a Rogue with a target and some combo points, and on a mana class (Druid: in each form).")
    Environment(add)
    ApiPresence(add)
    PowerTypes(add)
    ComboPoints(add)
    Secrets(add)
    Colors(add)
    Events(add)
    Frames(add)
    return lines
end

ns.Debug:Register("power", function()
    local ok, lines = pcall(Power.Report, Power)
    if not ok then lines = { "WowUtilities power debug failed: " .. tostring(lines) } end
    ns.Debug:Output("WowUtilities debug — power", lines)
end)
