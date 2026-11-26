-- ============================================================
--  Skin.lua
--  Fábrica de widgets no estilo do painel de Opções da Blizzard
--  (Strategy + Adapter). Cada construtor tenta o template/atlas da
--  Blizzard (confirmados no Forever pelo /wu debug ui) e, se o cliente
--  não tiver a peça, cai no widget simples de UI/Widgets.lua.
--  Contrato dos controles: o frame devolvido tem :Refresh() (relê o
--  valor) e :SetLocked(flag) (acinzenta e bloqueia). Quem usa não precisa
--  saber qual visual está ativo.
-- ============================================================

local _, ns = ...

local Skin = {}
ns.Skin = Skin

local W = ns.Widgets

local CHECK_SIZE = { 30, 29 }

-- ----------------------------------------------------------------
-- Utilitários
-- ----------------------------------------------------------------

--- O atlas existe neste cliente?
function Skin.HasAtlas(name)
    local api = rawget(_G, "C_Texture")
    if type(api) ~= "table" or type(api.GetAtlasInfo) ~= "function" then return false end
    local ok, info = pcall(api.GetAtlasInfo, name)
    return ok and type(info) == "table"
end

local function TryCreate(kind, name, parent, template)
    local ok, frame = pcall(CreateFrame, kind, name, parent, template)
    if ok and type(frame) == "table" then return frame end
end

--- Textura com atlas (nil se o atlas não existir).
function Skin.AtlasTexture(parent, layer, atlas, useAtlasSize)
    if not Skin.HasAtlas(atlas) then return nil end
    local texture = parent:CreateTexture(nil, layer)
    texture:SetAtlas(atlas, useAtlasSize)
    return texture
end

--- Texto com o objeto de fonte da Blizzard (o nome é passado como template).
function Skin.Text(parent, text, font, layer)
    local fs = parent:CreateFontString(nil, layer or "ARTWORK", font or "GameFontNormal")
    fs:SetText(text or "")
    return fs
end

-- ----------------------------------------------------------------
-- Janela (moldura de metal do painel de Opções)
-- ----------------------------------------------------------------

--- Janela com título e botão de fechar. :SetTitle(text) muda o título.
function Skin.Window(name, title, width, height)
    local frame = TryCreate("Frame", name, UIParent, "SettingsFrameTemplate") or CreateFrame("Frame", name, UIParent)
    frame:SetSize(width, height)
    local nine = rawget(frame, "NineSlice")
    local titleText = type(nine) == "table" and rawget(nine, "Text") or nil

    if titleText then
        frame.skinned = true
        local close = rawget(frame, "ClosePanelButton")
        if type(close) == "table" then close:SetScript("OnClick", function() frame:Hide() end) end
    else
        -- Sem o template: fundo simples, título e X padrão
        local bg = W.NewFrame(frame)
        bg:SetAllPoints()
        bg:SetFrameLevel(frame:GetFrameLevel())
        W.Backdrop(bg, { 0.06, 0.06, 0.08, 0.96 }, { 0.5, 0.5, 0.55, 1 })
        titleText = Skin.Text(frame, "", "GameFontNormal", "OVERLAY")
        titleText:SetPoint("TOP", frame, "TOP", 0, -8)
        local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)
        close:SetScript("OnClick", function() frame:Hide() end)
    end

    function frame:SetTitle(text) titleText:SetText(text or "") end
    frame:SetTitle(title)
    return frame
end

--- Painel com moldura de tooltip (grade de berloques, menus flutuantes).
function Skin.Panel(name, parent, bg, border)
    local frame = TryCreate("Frame", name, parent, "TooltipBackdropTemplate")
    if frame and type(rawget(frame, "NineSlice")) == "table" then return frame end
    frame = CreateFrame("Frame", name, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    W.Backdrop(frame, bg or { 0.06, 0.06, 0.08, 0.95 }, border or { 0.5, 0.5, 0.55, 1 })
    return frame
end

--- Linha divisória horizontal do painel de Opções.
function Skin.Divider(parent)
    local line = Skin.AtlasTexture(parent, "ARTWORK", "Options_HorizontalDivider")
    if not line then
        line = parent:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(0.4, 0.4, 0.45, 0.8)
    end
    line:SetHeight(1)
    return line
end

--- Área com rolagem vertical. Devolve scroll, conteúdo (largura fixa).
function Skin.Scroll(parent, contentWidth)
    local scroll = TryCreate("ScrollFrame", nil, parent, "ScrollFrameTemplate")
    if not (scroll and rawget(scroll, "ScrollBar")) then
        scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    end
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(contentWidth, 1)
    scroll:SetScrollChild(content)
    return scroll, content
end

-- ----------------------------------------------------------------
-- Controles
-- ----------------------------------------------------------------

--- Botão vermelho padrão (o mesmo de "Defaults" e "Close").
function Skin.Button(parent, text, width, onClick)
    return W.Button(parent, text, width or 96, onClick)
end

--- Caixa de seleção amarela do painel de Opções. get() -> bool | set(bool)
function Skin.Checkbox(parent, get, set)
    if not (Skin.HasAtlas("checkbox-minimal") and Skin.HasAtlas("checkmark-minimal")) then
        return W.Checkbox(parent, "", get, set)
    end
    local box = CreateFrame("CheckButton", nil, parent)
    box:SetSize(CHECK_SIZE[1], CHECK_SIZE[2])
    local normal = Skin.AtlasTexture(box, "BACKGROUND", "checkbox-minimal")
    normal:SetAllPoints()
    local check = Skin.AtlasTexture(box, "ARTWORK", "checkmark-minimal")
    check:SetAllPoints()
    box:SetCheckedTexture(check)
    local disabled = Skin.AtlasTexture(box, "ARTWORK", "checkmark-minimal-disabled")
    if disabled then
        disabled:SetAllPoints()
        box:SetDisabledCheckedTexture(disabled)
    end
    local hover = box:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(normal)
    hover:SetAtlas("checkbox-minimal")
    hover:SetBlendMode("ADD")
    hover:SetAlpha(0.3)

    box:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    function box:Refresh() self:SetChecked(get() and true or false) end
    function box:SetLocked(flag)
        self:SetEnabled(not flag)
        self:SetAlpha(flag and 0.5 or 1)
    end
    return box
end

local function Round(value, step)
    return tonumber(string.format("%.3f", math.floor(value / step + 0.5) * step))
end

--- Slider com setas e o valor à direita. get() -> número | set(número)
function Skin.Slider(parent, minValue, maxValue, step, format, get, set, width)
    local mixin = rawget(_G, "MinimalSliderWithSteppersMixin")
    local holder = type(mixin) == "table" and type(mixin.Event) == "table"
        and TryCreate("Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
    if not (holder and type(holder.Init) == "function" and type(holder.RegisterCallback) == "function") then
        if holder then holder:Hide() end
        return W.Slider(parent, "", minValue, maxValue, step, get, set, width, format)
    end

    local fmt = format or "%g"
    local formatters = {}
    if type(mixin.Label) == "table" and mixin.Label.Right then
        formatters[mixin.Label.Right] = function(value) return string.format(fmt, Round(value, step)) end
    end
    holder:SetWidth(width or 220)
    holder:Init(get(), minValue, maxValue, math.floor((maxValue - minValue) / step + 0.5), formatters)

    local updating = false
    holder:RegisterCallback(mixin.Event.OnValueChanged, function(_, value)
        if updating then return end
        set(Round(value, step))
    end, holder)

    function holder:Refresh()
        updating = true
        pcall(self.SetValue, self, get())
        updating = false
    end
    function holder:SetLocked(flag)
        if type(self.SetEnabled) == "function" then pcall(self.SetEnabled, self, not flag) end
        self:SetAlpha(flag and 0.5 or 1)
    end
    return holder
end

--- Menu de seleção. items = lista { id, label } ou função que a devolve.
--- opts.preview(item) -> path, r, g, b mostra uma textura de exemplo na opção.
function Skin.Dropdown(parent, items, get, set, width, opts)
    local dropdown = TryCreate("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    if not (dropdown and type(dropdown.SetupMenu) == "function") then
        if dropdown then dropdown:Hide() end
        return W.Dropdown(parent, "", items, get, set, width, { compact = true, preview = opts and opts.preview })
    end
    local preview = opts and opts.preview
    local function List() return type(items) == "function" and items() or items end

    dropdown:SetWidth(width or 200)
    dropdown:SetupMenu(function(_, root)
        for _, item in ipairs(List()) do
            local radio = root:CreateRadio(item.label,
                function() return get() == item.id end,
                function() set(item.id) end)
            if preview and type(radio) == "table" and type(radio.AddInitializer) == "function" then
                pcall(radio.AddInitializer, radio, function(button)
                    local path, r, g, b = preview(item)
                    if not path or type(button.AttachTexture) ~= "function" then return end
                    local bar = button:AttachTexture()
                    bar:SetTexture(path)
                    bar:SetVertexColor(r or 1, g or 1, b or 1, 0.6)
                    bar:SetPoint("TOPLEFT", 18, -2)
                    bar:SetPoint("BOTTOMRIGHT", -4, 2)
                    bar:SetDrawLayer("BACKGROUND")
                end)
            end
        end
    end)

    function dropdown:Refresh()
        if type(self.GenerateMenu) == "function" then pcall(self.GenerateMenu, self) end
    end
    function dropdown:SetLocked(flag)
        self:SetEnabled(not flag)
        self:SetAlpha(flag and 0.5 or 1)
    end
    return dropdown
end

--- Amostra de cor que abre o seletor da Blizzard.
--- get() -> r, g, b | set(r, g, b) | isDisabled() -> bool (opcional)
function Skin.ColorSwatch(parent, get, set, isDisabled)
    local swatch = TryCreate("Button", nil, parent, "ColorSwatchTemplate")
    local color = swatch and rawget(swatch, "Color")
    if not color then
        if swatch then swatch:Hide() end
        return W.ColorSwatch(parent, "", get, set, isDisabled)
    end

    swatch.disabled = false
    swatch:SetScript("OnClick", function(self)
        if self.disabled then return end
        W.OpenColorPicker(self, get, set)
    end)
    function swatch:Refresh()
        local r, g, b = get()
        color:SetVertexColor(r, g, b)
        self.disabled = (isDisabled and isDisabled()) or self.locked or false
        self:SetAlpha(self.disabled and 0.4 or 1)
        if self.disabled then W.CloseColorPicker(self) end
    end
    function swatch:SetLocked(flag)
        self.locked = flag and true or false
        self:Refresh()
    end
    return swatch
end
