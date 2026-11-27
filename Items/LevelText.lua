-- ============================================================
--  LevelText.lua
--  Pintor compartilhado do "número de item level" sobre um botão de
--  ícone (bolsas, janela de personagem...). Cada recurso cria o seu
--  pintor com um prefixo de configuração (items.<prefix>.*), então
--  ativar/desativar e customizar são independentes por recurso.
--  Só cuida do texto: quem decide qual nível mostrar é o módulo.
-- ============================================================

local _, ns = ...

local LevelText = {}
ns.LevelText = LevelText

local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"

local function FontPath()
    local ok, path = pcall(function()
        local font = rawget(_G, "NumberFontNormal")
        return type(font) == "table" and font:GetFont() or nil
    end)
    return (ok and type(path) == "string") and path or FALLBACK_FONT
end

--- Cria um pintor que lê as opções de items.<prefix>.
--- enabled, colorMode ("quality"|"fixed"), color, anchor, fontSize.
--- field (opcional) = campo do texto no botão; dois pintores com o mesmo
--- prefix e campos diferentes compartilham as opções e limpam separados.
function LevelText.Create(prefix, field)
    local painter = {}
    field = field or ("wu" .. prefix)
    local known = {} -- botões que já receberam texto (para limpar ao desligar)

    local function Cfg(key) return ns.Config:Get("items." .. prefix .. "." .. key) end

    function painter:Enabled() return Cfg("enabled") == true end

    function painter:TextOf(button)
        local text = rawget(button, field)
        if text then return text end
        if type(button.CreateFontString) ~= "function" then return nil end
        text = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        rawset(button, field, text)
        known[button] = true
        return text
    end

    function painter:Clear(button)
        local text = rawget(button, field)
        if text then text:SetText("") end
    end

    function painter:ClearAll()
        for button in pairs(known) do self:Clear(button) end
    end

    --- Escreve o nível no botão (nil apaga). quality escolhe a cor no modo "quality".
    function painter:Apply(button, level, quality)
        if not level then self:Clear(button) return end
        local text = self:TextOf(button)
        if not text then return end

        local anchor = Cfg("anchor")
        local x = anchor:find("LEFT") and 2 or (anchor:find("RIGHT") and -2 or 0)
        local y = anchor:find("TOP") and -2 or (anchor:find("BOTTOM") and 2 or 0)
        text:ClearAllPoints()
        text:SetPoint(anchor, x, y)
        text:SetFont(FontPath(), Cfg("fontSize"), "OUTLINE")

        if Cfg("colorMode") == "fixed" then
            local c = Cfg("color")
            text:SetTextColor(c.r, c.g, c.b)
        else
            text:SetTextColor(ns.ItemLevel:QualityColor(quality))
        end
        text:SetText(tostring(level))
    end

    return painter
end
