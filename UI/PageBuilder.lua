-- ============================================================
--  PageBuilder.lua
--  Monta uma página da janela /wu a partir de uma lista de linhas
--  (dados, como em UI/ConfigPages.lua), no estilo do painel de Opções
--  da Blizzard: rótulo à esquerda, controle à direita, linhas empilhadas
--  sozinhas (sem coordenadas fixas). Linhas com `visible` somem e as de
--  baixo sobem a cada Refresh.
--
--  Tipos de linha (campos comuns: indent, visible = fn, when = fn):
--    { header = texto }
--    { checkbox = caminho, label = texto }
--    { slider = caminho, label, min, max, step, format }  (limites do SettingSpecs se omitidos)
--    { dropdown = caminho, label, items = lista|fn, preview = fn }
--    { color = caminho, label, disabled = fn }
--    { toggle = texto, get = fn, set = fn }               (caixa fora da configuração)
--    { buttons = { { text, width, onClick }, ... } }
--    { text = texto|fn, font = nome da fonte }
--  `when` decide na montagem; `visible` a cada Refresh.
-- ============================================================

local _, ns = ...

local Builder = {}
ns.PageBuilder = Builder

local Skin = ns.Skin

local LABEL_X = 37      -- recuo do rótulo (igual ao painel de Opções)
local INDENT = 20       -- recuo extra por nível
local CONTROL_X = 300   -- início da coluna dos controles
local ROW_HEIGHT = 26
local HEADER_HEIGHT = 45
local BUTTON_ROW_HEIGHT = 32
local TOP_PADDING = 4

local function Bind(path)
    return function() return ns.Config:Get(path) end,
           function(value) ns.Config:Set(path, value) end
end

--- Cria a página dentro de `content` (largura fixa). `ctx.locked(path)` diz se
--- a opção está travada pelo Edit Mode. Devolve { Refresh, Layout, controls }.
function Builder.Build(content, rows, ctx)
    local width = content:GetWidth()
    local page = { entries = {}, controls = {} }

    local function Row(height)
        local row = CreateFrame("Frame", nil, content)
        row:SetSize(width, height)
        return row
    end

    local function Label(row, text, indent)
        local label = Skin.Text(row, text, "GameFontNormal")
        label:SetPoint("LEFT", row, "LEFT", LABEL_X + indent, 0)
        label:SetWidth(CONTROL_X - LABEL_X - indent - 12)
        label:SetJustifyH("LEFT")
        if type(label.SetWordWrap) == "function" then label:SetWordWrap(true) end
        return label
    end

    local function Fit(row, label)
        local height = type(label.GetStringHeight) == "function" and label:GetStringHeight() or 0
        row:SetHeight(math.max(ROW_HEIGHT, (height or 0) + 10))
    end

    local function Add(entry, spec)
        entry.visible = spec.visible
        page.entries[#page.entries + 1] = entry
        return entry
    end

    --- Linha "rótulo + controle"; registra o travamento pelo caminho.
    local function ControlRow(spec, control, path)
        local indent = (spec.indent or 0) * INDENT
        local row = Row(ROW_HEIGHT)
        local label = Label(row, spec.label or "", indent)
        Fit(row, label)
        control:SetParent(row)
        control:ClearAllPoints()
        control:SetPoint("LEFT", row, "LEFT", CONTROL_X, 0)
        local entry = Add({ row = row, label = label, control = control, path = path }, spec)
        if path then page.controls[path] = control end
        return entry
    end

    for _, spec in ipairs(rows) do
        if not spec.when or spec.when() then
            if spec.header then
                local row = Row(HEADER_HEIGHT)
                local title = Skin.Text(row, spec.header, "GameFontHighlightLarge")
                title:SetPoint("TOPLEFT", row, "TOPLEFT", 7, -16)
                Add({ row = row }, spec)

            elseif spec.checkbox then
                local get, set = Bind(spec.checkbox)
                ControlRow(spec, Skin.Checkbox(content, get, set), spec.checkbox)

            elseif spec.toggle then
                local entry = ControlRow({ label = spec.toggle, indent = spec.indent, visible = spec.visible },
                    Skin.Checkbox(content, spec.get, spec.set))
                page.controls[spec.toggle] = entry.control

            elseif spec.slider then
                local s = ns.SettingSpecs:Get(spec.slider) or {}
                local get, set = Bind(spec.slider)
                local slider = Skin.Slider(content, spec.min or s.min, spec.max or s.max, spec.step or s.step,
                    spec.format or s.format, get, set, 220)
                ControlRow(spec, slider, spec.slider)

            elseif spec.dropdown then
                local get, set = Bind(spec.dropdown)
                ControlRow(spec, Skin.Dropdown(content, spec.items, get, set, 200, { preview = spec.preview }), spec.dropdown)

            elseif spec.color then
                local path = spec.color
                local function get() local c = ns.Config:Get(path) return c.r, c.g, c.b end
                local function set(r, g, b) ns.Config:Set(path, { r = r, g = g, b = b }) end
                local function disabled() return ctx.locked(path) or (spec.disabled and spec.disabled()) or false end
                ControlRow(spec, Skin.ColorSwatch(content, get, set, disabled), path)

            elseif spec.buttons then
                local row = Row(BUTTON_ROW_HEIGHT)
                local x = LABEL_X + (spec.indent or 0) * INDENT
                for _, b in ipairs(spec.buttons) do
                    local button = Skin.Button(row, b.text, b.width, b.onClick)
                    button:SetPoint("LEFT", row, "LEFT", x, 0)
                    x = x + (b.width or 96) + 8
                end
                Add({ row = row }, spec)

            elseif spec.text then
                local row = Row(ROW_HEIGHT)
                local indent = (spec.indent or 0) * INDENT
                local text = Skin.Text(row, "", spec.font or "GameFontHighlightSmall")
                text:SetPoint("TOPLEFT", row, "TOPLEFT", LABEL_X + indent, -6)
                text:SetWidth(width - LABEL_X - indent - 10)
                text:SetJustifyH("LEFT")
                local entry = Add({ row = row, text = text, source = spec.text }, spec)
                entry.update = function()
                    local value = type(spec.text) == "function" and spec.text() or spec.text
                    text:SetText(value or "")
                    local height = type(text.GetStringHeight) == "function" and text:GetStringHeight() or 0
                    row:SetHeight(math.max(ROW_HEIGHT - 6, (height or 0) + 10))
                end
            end
        end
    end

    --- Empilha as linhas visíveis e ajusta a altura do conteúdo (para a rolagem).
    function page:Layout()
        local y = TOP_PADDING
        for _, entry in ipairs(self.entries) do
            local shown = not entry.visible or entry.visible() and true or false
            entry.row:SetShown(shown)
            if shown then
                entry.row:ClearAllPoints()
                entry.row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                y = y + entry.row:GetHeight()
            end
        end
        content:SetHeight(y + 12)
    end

    --- Relê os valores, aplica as travas do Edit Mode e reorganiza.
    function page:Refresh()
        for _, entry in ipairs(self.entries) do
            if entry.update then entry.update() end
            local control = entry.control
            if control then
                if control.Refresh then control:Refresh() end
                local locked = entry.path and ctx.locked(entry.path) or false
                if control.SetLocked then control:SetLocked(locked) end
                entry.label:SetAlpha(locked and 0.5 or 1)
            end
        end
        self:Layout()
    end

    page:Refresh()
    return page
end
