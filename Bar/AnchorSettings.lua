-- ============================================================
--  AnchorSettings.lua
--  Opções de âncora na caixa do Edit Mode (LibEditMode), exclusivas dele
--  e POR LAYOUT (a posição já é por layout, e o alvo pode estar em
--  lugares diferentes em cada um):
--    Ancorar em | Lado | Ajustar largura | Deslocamento X e Y
--  Lê e grava pela `store` do Positioner (getAnchor/setAnchor); depois
--  de cada mudança pede ao Positioner para reposicionar o frame.
-- ============================================================

local _, ns = ...
local L = ns.L

local AnchorSettings = {}
ns.AnchorSettings = AnchorSettings

local NONE = "none"
local OFFSET_LIMIT = 400
local MENU_HEIGHT = 240 -- altura (px) do menu de alvos; passando disso, rola

--- ctx = { store, place(layout), layout(), exclude() -> {frame=true}, refresh() }
--- Devolve a lista de opções (ou nil se a biblioteca não tiver os tipos necessários).
function AnchorSettings:Build(lib, ctx)
    local types = lib.SettingType
    if type(types) ~= "table" or not (types.Dropdown and types.Checkbox and types.Slider) then return nil end
    local Anchoring = ns.Anchoring

    local function Current(layout) return ctx.store.getAnchor(layout or ctx.layout()) end
    local function NoAnchor(layout) return Current(layout) == nil end
    local function Change(layout, fn)
        local anchor = Current(layout)
        if not anchor then return end
        fn(anchor)
        ctx.store.setAnchor(layout, anchor)
        ctx.place(layout)
    end

    -- A lista é montada a cada abertura do menu: frames de outros addons podem chegar depois
    local function TargetValues()
        local values = { { text = L["None"], value = NONE } }
        for _, target in ipairs(Anchoring:Targets(ctx.exclude(), lib)) do
            values[#values + 1] = { text = target.label, value = target.id }
        end
        return values
    end

    local edges = {}
    for _, edge in ipairs(Anchoring.EDGES) do edges[#edges + 1] = { text = edge.label, value = edge.id } end

    local function OffsetSlider(name, field)
        return {
            kind = types.Slider, name = name, default = 0, minValue = -OFFSET_LIMIT, maxValue = OFFSET_LIMIT, valueStep = 1,
            hidden = NoAnchor,
            get = function(layout) local a = Current(layout); return a and a[field] or 0 end,
            set = function(layout, value) Change(layout, function(a) a[field] = value end) end,
        }
    end

    local list = {}
    if types.Divider then list[#list + 1] = { kind = types.Divider, name = L["Anchor"] } end

    list[#list + 1] = {
        kind = types.Dropdown, name = L["Anchor to"], default = NONE, values = TargetValues,
        height = MENU_HEIGHT, -- a lista tem ~40 itens: menu com rolagem
        get = function(layout) local a = Current(layout); return a and a.target or NONE end,
        set = function(layout, value)
            if value == NONE then
                ctx.store.setAnchor(layout, nil)
            else
                local anchor = Current(layout)
                if not anchor then anchor = { edge = Anchoring.DEFAULT_EDGE, matchWidth = false } end
                if anchor.target ~= value or anchor.x == nil then
                    anchor.target = value
                    anchor.x, anchor.y = Anchoring:DefaultOffset(anchor.edge)
                end
                ctx.store.setAnchor(layout, anchor)
            end
            ctx.place(layout)
            ctx.refresh()
        end,
    }

    list[#list + 1] = {
        kind = types.Dropdown, name = L["Anchor side"], default = Anchoring.DEFAULT_EDGE, values = edges,
        hidden = NoAnchor,
        get = function(layout) local a = Current(layout); return a and a.edge or Anchoring.DEFAULT_EDGE end,
        set = function(layout, value)
            Change(layout, function(a)
                a.edge = value
                a.x, a.y = Anchoring:DefaultOffset(value)
                if not Anchoring:CanMatchWidth(value) then a.matchWidth = false end
            end)
            ctx.refresh()
        end,
    }

    list[#list + 1] = {
        kind = types.Checkbox, name = L["Match width"], default = false,
        hidden = function(layout)
            local anchor = Current(layout)
            return anchor == nil or not Anchoring:CanMatchWidth(anchor.edge)
        end,
        get = function(layout) local a = Current(layout); return a ~= nil and a.matchWidth == true end,
        set = function(layout, value)
            Change(layout, function(a) a.matchWidth = value and true or false end)
            ctx.refresh()
        end,
    }

    list[#list + 1] = OffsetSlider(L["Horizontal offset"], "x")
    list[#list + 1] = OffsetSlider(L["Vertical offset"], "y")
    return list
end
