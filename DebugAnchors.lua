-- ============================================================
--  DebugAnchors.lua
--  /wu debug anchors
--  Diagnóstico para o recurso de "ancorar a barra em outro elemento do
--  Edit Mode": quais frames candidatos existem neste cliente, o tamanho,
--  a escala e o ponto de cada um, e quais a Blizzard registrou como
--  sistemas do Edit Mode. Rode no personagem e, se possível, também
--  DENTRO do Edit Mode. Só lê; não altera nada. Report monta as linhas
--  (testável sem o jogo); o comando abre a janela de texto copiável.
-- ============================================================

local _, ns = ...

local Anchors = {}
ns.DebugAnchors = Anchors

local Show = ns.Debug.Show

-- Nomes globais prováveis (versões modernas e clássicas). O que não existir
-- aparece como ABSENT, o que já informa a lista final.
local CANDIDATES = {
    "PlayerFrame", "TargetFrame", "FocusFrame", "PetFrame", "TargetFrameToT",
    "PartyFrame", "PartyMemberFrame1", "CompactRaidFrameContainer", "CompactPartyFrame",
    "PlayerCastingBarFrame", "CastingBarFrame", "PetCastingBarFrame",
    "MainMenuBar", "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight",
    "MultiBarLeft", "MultiBarRight", "MultiBar5", "MultiBar6", "MultiBar7",
    "StanceBar", "PetActionBar", "PossessActionBar", "OverrideActionBar",
    "MicroMenu", "MicroMenuContainer", "BagsBar", "StatusTrackingBarManager",
    "MainStatusTrackingBarContainer", "MainMenuExpBar", "ReputationWatchBar",
    "MinimapCluster", "Minimap", "BuffFrame", "DebuffFrame", "TemporaryEnchantFrame",
    "ObjectiveTrackerFrame", "QuestWatchFrame", "ChatFrame1", "GameTooltipDefaultContainer",
    "TalkingHeadFrame", "ExtraAbilityContainer", "ZoneAbilityFrame", "UIWidgetTopCenterContainerFrame",
    "DurabilityFrame", "VehicleSeatIndicator", "TotemFrame", "ArenaEnemyFramesContainer",
    "BossTargetFrameContainer", "LootFrame", "ActionBarController",
}

local function Method(obj, name, ...)
    if type(obj) ~= "table" then return end
    local fn = obj[name]
    if type(fn) ~= "function" then return end
    return ns.SafeCall(fn, obj, ...)
end

local function Round(n)
    if type(n) ~= "number" then return n end
    return math.floor(n * 100 + 0.5) / 100
end

local function PointText(frame)
    local count = Method(frame, "GetNumPoints")
    if type(count) ~= "number" or count < 1 then return "no points" end
    local parts = {}
    for i = 1, math.min(count, 2) do
        local point, relativeTo, relPoint, x, y = Method(frame, "GetPoint", i)
        local relName = type(relativeTo) == "table" and Method(relativeTo, "GetName") or "?"
        parts[#parts + 1] = string.format("%s -> %s/%s (%s, %s)", Show(point), Show(relName), Show(relPoint),
            Show(Round(x)), Show(Round(y)))
    end
    return table.concat(parts, "; ") .. (count > 2 and (" (+" .. (count - 2) .. ")") or "")
end

local function Describe(frame)
    return string.format("type %s | IsShown %s | IsVisible %s | size %s x %s | scale %s (effective %s) | protected %s | %s",
        Show(Method(frame, "GetObjectType")), Show(Method(frame, "IsShown")), Show(Method(frame, "IsVisible")),
        Show(Round(Method(frame, "GetWidth"))), Show(Round(Method(frame, "GetHeight"))),
        Show(Round(Method(frame, "GetScale"))), Show(Round(Method(frame, "GetEffectiveScale"))),
        Show(Method(frame, "IsProtected")), PointText(frame))
end

--- Frames que a Blizzard registrou como sistemas do Edit Mode, em tabela (frame -> true).
local function RegisteredSystems()
    local manager = rawget(_G, "EditModeManagerFrame")
    local set, list = {}, {}
    if type(manager) ~= "table" then return set, list, "EditModeManagerFrame ABSENT" end
    local source = manager.registeredSystemFrames
    if type(source) ~= "table" then
        local getter = manager.GetRegisteredSystemFrames
        source = type(getter) == "function" and ns.SafeCall(getter, manager) or nil
    end
    if type(source) ~= "table" then return set, list, "registeredSystemFrames not available" end
    for _, frame in pairs(source) do
        if type(frame) == "table" then
            set[frame] = true
            list[#list + 1] = frame
        end
    end
    return set, list, nil
end

local function Candidates(add, registered)
    add("")
    add("== Candidate frames (global name) ==")
    local present = 0
    for _, name in ipairs(CANDIDATES) do
        local frame = rawget(_G, name)
        if type(frame) == "table" and type(frame.GetObjectType) == "function" then
            present = present + 1
            add(string.format("%s: %s%s", name, registered[frame] and "[EDIT MODE SYSTEM] " or "", Describe(frame)))
        else
            add(name .. ": ABSENT")
        end
    end
    add(string.format("present: %d of %d", present, #CANDIDATES))
end

local function Systems(add, list, problem)
    add("")
    add("== Edit Mode system frames registered by Blizzard ==")
    if problem then add("  " .. problem) return end
    add("  count: " .. #list)
    local rows = {}
    for _, frame in ipairs(list) do
        local name = Method(frame, "GetName")
        local system = type(frame) == "table" and frame.system or nil
        rows[#rows + 1] = string.format("  %s | system %s | %s", Show(name or "(unnamed)"), Show(system), Describe(frame))
    end
    table.sort(rows)
    for _, row in ipairs(rows) do add(row) end
end

local function Library(add)
    add("")
    add("== LibEditMode (settings that the feature would use) ==")
    local stub = rawget(_G, "LibStub")
    local lib, minor
    if type(stub) == "table" or type(stub) == "function" then
        local ok, l, m = pcall(function() return stub("LibEditMode", true) end)
        if ok then lib, minor = l, m end
    end
    if type(lib) ~= "table" then add("  not loaded") return end
    add(string.format("  loaded (minor %s) | AddFrameSettings %s | RefreshFrameSettings %s", Show(minor),
        Show(type(lib.AddFrameSettings) == "function"), Show(type(lib.RefreshFrameSettings) == "function")))
    local types = {}
    for name in pairs(type(lib.SettingType) == "table" and lib.SettingType or {}) do types[#types + 1] = tostring(name) end
    table.sort(types)
    add("  SettingType: " .. (#types > 0 and table.concat(types, ", ") or "(none)"))
end

function Anchors:Report()
    local lines = {}
    local function add(text) lines[#lines + 1] = text end
    add("WowUtilities anchors diagnostic")
    add("UIParent: " .. Describe(rawget(_G, "UIParent")))
    local registered, list, problem = RegisteredSystems()
    Candidates(add, registered)
    Systems(add, list, problem)
    Library(add)
    return lines
end

ns.Debug:Register("anchors", function()
    local ok, lines = pcall(Anchors.Report, Anchors)
    if not ok then lines = { "WowUtilities anchors debug failed: " .. tostring(lines) } end
    ns.Debug:Output("WowUtilities debug — anchors", lines)
end)
