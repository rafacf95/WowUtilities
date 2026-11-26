-- ============================================================
--  CharacterEnchants.lua
--  Indica, ao lado dos botões de equipamento da janela de personagem,
--  quais itens estão encantados (nome do encantamento, em verde) e quais
--  estão sem (aviso em vermelho). A regra de quais slots contam e a
--  leitura do encantamento são do ns.EnchantInfo; a infraestrutura dos
--  botões é do ns.CharacterSlots.
--  Posição do texto: nas colunas, ao lado do ícone voltado para o
--  modelo do personagem; nos slots de baixo, a arma principal e a de
--  longe ficam ao lado e a secundária em cima.
-- ============================================================

local _, ns = ...
local L = ns.L

local Module = {}
ns.CharacterEnchants = Module

local FIELD = "wuenchant"
local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"
local SIDE_WIDTH, ABOVE_WIDTH = 96, 64

-- Onde o texto fica em relação ao botão: "right" = à direita do ícone,
-- "left" = à esquerda, "above" = em cima.
local PLACEMENT = {
    [1] = "right", [2] = "right", [3] = "right", [15] = "right", [5] = "right", [9] = "right", -- coluna esquerda
    [10] = "left", [6] = "left", [7] = "left", [8] = "left", [11] = "left", [12] = "left",     -- coluna direita
    [16] = "left", [17] = "above", [18] = "right",                                              -- armas
}

local known = {}

local function Cfg(key) return ns.Config:Get("items.characterEnchants." .. key) end

local function FontPath()
    local ok, path = pcall(function()
        local font = rawget(_G, "GameFontNormalSmall")
        return type(font) == "table" and font:GetFont() or nil
    end)
    return (ok and type(path) == "string") and path or FALLBACK_FONT
end

local function TextOf(button)
    local text = rawget(button, FIELD)
    if text then return text end
    if type(button.CreateFontString) ~= "function" then return nil end
    text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rawset(button, FIELD, text)
    known[button] = true
    return text
end

local function Place(text, button, slotID)
    local where = PLACEMENT[slotID] or "right"
    text:ClearAllPoints()
    if where == "left" then
        text:SetPoint("RIGHT", button, "LEFT", -4, 0)
        text:SetJustifyH("RIGHT"); text:SetWidth(SIDE_WIDTH)
    elseif where == "above" then
        text:SetPoint("BOTTOM", button, "TOP", 0, 2)
        text:SetJustifyH("CENTER"); text:SetWidth(ABOVE_WIDTH)
    else
        text:SetPoint("LEFT", button, "RIGHT", 4, 0)
        text:SetJustifyH("LEFT"); text:SetWidth(SIDE_WIDTH)
    end
    if type(text.SetWordWrap) == "function" then text:SetWordWrap(false) end -- uma linha só (corta com "...")
end

local function Clear(button)
    local text = rawget(button, FIELD)
    if text then text:SetText("") end
end

local function Paint(button, slotID)
    if not slotID then Clear(button) return end
    local state, name = ns.EnchantInfo:Status(slotID, { countRings = Cfg("countRings") == true })
    if state == "enchanted" and not Cfg("showEnchanted") then state = nil end
    if not state then Clear(button) return end

    local text = TextOf(button)
    if not text then return end
    Place(text, button, slotID)
    text:SetFont(FontPath(), Cfg("fontSize"), "OUTLINE")
    if state == "enchanted" then
        local c = Cfg("enchantedColor")
        text:SetTextColor(c.r, c.g, c.b)
        text:SetText(name and ns.EnchantAbbreviation:Format(name, Cfg("nameMode")) or L["Enchanted"])
    else
        local c = Cfg("missingColor")
        text:SetTextColor(c.r, c.g, c.b)
        text:SetText(L["No enchant"])
    end
end

ns.CharacterSlots:Register({
    path = "items.characterEnchants",
    enabled = function() return Cfg("enabled") == true end,
    paint = Paint,
    clear = function() for button in pairs(known) do Clear(button) end end,
})

function Module:IsInstalled() return ns.CharacterSlots:IsInstalled() end
