-- ============================================================
--  NpcBorder.lua
--  Pinta a borda da tooltip de NPCs elite (dourada) e raros (prateada).
--  Três partes, cada uma trocável sem tocar nas outras:
--    * GROUPS      — classificação do jogo -> grupo de configuração
--                    (Strategy: um tipo novo é uma linha nova);
--    * painters    — como colorir a borda neste cliente (Adapter);
--    * NpcBorder   — decide, pinta e restaura.
--  A GameTooltip é reaproveitada para tudo; por isso a cor volta ao
--  normal quando a tooltip é limpa ou escondida.
-- ============================================================

local _, ns = ...

local NpcBorder = {}
ns.NpcBorder = NpcBorder

-- UnitClassification -> grupo (chaves "tooltip.<grupo>Border" e "tooltip.<grupo>Color")
local GROUPS = {
    elite     = "elite",
    worldboss = "elite",
    rare      = "rare",
    rareelite = "rare",
}

local DEFAULT_BORDER = { 1, 1, 1 } -- cor padrão da borda da tooltip

-- Formas conhecidas de colorir a borda; a primeira que o frame suportar vence.
local painters = {
    -- Tooltips modernas (NineSlice)
    function(tooltip, r, g, b)
        local nine = tooltip.NineSlice
        if type(nine) == "table" and type(nine.SetBorderColor) == "function" then
            nine:SetBorderColor(r, g, b, 1)
            return true
        end
    end,
    -- Tooltips com backdrop
    function(tooltip, r, g, b)
        if type(tooltip.SetBackdropBorderColor) == "function" then
            tooltip:SetBackdropBorderColor(r, g, b, 1)
            return true
        end
    end,
}

local painted = false

local function Paint(tooltip, r, g, b)
    for _, painter in ipairs(painters) do
        local ok, done = pcall(painter, tooltip, r, g, b)
        if ok and done then return true end
    end
    return false
end

--- Cor padrão da borda neste cliente (TOOLTIP_DEFAULT_COLOR, se existir).
local function DefaultColor()
    local c = rawget(_G, "TOOLTIP_DEFAULT_COLOR")
    if type(c) == "table" and type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then
        return c.r, c.g, c.b
    end
    return DEFAULT_BORDER[1], DEFAULT_BORDER[2], DEFAULT_BORDER[3]
end

--- Grupo ("elite"/"rare") da unit, ou nil se não for um NPC destacável.
function NpcBorder:GroupOf(unit)
    if ns.Safe(UnitIsPlayer, unit) then return nil end
    local classification = ns.Safe(UnitClassification, unit)
    if type(classification) ~= "string" then return nil end
    return GROUPS[classification]
end

--- Devolve a borda ao normal (só se fomos nós que a pintamos).
function NpcBorder:Reset(tooltip)
    if not painted then return end
    painted = false
    Paint(tooltip, DefaultColor())
end

--- Chamado quando uma tooltip de unit é montada.
function NpcBorder:Apply(tooltip)
    local unit = ns.UnitResolver:GetUnit(tooltip)
    local group = unit and self:GroupOf(unit)

    local c = group and ns.Config:Get("tooltip." .. group .. "Border") and ns.Config:Get("tooltip." .. group .. "Color")
    if type(c) ~= "table" then
        self:Reset(tooltip)
        return
    end
    painted = Paint(tooltip, c.r, c.g, c.b) or painted
end

--- Liga a restauração aos eventos da tooltip (limpa / escondida).
function NpcBorder:Install(tooltip)
    if type(tooltip.HookScript) ~= "function" then return end
    for _, script in ipairs({ "OnTooltipCleared", "OnHide" }) do
        pcall(tooltip.HookScript, tooltip, script, function() NpcBorder:Reset(tooltip) end)
    end
end
