-- ============================================================
--  SettingSpecs.lua
--  Descrição única das opções que aparecem em mais de um lugar (a janela
--  /wu e a caixa de opções do Edit Mode): tipo, rótulo e limites.
--  Quem exibe a opção (ConfigWindow, Positioner) só consulta aqui, então
--  os limites e textos não ficam duplicados.
--    kind = "slider"   (min, max, step, format)
--         | "checkbox"
--         | "color"    (valor guardado como { r, g, b })
--         | "dropdown" (values = { { id, label }, ... })
-- ============================================================

local _, ns = ...
local L = ns.L

local Specs = {}
ns.SettingSpecs = Specs

local SPECS = {
    -- Barra de voo
    ["bar.scale"]       = { kind = "slider", label = L["Scale"], min = 0.5, max = 2, step = 0.05, format = "%.2f" },
    ["bar.width"]       = { kind = "slider", label = L["Width"], min = 100, max = 500, step = 5, format = "%d" },
    ["bar.height"]      = { kind = "slider", label = L["Height"], min = 10, max = 60, step = 1, format = "%d" },
    ["bar.fontSize"]    = { kind = "slider", label = L["Text size"], min = 8, max = 24, step = 1, format = "%d" },
    ["bar.borderSize"]  = { kind = "slider", label = L["Border thickness"], min = 0, max = 16, step = 1, format = "%d" },
    ["bar.classColor"]  = { kind = "checkbox", label = L["Class color"] },
    ["bar.drain"]       = { kind = "checkbox", label = L["Drain bar (like a channel)"] },
    ["bar.fillColor"]   = { kind = "color", label = L["Bar color"] },
    ["bar.borderColor"] = { kind = "color", label = L["Border color"] },

    -- Seletor de trinkets
    ["trinkets.scale"]         = { kind = "slider", label = L["Scale"], min = 0.5, max = 2, step = 0.05, format = "%.2f" },
    ["trinkets.slotSize"]      = { kind = "slider", label = L["Button size"], min = 28, max = 64, step = 2, format = "%d" },
    ["trinkets.gap"]           = { kind = "slider", label = L["Button spacing"], min = 0, max = 24, step = 1, format = "%d" },
    ["trinkets.columns"]       = { kind = "slider", label = L["Grid columns"], min = 3, max = 8, step = 1, format = "%d" },
    ["trinkets.itemSize"]      = { kind = "slider", label = L["Icon size"], min = 24, max = 64, step = 2, format = "%d" },
    ["trinkets.itemGap"]       = { kind = "slider", label = L["Icon spacing"], min = 0, max = 16, step = 1, format = "%d" },
    ["trinkets.showItemLevel"] = { kind = "checkbox", label = L["Show item level on icons"] },
    ["trinkets.hideInCombat"]  = { kind = "checkbox", label = L["Hide the selector in combat"] },
    ["trinkets.orientation"]   = { kind = "dropdown", label = L["Layout"], values = {
        { id = "vertical",   label = L["Vertical"] },
        { id = "horizontal", label = L["Horizontal"] },
    } },
}

--- Descrição da opção (nil se o caminho não estiver registrado).
function Specs:Get(path)
    return SPECS[path]
end
