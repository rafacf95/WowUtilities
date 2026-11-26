-- ============================================================
--  Widgets.lua
--  Controles de interface próprios (checkbox, slider, lista
--  suspensa, botão). Feitos à mão porque os templates de slider e
--  dropdown da Blizzard mudam entre versões do cliente.
--  Todo widget devolve um frame com :Refresh() que relê o valor.
-- ============================================================

local _, ns = ...

local Widgets = {}
ns.Widgets = Widgets

local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil
local WHITE = "Interface\\Buttons\\WHITE8X8"

function Widgets.NewFrame(parent, name)
    return CreateFrame("Frame", name, parent, BACKDROP)
end

--- Fundo e borda de 1px. bg/border = { r, g, b, a }.
function Widgets.Backdrop(frame, bg, border)
    if not frame.SetBackdrop then return end
    pcall(function()
        frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
        frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
    end)
end

local function Round(value, step)
    return tonumber(string.format("%.3f", math.floor(value / step + 0.5) * step))
end

local function Label(parent, text, template)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    fs:SetText(text)
    return fs
end
Widgets.Label = Label

-- ----------------------------------------------------------------
-- Botão
-- ----------------------------------------------------------------
function Widgets.Button(parent, text, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 120, 24)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    function button:Refresh() end
    return button
end

-- ----------------------------------------------------------------
-- Checkbox
-- ----------------------------------------------------------------
function Widgets.Checkbox(parent, text, get, set)
    local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    box:SetSize(24, 24)
    box.text = Label(box, text)
    box.text:SetPoint("LEFT", box, "RIGHT", 4, 0)
    box:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    function box:Refresh() self:SetChecked(get() and true or false) end
    function box:SetLocked(flag)
        self:SetEnabled(not flag)
        self:SetAlpha(flag and 0.4 or 1)
    end
    return box
end

-- ----------------------------------------------------------------
-- Slider
-- ----------------------------------------------------------------
function Widgets.Slider(parent, text, minValue, maxValue, step, get, set, width, format)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width or 200, 38)

    holder.label = Label(holder, text)
    holder.label:SetPoint("TOPLEFT")
    holder.value = Label(holder, "", "GameFontNormal")
    holder.value:SetPoint("TOPRIGHT")

    local slider = CreateFrame("Slider", nil, holder)
    slider:SetPoint("BOTTOMLEFT")
    slider:SetPoint("BOTTOMRIGHT")
    slider:SetHeight(16)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(0.15, 0.15, 0.15, 0.9)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(4)

    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slider:GetThumbTexture():SetSize(14, 22)

    local fmt = format or "%g"
    local updating = false

    slider:SetScript("OnValueChanged", function(_, value, userInput)
        if updating then return end
        value = Round(value, step)
        holder.value:SetText(string.format(fmt, value))
        if userInput then set(value) end
    end)

    function holder:Refresh()
        updating = true
        local value = get()
        slider:SetValue(value)
        self.value:SetText(string.format(fmt, value))
        updating = false
    end
    function holder:SetLocked(flag)
        slider:EnableMouse(not flag)
        self:SetAlpha(flag and 0.4 or 1)
    end
    return holder
end

-- ----------------------------------------------------------------
-- Lista suspensa
-- Cada item: { id, label }. Com `preview(item)` -> path, r, g, b a linha
-- ganha a textura desenhada atrás do nome (como nos addons de barras).
-- ----------------------------------------------------------------
local ROW_HEIGHT, MAX_ROWS, GUTTER = 20, 12, 8
local CHECK_TEXTURE = "Interface\\Buttons\\UI-CheckBox-Check"
local popup, catcher, popupState = nil, nil, { items = {}, offset = 0 }

local function ClosePopup()
    if popup then popup:Hide() end
    if catcher then catcher:Hide() end
end

--- Indicador de rolagem: só aparece quando a lista não cabe.
local function RenderScroll()
    local total = #popupState.items
    if total <= MAX_ROWS then
        popup.track:Hide()
        popup.thumb:Hide()
        return
    end
    local trackHeight = MAX_ROWS * ROW_HEIGHT
    local thumbHeight = math.max(12, trackHeight * MAX_ROWS / total)
    local maxOffset = total - MAX_ROWS
    local travel = trackHeight - thumbHeight
    popup.track:Show()
    popup.thumb:SetHeight(thumbHeight)
    popup.thumb:ClearAllPoints()
    popup.thumb:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -2, -4 - travel * popupState.offset / maxOffset)
    popup.thumb:Show()
end

local function RenderRow(row, item)
    row.item = item
    row.text:SetText(item.label)

    local preview = popupState.preview
    local path, r, g, b
    if preview then path, r, g, b = preview(item) end
    if path then
        row.bar:SetTexture(path)
        row.bar:SetVertexColor(r or 1, g or 1, b or 1, 1)
        row.bar:Show()
    else
        row.bar:Hide()
    end

    row.check:SetShown(item.id == popupState.current)
    row:Show()
end

local function RenderPopup()
    local items, offset = popupState.items, popupState.offset
    for i = 1, MAX_ROWS do
        local row = popup.rows[i]
        if not row then
            row = CreateFrame("Button", nil, popup)
            row:SetHeight(ROW_HEIGHT)
            row:SetPoint("TOPLEFT", popup, "TOPLEFT", 4, -4 - (i - 1) * ROW_HEIGHT)
            row:SetPoint("RIGHT", popup, "RIGHT", -GUTTER, 0)

            row.bar = row:CreateTexture(nil, "BACKGROUND")
            row.bar:SetPoint("TOPLEFT", 0, -1)
            row.bar:SetPoint("BOTTOMRIGHT", 0, 1)

            row.text = Label(row, "", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", 6, 0)
            row.text:SetPoint("RIGHT", -22, 0)
            row.text:SetJustifyH("LEFT")

            row.check = row:CreateTexture(nil, "OVERLAY")
            row.check:SetTexture(CHECK_TEXTURE)
            row.check:SetSize(16, 16)
            row.check:SetPoint("RIGHT", -4, 0)

            row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
            row.highlight:SetAllPoints()
            row.highlight:SetColorTexture(1, 1, 1, 0.15)

            row:SetScript("OnClick", function(self)
                local onSelect, item = popupState.onSelect, self.item
                ClosePopup()
                if onSelect and item then onSelect(item) end
            end)
            popup.rows[i] = row
        end

        local item = items[offset + i]
        if item then RenderRow(row, item) else row:Hide() end
    end
    RenderScroll()
end

local function BuildPopup()
    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN")
    catcher:Hide()
    catcher:SetScript("OnClick", ClosePopup)

    popup = Widgets.NewFrame(UIParent)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:EnableMouse(true)
    popup:EnableMouseWheel(true)
    popup:Hide()
    popup.rows = {}
    Widgets.Backdrop(popup, { 0.08, 0.08, 0.08, 0.98 }, { 0.45, 0.45, 0.45, 1 })

    popup.track = popup:CreateTexture(nil, "ARTWORK")
    popup.track:SetColorTexture(0.2, 0.2, 0.2, 0.9)
    popup.track:SetWidth(4)
    popup.track:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -2, -4)
    popup.track:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -2, 4)
    popup.thumb = popup:CreateTexture(nil, "OVERLAY")
    popup.thumb:SetColorTexture(0.7, 0.7, 0.7, 0.9)
    popup.thumb:SetWidth(4)

    popup:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = math.max(0, #popupState.items - MAX_ROWS)
        popupState.offset = math.max(0, math.min(maxOffset, popupState.offset - delta))
        RenderPopup()
    end)
end

--- Abre a lista logo abaixo de `anchor`. items = { {id, label}, ... }.
--- `preview` (opcional): função(item) -> caminho da textura, r, g, b.
function Widgets.OpenList(anchor, items, current, onSelect, preview)
    if not popup then BuildPopup() end
    popupState.items, popupState.current = items, current
    popupState.onSelect, popupState.preview = onSelect, preview

    local currentIndex = 1
    for i, item in ipairs(items) do
        if item.id == current then currentIndex = i break end
    end
    popupState.offset = math.max(0, math.min(currentIndex - 1, #items - MAX_ROWS))

    popup:SetSize(anchor:GetWidth(), math.min(#items, MAX_ROWS) * ROW_HEIGHT + 8)
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    catcher:Show()
    popup:Show()
    RenderPopup()
end

--- opts.preview: ver OpenList. opts.compact: sem rótulo (só o botão, 22px).
function Widgets.Dropdown(parent, text, getItems, get, set, width, opts)
    local compact = opts and opts.compact
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width or 200, compact and 22 or 42)

    if not compact then
        holder.label = Label(holder, text)
        holder.label:SetPoint("TOPLEFT")
    end

    local button = Widgets.NewFrame(holder)
    button:SetPoint("BOTTOMLEFT")
    button:SetSize(width or 200, 22)
    button:EnableMouse(true)
    Widgets.Backdrop(button, { 0.1, 0.1, 0.1, 0.95 }, { 0.45, 0.45, 0.45, 1 })

    button.text = Label(button, "", "GameFontHighlightSmall")
    button.text:SetPoint("LEFT", 6, 0)
    button.text:SetPoint("RIGHT", -18, 0)
    button.text:SetJustifyH("LEFT")
    button.arrow = Label(button, "v", "GameFontNormalSmall")
    button.arrow:SetPoint("RIGHT", -6, 0)

    local function Items()
        return type(getItems) == "function" and getItems() or getItems
    end

    holder.locked = false
    button:SetScript("OnMouseUp", function()
        if holder.locked then return end
        Widgets.OpenList(button, Items(), get(), function(item)
            set(item.id)
            holder:Refresh()
        end, opts and opts.preview)
    end)

    function holder:Refresh()
        local current = get()
        for _, item in ipairs(Items()) do
            if item.id == current then
                button.text:SetText(item.label)
                return
            end
        end
        button.text:SetText(tostring(current))
    end
    function holder:SetLocked(flag)
        self.locked = flag and true or false
        self:SetAlpha(flag and 0.4 or 1)
    end
    return holder
end

-- ----------------------------------------------------------------
-- Seletor de cor: quadrado colorido + nome. Clicar abre o
-- ColorPickerFrame da Blizzard (Okay/Cancelar, campo hexadecimal).
-- get() -> r, g, b | set(r, g, b) | isDisabled() -> bool (opcional)
-- ----------------------------------------------------------------
local pickerOwner -- swatch que abriu o seletor no momento

local function ClosePickerOf(owner)
    if pickerOwner == owner and ColorPickerFrame and ColorPickerFrame:IsShown() then
        ColorPickerFrame:Hide()
    end
    if pickerOwner == owner then pickerOwner = nil end
end

local function OpenPicker(owner, get, set)
    if not ColorPickerFrame then return end
    local r, g, b = get()
    local function Live()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        set(nr, ng, nb)
    end
    local function Cancel() set(r, g, b) end -- volta à cor de antes de abrir

    pickerOwner = owner
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b, hasOpacity = false,
            swatchFunc = Live, cancelFunc = Cancel,
        })
    else -- cliente com a API antiga
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.opacity = nil
        ColorPickerFrame.func = Live
        ColorPickerFrame.cancelFunc = Cancel
        ColorPickerFrame.previousValues = { r = r, g = g, b = b }
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Hide() -- força o OnShow a reler as cores
        ColorPickerFrame:Show()
    end
end

-- Compartilhados com o Skin (amostra de cor no estilo da Blizzard)
Widgets.OpenColorPicker = OpenPicker
Widgets.CloseColorPicker = ClosePickerOf

function Widgets.ColorSwatch(parent, text, get, set, isDisabled)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(200, 24)

    local button = Widgets.NewFrame(holder)
    button:SetSize(24, 24)
    button:SetPoint("LEFT")
    button:EnableMouse(true)
    Widgets.Backdrop(button, { 0, 0, 0, 1 }, { 0.6, 0.6, 0.6, 1 })

    button.color = button:CreateTexture(nil, "ARTWORK")
    button.color:SetPoint("TOPLEFT", 2, -2)
    button.color:SetPoint("BOTTOMRIGHT", -2, 2)

    holder.label = Label(holder, text)
    holder.label:SetPoint("LEFT", button, "RIGHT", 8, 0)

    holder.disabled = false
    button:SetScript("OnMouseUp", function()
        if holder.disabled then return end
        OpenPicker(holder, get, set)
    end)

    function holder:Refresh()
        local r, g, b = get()
        button.color:SetColorTexture(r, g, b, 1)

        self.disabled = isDisabled and isDisabled() or false
        holder:SetAlpha(self.disabled and 0.4 or 1)
        if self.disabled then ClosePickerOf(self) end
    end
    return holder
end
