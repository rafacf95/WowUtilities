-- ============================================================
--  Config.lua
--  Configuração persistente (SavedVariables) com valores padrão e
--  notificação de mudanças (Observer, via ns.Bus).
--  Responsabilidade única: ler/gravar configuração. Não conhece UI.
-- ============================================================

local _, ns = ...

local Config = {}
ns.Config = Config

local DEFAULTS = {
    tooltip = {
        name = true, class = true, faction = true,
        eliteBorder = true, eliteColor = { r = 1.0, g = 0.82, b = 0.0 },   -- elite e chefes de mundo: dourada
        rareBorder  = true, rareColor  = { r = 0.78, g = 0.78, b = 0.82 }, -- raros e raros elite: prateada
    },
    taxi    = { tooltip = true, bar = true },
    ui      = { allowWindowEdit = false }, -- libera na janela /wu as opções que o Edit Mode edita
    vendor  = {
        enabled        = true,
        onClose        = true,  -- resumo ao fechar o vendedor
        perTransaction = false, -- mensagem após cada compra/venda/reparo
        showZero       = false, -- avisar também quando nada mudou
    },
    bar = {
        texture     = "blizzard",
        border      = "thin",
        borderSize  = 1,
        borderColor = { r = 0.5, g = 0.5, b = 0.5 },
        fillColor   = { r = 1.0, g = 0.7, b = 0.0 },
        classColor  = false, -- true = o preenchimento usa a cor da classe do jogador
        fontSize    = 12,
        width       = 250,
        height      = 20,
        scale       = 1,
        drain       = false, -- false = enche (cast); true = esvazia (channel)
    },
    wardrobe = {
        enabled     = true,  -- filtro de armadura na janela de coleção
        armorFilter = "all", -- all | cloth | leather | mail | plate | cosmetic
    },
    trinkets = {
        enabled        = true,       -- seletor de trinkets na tela
        scale          = 1,
        orientation    = "vertical", -- vertical | horizontal
        slotSize       = 40,         -- tamanho dos botões dos slots (px)
        gap            = 6,          -- espaço entre os dois botões (px)
        columns        = 5,          -- colunas da grade de trinkets
        itemSize       = 36,         -- tamanho dos ícones da grade (px)
        itemGap        = 4,          -- espaço entre os ícones da grade (px)
        showItemLevel  = true,       -- nível do item sobre os ícones
        hideInCombat   = false,      -- esconde o seletor em combate (senão, só escurece)
    },
    items = {
        itemLevel = {
            enabled   = true,
            colorMode = "quality",                       -- quality | fixed
            color     = { r = 1.0, g = 1.0, b = 1.0 },   -- usada com colorMode = fixed
            anchor    = "BOTTOMRIGHT",                   -- canto do ícone
            fontSize  = 12,
        },
        characterLevel = {
            enabled   = true,
            colorMode = "quality",
            color     = { r = 1.0, g = 1.0, b = 1.0 },
            anchor    = "BOTTOMRIGHT",
            fontSize  = 11,
            inspect   = true,  -- também na janela de inspeção (mesmo visual)
        },
        characterEnchants = {
            enabled        = true,
            showEnchanted  = true,   -- false = só avisa os que faltam
            nameMode       = "short", -- full | short | value (nome do encantamento)
            countRings     = false,  -- anéis só contam para quem tem Encantamento
            inspect        = true,   -- também na janela de inspeção (mesmo visual)
            inspectCountRings = false, -- anéis na inspeção (não dá para saber a profissão do outro)
            enchantedColor = { r = 0.1, g = 1.0, b = 0.1 },
            missingColor   = { r = 1.0, g = 0.15, b = 0.15 },
            fontSize       = 10,
        },
    },
    resource = {
        enabled         = false,        -- desligada até o jogador ligar (aparece na tela)
        visibility      = "always",     -- always | combat | combatOrTarget
        width           = 220,
        height          = 18,
        scale           = 1,
        texture         = "blizzard",
        border          = "thin",
        borderSize      = 1,
        borderColor     = { r = 0, g = 0, b = 0 },
        colorMode       = "power",      -- power (cor do jogo) | class | fixed
        fillColor       = { r = 0.2, g = 0.6, b = 1.0 },
        text            = "value",      -- none | value | both | percent
        fontSize        = 12,
        smooth          = true,         -- animação suave da barra
        comboPoints     = true,
        comboPosition   = "above",      -- above | below
        comboHeight     = 8,
        comboSpacing    = 2,
        comboColor      = { r = 1.0, g = 0.96, b = 0.41 },
        comboEmptyColor = { r = 0.15, g = 0.15, b = 0.15 },
    },
    positions = {}, -- [nomeDoLayout] = { point, relPoint, x, y }
    trinketPositions = {}, -- idem, para o seletor de trinkets
    resourcePositions = {}, -- idem, para a barra de recurso
}

local BAR_DEFAULT_POSITION = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 220 }

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = DeepCopy(v) end
    return copy
end

--- Completa `target` com o que faltar de `defaults` (sem sobrescrever).
local function FillDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            target[k] = DeepCopy(v)
        elseif type(v) == "table" and type(target[k]) == "table" then
            FillDefaults(target[k], v)
        end
    end
end

local function Walk(root, path)
    local node = root
    for key in path:gmatch("[^%.]+") do
        if type(node) ~= "table" then return nil end
        node = node[key]
    end
    return node
end

-- Versões antigas guardavam a cor como id de lista ("gold", "gray"...).
local LEGACY_COLORS = {
    gold  = { r = 1.0, g = 0.7, b = 0.0 },
    white = { r = 1.0, g = 1.0, b = 1.0 },
    gray  = { r = 0.5, g = 0.5, b = 0.5 },
    black = { r = 0.0, g = 0.0, b = 0.0 },
    red   = { r = 0.9, g = 0.1, b = 0.1 },
    blue  = { r = 0.2, g = 0.5, b = 1.0 },
    green = { r = 0.2, g = 0.8, b = 0.3 },
}

local function MigrateColors(bar)
    if type(bar) ~= "table" then return end
    for _, key in ipairs({ "borderColor", "fillColor" }) do
        local value = bar[key]
        if type(value) == "string" then
            bar[key] = DeepCopy(LEGACY_COLORS[value]) -- nil => cai no padrão
        end
    end
end

function Config:Init()
    WowUtilitiesDB = WowUtilitiesDB or {}
    ns.db = WowUtilitiesDB
    MigrateColors(ns.db.bar)
    FillDefaults(ns.db, DEFAULTS)
end

--- Valor padrão de um caminho ("bar.width").
function Config:Default(path)
    return DeepCopy(Walk(DEFAULTS, path))
end

--- Valor atual; antes do Init devolve o padrão.
function Config:Get(path)
    local value = ns.db and Walk(ns.db, path)
    if value == nil then value = Walk(DEFAULTS, path) end
    return value
end

function Config:Set(path, value)
    if not ns.db then return end
    local node, last = ns.db, nil
    local keys = {}
    for key in path:gmatch("[^%.]+") do keys[#keys + 1] = key end
    last = table.remove(keys)
    for _, key in ipairs(keys) do
        if type(node[key]) ~= "table" then node[key] = {} end
        node = node[key]
    end
    if node[last] == value then return end
    node[last] = value
    ns.Bus:Fire("CONFIG_CHANGED", path, value)
end

--- Restaura uma seção inteira ("bar") para o padrão.
function Config:ResetSection(section)
    if not ns.db or DEFAULTS[section] == nil then return end
    ns.db[section] = DeepCopy(DEFAULTS[section])
    ns.Bus:Fire("CONFIG_CHANGED", section, nil)
end

-- ----------------------------------------------------------------
-- Posição da barra, por layout do Edit Mode
-- ----------------------------------------------------------------

function Config:GetBarPosition(layoutName)
    local saved = ns.db and ns.db.positions[layoutName or "Default"]
    local pos = saved or BAR_DEFAULT_POSITION
    return pos.point, pos.relPoint or pos.point, pos.x, pos.y
end

function Config:SetBarPosition(layoutName, point, x, y, relPoint)
    if not ns.db then return end
    local old = ns.db.positions[layoutName or "Default"]
    ns.db.positions[layoutName or "Default"] = {
        point = point, relPoint = relPoint or point, x = x, y = y,
        anchor = old and old.anchor, -- a âncora (se houver) é independente do ponto livre
    }
end

--- Âncora da barra no layout (ver Bar/Anchoring.lua), ou nil.
function Config:GetBarAnchor(layoutName)
    local saved = ns.db and ns.db.positions[layoutName or "Default"]
    return saved and saved.anchor or nil
end

--- Grava (ou, com nil, remove) a âncora; cria o registro do layout se ainda não existe.
function Config:SetBarAnchor(layoutName, anchor)
    if not ns.db then return end
    local key = layoutName or "Default"
    local entry = ns.db.positions[key]
    if not entry then
        if anchor == nil then return end
        entry = DeepCopy(BAR_DEFAULT_POSITION)
        ns.db.positions[key] = entry
    end
    entry.anchor = anchor
end

--- Copia (create), renomeia ou apaga posições quando o layout muda.
function Config:CopyBarPosition(from, to)
    if ns.db and ns.db.positions[from] then
        ns.db.positions[to] = DeepCopy(ns.db.positions[from])
    end
end

function Config:RenameBarPosition(from, to)
    if ns.db and ns.db.positions[from] then
        ns.db.positions[to] = ns.db.positions[from]
        ns.db.positions[from] = nil
    end
end

function Config:DeleteBarPosition(name)
    if ns.db then ns.db.positions[name] = nil end
end

--- Posições por layout guardadas em ns.db[key], no formato esperado pelo
--- Positioner (get/set/copy/rename/delete). `default` = { point, relPoint, x, y }.
function Config:PositionStore(key, default)
    local function Table()
        if not ns.db then return nil end
        ns.db[key] = ns.db[key] or {}
        return ns.db[key]
    end
    return {
        get = function(layout)
            local t = Table()
            local pos = (t and t[layout or "Default"]) or default
            return pos.point, pos.relPoint or pos.point, pos.x, pos.y
        end,
        set = function(layout, point, x, y, relPoint)
            local t = Table()
            if t then
                local old = t[layout or "Default"]
                t[layout or "Default"] = { point = point, relPoint = relPoint or point, x = x, y = y,
                                           anchor = old and old.anchor }
            end
        end,
        getAnchor = function(layout)
            local t = Table()
            local entry = t and t[layout or "Default"]
            return entry and entry.anchor or nil
        end,
        setAnchor = function(layout, anchor)
            local t = Table()
            if not t then return end
            local key = layout or "Default"
            if not t[key] then
                if anchor == nil then return end
                t[key] = DeepCopy(default)
            end
            t[key].anchor = anchor
        end,
        copy = function(from, to)
            local t = Table()
            if t and t[from] then t[to] = DeepCopy(t[from]) end
        end,
        rename = function(old, new)
            local t = Table()
            if t and t[old] then t[new] = t[old]; t[old] = nil end
        end,
        delete = function(name)
            local t = Table()
            if t then t[name] = nil end
        end,
    }
end
