-- ============================================================
--  DebugEditMode.lua
--  /wu debug editmode          relatório do estado
--  /wu debug editmode watch    liga/desliga o acompanhamento do arrasto
--  Diagnóstico do Edit Mode: o que o jogo e a LibEditMode informam e,
--  para cada frame registrado na biblioteca (barra de voo, seletor de
--  trinkets), o estado do frame e da área de seleção que o jogador
--  arrasta. Rode DENTRO do Edit Mode, com o layout que você usa. Só
--  lê; não altera nada. Report monta as linhas (testável sem o jogo);
--  o comando abre a janela de texto copiável.
-- ============================================================

local _, ns = ...

local EditMode = {}
ns.DebugEditMode = EditMode

local Show = ns.Debug.Show

local function Method(obj, name, ...)
    if type(obj) ~= "table" then return end
    local fn = obj[name]
    if type(fn) ~= "function" then return end
    return ns.SafeCall(fn, obj, ...)
end

local function Present(name)
    local v = rawget(_G, name)
    return type(v) == "table" or type(v) == "function"
end

local function Round(n)
    if type(n) ~= "number" then return n end
    return math.floor(n * 100 + 0.5) / 100
end

local function Library()
    local stub = rawget(_G, "LibStub")
    if type(stub) ~= "table" and type(stub) ~= "function" then return nil end
    local ok, lib, minor = pcall(function()
        local l, m = stub("LibEditMode", true)
        return l, m
    end)
    if ok and type(lib) == "table" then return lib, minor end
end

local function Environment(add, lib, minor)
    local version, build, _, toc = ns.SafeCall(GetBuildInfo)
    add(string.format("Game version: %s (build %s, interface %s)", Show(version), Show(build), Show(toc)))
    add("InCombatLockdown = " .. Show(ns.SafeCall(rawget(_G, "InCombatLockdown") or function() end)))
    local manager = rawget(_G, "EditModeManagerFrame")
    add(string.format("EditModeManagerFrame: %s | IsShown %s | C_EditMode %s",
        type(manager) == "table" and "present" or "ABSENT", Show(Method(manager, "IsShown")), Show(Present("C_EditMode"))))
    add(string.format("EditModeManagerFrame.ClearSelectedSystem: %s | EventRegistry: %s",
        Show(type(manager) == "table" and type(manager.ClearSelectedSystem) == "function"), Show(Present("EventRegistry"))))
    add(string.format("LibStub: %s | LibEditMode: %s (minor %s)",
        Show(Present("LibStub")), lib and "loaded" or "NOT loaded", Show(minor)))
end

local function Layouts(add, lib)
    add("")
    add("== Layouts ==")
    if not lib then add("  (library not loaded)") return end
    add(string.format("  IsInEditMode %s | GetActiveLayoutName %s | lib.activeLayout %s",
        Show(Method(lib, "IsInEditMode")), Show(Method(lib, "GetActiveLayoutName")), Show(lib.activeLayout)))
    local api = rawget(_G, "C_EditMode")
    local info = type(api) == "table" and type(api.GetLayouts) == "function" and ns.SafeCall(api.GetLayouts) or nil
    if type(info) == "table" then
        local custom, names, isCustom = type(info.layouts) == "table" and #info.layouts or 0, {}, false
        local active = Method(lib, "GetActiveLayoutName")
        for _, layout in ipairs(info.layouts or {}) do
            names[#names + 1] = tostring(layout.layoutName)
            if layout.layoutName == active then isCustom = true end
        end
        add(string.format("  C_EditMode.GetLayouts: activeLayout index %s | custom layouts %d (%s)",
            Show(info.activeLayout), custom, table.concat(names, ", ")))
        add("  ACTIVE LAYOUT IS " .. (isCustom and "a custom layout" or "NOT one of the custom layouts (a preset: Blizzard does not allow editing presets)"))
    else
        add("  C_EditMode.GetLayouts: no data")
    end
end

local function Describe(add, frame, selection)
    local point, relTo, relPoint, x, y = Method(frame, "GetPoint", 1)
    local relName = type(relTo) == "table" and Method(relTo, "GetName") or relTo
    add(string.format("  frame %s | IsShown %s | IsVisible %s | IsMovable %s | mouse %s | clamped %s",
        Show(Method(frame, "GetName")), Show(Method(frame, "IsShown")), Show(Method(frame, "IsVisible")),
        Show(Method(frame, "IsMovable")), Show(Method(frame, "IsMouseEnabled")), Show(Method(frame, "IsClampedToScreen"))))
    add(string.format("      point %s -> %s %s (%s, %s) | scale %s | strata %s | level %s | size %sx%s",
        Show(point), Show(relName), Show(relPoint), Show(Round(x)), Show(Round(y)), Show(Round(Method(frame, "GetScale"))),
        Show(Method(frame, "GetFrameStrata")), Show(Method(frame, "GetFrameLevel")),
        Show(Round(Method(frame, "GetWidth"))), Show(Round(Method(frame, "GetHeight"))))) 
    if type(selection) ~= "table" then add("      selection: none") return end
    add(string.format("      selection: IsShown %s | IsVisible %s | mouse %s | isSelected %s | strata %s | level %s | size %sx%s",
        Show(Method(selection, "IsShown")), Show(Method(selection, "IsVisible")), Show(Method(selection, "IsMouseEnabled")),
        Show(selection.isSelected), Show(Method(selection, "GetFrameStrata")), Show(Method(selection, "GetFrameLevel")),
        Show(Round(Method(selection, "GetWidth"))), Show(Round(Method(selection, "GetHeight")))))
    add(string.format("      selection scripts: OnMouseDown %s | OnDragStart %s | OnDragStop %s | RegisterForDrag %s",
        Show(Method(selection, "GetScript", "OnMouseDown") ~= nil), Show(Method(selection, "GetScript", "OnDragStart") ~= nil),
        Show(Method(selection, "GetScript", "OnDragStop") ~= nil), Show(type(selection.RegisterForDrag) == "function")))
end

local function Frames(add, lib)
    add("")
    add("== Frames registered in the library ==")
    if not lib or type(lib.frameSelections) ~= "table" then add("  (none visible)") return end
    local count = 0
    for frame, selection in pairs(lib.frameSelections) do
        count = count + 1
        Describe(add, frame, selection)
    end
    add("Registered frames: " .. count)
end

--- Monta o relatório como lista de linhas.
function EditMode:Report()
    local lines = {}
    local function add(text) lines[#lines + 1] = text end
    local lib, minor = Library()
    add("WowUtilities edit mode debug (read-only; nothing is changed)")
    Environment(add, lib, minor)
    Layouts(add, lib)
    Frames(add, lib)
    return lines
end


-- ----------------------------------------------------------------
-- Acompanhamento do arrasto: imprime no chat o que acontece quando o
-- jogador clica e arrasta uma área de seleção (só observa, via HookScript).
-- ----------------------------------------------------------------

local watching, hooked = false, {}

local function Say(text)
    print("|cff66ccffWowUtilities|r edit mode: " .. text)
end

local function PointText(frame)
    local point, _, relPoint, x, y = Method(frame, "GetPoint", 1)
    return string.format("%s/%s (%s, %s)", Show(point), Show(relPoint), Show(Round(x)), Show(Round(y)))
end

local function Trace(selection, frame, event)
    if not watching then return end
    local name = Method(frame, "GetName") or "?"
    Say(string.format("%s on %s | IsMovable %s | InCombat %s | at %s", event, name, Show(Method(frame, "IsMovable")),
        Show(ns.SafeCall(rawget(_G, "InCombatLockdown") or function() end)), PointText(frame)))
    if event == "OnDragStop" and C_Timer and C_Timer.After then
        C_Timer.After(0.2, function() if watching then Say(name .. " after the drop: " .. PointText(frame)) end end)
    end
end

function EditMode:Watch(lib)
    if not lib or type(lib.frameSelections) ~= "table" then
        Say("LibEditMode is not loaded; nothing to watch.")
        return
    end
    watching = not watching
    if not watching then Say("watching OFF") return end
    for frame, selection in pairs(lib.frameSelections) do
        if not hooked[selection] and type(selection.HookScript) == "function" then
            hooked[selection] = true
            for _, event in ipairs({ "OnMouseDown", "OnMouseUp", "OnDragStart", "OnDragStop" }) do
                selection:HookScript(event, function() Trace(selection, frame, event) end)
            end
        end
    end
    Say("watching ON. Open the Edit Mode, click and drag the bars, then copy the lines printed here.")
end

ns.Debug:Register("editmode", function(arg)
    if type(arg) == "string" and arg:lower():match("^%s*watch") then
        EditMode:Watch((Library()))
        return
    end
    local ok, lines = pcall(EditMode.Report, EditMode)
    if not ok then lines = { "WowUtilities edit mode debug failed: " .. tostring(lines) } end
    ns.Debug:Output("WowUtilities debug — edit mode", lines)
end)
