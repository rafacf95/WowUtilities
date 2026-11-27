-- ============================================================
--  Locales.lua
--  Sistema de idiomas. Todo texto do addon passa por ns.L:
--      L["Duration: %s"]
--  O texto em inglês é a própria chave, então:
--    * inglês (enUS/enGB) não precisa de arquivo de tradução;
--    * idioma sem tradução (ex.: deDE) cai automaticamente em inglês;
--    * chave sem tradução aparece em inglês, nunca vazia.
--  Cada arquivo de idioma chama ns.RegisterLocale("ptBR", { ... }).
-- ============================================================

local _, ns = ...

local locale = GetLocale and GetLocale() or "enUS"
if locale == "enGB" then locale = "enUS" end

--- Código do idioma ativo ("enUS", "ptBR", ...).
ns.locale = locale

local L = setmetatable({}, {
    __index = function(_, key) return key end,
})
ns.L = L

-- Texto traduzido -> chave em inglês (para achar o rótulo curto do Edit Mode)
local keyOf = {}
-- Rótulos curtos da caixa do Edit Mode: [chave em inglês] = texto curto
local editModeLabels = {}

--- Registra as traduções de `code`; só aplica se for o idioma do cliente.
function ns.RegisterLocale(code, translations)
    if code ~= ns.locale then return end
    for key, text in pairs(translations) do
        L[key] = text
        keyOf[text] = key
    end
end

--- Registra rótulos curtos para a caixa de opções do Edit Mode (que é
--- estreita). Chave = texto em inglês, como em RegisterLocale.
function ns.RegisterEditModeLabels(code, labels)
    if code ~= ns.locale then return end
    for key, text in pairs(labels) do editModeLabels[key] = text end
end

--- Rótulo para o Edit Mode: recebe o texto já traduzido (L[...]) e devolve
--- a versão curta, se o idioma tiver uma; senão, o próprio texto.
function ns.EditModeLabel(text)
    if type(text) ~= "string" then return text end
    return editModeLabels[keyOf[text] or text] or text
end

-- Abreviações de nomes de encantamento por idioma (dados; usados por
-- ns.EnchantAbbreviation). Cada lista: { { "texto completo", "abreviação" }, ... }.
local abbreviations = {}
ns.enchantAbbreviations = abbreviations

--- Registra as abreviações de `code`; só aplica se for o idioma do cliente.
function ns.RegisterEnchantAbbreviations(code, list)
    if code ~= ns.locale then return end
    abbreviations.list = list
end
