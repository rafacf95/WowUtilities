-- ============================================================
--  Positioner.lua
--  Posicionamento de frames móveis. Strategy: duas implementações
--  intercambiáveis; quem usa só pede "me posicione".
--    EditMode — usa o Edit Mode da Blizzard via LibEditMode
--               (addon opcional). Posições salvas por layout.
--    Drag     — fallback sem biblioteca: arrastar o frame com o
--               mouse enquanto "destravado" na janela /wu.
--  Cada frame tem a sua instância (Positioner.New(spec)); ns.Positioner
--  é a da barra de voo. A spec descreve o frame:
--    label    nome mostrado no Edit Mode
--    default  { point, x, y } padrão do Edit Mode
--    store    { get, set, copy, rename, delete } das posições por layout
--    fireBus  publica EDITMODE_ENTER / EDITMODE_EXIT (a barra se mostra
--             como pré-visualização enquanto edita a posição)
--    handles  função opcional que devolve outros frames que também
--             arrastam o frame principal (botões dentro dele)
--    settings lista opcional das opções que aparecem na caixa do Edit Mode:
--             caminhos da configuração ("bar.scale"; descritos em
--             ns.SettingSpecs) e separadores { divider = "texto" }
--    anchorable  o frame pode ser ancorado em outro elemento do Edit Mode
--             (ns.Anchoring; opções por layout em ns.AnchorSettings). Exige
--             store.getAnchor/setAnchor.
--    matchWidthLocks  caminho da opção de largura, que fica desabilitada
--             enquanto o frame acompanha a largura do alvo
-- ============================================================

local _, ns = ...
local L = ns.L

local Positioner = {}
ns.Positioner = Positioner

-- A biblioteca recebe um único conjunto de callbacks, que repassa a todos os
-- frames registrados (cada instância adiciona o seu a `registry`).
local registry, hooked = {}, false
local editingFromEditMode = false -- evita redesenhar a caixa por uma mudança que veio dela

local function EachSpec(fn)
    for _, entry in ipairs(registry) do fn(entry) end
end


-- ----------------------------------------------------------------
-- Opções do Edit Mode: traduz as descrições (ns.SettingSpecs) para os
-- objetos de configuração da LibEditMode. Lê e grava a mesma
-- configuração da janela /wu (valores iguais em todos os layouts).
-- ----------------------------------------------------------------

local function Apply(path, value)
    editingFromEditMode = true
    local ok, err = pcall(ns.Config.Set, ns.Config, path, value)
    editingFromEditMode = false
    if not ok and geterrorhandler then geterrorhandler()(err) end
end

local function Getter(path) return function() return ns.Config:Get(path) end end

local BUILDERS = {
    slider = function(types, path, spec)
        if not types.Slider then return end
        return { kind = types.Slider, name = spec.label, default = ns.Config:Default(path),
                 minValue = spec.min, maxValue = spec.max, valueStep = spec.step,
                 get = Getter(path), set = function(_, value) Apply(path, value) end }
    end,
    checkbox = function(types, path, spec)
        if not types.Checkbox then return end
        return { kind = types.Checkbox, name = spec.label, default = ns.Config:Default(path) == true,
                 get = function() return ns.Config:Get(path) == true end,
                 set = function(_, value) Apply(path, value and true or false) end }
    end,
    dropdown = function(types, path, spec)
        if not types.Dropdown then return end
        local values = {}
        for _, item in ipairs(spec.values) do values[#values + 1] = { text = item.label, value = item.id } end
        return { kind = types.Dropdown, name = spec.label, default = ns.Config:Default(path),
                 values = values, get = Getter(path), set = function(_, value) Apply(path, value) end }
    end,
    color = function(types, path, spec)
        if not types.ColorPicker or type(CreateColor) ~= "function" then return end
        local function Mixin(c) return CreateColor(c.r, c.g, c.b) end
        return { kind = types.ColorPicker, name = spec.label, default = Mixin(ns.Config:Default(path)),
                 get = function() return Mixin(ns.Config:Get(path)) end,
                 set = function(_, color) Apply(path, { r = color.r, g = color.g, b = color.b }) end }
    end,
}

--- Monta a lista de opções do frame e registra na biblioteca. Devolve o
--- conjunto de caminhos exibidos (para sincronizar com a janela /wu).
local function AddSettings(lib, frame, items, extra, lockWidth)
    local types = lib.SettingType
    if type(lib.AddFrameSettings) ~= "function" or type(types) ~= "table" or type(items) ~= "table" then return nil end

    local list, paths = {}, {}
    for _, item in ipairs(items) do
        local setting
        if type(item) == "table" then
            if types.Divider then setting = { kind = types.Divider, name = item.divider } end
        else
            local spec = ns.SettingSpecs:Get(item)
            local build = spec and BUILDERS[spec.kind]
            setting = build and build(types, item, spec)
            if setting then
                paths[item] = true
                if lockWidth and item == lockWidth.path then setting.disabled = lockWidth.isLocked end
            end
        end
        if setting then list[#list + 1] = setting end
    end
    for _, setting in ipairs(extra or {}) do list[#list + 1] = setting end
    if #list == 0 then return nil end

    -- A caixa do Edit Mode é estreita: rótulos curtos quando o idioma tiver
    for _, setting in ipairs(list) do
        setting.name = ns.EditModeLabel(setting.name)
        if type(setting.values) == "table" then
            for _, value in ipairs(setting.values) do value.text = ns.EditModeLabel(value.text) end
        end
    end

    local ok, err = pcall(lib.AddFrameSettings, lib, frame, list)
    if not ok then
        if geterrorhandler then geterrorhandler()(err) end
        return nil
    end
    return paths
end

--- Uma opção mudou fora da caixa (janela /wu): a caixa aberta se redesenha.
ns.Bus:Subscribe("CONFIG_CHANGED", function(path)
    if editingFromEditMode or type(path) ~= "string" then return end
    for _, entry in ipairs(registry) do
        local paths = entry.paths
        local hit = paths and (paths[path] or path == entry.root)
        if hit and entry.lib and type(entry.lib.RefreshFrameSettings) == "function" then
            pcall(entry.lib.RefreshFrameSettings, entry.lib, entry.frame)
        end
    end
end)

--- Alguma caixa do Edit Mode já exibe esta opção? (a janela /wu a deixa só para leitura)
function Positioner.IsEditedInEditMode(path)
    for _, entry in ipairs(registry) do
        if entry.paths and entry.paths[path] then return true end
    end
    return false
end

--- Existe alguma opção editável no Edit Mode (ou seja, algo a bloquear na janela)?
function Positioner.HasEditModeSettings()
    for _, entry in ipairs(registry) do
        if entry.paths and next(entry.paths) then return true end
    end
    return false
end

local function HookLibraryOnce(lib)
    if hooked then return end
    hooked = true
    lib:RegisterCallback("layout", function(layoutName)
        EachSpec(function(e) e.place(e.frame, layoutName) end)
    end)
    local function Announce(event)
        local fired = false
        EachSpec(function(e)
            if e.spec.fireBus and not fired then
                fired = true
                ns.Bus:Fire(event)
            end
        end)
    end
    lib:RegisterCallback("enter", function() Announce("EDITMODE_ENTER") end)
    lib:RegisterCallback("exit", function() Announce("EDITMODE_EXIT") end)
    lib:RegisterCallback("create", function(layoutName, _, source)
        if source then EachSpec(function(e) e.spec.store.copy(source, layoutName) end) end
    end)
    lib:RegisterCallback("rename", function(old, new)
        EachSpec(function(e) e.spec.store.rename(old, new) end)
    end)
    lib:RegisterCallback("delete", function(name)
        EachSpec(function(e) e.spec.store.delete(name) end)
    end)
end

local function Create(spec)
    local instance = {}
    local active

    -- O WoW mede o deslocamento de um frame nas unidades dele, ou seja, vezes a
    -- escala. Guardamos em unidades da tela (independentes da escala) para que
    -- mudar a escala não tire o frame do lugar.
    local function ScaleOf(frame)
        local scale = frame:GetScale()
        return (type(scale) == "number" and scale > 0) and scale or 1
    end

    local function AnchorOf(layoutName)
        if not (spec.anchorable and spec.store.getAnchor) then return nil end
        return spec.store.getAnchor(layoutName)
    end

    local function Place(frame, layoutName)
        local scale = ScaleOf(frame)
        local anchor = AnchorOf(layoutName)
        if anchor and ns.Anchoring:Apply(frame, anchor, scale, function() Place(frame, layoutName) end) then
            return -- ancorado: o WoW move o frame junto com o alvo
        end
        local point, relPoint, x, y = spec.store.get(layoutName)
        frame:ClearAllPoints()
        frame:SetPoint(point, UIParent, relPoint, x / scale, y / scale)
    end

    --- Guarda a posição atual do frame (x, y nas unidades dele) em unidades da tela.
    local function Save(frame, layoutName, point, x, y, relPoint)
        local scale = ScaleOf(frame)
        spec.store.set(layoutName, point, x * scale, y * scale, relPoint)
    end

    local function Fire(event)
        if spec.fireBus then ns.Bus:Fire(event) end
    end

    -- ------------------------------------------------------------
    -- Strategy 1: Edit Mode (LibEditMode)
    -- ------------------------------------------------------------
    local EditMode = { name = "editmode" }

    function EditMode:Available()
        return LibStub ~= nil and LibStub("LibEditMode", true) ~= nil
    end

    function EditMode:Attach(frame)
        local lib = LibStub("LibEditMode")
        local default = spec.default or { point = "BOTTOM", x = 0, y = 220 }

        -- A biblioteca move o frame; nós só guardamos a posição do layout ativo
        local function Refresh() pcall(lib.RefreshFrameSettings, lib, frame) end

        --- Com âncora, soltar o frame muda o deslocamento em relação ao alvo (e não a
        --- posição na tela). Com "ajustar largura" só a vertical muda: a horizontal
        --- é decidida pelo alvo.
        local function SaveAnchored(layoutName)
            local anchor = AnchorOf(layoutName)
            local target = anchor and ns.Anchoring:Resolve(anchor.target, frame)
            if not target then return false end
            local x, y = ns.Anchoring:OffsetFromPosition(frame, target, anchor)
            if x then
                if not ns.Anchoring:UsesWidth(anchor) then anchor.x = math.floor(x + 0.5) end
                anchor.y = math.floor(y + 0.5)
                spec.store.setAnchor(layoutName, anchor)
            end
            Place(frame, layoutName)
            Refresh()
            return true
        end

        lib:AddFrame(frame, function(_, layoutName, point, x, y)
            if not SaveAnchored(layoutName) then Save(frame, layoutName, point, x, y) end
        end, default, spec.label)

        local extra
        if spec.anchorable and spec.store.getAnchor and spec.store.setAnchor then
            extra = ns.AnchorSettings:Build(lib, {
                store = spec.store,
                place = function(layout) Place(frame, layout) end,
                layout = function() return lib:GetActiveLayoutName() end,
                exclude = function()
                    local own = {}
                    for _, entry in ipairs(registry) do own[entry.frame] = true end
                    own[frame] = true
                    return own
                end,
                refresh = Refresh,
            })
        end
        local lockWidth = extra and spec.matchWidthLocks and {
            path = spec.matchWidthLocks,
            isLocked = function(layout)
                return ns.Anchoring:UsesWidth(spec.store.getAnchor(layout or lib:GetActiveLayoutName()))
            end,
        } or nil

        registry[#registry + 1] = { frame = frame, spec = spec, place = Place, lib = lib,
                                    paths = AddSettings(lib, frame, spec.settings, extra, lockWidth),
                                    root = type(spec.settings) == "table" and type(spec.settings[1]) == "string"
                                           and spec.settings[1]:match("^[^.]+") or nil }
        HookLibraryOnce(lib)

        Place(frame, lib:GetActiveLayoutName())
    end

    -- ------------------------------------------------------------
    -- Strategy 2: arrastar (fallback)
    -- ------------------------------------------------------------
    local Drag = { name = "drag", unlocked = false }

    function Drag:Available() return true end

    function Drag:Attach(frame)
        self.frame = frame
        Place(frame, "Default")
        frame:SetMovable(true)

        local function Wire(target)
            target:RegisterForDrag("LeftButton")
            target:SetScript("OnDragStart", function()
                if self.unlocked then frame:StartMoving() end
            end)
            target:SetScript("OnDragStop", function()
                frame:StopMovingOrSizing()
                local point, _, relPoint, x, y = frame:GetPoint(1)
                Save(frame, "Default", point, x, y, relPoint)
            end)
        end
        Wire(frame)
        if spec.handles then
            for _, handle in ipairs(spec.handles()) do Wire(handle) end
        end
    end

    function Drag:SetUnlocked(flag)
        self.unlocked = flag and true or false
        if self.frame then self.frame:EnableMouse(self.unlocked) end
        Fire(self.unlocked and "EDITMODE_ENTER" or "EDITMODE_EXIT")
    end

    -- ------------------------------------------------------------
    -- API pública
    -- ------------------------------------------------------------

    local strategies = { EditMode, Drag }

    --- Escolhe a primeira estratégia disponível e liga ao frame.
    --- Se a biblioteca falhar, cai para o fallback.
    function instance:Attach(frame)
        for _, strategy in ipairs(strategies) do
            if strategy:Available() then
                local ok, err = pcall(strategy.Attach, strategy, frame)
                if ok then
                    active = strategy
                    self.mode = strategy.name
                    return
                elseif geterrorhandler then
                    geterrorhandler()(err)
                end
            end
        end
    end

    --- "editmode", "drag" ou nil (antes do Attach).
    function instance:Mode() return self.mode end

    --- Só no modo "drag": destrava/trava o frame para arrastar.
    function instance:SetUnlocked(flag)
        if active == Drag then Drag:SetUnlocked(flag) end
    end

    function instance:IsUnlocked()
        return active == Drag and Drag.unlocked or false
    end

    --- Reposiciona o frame na posição salva do layout ativo (depois de apagar a
    --- posição salva ou de mudar a escala).
    function instance:Replace(frame)
        if not active then return end -- ainda não foi ligado ao frame
        local layout = "Default"
        if active == EditMode then
            local lib = LibStub("LibEditMode")
            layout = lib:GetActiveLayoutName()
        end
        Place(frame, layout)
    end

    return instance
end

--- Cria um posicionador independente para outro frame.
function Positioner.New(spec) return Create(spec) end

-- ns.Positioner continua sendo a instância da barra de voo
local bar = Create({
    label = L["Flight bar"] .. " (WowUtilities)",
    default = { point = "BOTTOM", x = 0, y = 220 },
    fireBus = true,
    anchorable = true,
    matchWidthLocks = "bar.width",
    settings = { "bar.scale", "bar.width", "bar.height", "bar.fontSize", "bar.borderSize",
                 "bar.classColor", "bar.drain", "bar.fillColor", "bar.borderColor" },
    store = {
        get = function(layout) return ns.Config:GetBarPosition(layout) end,
        set = function(layout, point, x, y, relPoint) ns.Config:SetBarPosition(layout, point, x, y, relPoint) end,
        getAnchor = function(layout) return ns.Config:GetBarAnchor(layout) end,
        setAnchor = function(layout, anchor) ns.Config:SetBarAnchor(layout, anchor) end,
        copy = function(from, to) ns.Config:CopyBarPosition(from, to) end,
        rename = function(old, new) ns.Config:RenameBarPosition(old, new) end,
        delete = function(name) ns.Config:DeleteBarPosition(name) end,
    },
})
for key, value in pairs(bar) do Positioner[key] = value end
