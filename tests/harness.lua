-- ============================================================
--  harness.lua — WoW simulado + testes do WowUtilities.
--  Rodado por tests/run.py (lupa, Lua 5.1), uma vez por variação.
--  Entradas (globais definidas pelo run.py):
--    HARNESS_ROOT    pasta do addon
--    HARNESS_FILES   arquivos na ordem do .toc
--    HARNESS_VARIANT { name, locale, editmode, legacyDb, lsm, oldPicker, coin }
--  Devolve { fail = n, pass = n, lines = { ... } }.
--
--  Organização:
--    1. Núcleo do simulador (H): tempo, eventos, erros, prints.
--    2. Widgets (frames, texturas, textos) com geometria simples.
--    3. APIs do jogo (unidades, itens, bolsas, voo, tooltip...).
--    4. Variação (locale, LibEditMode, LibSharedMedia, banco legado...).
--    5. Carga do addon na ordem do .toc e boot (ADDON_LOADED).
--    6. Testes, um bloco por módulo.
--  Os testes compartilham o estado do jogo e rodam em ordem.
-- ============================================================

local VARIANT = HARNESS_VARIANT
local unpack = unpack or table.unpack

-- ================================================================
-- 1. Núcleo do simulador
-- ================================================================

local H = { now = 1000, timers = {}, errors = {}, printed = {}, all = {}, eventFrames = {} }

local originals = {} -- set(nome, valor) guarda o valor original UMA vez (restore() volta a ele)

--- Troca uma global durante um teste; restore() devolve todas ao valor original.
local function set(name, value)
    if originals[name] == nil then originals[name] = { value = rawget(_G, name) } end
    rawset(_G, name, value)
end

local function restore()
    for name, saved in pairs(originals) do rawset(_G, name, saved.value) end
    originals = {}
end

function GetTime() return H.now end
time = os.time
date = os.date

C_Timer = {
    After = function(delay, fn)
        H.timers[#H.timers + 1] = { at = H.now + (delay or 0), fn = fn, seq = #H.timers + 1 }
    end,
}

--- Avança o relógio, roda os timers vencidos (inclusive os criados por eles) e,
--- no fim, um OnUpdate dos frames visíveis (no jogo ele roda a cada quadro).
function H.advance(seconds)
    H.runTimers(seconds)
    local elapsed = seconds or 0
    for _, obj in ipairs(H.all) do
        local s = rawget(obj, "__h")
        if s.scripts and s.scripts.OnUpdate and obj:IsVisible() then H.script(obj, "OnUpdate", elapsed) end
    end
end

function H.runTimers(seconds)
    local target = H.now + (seconds or 0)
    while true do
        local best, index
        for i, timer in ipairs(H.timers) do
            if timer.at <= target and (not best or timer.at < best.at) then best, index = timer, i end
        end
        if not best then break end
        table.remove(H.timers, index)
        if best.at > H.now then H.now = best.at end
        local ok, err = pcall(best.fn)
        if not ok then H.errors[#H.errors + 1] = err end
    end
    H.now = target
end

local function ErrorHandler(err) H.errors[#H.errors + 1] = tostring(err) end
function geterrorhandler() return ErrorHandler end
function seterrorhandler() end

print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    H.printed[#H.printed + 1] = table.concat(parts, " ")
end

--- Última mensagem impressa que contém `text` (busca literal), ou nil.
function H.printedWith(text, since)
    for i = #H.printed, (since or 0) + 1, -1 do
        if H.printed[i]:find(text, 1, true) then return H.printed[i] end
    end
end

-- Utilitários globais do WoW
tinsert, tremove, tContains = table.insert, table.remove, function(t, v)
    for _, x in pairs(t) do if x == v then return true end end
    return false
end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strsplit = function(sep, text, limit)
    local out, pos = {}, 1
    while true do
        if limit and #out == limit - 1 then break end
        local s, e = text:find(sep, pos, true)
        if not s then break end
        out[#out + 1] = text:sub(pos, s - 1)
        pos = e + 1
    end
    out[#out + 1] = text:sub(pos)
    return unpack(out)
end
strjoin = function(sep, ...) return table.concat({ ... }, sep) end
strlower, strupper, strfind, strsub, strlen, strmatch, gsub, format =
    string.lower, string.upper, string.find, string.sub, string.len, string.match, string.gsub, string.format
floor, ceil, abs, max, min, mod = math.floor, math.ceil, math.abs, math.max, math.min, math.fmod
debugstack = function() return "" end

function hooksecurefunc(a, b, c)
    local tbl, name, fn = a, b, c
    if type(a) == "string" then tbl, name, fn = _G, a, b end
    local original = tbl[name]
    assert(type(original) == "function", "hooksecurefunc: " .. tostring(name) .. " nao e funcao")
    tbl[name] = function(...)
        local r = { original(...) }
        fn(...)
        return unpack(r)
    end
end

-- ================================================================
-- 2. Widgets
-- ================================================================

local SCREEN_W, SCREEN_H = 1920, 1080
local Classes = {}

local function Class(name, parent)
    local methods = setmetatable({}, parent and { __index = Classes[parent].methods } or nil)
    Classes[name] = { methods = methods, meta = { __index = methods }, parent = parent }
    return methods
end

local function S(obj) return rawget(obj, "__h") end

local function New(kind, name, parent)
    local obj = setmetatable({ __h = {
        kind = kind, name = name, parent = parent, shown = true, points = {}, scripts = {},
        width = 0, height = 0, scale = 1, alpha = 1, level = 1, events = {}, children = {}, id = 0,
    } }, Classes[kind].meta)
    if parent and S(parent) then local kids = S(parent).children; kids[#kids + 1] = obj end
    if type(name) == "string" then rawset(_G, name, obj) end
    H.all[#H.all + 1] = obj
    return obj
end

--- Chama o script `name` do objeto (sem erro se não houver).
function H.script(obj, name, ...)
    local fn = S(obj).scripts[name]
    if fn then
        local ok, err = pcall(fn, obj, ...)
        if not ok then H.errors[#H.errors + 1] = err end
    end
end

-- ----- Region (base de tudo) -----
local Region = Class("Region")

function Region:GetName() return S(self).name end
function Region:GetObjectType() return S(self).kind end
function Region:IsObjectType(kind)
    local class = S(self).kind
    while class do
        if class == kind then return true end
        class = Classes[class].parent
    end
    return false
end
function Region:GetParent() return S(self).parent end
function Region:SetParent(parent) S(self).parent = parent end
function Region:IsShown() return S(self).shown end
function Region:IsVisible()
    local obj = self
    while obj do
        if not S(obj) or not S(obj).shown then return false end
        obj = S(obj).parent
    end
    return true
end
function Region:Show()
    local s = S(self)
    if s.shown then return end
    s.shown = true
    H.script(self, "OnShow")
end
function Region:Hide()
    local s = S(self)
    if not s.shown then return end
    s.shown = false
    H.script(self, "OnHide")
end
function Region:SetShown(flag) if flag then self:Show() else self:Hide() end end

local function Resolve(rel) if type(rel) == "string" then return rawget(_G, rel) end return rel end

function Region:SetPoint(point, rel, relPoint, x, y)
    local s = S(self)
    if type(rel) == "number" then -- SetPoint("TOPLEFT", 10, -5)
        rel, relPoint, x, y = nil, nil, rel, relPoint
    elseif type(relPoint) == "number" then -- SetPoint("TOPLEFT", frame, 10, -5)
        relPoint, x, y = nil, relPoint, x
    end
    rel = Resolve(rel) or s.parent or UIParent
    assert(type(point) == "string", "SetPoint: ponto invalido")
    for i, p in ipairs(s.points) do
        if p.point == point then table.remove(s.points, i) break end
    end
    s.points[#s.points + 1] = { point = point, rel = rel, relPoint = relPoint or point, x = x or 0, y = y or 0 }
end
function Region:SetAllPoints(rel)
    rel = Resolve(rel) or S(self).parent or UIParent
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", rel, "TOPLEFT", 0, 0)
    self:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0)
end
function Region:ClearAllPoints() S(self).points = {} end
function Region:GetNumPoints() return #S(self).points end
function Region:GetPoint(i)
    local p = S(self).points[i or 1]
    if p then return p.point, p.rel, p.relPoint, p.x, p.y end
end
function Region:SetWidth(w) S(self).width = w end
function Region:SetHeight(h) S(self).height = h end
function Region:SetSize(w, h) S(self).width, S(self).height = w, h or w end

local function AnchorXY(rect, point)
    local x = point:find("LEFT") and rect.l or (point:find("RIGHT") and rect.r) or (rect.l + rect.r) / 2
    local y = point:find("TOP") and rect.t or (point:find("BOTTOM") and rect.b) or (rect.b + rect.t) / 2
    return x, y
end

--- Retângulo na tela { l, b, r, t } (sem considerar escala), ou nil sem pontos.
function H.rect(obj, depth)
    depth = depth or 0
    if obj == UIParent then return { l = 0, b = 0, r = SCREEN_W, t = SCREEN_H } end
    local s = S(obj)
    if not s or #s.points == 0 or depth > 30 then return nil end
    local w, h = s.width, s.height
    local left, right, top, bottom, cx, cy
    for _, p in ipairs(s.points) do
        local rr = H.rect(p.rel, depth + 1)
        if not rr then return nil end
        local ax, ay = AnchorXY(rr, p.relPoint)
        ax, ay = ax + p.x, ay + p.y
        if p.point:find("LEFT") then left = ax elseif p.point:find("RIGHT") then right = ax else cx = ax end
        if p.point:find("TOP") then top = ay elseif p.point:find("BOTTOM") then bottom = ay else cy = ay end
    end
    if left and right then w = right - left end
    if top and bottom then h = top - bottom end
    local l = left or (right and right - w) or (cx - w / 2)
    local b = bottom or (top and top - h) or (cy - h / 2)
    return { l = l, b = b, r = l + w, t = b + h }
end

function Region:GetWidth()
    local s = S(self)
    if #s.points > 1 then local r = H.rect(self); if r then return r.r - r.l end end
    return s.width
end
function Region:GetHeight()
    local s = S(self)
    if #s.points > 1 then local r = H.rect(self); if r then return r.t - r.b end end
    return s.height
end
function Region:GetSize() return self:GetWidth(), self:GetHeight() end
function Region:GetLeft() local r = H.rect(self) return r and r.l end
function Region:GetRight() local r = H.rect(self) return r and r.r end
function Region:GetTop() local r = H.rect(self) return r and r.t end
function Region:GetBottom() local r = H.rect(self) return r and r.b end
function Region:GetCenter()
    local r = H.rect(self)
    if r then return (r.l + r.r) / 2, (r.b + r.t) / 2 end
end
function Region:SetAlpha(a) S(self).alpha = a end
function Region:GetAlpha() return S(self).alpha end
function Region:SetScale(scale) S(self).scale = scale end
function Region:GetScale() return S(self).scale end
function Region:GetEffectiveScale()
    local scale, obj = 1, self
    while obj and S(obj) do scale = scale * S(obj).scale; obj = S(obj).parent end
    return scale
end
function Region:SetDrawLayer() end
function Region:IsMouseOver() return H.mouseOver == self end

-- ----- Texture -----
local Texture = Class("Texture", "Region")
function Texture:SetTexture(path) S(self).texture = path end
function Texture:GetTexture() return S(self).texture end
function Texture:SetColorTexture(r, g, b, a) S(self).color = { r, g, b, a } end
function Texture:SetVertexColor(r, g, b, a) S(self).vertex = { r, g, b, a } end
function Texture:GetVertexColor() local c = S(self).vertex or { 1, 1, 1, 1 } return unpack(c) end
function Texture:SetBlendMode() end
function Texture:SetTexCoord() end
function Texture:SetDesaturated() end
function Texture:SetAtlas(atlas) S(self).texture = atlas end

-- ----- FontString -----
local FontString = Class("FontString", "Region")
function FontString:SetText(text) S(self).text = text end
function FontString:GetText() return S(self).text end
function FontString:SetFormattedText(fmt, ...) S(self).text = string.format(fmt, ...) end
function FontString:SetFont(path, size, flags) S(self).font = { path, size, flags } return true end
function FontString:GetFont() local f = S(self).font or { "Fonts\\FRIZQT__.TTF", 12, "" } return unpack(f) end
function FontString:SetFontObject(obj) S(self).fontObject = obj end
function FontString:SetTextColor(r, g, b, a) S(self).textColor = { r, g, b, a } end
function FontString:GetTextColor() local c = S(self).textColor or { 1, 1, 1, 1 } return unpack(c) end
function FontString:SetJustifyH(v) S(self).justifyH = v end
function FontString:SetJustifyV() end
function FontString:SetWordWrap() end
function FontString:SetNonSpaceWrap() end
function FontString:SetMaxLines() end
function FontString:SetShadowOffset() end
function FontString:GetStringWidth() return #(S(self).text or "") * 6 end
function FontString:GetStringHeight() return 12 end

-- ----- Frame -----
local Frame = Class("Frame", "Region")
function Frame:SetScript(name, fn) S(self).scripts[name] = fn end
function Frame:GetScript(name) return S(self).scripts[name] end
function Frame:HasScript() return true end
function Frame:HookScript(name, fn)
    local old = S(self).scripts[name]
    if old then
        S(self).scripts[name] = function(...) old(...); fn(...) end
    else
        S(self).scripts[name] = fn
    end
end
function Frame:RegisterEvent(event)
    local s = S(self)
    if not s.events[event] then
        s.events[event] = true
        H.eventFrames[#H.eventFrames + 1] = self
    end
end
function Frame:UnregisterEvent(event) S(self).events[event] = nil end
function Frame:UnregisterAllEvents() S(self).events = {} end
function Frame:IsEventRegistered(event) return S(self).events[event] == true end
function Frame:CreateTexture(name, layer) return New("Texture", name, self) end
function Frame:CreateFontString(name, layer, template) return New("FontString", name, self) end
function Frame:SetFrameStrata(v) S(self).strata = v end
function Frame:GetFrameStrata() return S(self).strata or "MEDIUM" end
function Frame:SetFrameLevel(v) S(self).level = v end
function Frame:GetFrameLevel() return S(self).level end
function Frame:SetClampedToScreen() end
function Frame:SetMovable(v) S(self).movable = v end
function Frame:IsMovable() return S(self).movable == true end
function Frame:EnableMouse(v) S(self).mouse = v end
function Frame:IsMouseEnabled() return S(self).mouse == true end
function Frame:EnableMouseWheel() end
function Frame:EnableKeyboard() end
function Frame:RegisterForDrag() end
function Frame:RegisterForClicks() end
function Frame:StartMoving() end
function Frame:StopMovingOrSizing() end
function Frame:SetID(id) S(self).id = id end
function Frame:GetID() return S(self).id end
function Frame:GetChildren() return unpack(S(self).children) end
function Frame:GetNumChildren() return #S(self).children end
function Frame:SetToplevel() end
function Frame:Raise() end
function Frame:SetHitRectInsets() end

local BackdropMethods = {
    SetBackdrop = function(self, info) S(self).backdrop = info end,
    GetBackdrop = function(self) return S(self).backdrop end,
    SetBackdropColor = function(self, r, g, b, a) S(self).backdropColor = { r, g, b, a } end,
    SetBackdropBorderColor = function(self, r, g, b, a) S(self).borderColor = { r, g, b, a } end,
}

-- ----- Button / CheckButton -----
local Button = Class("Button", "Frame")
function Button:SetText(text) S(self).text = text end
function Button:GetText() return S(self).text end
function Button:Click(button)
    if S(self).enabled == false then return end
    H.script(self, "OnClick", button or "LeftButton", false)
end
function Button:Enable() S(self).enabled = true end
function Button:Disable() S(self).enabled = false end
function Button:SetEnabled(flag) S(self).enabled = flag and true or false end
function Button:IsEnabled() return S(self).enabled ~= false end
function Button:SetNormalFontObject() end
function Button:SetHighlightFontObject() end
function Button:SetDisabledFontObject() end
function Button:SetNormalTexture() end
function Button:SetPushedTexture() end
function Button:SetHighlightTexture() end
function Button:GetFontString() return nil end

local CheckButton = Class("CheckButton", "Button")
function CheckButton:SetChecked(v) S(self).checked = v and true or false end
function CheckButton:GetChecked() return S(self).checked == true end
function CheckButton:SetCheckedTexture(t) S(self).checkedTexture = t end
function CheckButton:SetDisabledCheckedTexture(t) S(self).disabledCheckedTexture = t end
function CheckButton:Click(button)
    if S(self).enabled == false then return end
    S(self).checked = not S(self).checked
    H.script(self, "OnClick", button or "LeftButton", false)
end

Class("DropdownButton", "Button")
local Dropdown = Classes.DropdownButton.methods
function Dropdown:SetupMenu(generator) S(self).generator = generator; self:GenerateMenu() end
function Dropdown:GenerateMenu()
    local root = { radios = {} }
    function root:CreateRadio(label, isSelected, onSelect)
        local description = { label = label, isSelected = isSelected, onSelect = onSelect, initializers = {} }
        function description:AddInitializer(fn) self.initializers[#self.initializers + 1] = fn end
        self.radios[#self.radios + 1] = description
        return description
    end
    S(self).generator(self, root)
    S(self).menu = root
end

-- ----- StatusBar / Slider -----
local StatusBar = Class("StatusBar", "Frame")
function StatusBar:SetMinMaxValues(a, b) S(self).min, S(self).max = a, b end
function StatusBar:GetMinMaxValues() return S(self).min, S(self).max end
function StatusBar:SetValue(v) S(self).value = v end
function StatusBar:GetValue() return S(self).value end
function StatusBar:SetStatusBarTexture(path) S(self).barTexture = path end
function StatusBar:GetStatusBarTexture() return S(self).barTexture end
function StatusBar:SetStatusBarColor(r, g, b) S(self).barColor = { r, g, b } end
function StatusBar:GetStatusBarColor() return unpack(S(self).barColor or { 1, 1, 1 }) end

local Slider = Class("Slider", "Frame")
function Slider:SetMinMaxValues(a, b) S(self).min, S(self).max = a, b end
function Slider:GetMinMaxValues() return S(self).min, S(self).max end
function Slider:SetValueStep(v) S(self).step = v end
function Slider:SetObeyStepOnDrag() end
function Slider:SetOrientation() end
function Slider:SetThumbTexture(path)
    S(self).thumb = S(self).thumb or New("Texture", nil, self)
    S(self).thumb:SetTexture(path)
end
function Slider:GetThumbTexture() return S(self).thumb end
function Slider:GetValue() return S(self).value end
local function SetSliderValue(self, v, userInput)
    local s = S(self)
    if s.min then v = math.max(s.min, math.min(s.max, v)) end
    if s.value == v then return end
    s.value = v
    H.script(self, "OnValueChanged", v, userInput)
end
function Slider:SetValue(v) SetSliderValue(self, v, false) end
--- Simula o jogador arrastando o slider.
function H.slide(slider, v) SetSliderValue(slider, v, true) end

-- ----- EditBox / ScrollFrame / Cooldown -----
local EditBox = Class("EditBox", "Frame")
function EditBox:SetText(text)
    S(self).text = text
    H.script(self, "OnTextChanged", false)
end
function EditBox:GetText() return S(self).text or "" end
function EditBox:SetMultiLine() end
function EditBox:SetAutoFocus() end
function EditBox:SetFontObject() end
function EditBox:SetFocus() S(self).focus = true end
function EditBox:ClearFocus() S(self).focus = false end
function EditBox:HighlightText() S(self).highlighted = true end
function EditBox:SetMaxLetters() end
function EditBox:SetTextInsets() end
function EditBox:Insert(text) self:SetText((S(self).text or "") .. text) end

local ScrollFrame = Class("ScrollFrame", "Frame")
function ScrollFrame:SetScrollChild(child) S(self).child = child end
function ScrollFrame:GetScrollChild() return S(self).child end
function ScrollFrame:SetVerticalScroll() end

local Cooldown = Class("Cooldown", "Frame")
function Cooldown:SetCooldown(start, duration) S(self).cooldown = { start, duration } end
function Cooldown:Clear() S(self).cooldown = nil end
function Cooldown:SetDrawEdge() end
function Cooldown:SetHideCountdownNumbers() end

-- ----- GameTooltip -----
local Tooltip = Class("GameTooltip", "Frame")
function Tooltip:SetOwner(owner) S(self).owner = owner; S(self).lines = {} end
function Tooltip:ClearLines() S(self).lines = {} end
local function SyncLines(self)
    local name = S(self).name
    if not name then return end
    for i, text in ipairs(S(self).lines) do
        local region = rawget(_G, name .. "TextLeft" .. i) or New("FontString", name .. "TextLeft" .. i, self)
        region:SetText(text)
    end
end
function Tooltip:AddLine(text) local l = S(self).lines; l[#l + 1] = text; SyncLines(self) end
function Tooltip:AddDoubleLine(a) self:AddLine(a) end
function Tooltip:NumLines() return #(S(self).lines or {}) end
function Tooltip:SetHyperlink(link) S(self).hyperlink = link end
function Tooltip:SetInventoryItem(unit, slot)
    S(self).lines = {}
    for _, text in ipairs(H.inventoryTooltip(slot) or {}) do self:AddLine(text) end
end
function Tooltip:GetUnit()
    local unit = H.tooltipUnit
    local data = unit and H.units[unit]
    return data and data.name, unit
end
function Tooltip:SetUnit(unit) H.tooltipUnit = unit end

-- ----- CreateFrame -----
function CreateFrame(kind, name, parent, template)
    if not Classes[kind] or kind == "Region" or kind == "Texture" or kind == "FontString" then
        error("CreateFrame: tipo desconhecido " .. tostring(kind), 2)
    end
    local obj = New(kind, name, parent)
    if type(template) == "string" and template:find("BackdropTemplate") then
        for key, fn in pairs(BackdropMethods) do rawset(obj, key, fn) end
    end
    if type(template) == "string" and not VARIANT.noTemplates then
        for each in template:gmatch("[^,%s]+") do
            if H.templates[each] then H.templates[each](obj) end
        end
    end
    return obj
end

-- Templates da Blizzard simulados (só as peças que o addon usa; ver /wu debug ui).
-- Variações com noTemplates ficam sem eles para testar os fallbacks do Skin.
H.templates = {
    SettingsFrameTemplate = function(obj)
        obj.NineSlice = New("Frame", nil, obj)
        obj.NineSlice.Text = New("FontString", nil, obj.NineSlice)
        obj.Bg = New("Frame", nil, obj)
        obj.ClosePanelButton = New("Button", nil, obj)
    end,
    TooltipBackdropTemplate = function(obj) obj.NineSlice = New("Frame", nil, obj) end,
    ScrollFrameTemplate = function(obj) obj.ScrollBar = New("Frame", nil, obj) end,
    ColorSwatchTemplate = function(obj)
        obj.Color = New("Texture", nil, obj)
        obj.SwatchBg = New("Texture", nil, obj)
        obj.InnerBorder = New("Texture", nil, obj)
    end,
    MinimalSliderWithSteppersTemplate = function(obj)
        obj.Slider = New("Slider", nil, obj)
        obj.RightText = New("FontString", nil, obj)
        local callbacks = {}
        function obj:Init(value, minValue, maxValue, steps, formatters)
            self.formatters = formatters
            self.Slider:SetMinMaxValues(minValue, maxValue)
            self.Slider:SetValue(value)
        end
        function obj:RegisterCallback(event, fn, owner) callbacks[#callbacks + 1] = { fn = fn, owner = owner } end
        function obj:SetValue(v) self.Slider:SetValue(v) end
        function obj:GetValue() return self.Slider:GetValue() end
        function obj:SetEnabled(flag) self.enabled = flag end
        obj.Slider:SetScript("OnValueChanged", function(_, value)
            local format = obj.formatters and obj.formatters[MinimalSliderWithSteppersMixin.Label.Right]
            if format then obj.RightText:SetText(format(value)) end
            for _, c in ipairs(callbacks) do c.fn(c.owner, value) end
        end)
    end,
}
if not VARIANT.noTemplates then
    MinimalSliderWithSteppersMixin = { Event = { OnValueChanged = "OnValueChanged" }, Label = { Right = "Right" } }
    C_Texture = { GetAtlasInfo = function(name) return { width = 16, height = 16, file = name } end }
end

--- Procura o primeiro objeto criado que satisfaz `pred`.
function H.find(pred)
    for _, obj in ipairs(H.all) do
        local ok, hit = pcall(pred, obj)
        if ok and hit then return obj end
    end
end

--- FontString com exatamente esse texto (opcionalmente dentro de `ancestor`).
function H.findText(text, kind)
    return H.find(function(o) return S(o).kind == (kind or "FontString") and S(o).text == text end)
end

-- ================================================================
-- 3. APIs do jogo
-- ================================================================

UIParent = New("Frame", "UIParent")
UIParent:SetSize(SCREEN_W, SCREEN_H)
WorldFrame = New("Frame", "WorldFrame")
UISpecialFrames = {}
SlashCmdList = {}
BackdropTemplateMixin = {}
CANCEL = "Cancel"
UNKNOWNOBJECT = "Unknown"
FACTION_HORDE, FACTION_ALLIANCE = "Horde", "Alliance"
ENCHANTED_TOOLTIP_LINE = "Enchanted: %s"
DELETE_ITEM_CONFIRM_STRING = "DELETE"
NUM_BAG_SLOTS = 4
ITEM_QUALITY_COLORS = {
    [0] = { r = 0.62, g = 0.62, b = 0.62 }, [1] = { r = 1, g = 1, b = 1 },
    [2] = { r = 0.12, g = 1, b = 0 }, [3] = { r = 0, g = 0.44, b = 0.87 },
    [4] = { r = 0.64, g = 0.21, b = 0.93 }, [5] = { r = 1, g = 0.5, b = 0 },
}

local function FontObject(size)
    return { GetFont = function() return "Fonts\\FRIZQT__.TTF", size, "" end }
end
for _, name in ipairs({ "GameFontNormal", "GameFontNormalLarge", "GameFontHighlight", "GameFontHighlightSmall",
                        "GameFontDisableSmall", "GameFontNormalSmall", "NumberFontNormal",
                        "NumberFontNormalSmall", "ChatFontNormal" }) do
    _G[name] = FontObject(12)
end

function CreateColor(r, g, b, a)
    return { r = r, g = g, b = b, a = a or 1, GetRGB = function(c) return c.r, c.g, c.b end }
end

Enum = {
    TooltipDataType = { Item = 0, Unit = 2 },
    TransmogCollectionType = { Head = 1, Shoulder = 2, Back = 3, Chest = 4, Shirt = 5, Tabard = 6,
                               Wrist = 7, Hands = 8, Waist = 9, Legs = 10, Feet = 11, Wand = 12 },
    ItemClass = { Weapon = 2, Armor = 4 },
}

H.postCalls = {}
TooltipDataProcessor = {
    AddTooltipPostCall = function(kind, fn)
        H.postCalls[kind] = H.postCalls[kind] or {}
        table.insert(H.postCalls[kind], fn)
    end,
}

GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
GameTooltip.NineSlice = { SetBorderColor = function(self, r, g, b, a) self.color = { r, g, b, a } end }

--- Monta a tooltip de unidade com essas linhas e roda os post-calls (como o jogo).
function H.showUnitTooltip(unit, lines)
    H.tooltipUnit = unit
    GameTooltip:SetOwner(UIParent)
    for _, text in ipairs(lines) do GameTooltip:AddLine(text) end
    for _, fn in ipairs(H.postCalls[Enum.TooltipDataType.Unit] or {}) do
        local ok, err = pcall(fn, GameTooltip, {})
        if not ok then H.errors[#H.errors + 1] = err end
    end
end

-- ----- Unidades -----
H.units = {
    player = { name = "Tester", guid = "Player-1-0001", class = "Warrior", classFile = "WARRIOR",
               faction = "Horde", factionName = "Horde", isPlayer = true, classification = "normal" },
    mouseover = { name = "Thrall", guid = "Player-1-0002", class = "Shaman", classFile = "SHAMAN",
                  faction = "Horde", factionName = "Horde", isPlayer = true, pvpName = "Warchief Thrall",
                  classification = "normal" },
}
local function U(unit) return H.units[unit] end
function UnitExists(unit) return U(unit) ~= nil end
function UnitName(unit) local u = U(unit) if u then return u.name, u.realm end end
function UnitFullName(unit) local u = U(unit) if u then return u.name, u.realm end end
function UnitPVPName(unit) local u = U(unit) return u and u.pvpName end
function GetUnitName(unit) local u = U(unit) return u and u.name end
function UnitGUID(unit) local u = U(unit) return u and u.guid end
function GetPlayerInfoByGUID(guid)
    for _, u in pairs(H.units) do
        if u.guid == guid then return u.class, u.classFile, "Orc", "Orc", 2, u.name, u.realm end
    end
end
function UnitFactionGroup(unit) local u = U(unit) if u then return u.faction, u.factionName end end
function UnitIsVisible(unit) return U(unit) ~= nil end
function UnitIsPlayer(unit) local u = U(unit) return u ~= nil and u.isPlayer == true end
function UnitClass(unit) local u = U(unit) if u then return u.class, u.classFile end end
function UnitClassification(unit) local u = U(unit) return u and u.classification end
function UnitLevel() return 60 end
function UnitOnTaxi() return H.onTaxi == true end
function InCombatLockdown() return H.combat == true end
function GetLocale() return VARIANT.locale end

-- ----- Itens -----
H.items = {
    [1001] = { name = "Helm of Testing", equipLoc = "INVTYPE_HEAD", ilvl = 200, quality = 4, classID = 4, subClassID = 4 },
    [1002] = { name = "Healing Potion", equipLoc = "INVTYPE_NON_EQUIP_IGNORE", ilvl = 5, quality = 1, classID = 0, subClassID = 1 },
    [1003] = { name = "Chestguard", equipLoc = "INVTYPE_CHEST", ilvl = 210, quality = 3, classID = 4, subClassID = 4 },
    [1004] = { name = "Trinket A", equipLoc = "INVTYPE_TRINKET", ilvl = 180, quality = 3, classID = 4, subClassID = 0 },
    [1005] = { name = "Trinket B", equipLoc = "INVTYPE_TRINKET", ilvl = 190, quality = 4, classID = 4, subClassID = 0 },
    [1006] = { name = "Trinket C", equipLoc = "INVTYPE_TRINKET", ilvl = 170, quality = 2, classID = 4, subClassID = 0 },
    [1007] = { name = "Band", equipLoc = "INVTYPE_FINGER", ilvl = 150, quality = 2, classID = 4, subClassID = 0 },
    [1008] = { name = "Cloth Robe", equipLoc = "INVTYPE_ROBE", ilvl = 100, quality = 2, classID = 4, subClassID = 1 },
    [1009] = { name = "Leather Vest", equipLoc = "INVTYPE_CHEST", ilvl = 100, quality = 2, classID = 4, subClassID = 2 },
}
H.enchantNames = { [1888] = "+4 All Stats" }

function H.link(id, enchant)
    local item = H.items[id]
    return string.format("|cffffffff|Hitem:%d:%d::::::::60:::::|h[%s]|h|r", id, enchant or 0, item.name)
end
local function ItemOf(link)
    if type(link) == "number" then return H.items[link], link end
    local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
    return id and H.items[id], id
end

C_Item = {
    GetItemInfoInstant = function(link)
        local item, id = ItemOf(link)
        if not item then return nil end
        return id, "Armor", "Misc", item.equipLoc, "icon" .. id, item.classID, item.subClassID
    end,
    GetDetailedItemLevelInfo = function(link)
        local item = ItemOf(link)
        return item and item.ilvl
    end,
    GetItemInfo = function(link)
        local item = ItemOf(link)
        if item then return item.name, link, item.quality, item.ilvl end
    end,
    EquipItemByName = function(link, slot)
        for bag, slots in pairs(H.bags) do
            for i, entry in pairs(slots) do
                if H.link(entry.id, entry.enchant) == link then
                    slots[i] = H.inv[slot]
                    H.inv[slot] = entry
                    return
                end
            end
        end
    end,
}

-- Bolsas: H.bags[bag][slot] = { id, enchant }; inventário: H.inv[slot] = { id, enchant }
H.bags = { [0] = { [1] = { id = 1001 }, [2] = { id = 1002 }, [3] = { id = 1004 }, [4] = { id = 1005 } } }
H.inv = { [1] = { id = 1001 }, [5] = { id = 1003, enchant = 1888 }, [11] = { id = 1007 }, [13] = { id = 1006 } }

local function BagEntry(bag, slot) return H.bags[bag] and H.bags[bag][slot] end
C_Container = {
    GetContainerNumSlots = function(bag) return H.bags[bag] and 16 or 0 end,
    GetContainerItemLink = function(bag, slot)
        local e = BagEntry(bag, slot)
        return e and H.link(e.id, e.enchant)
    end,
    GetContainerItemInfo = function(bag, slot)
        local e = BagEntry(bag, slot)
        if e then return { itemID = e.id, quality = H.items[e.id].quality, hyperlink = H.link(e.id, e.enchant) } end
    end,
    GetContainerItemCooldown = function() return 0, 0, 1 end,
    PickupContainerItem = function() end,
}
function GetInventoryItemLink(unit, slot) local e = H.inv[slot] return e and H.link(e.id, e.enchant) end
function GetInventoryItemQuality(unit, slot) local e = H.inv[slot] return e and H.items[e.id].quality end
function GetInventoryItemTexture(unit, slot) local e = H.inv[slot] return e and ("icon" .. e.id) end
function GetInventoryItemCooldown() return 0, 0, 1 end
function GetInventoryItemID(unit, slot) local e = H.inv[slot] return e and e.id end
function PickupInventoryItem() end
function CursorHasItem() return false end
function ClearCursor() end

function H.inventoryTooltip(slot)
    local e = H.inv[slot]
    if not e then return nil end
    local lines = { H.items[e.id].name }
    if e.enchant and e.enchant ~= 0 then lines[#lines + 1] = ENCHANTED_TOOLTIP_LINE:format(H.enchantNames[e.enchant]) end
    return lines
end
C_TooltipInfo = {
    GetInventoryItem = function(unit, slot)
        local lines = {}
        for _, text in ipairs(H.inventoryTooltip(slot) or {}) do lines[#lines + 1] = { leftText = text } end
        return { lines = lines }
    end,
}

H.professions = {} -- índices; GetProfessionInfo devolve skillLine 333 para o índice 7
function GetProfessions() return unpack(H.professions) end
function GetProfessionInfo(index)
    if index == 7 then return "Enchanting", 1, 300, 300, 0, 0, 333 end
    return "Mining", 1, 300, 300, 0, 0, 186
end

-- ----- Dinheiro / vendedor -----
H.money = 10000
function GetMoney() return H.money end
function RepairAllItems() end
if VARIANT.coin then
    C_CurrencyInfo = { GetCoinTextureString = function(copper) return "COIN(" .. copper .. ")" end }
end

-- ----- Voo -----
H.taxi = {
    nodes = {
        { name = "Orgrimmar, Durotar", type = "CURRENT", x = 0.5, y = 0.5 },
        { name = "Crossroads, The Barrens", type = "REACHABLE", x = 0.5, y = 0.8 },
        { name = "Booty Bay, Stranglethorn", type = "REACHABLE", x = 0.5, y = 1.2 },
    },
    routes = { [2] = { { 1, 2 } }, [3] = { { 1, 2 }, { 2, 3 } } },
}
function NumTaxiNodes() return #H.taxi.nodes end
function TaxiNodeName(i) return H.taxi.nodes[i] and H.taxi.nodes[i].name end
function TaxiNodeGetType(i) return H.taxi.nodes[i] and H.taxi.nodes[i].type end
function TaxiNodePosition(i) local n = H.taxi.nodes[i] if n then return n.x, n.y end end
function GetNumRoutes(i) return #(H.taxi.routes[i] or {}) end
function TaxiGetNodeSlot(dest, hop, isSource)
    local leg = H.taxi.routes[dest] and H.taxi.routes[dest][hop]
    if leg then return isSource and leg[1] or leg[2] end
end
function TakeTaxiNode() end
function TaxiRequestEarlyLanding() end
function TaxiNodeOnButtonEnter() end

-- ----- Popups / metadados / addons -----
StaticPopupDialogs = {}
function StaticPopup_Show(which, a1, a2, data)
    local info = StaticPopupDialogs[which]
    if not info then return nil end
    local dialog = CreateFrame("Frame", nil, UIParent)
    dialog.which, dialog.data = which, data
    dialog.editBox = CreateFrame("EditBox", nil, dialog)
    dialog.button1 = CreateFrame("Button", nil, dialog)
    if info.OnShow then info.OnShow(dialog, data) end
    dialog.editBox:SetScript("OnTextChanged", function(box) if info.EditBoxOnTextChanged then info.EditBoxOnTextChanged(box) end end)
    H.popup = dialog
    return dialog
end

C_AddOns = {
    IsAddOnLoaded = function() return false end,
    GetAddOnMetadata = function(addon, field)
        if field == "Version" then return "@project-version@" end
        if field == "Author" then return "rafacf95" end
    end,
}

-- ----- Seletor de cor -----
H.pickerColor = { 0.2, 0.4, 0.6 }
ColorPickerFrame = CreateFrame("Frame", "ColorPickerFrame", UIParent)
ColorPickerFrame:Hide()
function ColorPickerFrame:GetColorRGB() return unpack(H.pickerColor) end
if VARIANT.oldPicker then
    function ColorPickerFrame:SetColorRGB(r, g, b) H.pickerColor = { r, g, b } end
else
    function ColorPickerFrame:SetupColorPickerAndShow(info) self.info = info; self:Show() end
end

--- Simula o jogador escolhendo uma cor no seletor aberto.
function H.pickColor(r, g, b)
    H.pickerColor = { r, g, b }
    if ColorPickerFrame.info then ColorPickerFrame.info.swatchFunc() else ColorPickerFrame.func() end
end

-- ----- Janelas da Blizzard usadas como alvo de âncora e pelos itens -----
PlayerFrame = CreateFrame("Frame", "PlayerFrame", UIParent)
PlayerFrame:SetSize(232, 100)
PlayerFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -100)
MainActionBar = CreateFrame("Frame", "MainActionBar", UIParent)
MainActionBar:SetSize(500, 45)
MainActionBar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 20)
EditModeManagerFrame = { registeredSystemFrames = { PlayerFrame, MainActionBar } }

-- Janela de personagem
PaperDollItemsFrame = CreateFrame("Frame", "PaperDollItemsFrame", UIParent)
local SLOT_IDS = {
    Head = 1, Neck = 2, Shoulder = 3, Back = 15, Chest = 5, Shirt = 4, Tabard = 19, Wrist = 9, Hands = 10,
    Waist = 6, Legs = 7, Feet = 8, Finger0 = 11, Finger1 = 12, Trinket0 = 13, Trinket1 = 14,
    MainHand = 16, SecondaryHand = 17, Ranged = 18,
}
for name, id in pairs(SLOT_IDS) do
    local button = CreateFrame("Button", "Character" .. name .. "Slot", PaperDollItemsFrame)
    button:SetID(id)
end
function PaperDollItemSlotButton_Update(button) end

-- Bolsas (ContainerFrame1 aberta, com 4 botões do bag 0)
local bagFrame = CreateFrame("Frame", "ContainerFrame1", UIParent)
bagFrame.buttons = {}
for slot = 1, 4 do
    local button = CreateFrame("Button", nil, bagFrame)
    button:SetID(slot)
    function button:GetBagID() return 0 end
    bagFrame.buttons[slot] = button
end
function bagFrame:EnumerateValidItems()
    local i = 0
    return function()
        i = i + 1
        if self.buttons[i] then return i, self.buttons[i] end
    end
end
function bagFrame:UpdateItems() end
local closedBag = CreateFrame("Frame", "ContainerFrame2", UIParent)
closedBag:Hide()
function ContainerFrame_GenerateFrame() end

-- Coleção de aparências (criada sob demanda; ver testes de Wardrobe)
C_TransmogCollection = {
    GetAppearanceSources = function(visualID)
        local map = { [1] = 1008, [2] = 1009, [3] = 1001 }
        if map[visualID] then return { { itemID = map[visualID], isCollected = true } } end
        return {}
    end,
}

-- ================================================================
-- 4. Variação
-- ================================================================

H.libs = {}

if VARIANT.editmode then
    local lib = { SettingType = { Dropdown = 0, Checkbox = 1, Slider = 2, ColorPicker = 3, Divider = 4 },
                  frameSelections = {}, frames = {}, settings = {}, callbacks = {}, refreshes = 0, layout = "Modern" }
    function lib:AddFrame(frame, callback, default, name)
        self.frames[frame] = { callback = callback, default = default, name = name }
        self.frameSelections[frame] = CreateFrame("Frame", nil, frame)
    end
    function lib:AddFrameSettings(frame, list) self.settings[frame] = list end
    function lib:RefreshFrameSettings() self.refreshes = self.refreshes + 1 end
    function lib:RegisterCallback(event, fn)
        self.callbacks[event] = self.callbacks[event] or {}
        table.insert(self.callbacks[event], fn)
    end
    function lib:GetActiveLayoutName() return self.layout end
    function lib:Fire(event, ...)
        for _, fn in ipairs(self.callbacks[event] or {}) do fn(...) end
    end
    --- Opção do Edit Mode de `frame` cujo nome é `name`.
    function lib:Setting(frame, name)
        for _, setting in ipairs(self.settings[frame] or {}) do
            if setting.name == name then return setting end
        end
    end
    H.libs.LibEditMode = lib
    H.lem = lib
end

if VARIANT.lsm then
    H.libs["LibSharedMedia-3.0"] = {
        List = function(_, kind) return kind == "statusbar" and { "Smooth" } or {} end,
        Fetch = function(_, kind, name) return "Interface\\LSM\\" .. name end,
    }
end

if next(H.libs) then
    LibStub = setmetatable({}, { __call = function(_, name, silent)
        local lib = H.libs[name]
        if not lib and not silent then error("Cannot find a library instance of " .. tostring(name)) end
        return lib
    end })
end

if VARIANT.legacyDb then
    WowUtilitiesDB = {
        bar = { fillColor = "gold", borderColor = "pink", width = 300 },
        taxiTimes = { ["A|B"] = { seconds = 42, count = 1, hops = 1 } },
    }
end

-- ================================================================
-- 5. Carga do addon
-- ================================================================

local results = { fail = 0, pass = 0, lines = {} }

local function test(name, fn)
    local before = #H.errors
    local ok, err = pcall(fn)
    restore()
    if ok and #H.errors > before then
        ok, err = false, "erro capturado pelo geterrorhandler: " .. tostring(H.errors[before + 1])
    end
    if ok then
        results.pass = results.pass + 1
        results.lines[#results.lines + 1] = "ok " .. name
    else
        results.fail = results.fail + 1
        results.lines[#results.lines + 1] = "FALHOU " .. name .. ": " .. tostring(err)
    end
end

local function eq(actual, expected, what)
    if actual ~= expected then
        error(string.format("%s: esperado %q, veio %q", what or "valor", tostring(expected), tostring(actual)), 2)
    end
end
local function near(actual, expected, what, tolerance)
    if type(actual) ~= "number" or math.abs(actual - expected) > (tolerance or 0.01) then
        error(string.format("%s: esperado ~%s, veio %s", what or "valor", tostring(expected), tostring(actual)), 2)
    end
end
local function check(value, what)
    if not value then error((what or "condicao") .. " falsa", 2) end
end
local function has(text, piece, what)
    if type(text) ~= "string" or not text:find(piece, 1, true) then
        error(string.format("%s: %q nao contem %q", what or "texto", tostring(text), tostring(piece)), 2)
    end
end

--- Dispara um evento do jogo para os frames registrados.
function H.fire(event, ...)
    for _, frame in ipairs(H.eventFrames) do
        if S(frame).events[event] then H.script(frame, "OnEvent", event, ...) end
    end
end

local ns = {}
local loadOk = true
test("carga: arquivos do .toc", function()
    for i = 1, #HARNESS_FILES do
        local file = HARNESS_FILES[i]
        local chunk, err = loadfile(HARNESS_ROOT .. "/" .. file)
        if not chunk then loadOk = false; error("sintaxe em " .. file .. ": " .. tostring(err)) end
        local ok, runErr = pcall(chunk, "WowUtilities", ns)
        if not ok then loadOk = false; error("erro ao carregar " .. file .. ": " .. tostring(runErr)) end
    end
end)
if not loadOk then return results end

test("boot: ADDON_LOADED inicializa a configuracao e dispara READY", function()
    local ready = false
    ns.Bus:Subscribe("READY", function() ready = true end)
    H.fire("ADDON_LOADED", "OutroAddon")
    check(not ready, "READY com outro addon")
    H.fire("ADDON_LOADED", "WowUtilities")
    check(ready, "READY disparado")
    check(ns.db == WowUtilitiesDB, "ns.db e o SavedVariables")
    H.fire("PLAYER_LOGIN")
    H.fire("PLAYER_ENTERING_WORLD")
    H.advance(1)
end)

local L = ns.L

-- ================================================================
-- 6. Testes
-- ================================================================

-- ----- Núcleo -----
test("core: FormatTime e PlaceName", function()
    eq(ns.FormatTime(75), "1:15", "75s")
    eq(ns.FormatTime(0), "0:00", "zero")
    eq(ns.FormatTime(-3), "0:00", "negativo")
    eq(ns.PlaceName("Booty Bay, Stranglethorn"), "Booty Bay", "com zona")
    eq(ns.PlaceName("Ironforge"), "Ironforge", "sem zona")
    eq(ns.PlaceName(nil), nil, "nil")
end)

test("core: SafeCall devolve todos os retornos e engole erros", function()
    local a, b, c, d = ns.SafeCall(function() return 1, 2, 3, 4 end)
    eq(d, 4, "quarto retorno")
    eq(ns.SafeCall(function() error("x") end), nil, "erro vira nil")
    eq(ns.Safe(function() error("x") end), nil, "Safe com erro")
end)

test("core: Bus isola erro de um assinante", function()
    local after = false
    ns.Bus:Subscribe("TEST_EVENT", function() error("boom") end)
    ns.Bus:Subscribe("TEST_EVENT", function() after = true end)
    local before = #H.errors
    ns.Bus:Fire("TEST_EVENT")
    check(after, "segundo assinante chamado")
    eq(#H.errors, before + 1, "erro enviado ao geterrorhandler")
    table.remove(H.errors) -- erro esperado
end)

-- ----- Configuração -----
test("config: padroes, Set dispara CONFIG_CHANGED uma vez, ResetSection", function()
    eq(ns.Config:Get("trinkets.columns"), 5, "padrao")
    eq(ns.Config:Get("nao.existe"), nil, "caminho inexistente")
    local fired = {}
    ns.Bus:Subscribe("CONFIG_CHANGED", function(path, value) fired[#fired + 1] = path end)
    ns.Config:Set("vendor.showZero", true)
    ns.Config:Set("vendor.showZero", true) -- igual: nao dispara
    eq(#fired, 1, "disparos")
    eq(fired[1], "vendor.showZero", "caminho")
    eq(ns.Config:Get("vendor.showZero"), true, "valor novo")
    ns.Config:ResetSection("vendor")
    eq(ns.Config:Get("vendor.showZero"), false, "depois do reset")
    local d = ns.Config:Default("bar.fillColor")
    d.r = 0
    eq(ns.Config:Default("bar.fillColor").r, 1, "Default devolve copia")
end)

test("config: SettingSpecs descreve as opcoes compartilhadas", function()
    local spec = ns.SettingSpecs:Get("bar.width")
    eq(spec.kind, "slider", "tipo")
    eq(spec.min, 100, "minimo")
    eq(ns.SettingSpecs:Get("nao.existe"), nil, "inexistente")
end)

if VARIANT.legacyDb then
    test("config: banco legado migra cores e tempos de voo", function()
        local c = ns.Config:Get("bar.fillColor")
        eq(type(c), "table", "cor migrada")
        eq(c.r, 1.0, "gold.r")
        eq(c.g, 0.7, "gold.g")
        eq(type(ns.Config:Get("bar.borderColor")), "table", "cor desconhecida volta ao padrao")
        eq(ns.Config:Get("bar.width"), 300, "valor antigo preservado")
        eq(ns.Config:Get("bar.height"), 20, "faltante preenchido")
        eq(ns.TaxiDatabase:Get("A", "B").seconds, 42, "tempos movidos para o idioma")
    end)
end

-- ----- Idioma -----
test("locale: traducao conforme o idioma do cliente", function()
    if VARIANT.locale == "ptBR" then
        eq(L["Flight"], "Voo", "ptBR")
    else
        eq(L["Flight"], "Flight", "cai no ingles")
    end
    eq(L["Chave sem traducao"], "Chave sem traducao", "chave desconhecida")
end)

test("locale: abreviacao de encantamentos", function()
    local A = ns.EnchantAbbreviation
    eq(A:Format("+4 All Stats", "full"), "+4 All Stats", "full")
    eq(A:Format("+4 All Stats", "value"), "+4", "value")
    if VARIANT.locale == "enUS" then
        eq(A:Format("+4 All Stats", "short"), "+4 All", "short enUS")
        eq(A:Format("+15 Agility", "short"), "+15 Agi", "palavra inteira")
    elseif VARIANT.locale == "ptBR" then
        eq(A:Format("+15 Agilidade", "short"), "+15 Agi", "short ptBR")
    else
        eq(A:Format("+4 All Stats", "short"), "+4 All Stats", "sem lista: inalterado")
    end
end)

-- ----- Tooltip -----
test("tooltip: nome, classe e faccao coloridos", function()
    H.showUnitTooltip("mouseover", { "Thrall", "Level 60 Shaman (Player)", "Horde" })
    eq(GameTooltipTextLeft1:GetText(), "|cff0070deWarchief Thrall|r", "nome com titulo")
    eq(GameTooltipTextLeft2:GetText(), "Level 60 |cff0070deShaman (Player)|r", "classe")
    eq(GameTooltipTextLeft3:GetText(), "|cffff2020Horde|r", "faccao")
end)

test("tooltip: opcoes desligadas nao mexem nas linhas", function()
    ns.Config:Set("tooltip.name", false)
    ns.Config:Set("tooltip.faction", false)
    H.showUnitTooltip("mouseover", { "Thrall", "Level 60 Shaman (Player)", "Horde" })
    eq(GameTooltipTextLeft1:GetText(), "Thrall", "nome intacto")
    eq(GameTooltipTextLeft3:GetText(), "Horde", "faccao intacta")
    ns.Config:Set("tooltip.name", true)
    ns.Config:Set("tooltip.faction", true)
end)

test("tooltip: borda de NPC elite e reset ao limpar", function()
    H.units.npc = { name = "Ogre", isPlayer = false, classification = "elite" }
    H.showUnitTooltip("npc", { "Ogre", "Level 60 Elite" })
    local c = GameTooltip.NineSlice.color
    eq(c[1], 1.0, "dourada r")
    eq(c[2], 0.82, "dourada g")
    H.script(GameTooltip, "OnTooltipCleared")
    eq(GameTooltip.NineSlice.color[2], 1, "voltou ao padrao")
    H.units.npc.classification = "rare"
    H.showUnitTooltip("npc", { "Ogre" })
    eq(GameTooltip.NineSlice.color[1], 0.78, "prateada")
    H.script(GameTooltip, "OnHide")
end)

-- ----- Voo -----
test("taxi: voo gravado do inicio ao fim, com a barra", function()
    TakeTaxiNode(2)
    H.fire("PLAYER_CONTROL_LOST")
    H.onTaxi = true
    H.advance(0.3)
    check(ns.TaxiRecorder:IsFlying(), "em voo")
    local bar = WowUtilitiesFlightBar
    check(bar:IsShown(), "barra visivel")
    H.script(bar, "OnUpdate", 0.1)
    eq(bar.label:GetText(), L["Recording flight time"], "rotulo sem tempo conhecido")
    H.advance(60)
    H.onTaxi = false
    H.fire("PLAYER_CONTROL_GAINED")
    check(not ns.TaxiRecorder:IsFlying(), "pousou")
    local entry = ns.TaxiDatabase:Get("Orgrimmar, Durotar", "Crossroads, The Barrens")
    near(entry.seconds, 60, "duracao gravada", 0.5)
    eq(entry.hops, 1, "trechos")
    H.advance(1)
    H.script(bar, "OnUpdate", 0.1)
    check(not bar:IsShown(), "barra some depois do fade")
end)

test("taxi: voo curto ou abortado nao grava", function()
    local count = ns.TaxiDatabase:Count()
    TakeTaxiNode(3)
    H.fire("PLAYER_CONTROL_LOST")
    H.onTaxi = true
    H.advance(0.3)
    H.advance(2)
    H.onTaxi = false
    H.fire("PLAYER_CONTROL_GAINED")
    eq(ns.TaxiDatabase:Count(), count, "voo de 2s descartado")
    TakeTaxiNode(3)
    H.fire("PLAYER_CONTROL_LOST")
    H.onTaxi = true
    H.advance(0.3)
    TaxiRequestEarlyLanding()
    H.advance(30)
    H.onTaxi = false
    H.fire("PLAYER_CONTROL_GAINED")
    eq(ns.TaxiDatabase:Count(), count, "voo abortado descartado")
    H.advance(1)
end)

test("taxi: estimativas medida, por trechos e por distancia", function()
    local s, kind = ns.TaxiEstimator:ForNode(2)
    near(s, 60, "medido", 0.5)
    eq(kind, "measured", "tipo medido")
    s, kind = ns.TaxiEstimator:ForNode(3) -- trecho 1 medido + trecho 2 pela distancia
    near(s, 140, "estimado", 1)
    eq(kind, "estimate", "tipo estimado")
    ns.TaxiDatabase:Record("Crossroads, The Barrens", "Booty Bay, Stranglethorn", 90, 1, 0.4)
    s = ns.TaxiEstimator:ForNode(3)
    near(s, 150, "soma dos trechos", 1)
end)

test("taxi: media movel ao gravar de novo", function()
    ns.TaxiDatabase:Record("X", "Y", 100, 1, 1)
    ns.TaxiDatabase:Record("X", "Y", 200, 1, 1)
    near(ns.TaxiDatabase:Get("X", "Y").seconds, 150, "media")
    eq(ns.TaxiDatabase:Get("X", "Y").count, 2, "contagem")
end)

test("taxi: tooltip do mapa mostra a duracao", function()
    local button = CreateFrame("Button", nil, UIParent)
    button:SetID(2)
    GameTooltip:SetOwner(UIParent)
    TaxiNodeOnButtonEnter(button)
    has(GameTooltipTextLeft1:GetText(), "1:00", "linha da duracao")
    button:SetID(1) -- o no atual nao recebe linha
    GameTooltip:SetOwner(UIParent)
    TaxiNodeOnButtonEnter(button)
    eq(GameTooltip:NumLines(), 0, "no atual")
end)

test("taxi: /wu taxi lista e o clear pede confirmacao", function()
    local mark = #H.printed
    SlashCmdList.WOWUTILITIES("taxi")
    has(H.printed[mark + 1], string.format(L["%d route(s) recorded."], ns.TaxiDatabase:Count()), "contagem")
    SlashCmdList.WOWUTILITIES("taxi clear")
    local dialog = H.popup
    check(dialog, "popup aberto")
    check(not dialog.button1:IsEnabled(), "botao travado sem a palavra")
    dialog.editBox:SetText("delete")
    check(dialog.button1:IsEnabled(), "palavra destrava (sem diferenciar maiusculas)")
    dialog.editBox:SetText("errado")
    StaticPopupDialogs[dialog.which].OnAccept(dialog, dialog.data)
    check(ns.TaxiDatabase:Count() > 0, "palavra errada nao apaga")
    dialog.editBox:SetText("DELETE")
    StaticPopupDialogs[dialog.which].OnAccept(dialog, dialog.data)
    eq(ns.TaxiDatabase:Count(), 0, "apagado")
    mark = #H.printed
    check(not ns.TaxiClearConfirm:Request(), "sem rotas nao abre")
    has(H.printed[mark + 1], L["No recorded routes to delete."], "aviso")
end)

-- ----- Vendedor -----
test("vendor: resumo ao fechar com venda, reparo e compra", function()
    H.money = 10000
    H.fire("MERCHANT_SHOW")
    H.money = 10500; H.fire("PLAYER_MONEY")
    RepairAllItems()
    H.money = 10300; H.fire("PLAYER_MONEY")
    H.advance(2)
    H.money = 10200; H.fire("PLAYER_MONEY")
    local mark = #H.printed
    H.fire("MERCHANT_CLOSED")
    local line = H.printed[mark + 1]
    has(line, L["Sold"], "venda")
    has(line, L["Repair"], "reparo")
    has(line, L["Bought"], "compra")
    has(line, L["Net"], "saldo")
    if VARIANT.coin then
        has(line, "COIN(500)", "formato nativo")
        has(line, "COIN(200)", "saldo nativo")
    else
        has(line, "5s", "formato manual")
        has(line, "2s", "saldo manual")
    end
end)

test("vendor: modo por transacao agrupa e desligado nao imprime", function()
    ns.Config:Set("vendor.perTransaction", true)
    ns.Config:Set("vendor.onClose", false)
    H.fire("MERCHANT_SHOW")
    local mark = #H.printed
    H.money = H.money + 100; H.fire("PLAYER_MONEY")
    H.money = H.money + 100; H.fire("PLAYER_MONEY")
    H.advance(0.5)
    eq(#H.printed, mark + 1, "uma mensagem para duas vendas")
    H.fire("MERCHANT_CLOSED")
    eq(#H.printed, mark + 1, "sem resumo ao fechar")
    ns.Config:Set("vendor.enabled", false)
    H.fire("MERCHANT_SHOW")
    H.money = H.money + 100; H.fire("PLAYER_MONEY")
    H.advance(0.5)
    H.fire("MERCHANT_CLOSED")
    eq(#H.printed, mark + 1, "desligado")
    ns.Config:ResetSection("vendor")
end)

test("vendor: formato manual de moedas", function()
    if VARIANT.coin then return end
    eq(ns.MoneyFormat:Coins(12345), "|cffffd7001g|r |cffc7c7cf23s|r |cffeda55f45c|r", "ouro, prata, cobre")
    eq(ns.MoneyFormat:Coins(0), "|cffeda55f0c|r", "zero")
    eq(ns.MoneyFormat:Coins(-200), "|cffc7c7cf2s|r", "valor absoluto")
end)

-- ----- Barra de voo e posicionamento -----
local bar = WowUtilitiesFlightBar

test("bar: estilo segue a configuracao", function()
    ns.Config:Set("bar.width", 320)
    eq(bar:GetWidth(), 320, "largura")
    ns.Config:Set("bar.scale", 1.5)
    eq(bar:GetScale(), 1.5, "escala")
    ns.Config:Set("bar.classColor", true)
    local r, g, b = bar.status:GetStatusBarColor()
    eq(r, 0.78, "cor de guerreiro")
    ns.Config:ResetSection("bar")
    eq(bar:GetWidth(), 250, "reset")
end)

if VARIANT.lsm then
    test("bar: texturas do LibSharedMedia", function()
        local found
        for _, t in ipairs(ns.StyleCatalog:Textures()) do if t.id == "lsm:Smooth" then found = t end end
        check(found, "textura lsm listada")
        ns.Config:Set("bar.texture", "lsm:Smooth")
        eq(bar.status:GetStatusBarTexture(), "Interface\\LSM\\Smooth", "textura aplicada")
        ns.Config:ResetSection("bar")
    end)
end

test("bar: textura desconhecida cai na primeira", function()
    eq(ns.StyleCatalog:TexturePath("nao-existe"), "Interface\\TargetingFrame\\UI-StatusBar", "padrao")
end)

if VARIANT.editmode then
    local lem = H.lem

    test("editmode: barra registrada com as opcoes do SettingSpecs", function()
        eq(ns.Positioner:Mode(), "editmode", "modo")
        check(lem.frames[bar], "AddFrame")
        check(ns.Positioner.IsEditedInEditMode("bar.width"), "largura no Edit Mode")
        check(not ns.Positioner.IsEditedInEditMode("bar.texture"), "textura so na /wu")
        check(ns.Positioner.HasEditModeSettings(), "ha opcoes")
        local width = lem:Setting(bar, L["Width"])
        check(width, "opcao Largura")
        eq(width.minValue, 100, "limite do SettingSpecs")
        width.set("Modern", 400)
        eq(ns.Config:Get("bar.width"), 400, "Edit Mode grava na configuracao")
        eq(bar:GetWidth(), 400, "barra redimensionada")
        local refreshes = lem.refreshes
        ns.Config:Set("bar.width", 250)
        check(lem.refreshes > refreshes, "mudanca na /wu atualiza o Edit Mode")
        local color = lem:Setting(bar, L["Bar color"])
        color.set("Modern", CreateColor(0.1, 0.2, 0.3))
        eq(ns.Config:Get("bar.fillColor").g, 0.2, "cor")
    end)

    test("editmode: posicao por layout e callbacks de layout", function()
        lem.frames[bar].callback(bar, "Modern", "CENTER", 10, 20)
        local point, _, x, y = ns.Config:GetBarPosition("Modern")
        eq(point, "CENTER", "ponto")
        eq(x, 10, "x")
        lem:Fire("layout", "Modern")
        local p, rel, relPoint, px, py = bar:GetPoint(1)
        eq(p, "CENTER", "aplicado")
        eq(rel, UIParent, "relativo")
        lem:Fire("create", "Copia", nil, "Modern")
        eq(ns.db.positions.Copia.x, 10, "copiado")
        lem:Fire("rename", "Copia", "Copia2")
        check(ns.db.positions.Copia == nil and ns.db.positions.Copia2, "renomeado")
        lem:Fire("delete", "Copia2")
        eq(ns.db.positions.Copia2, nil, "apagado")
    end)

    test("editmode: enter/exit mostra a barra", function()
        lem:Fire("enter")
        check(bar:IsShown(), "visivel no Edit Mode")
        lem:Fire("exit")
        check(not bar:IsShown(), "escondida ao sair")
    end)

    test("anchor: ancorar a barra no PlayerFrame e ajustar largura", function()
        local target = lem:Setting(bar, L["Anchor to"])
        local ids = {}
        for _, v in ipairs(target.values()) do ids[v.value] = true end
        check(ids.PlayerFrame and ids.MainActionBar, "alvos do Edit Mode")
        check(not ids.WowUtilitiesFlightBar, "a propria barra fora da lista")
        target.set("Modern", "PlayerFrame")
        local p, rel, relPoint, x, y = bar:GetPoint(1)
        eq(rel, PlayerFrame, "ancorada")
        eq(p, "TOP", "ponto proprio")
        eq(relPoint, "BOTTOM", "ponto do alvo")
        eq(y, -2, "deslocamento padrao")
        lem:Setting(bar, L["Match width"]).set("Modern", true)
        eq(bar:GetNumPoints(), 2, "dois pontos")
        eq(bar:GetWidth(), 232, "largura do alvo")
        check(lem:Setting(bar, L["Width"]).disabled("Modern"), "largura travada")
        lem:Setting(bar, L["Anchor side"]).set("Modern", "LEFT")
        eq(ns.Config:GetBarAnchor("Modern").matchWidth, false, "lado sem largura desliga o ajuste")
        lem:Setting(bar, L["Vertical offset"]).set("Modern", 7)
        local _, _, _, _, vy = bar:GetPoint(1)
        eq(vy, 7, "deslocamento vertical")
    end)

    test("anchor: arrastar ancorado recalcula o deslocamento", function()
        lem:Setting(bar, L["Anchor side"]).set("Modern", "BELOW")
        bar:ClearAllPoints()
        bar:SetPoint("TOP", PlayerFrame, "BOTTOM", 15, -30) -- onde o jogador soltou
        lem.frames[bar].callback(bar, "Modern", "CENTER", 0, 0)
        local anchor = ns.Config:GetBarAnchor("Modern")
        eq(anchor.x, 15, "x")
        eq(anchor.y, -30, "y")
        eq(ns.Config:GetBarPosition("Modern"), "CENTER", "posicao livre preservada")
    end)

    test("anchor: alvo ausente ou circular cai na posicao normal", function()
        ns.Config:SetBarAnchor("Modern", { target = "NaoExiste", edge = "BELOW", x = 0, y = -2 })
        lem:Fire("layout", "Modern")
        local _, rel = bar:GetPoint(1)
        eq(rel, UIParent, "alvo ausente")
        PlayerFrame:ClearAllPoints()
        PlayerFrame:SetPoint("TOP", bar, "BOTTOM", 0, 0)
        eq(ns.Anchoring:Resolve("PlayerFrame", bar), nil, "circular rejeitado")
        PlayerFrame:ClearAllPoints()
        PlayerFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -100)
        lem:Setting(bar, L["Anchor to"]).set("Modern", "none")
        eq(ns.Config:GetBarAnchor("Modern"), nil, "ancora removida")
    end)

    test("editmode: seletor de trinkets tem as proprias opcoes", function()
        local frame = ns.TrinketSelector:Frame()
        eq(ns.TrinketSelector.positioner:Mode(), "editmode", "modo")
        check(lem:Setting(frame, L["Grid columns"]), "colunas")
        check(not lem:Setting(frame, L["Anchor to"]), "sem ancora (anchorable desligado)")
    end)
else
    test("drag: sem LibEditMode a barra usa o modo arrastar", function()
        eq(ns.Positioner:Mode(), "drag", "modo")
        local p, rel, relPoint, x, y = bar:GetPoint(1)
        eq(p, "BOTTOM", "ponto padrao")
        eq(y, 220, "altura padrao")
        check(not ns.Positioner.HasEditModeSettings(), "sem opcoes travadas")
        ns.Positioner:SetUnlocked(true)
        check(ns.Positioner:IsUnlocked(), "destravado")
        check(bar:IsShown(), "visivel para arrastar")
        bar:ClearAllPoints()
        bar:SetPoint("CENTER", UIParent, "CENTER", 30, 40)
        H.script(bar, "OnDragStop")
        local point, _, px, py = ns.Config:GetBarPosition("Default")
        eq(point, "CENTER", "ponto salvo")
        eq(px, 30, "x salvo")
        ns.Positioner:SetUnlocked(false)
        check(not bar:IsShown(), "escondida ao travar")
    end)
end

-- ----- Itens: bolsas e personagem -----
test("items: nivel de item nas bolsas, so para equipamento", function()
    H.advance(0.5)
    local helm, potion = ContainerFrame1.buttons[1], ContainerFrame1.buttons[2]
    eq(rawget(helm, "wuitemLevel"):GetText(), "200", "elmo")
    check(rawget(potion, "wuitemLevel") == nil, "pocao sem texto")
    local r, g, b = rawget(helm, "wuitemLevel"):GetTextColor()
    eq(r, 0.64, "cor da qualidade epica")
    ns.Config:Set("items.itemLevel.colorMode", "fixed")
    ns.Config:Set("items.itemLevel.color", { r = 0.5, g = 0.5, b = 0.5 })
    eq((rawget(helm, "wuitemLevel"):GetTextColor()), 0.5, "cor fixa")
    ns.Config:Set("items.itemLevel.enabled", false)
    eq(rawget(helm, "wuitemLevel"):GetText(), "", "desligado limpa")
    ns.Config:ResetSection("items")
    H.advance(0.5)
    eq(rawget(helm, "wuitemLevel"):GetText(), "200", "religado")
end)

test("items: nivel e encantamento na janela de personagem", function()
    H.advance(0.5)
    eq(rawget(CharacterHeadSlot, "wucharacterLevel"):GetText(), "200", "nivel do elmo")
    eq(rawget(CharacterHeadSlot, "wuenchant"):GetText(), L["No enchant"], "elmo sem encantamento")
    local chest = rawget(CharacterChestSlot, "wuenchant"):GetText()
    if VARIANT.locale == "enUS" then eq(chest, "+4 All", "abreviado") else has(chest, "+4", "nome do encantamento") end
    check(rawget(CharacterFinger0Slot, "wuenchant") == nil, "anel nao conta por padrao")
    H.professions = { 7 } -- Encantamento
    ns.Config:Set("items.characterEnchants.countRings", true)
    eq(rawget(CharacterFinger0Slot, "wuenchant"):GetText(), L["No enchant"], "anel conta para encantador")
    ns.Config:Set("items.characterEnchants.showEnchanted", false)
    eq(rawget(CharacterChestSlot, "wuenchant"):GetText(), "", "so os que faltam")
    ns.Config:Set("items.characterEnchants.enabled", false)
    eq(rawget(CharacterHeadSlot, "wuenchant"):GetText(), "", "desligado")
    ns.Config:ResetSection("items")
    H.professions = {}
end)

test("items: hook do PaperDollItemSlotButton_Update repinta o slot", function()
    H.inv[1] = { id = 1003 }
    PaperDollItemSlotButton_Update(CharacterHeadSlot)
    eq(rawget(CharacterHeadSlot, "wucharacterLevel"):GetText(), "210", "repintado")
    H.inv[1] = { id = 1001 }
    PaperDollItemSlotButton_Update(CharacterHeadSlot)
end)

test("items: id do encantamento no link", function()
    eq(ns.EnchantInfo:Id(H.link(1003, 1888)), 1888, "com encantamento")
    eq(ns.EnchantInfo:Id(H.link(1003)), 0, "sem")
    eq(ns.EnchantInfo:Id("lixo"), nil, "link invalido")
end)

-- ----- Coleção de aparências -----
test("wardrobe: filtro de armadura na janela de colecao", function()
    local items = CreateFrame("Frame", nil, UIParent)
    items.transmogLocation = {}
    items.activeCategory = Enum.TransmogCollectionType.Chest
    items.visuals = { { visualID = 1 }, { visualID = 2 }, { visualID = 3 }, { visualID = 99, isHideVisual = true } }
    function items:GetActiveCategory() return self.activeCategory end
    function items:SetActiveCategory(c) self.activeCategory = c end
    function items:FilterVisuals() self.filteredVisualsList = { unpack(self.visuals) } end
    function items:RefreshVisualsList() self:FilterVisuals() end
    function items:UpdateItems() end
    items.WeaponDropdown = CreateFrame("Frame", nil, items)
    items.WeaponDropdown:SetSize(160, 20)
    items.WeaponDropdown:SetPoint("TOPRIGHT", items, "TOPRIGHT", -10, -10)
    WardrobeCollectionFrame = { ItemsCollectionFrame = items }
    H.fire("ADDON_LOADED", "Blizzard_Collections")
    check(ns.WardrobeIntegration:IsInstalled(), "instalado")
    eq(ns.WardrobeIntegration.dropdownStyle, "blizzard", "menu da Blizzard")

    ns.Config:Set("wardrobe.armorFilter", "plate")
    items:FilterVisuals()
    eq(#items.filteredVisualsList, 2, "placa + esconder item")
    eq(items.filteredVisualsList[1].visualID, 3, "placa")
    ns.Config:Set("wardrobe.armorFilter", "cloth")
    items:FilterVisuals()
    eq(items.filteredVisualsList[1].visualID, 1, "tecido")
    items:SetActiveCategory(12) -- arma: sem filtro e sem menu
    items:FilterVisuals()
    eq(#items.filteredVisualsList, 4, "arma sem filtro")
    ns.Config:Set("wardrobe.enabled", false)
    items:SetActiveCategory(Enum.TransmogCollectionType.Chest)
    items:FilterVisuals()
    eq(#items.filteredVisualsList, 4, "desligado")
    ns.Config:ResetSection("wardrobe")
end)

-- ----- Berloques -----
test("trinkets: seletor mostra o equipado e lista as bolsas por nivel", function()
    local frame = ns.TrinketSelector:Frame()
    check(frame:IsShown(), "seletor visivel")
    local slot13 = ns.TrinketSelector:SlotButton(13)
    eq(slot13.entry.itemID, 1006, "equipado no 13")
    slot13:Click()
    check(ns.TrinketSelector:IsOpen(), "grade aberta")
    local buttons = ns.TrinketSelector:ItemButtons()
    eq(buttons[1].entry.itemID, 1005, "maior nivel primeiro")
    eq(buttons[2].entry.itemID, 1004, "segundo")
    eq(buttons[1].ilvl:GetText(), "190", "nivel no icone")
end)

test("trinkets: clicar equipa e confirma a troca", function()
    local buttons = ns.TrinketSelector:ItemButtons()
    local mark = #H.printed
    buttons[1]:Click()
    eq(H.inv[13].id, 1005, "equipado")
    check(not ns.TrinketSelector:IsOpen(), "grade fechada")
    H.advance(1.5)
    eq(#H.printed, mark, "sem aviso de falha")
end)

test("trinkets: combate escurece, esconde e bloqueia", function()
    local frame = ns.TrinketSelector:Frame()
    H.combat = true
    H.fire("PLAYER_REGEN_DISABLED")
    eq(frame:GetAlpha(), 0.6, "escurecido")
    ns.TrinketSelector:SlotButton(14):Click()
    check(not ns.TrinketSelector:IsOpen(), "nao abre em combate")
    ns.Config:Set("trinkets.hideInCombat", true)
    check(not frame:IsShown(), "escondido em combate")
    H.combat = false
    H.fire("PLAYER_REGEN_ENABLED")
    check(frame:IsShown(), "volta depois do combate")
    eq(frame:GetAlpha(), 1, "opaco")
    ns.Config:ResetSection("trinkets")
end)

test("trinkets: disposicao horizontal e item que saiu da bolsa", function()
    ns.Config:Set("trinkets.orientation", "horizontal")
    local frame = ns.TrinketSelector:Frame()
    eq(frame:GetWidth(), 2 * 40 + 6, "largura horizontal")
    local mark = #H.printed
    local ok, reason = ns.TrinketSwapper:Equip({ bag = 0, slot = 9, link = "x" }, 13)
    eq(reason, "moved", "item sumiu")
    has(H.printed[mark + 1], L["That item is no longer in that bag slot."], "aviso")
    ns.Config:ResetSection("trinkets")
end)

-- ----- Janela /wu -----
local Window = ns.ConfigWindow
local PAGE_TITLES = { tooltip = "Tooltip", items = "Items", wardrobe = "Wardrobe",
                      flight = "Flight", vendor = "Vendor", trinkets = "Trinkets" }

--- Botão da lista de categorias com esse título.
local function CategoryButton(title)
    return H.find(function(o)
        local label = S(o).kind == "Button" and rawget(o, "Label")
        return label and S(label).text == title
    end)
end

--- Slider interno do controle (template da Blizzard ou fallback).
local function InnerSlider(control)
    return rawget(control, "Slider") or H.find(function(o) return S(o).kind == "Slider" and S(o).parent == control end)
end

test("ui: /wu abre a janela e a lista de categorias troca as paginas", function()
    SlashCmdList.WOWUTILITIES("")
    local frame = WowUtilitiesConfig
    check(frame:IsShown(), "janela aberta")
    eq(frame.skinned == true, not VARIANT.noTemplates, "moldura do painel de Opcoes")
    eq(Window:Current(), "tooltip", "primeira pagina")
    for id, key in pairs(PAGE_TITLES) do
        local button = CategoryButton(L[key])
        check(button, "categoria " .. key)
        button:Click()
        eq(Window:Current(), id, "pagina " .. key)
    end
    check(CategoryButton(L["Interface"]) == nil and H.findText(L["Interface"]), "grupo Interface")
    check(H.findText(L["Tools"]), "grupo Ferramentas")
    check(H.find(function(o)
        return S(o).kind == "FontString" and type(S(o).text) == "string" and S(o).text:find("dev", 1, true)
            and S(o).text:find("rafacf95", 1, true)
    end), "rodape com versao dev")
    check(H.findText(string.format(L["© %d %s. All rights reserved."], 2026, "rafacf95")), "rodape com os direitos")
end)

test("ui: caixa de selecao grava a configuracao", function()
    local box = Window:Control("items.itemLevel.enabled")
    check(box, "caixa encontrada")
    check(box:GetChecked(), "marcada")
    box:Click()
    eq(ns.Config:Get("items.itemLevel.enabled"), false, "desligado")
    box:Click()
    eq(ns.Config:Get("items.itemLevel.enabled"), true, "religado")
end)

test("ui: slider e menu gravam a configuracao", function()
    local columns = Window:Control("trinkets.columns")
    H.slide(InnerSlider(columns), 7)
    eq(ns.Config:Get("trinkets.columns"), 7, "colunas")
    ns.Config:Set("ui.allowWindowEdit", true) -- com o Edit Mode, a disposicao fica travada na /wu
    local layout = Window:Control("trinkets.orientation")
    local menu = S(layout).menu
    if menu then -- menu da Blizzard (WowStyle1DropdownTemplate)
        local picked
        for _, radio in ipairs(menu.radios) do if radio.label == L["Horizontal"] then picked = radio end end
        check(picked, "opcao Horizontal")
        picked.onSelect()
    else -- fallback: lista propria
        local button = H.find(function(o) return S(o).parent == layout and rawget(o, "arrow") end)
        H.script(button, "OnMouseUp")
        local row = H.find(function(o)
            return S(o).kind == "Button" and rawget(o, "text") and S(rawget(o, "text")).text == L["Horizontal"] and o:IsShown()
        end)
        row:Click()
    end
    eq(ns.Config:Get("trinkets.orientation"), "horizontal", "disposicao")
    ns.Config:ResetSection("trinkets")
    ns.Config:Set("ui.allowWindowEdit", false)
end)

test("ui: menu de textura mostra a pre-visualizacao", function()
    if VARIANT.noTemplates then return end
    local texture = Window:Control("bar.texture")
    local first = S(texture).menu.radios[1]
    eq(#first.initializers, 1, "textura de exemplo na opcao")
end)

test("ui: seletor de cor grava a cor e desativa com a borda desligada", function()
    local swatch = Window:Control("tooltip.eliteColor")
    if VARIANT.noTemplates then
        H.script(H.find(function(o) return S(o).parent == swatch and rawget(o, "color") end), "OnMouseUp")
    else
        swatch:Click()
    end
    H.pickColor(0.25, 0.5, 0.75)
    eq(ns.Config:Get("tooltip.eliteColor").g, 0.5, "cor gravada")
    ns.Config:Set("tooltip.eliteBorder", false)
    check(swatch:GetAlpha() < 1, "cor desativada com a borda desligada")
    ns.Config:ResetSection("tooltip")
    eq(swatch:GetAlpha(), 1, "reativada")
end)

test("ui: opcoes do Edit Mode travadas, salvo com Forcar edicao", function()
    local width = Window:Control("bar.width")
    local force = Window:Control(L["Force edit"])
    ns.Config:Set("ui.allowWindowEdit", false)
    if VARIANT.editmode then
        check(width:GetAlpha() < 1, "travado")
        check(force:GetParent():IsShown(), "caixa Forcar edicao visivel")
        force:Click()
        eq(ns.Config:Get("ui.allowWindowEdit"), true, "forcar edicao")
        eq(width:GetAlpha(), 1, "liberado")
        ns.Config:Set("ui.allowWindowEdit", false)
    else
        eq(width:GetAlpha(), 1, "sem Edit Mode nunca trava")
        check(not force:GetParent():IsShown(), "sem Forcar edicao")
    end
end)

test("ui: Defaults restaura so a pagina aberta, com confirmacao", function()
    CategoryButton(L["Flight"]):Click()
    ns.Config:Set("bar.width", 300)
    ns.Config:Set("vendor.showZero", true)
    local defaults = H.find(function(o) return S(o).kind == "Button" and S(o).text == L["Defaults"] end)
    defaults:Click()
    local dialog = H.popup
    check(dialog and dialog.which == "WOWUTILITIES_RESET_PAGE", "confirmacao aberta")
    eq(ns.Config:Get("bar.width"), 300, "nada muda antes de confirmar")
    StaticPopupDialogs[dialog.which].OnAccept(dialog, dialog.data)
    eq(ns.Config:Get("bar.width"), 250, "barra restaurada")
    eq(ns.Config:Get("vendor.showZero"), true, "outra pagina intacta")
    ns.Config:ResetSection("vendor")
end)

test("ui: posicao da janela fica salva", function()
    local frame = WowUtilitiesConfig
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -50)
    H.script(frame, "OnDragStop")
    eq(ns.db.ui.window.point, "TOPLEFT", "ponto salvo")
    eq(ns.db.ui.window.x, 40, "x salvo")
end)

test("ui: lista de tempos de voo se atualiza", function()
    CategoryButton(L["Flight"]):Click()
    ns.TaxiDatabase:Record("P", "Q", 30, 1, 1)
    Window:Refresh()
    check(H.findText(string.format(L["Recorded routes: %d"], ns.TaxiDatabase:Count())), "contagem de rotas")
end)

test("ui: fechar a janela desliga a pre-visualizacao", function()
    ns.FlightCastBar:Preview(true)
    check(ns.FlightCastBar:IsPreviewing(), "pre-visualizando")
    WowUtilitiesConfig:Hide()
    check(not ns.FlightCastBar:IsPreviewing(), "desligada")
end)

test("ui: grade de berloques e janela de texto usam a moldura da Blizzard", function()
    eq(rawget(WowUtilitiesTrinketFlyout, "NineSlice") ~= nil, not VARIANT.noTemplates, "grade com moldura de tooltip")
end)

test("ui: /wu com comando desconhecido mostra a ajuda", function()
    local mark = #H.printed
    SlashCmdList.WOWUTILITIES("naoexiste")
    has(H.printed[mark + 1], L["WowUtilities — commands:"], "ajuda")
    check(H.printedWith("/wu taxi", mark), "lista o taxi")
end)

-- ----- Diagnósticos -----
test("debug: /wu debug ui descreve o painel de Opcoes e os templates", function()
    local panel = CreateFrame("Frame", nil, UIParent)
    panel:SetSize(920, 730)
    panel.CategoryList = CreateFrame("Frame", nil, panel)
    panel.CategoryList.Title = panel.CategoryList:CreateFontString(nil, "OVERLAY")
    panel.CategoryList.Title:SetText("Gameplay")
    set("SettingsPanel", panel)
    local lines = ns.DebugUI:Report()
    local text = table.concat(lines, "\n")
    has(text, "SettingsPanel: present", "painel encontrado")
    has(text, "CategoryList: Frame", "arvore do painel")
    has(text, "text=\"Gameplay\"", "texto das fontes")
    has(text, "UIPanelButtonTemplate (Button): OK", "template testado")
    has(text, "MinimalScrollBar (EventFrame): FAIL", "tipo inexistente nao quebra o relatorio")
    check(not text:find("failed", 1, true), "relatorio sem falha")
end)

for _, sub in ipairs({ "player", "bags", "character", "enchants", "editmode", "anchors", "trinkets", "wardrobe", "ui" }) do
    test("debug: /wu debug " .. sub .. " gera o relatorio sem falhar", function()
        SlashCmdList.WOWUTILITIES("debug " .. sub)
        local edit = H.find(function(o) return S(o).kind == "EditBox" and S(o).parent == WowUtilitiesTextWindowScroll end)
        check(edit, "janela de texto")
        local text = edit:GetText()
        check(#text > 0, "relatorio vazio")
        check(not text:find("failed", 1, true), "relatorio falhou: " .. text:sub(1, 300))
    end)
end

test("final: nenhum erro pendente no geterrorhandler", function()
    H.advance(5)
end)

return results
