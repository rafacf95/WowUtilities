-- ============================================================
--  Anchoring.lua
--  Ancora um frame nosso em outro elemento do Edit Mode, usando a âncora
--  nativa do WoW: o frame acompanha o alvo sozinho, inclusive quando o
--  alvo é arrastado. Com "ajustar largura" o frame usa dois pontos (as
--  duas pontas do alvo) e o WoW calcula a largura, já compensando a
--  diferença de escala entre os dois.
--  Só conhece frames e geometria; quem guarda a configuração (por
--  layout) é o Positioner, e quem monta as opções é o AnchorSettings.
--
--  anchor = { target = "PlayerFrame", edge = "BELOW", x = 0, y = -2,
--             matchWidth = false }   (x, y em unidades da tela)
-- ============================================================

local _, ns = ...
local L = ns.L

local Anchoring = {}
ns.Anchoring = Anchoring

local MIN_MATCH_WIDTH = 40 -- alvo mais estreito (vazio, 1x1, em formação) não serve de régua
local MAX_STEPS = 40       -- limite da busca por dependência circular

-- Geometria de cada lado: ponto do nosso frame -> ponto do alvo. As entradas
-- "wide" são o par de pontos usado para acompanhar a largura do alvo.
local GEOMETRY = {
    BELOW = { own = "TOP",    target = "BOTTOM", x = 0,  y = -2,
              wideOwn = { "TOPLEFT", "TOPRIGHT" },       wideTarget = { "BOTTOMLEFT", "BOTTOMRIGHT" } },
    ABOVE = { own = "BOTTOM", target = "TOP",    x = 0,  y = 2,
              wideOwn = { "BOTTOMLEFT", "BOTTOMRIGHT" }, wideTarget = { "TOPLEFT", "TOPRIGHT" } },
    LEFT  = { own = "RIGHT",  target = "LEFT",   x = -2, y = 0 },
    RIGHT = { own = "LEFT",   target = "RIGHT",  x = 2,  y = 0 },
    OVER  = { own = "CENTER", target = "CENTER", x = 0,  y = 0,
              wideOwn = { "LEFT", "RIGHT" },             wideTarget = { "LEFT", "RIGHT" } },
}

Anchoring.DEFAULT_EDGE = "BELOW"
Anchoring.EDGES = {
    { id = "BELOW", label = L["Below"] },
    { id = "ABOVE", label = L["Above"] },
    { id = "LEFT",  label = L["Left side"] },
    { id = "RIGHT", label = L["Right side"] },
    { id = "OVER",  label = L["Over (centered)"] },
}

-- Nomes amigáveis dos elementos conhecidos; os demais aparecem pelo nome do frame.
local LABELS = {
    PlayerFrame = L["Player frame"], TargetFrame = L["Target frame"], FocusFrame = L["Focus frame"],
    PetFrame = L["Pet frame"], PartyFrame = L["Party frames"], CompactRaidFrameContainer = L["Raid frames"],
    PlayerCastingBarFrame = L["Player cast bar"],
    MainActionBar = L["Main action bar"], MultiBarBottomLeft = L["Action bar 2"],
    MultiBarBottomRight = L["Action bar 3"], MultiBarRight = L["Action bar 4"], MultiBarLeft = L["Action bar 5"],
    MultiBar5 = L["Action bar 6"], MultiBar6 = L["Action bar 7"], MultiBar7 = L["Action bar 8"],
    StanceBar = L["Stance bar"], PetActionBar = L["Pet action bar"], MultiCastActionBarFrame = L["Totem bar"],
    MicroMenuContainer = L["Micro menu"], BagsBar = L["Bags bar"],
    MainStatusTrackingBarContainer = L["Experience bar"],
    SecondaryStatusTrackingBarContainer = L["Second tracking bar"],
    MinimapCluster = L["Minimap"], BuffFrame = L["Buffs"], DebuffFrame = L["Debuffs"],
    ObjectiveTrackerFrame = L["Objective tracker"], ChatFrame1 = L["Chat"], DamageMeter = L["Damage meter"],
    EssentialCooldownViewer = L["Essential cooldowns"], UtilityCooldownViewer = L["Utility cooldowns"],
    BuffIconCooldownViewer = L["Buff icons"], BuffBarCooldownViewer = L["Buff bars"],
    PersonalResourceDisplayFrame = L["Personal resource display"],
    SwingTimerMainHandFrame = L["Swing timer (main hand)"], SwingTimerOffHandFrame = L["Swing timer (off hand)"],
    SwingTimerRangedFrame = L["Swing timer (ranged)"],
    GameTooltipDefaultContainer = L["Tooltip"], ExtraAbilityContainer = L["Extra ability button"],
    EncounterBar = L["Encounter bar"], DurabilityFrame = L["Durability"], LossOfControlFrame = L["Loss of control"],
}

-- Elementos do Edit Mode que não servem de âncora (botões soltos, avisos passageiros)
local DENY = {
    MainMenuBarVehicleLeaveButton = true, GamepadMainActionBarFrame = true, QueueStatusButton = true,
    MirrorTimerContainer = true, RaidWarningFrame = true, ArcheologyDigsiteProgressBar = true,
    LootFrame = true, TalkingHeadFrame = true, VehicleSeatIndicator = true, ExternalDefensivesFrame = true,
}

function Anchoring:CanMatchWidth(edge)
    local geometry = GEOMETRY[edge]
    return geometry ~= nil and geometry.wideOwn ~= nil
end

--- A configuração pede para acompanhar a largura do alvo (e o lado permite)?
function Anchoring:UsesWidth(anchor)
    return anchor ~= nil and anchor.matchWidth == true and self:CanMatchWidth(anchor.edge)
end

--- Deslocamento inicial de cada lado (um respiro de 2 px do alvo).
function Anchoring:DefaultOffset(edge)
    local geometry = GEOMETRY[edge] or GEOMETRY[Anchoring.DEFAULT_EDGE]
    return geometry.x, geometry.y
end

-- ----------------------------------------------------------------
-- Alvos
-- ----------------------------------------------------------------

--- Elementos do Edit Mode (da Blizzard e de outros addons que usam a LibEditMode)
--- que podem ser alvo. `exclude`: conjunto de frames nossos (frame -> true).
--- Devolve { { id = nome do frame, label } } em ordem alfabética.
function Anchoring:Targets(exclude, lib)
    local found, list = {}, {}
    local function Consider(frame)
        if type(frame) ~= "table" or type(frame.GetName) ~= "function" then return end
        local ok, name = pcall(frame.GetName, frame)
        if not ok or type(name) ~= "string" or found[name] or DENY[name] then return end
        if name:find("^WowUtilities") or (exclude and exclude[frame]) then return end
        found[name] = true
        list[#list + 1] = { id = name, label = LABELS[name] or name }
    end

    local manager = rawget(_G, "EditModeManagerFrame")
    if type(manager) == "table" and type(manager.registeredSystemFrames) == "table" then
        for _, frame in pairs(manager.registeredSystemFrames) do Consider(frame) end
    end
    if type(lib) == "table" and type(lib.frameSelections) == "table" then
        for frame in pairs(lib.frameSelections) do Consider(frame) end
    end
    table.sort(list, function(a, b) return a.label:lower() < b.label:lower() end)
    return list
end

--- O alvo depende de `owner` (âncora ou pai)? O WoW recusa ancorar em algo
--- que depende do próprio frame.
local function DependsOn(target, owner)
    local stack, seen, steps = { target }, {}, 0
    while #stack > 0 and steps < MAX_STEPS do
        steps = steps + 1
        local current = table.remove(stack)
        if not seen[current] then
            seen[current] = true
            local count = type(current.GetNumPoints) == "function" and current:GetNumPoints() or 0
            for i = 1, count do
                local _, relativeTo = current:GetPoint(i)
                if relativeTo == owner then return true end
                if type(relativeTo) == "table" and relativeTo ~= UIParent then stack[#stack + 1] = relativeTo end
            end
            local parent = type(current.GetParent) == "function" and current:GetParent() or nil
            if parent == owner then return true end
            if type(parent) == "table" and parent ~= UIParent then stack[#stack + 1] = parent end
        end
    end
    return false
end

--- O frame do alvo, ou nil se ele não existe neste cliente ou não pode ser âncora.
function Anchoring:Resolve(id, owner)
    if type(id) ~= "string" then return nil end
    local frame = rawget(_G, id)
    if type(frame) ~= "table" or type(frame.GetObjectType) ~= "function" or type(frame.GetPoint) ~= "function" then
        return nil
    end
    if frame == owner then return nil end
    local ok, circular = pcall(DependsOn, frame, owner)
    if not ok or circular then return nil end
    return frame
end

-- ----------------------------------------------------------------
-- Aplicar
-- ----------------------------------------------------------------

-- Com "ajustar largura", o frame se refaz quando o alvo muda de tamanho
-- (o alvo pode estar vazio ou em formação e depois crescer).
local watchers, hooked, watching = {}, {}, {}

local function Unwatch(frame)
    local target = watching[frame]
    if target and watchers[target] then watchers[target][frame] = nil end
    watching[frame] = nil
end

local function Watch(frame, target, again)
    watching[frame] = target
    watchers[target] = watchers[target] or {}
    watchers[target][frame] = again
    if hooked[target] or type(target.HookScript) ~= "function" then return end
    hooked[target] = true
    pcall(target.HookScript, target, "OnSizeChanged", function()
        for _, fn in pairs(watchers[target]) do pcall(fn) end
    end)
end

--- Ancora o frame. `scale`: escala do frame (os deslocamentos são guardados em
--- unidades da tela). `again`: o que refazer quando o alvo mudar de tamanho.
--- Devolve false se não foi possível (alvo ausente, circular...); o chamador
--- então usa a posição normal.
function Anchoring:Apply(frame, anchor, scale, again)
    Unwatch(frame)
    local target = self:Resolve(anchor.target, frame)
    if not target then return false end
    local geometry = GEOMETRY[anchor.edge] or GEOMETRY[Anchoring.DEFAULT_EDGE]
    local x, y = (anchor.x or 0) / scale, (anchor.y or 0) / scale

    local width = type(target.GetWidth) == "function" and target:GetWidth() or nil
    local wide = self:UsesWidth(anchor) and type(width) == "number" and width >= MIN_MATCH_WIDTH

    local ok = pcall(function()
        frame:ClearAllPoints()
        if wide then
            frame:SetPoint(geometry.wideOwn[1], target, geometry.wideTarget[1], x, y)
            frame:SetPoint(geometry.wideOwn[2], target, geometry.wideTarget[2], x, y)
        else
            frame:SetPoint(geometry.own, target, geometry.target, x, y)
        end
    end)
    if not ok then return false end
    if self:UsesWidth(anchor) and again then Watch(frame, target, again) end
    return true
end

-- ----------------------------------------------------------------
-- Arrastar com âncora
-- ----------------------------------------------------------------

--- Posição de um ponto do frame na tela (pixels), ou nil se ainda não tem geometria.
local function ScreenPoint(frame, point)
    local left, right = frame:GetLeft(), frame:GetRight()
    local top, bottom = frame:GetTop(), frame:GetBottom()
    if not (left and right and top and bottom) then return nil end
    local scale = frame:GetEffectiveScale()
    local x = (point:find("LEFT") and left) or (point:find("RIGHT") and right) or (left + right) / 2
    local y = (point:find("TOP") and top) or (point:find("BOTTOM") and bottom) or (top + bottom) / 2
    return x * scale, y * scale
end

--- Deslocamento (unidades da tela) do frame, na posição em que está agora, em
--- relação ao ponto do alvo. Usado quando o jogador solta o frame no Edit Mode.
function Anchoring:OffsetFromPosition(frame, target, anchor)
    local geometry = GEOMETRY[anchor.edge] or GEOMETRY[Anchoring.DEFAULT_EDGE]
    local wide = self:UsesWidth(anchor)
    local ownX, ownY = ScreenPoint(frame, wide and geometry.wideOwn[1] or geometry.own)
    local targetX, targetY = ScreenPoint(target, wide and geometry.wideTarget[1] or geometry.target)
    if not (ownX and targetX) then return nil end
    local ui = UIParent:GetEffectiveScale()
    return (ownX - targetX) / ui, (ownY - targetY) / ui
end
