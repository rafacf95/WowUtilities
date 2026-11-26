-- ============================================================
--  Decorators.lua
--  Padrão Strategy: cada decorator altera UMA parte da tooltip.
--  Contrato:  decorator:Apply(ctx)
--    ctx = { tooltip = <frame>, prefix = "GameTooltip", info = <perfil> }
--  Para novas funcionalidades (facção, guilda, ...) basta criar um
--  novo decorator e registrá-lo no Main.lua — sem editar os existentes
--  (Open/Closed).
-- ============================================================

local _, ns = ...

local Decorators = {}
ns.Decorators = Decorators

-- ----------------------------------------------------------------
-- Helpers compartilhados
-- ----------------------------------------------------------------

local function GetLeftLine(ctx, index)
    return _G[ctx.prefix .. "TextLeft" .. index]
end

-- Remove escapes de cor para comparar o texto "limpo".
local function StripColor(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    return text
end

-- ----------------------------------------------------------------
-- Decorator 1: Título + Nome (linha 1)
-- ----------------------------------------------------------------
Decorators.NameLine = { key = "name" }

function Decorators.NameLine:Apply(ctx)
    local line = GetLeftLine(ctx, 1)
    if not line then return end

    local text = ctx.info.displayName
    if not text then
        -- Sem nome confiável (ex.: jogador distante): colore o que o jogo já
        -- escreveu, em vez de sobrescrever a linha com algo vazio.
        local current = line:GetText()
        if type(current) ~= "string" or ns.IsSecret(current) then return end
        text = StripColor(current)
    end
    if text == "" then return end

    line:SetText(ns.ClassColors:Wrap(text, ctx.info.classFile))
end

-- ----------------------------------------------------------------
-- Decorator 2: Classe (e especialização, quando o jogo exibe)
-- A linha vem como "Nível 80 Fogo Mago", "Fogo Mago" ou "Mago".
-- O prefixo de nível fica sem cor; o resto recebe a cor da classe.
-- ----------------------------------------------------------------
Decorators.ClassLine = { key = "class" }

function Decorators.ClassLine:Apply(ctx)
    local className = ctx.info.className
    if not className then return end

    for i = 2, ctx.tooltip:NumLines() do
        local line = GetLeftLine(ctx, i)
        local text = line and line:GetText()

        -- GetText pode devolver valor secreto: nesse caso, ignora a linha
        if type(text) == "string" and not ns.IsSecret(text) then
            local clean = StripColor(text)
            if clean:find(className, 1, true) then
                -- Prefixo = tudo até o último número do nível (ex.: "Nível 80 ")
                local prefix, rest = clean:match("^(%D*%d+%s+)(.*)$")
                if prefix then
                    line:SetText(prefix .. ns.ClassColors:Wrap(rest, ctx.info.classFile))
                else
                    line:SetText(ns.ClassColors:Wrap(clean, ctx.info.classFile))
                end
                return -- só uma linha de classe por tooltip
            end
        end
    end
end

-- ----------------------------------------------------------------
-- Decorator 3: Facção
-- A tooltip mostra a facção como uma linha própria ("Horda"/"Aliança").
-- Só colore linhas cujo texto seja exatamente o nome da facção, para
-- nunca alterar outra informação (ex.: nome de guilda).
-- ----------------------------------------------------------------
Decorators.FactionLine = { key = "faction" }

function Decorators.FactionLine:Apply(ctx)
    local info = ctx.info
    if not info.faction or not ns.FactionColors:Has(info.faction) then return end

    -- Nomes aceitos: o localizado pelo jogo e as globais do cliente
    local accepted = {}
    if info.factionName then accepted[info.factionName] = true end
    if info.faction == "Horde" and FACTION_HORDE then accepted[FACTION_HORDE] = true end
    if info.faction == "Alliance" and FACTION_ALLIANCE then accepted[FACTION_ALLIANCE] = true end

    for i = 2, ctx.tooltip:NumLines() do
        local line = GetLeftLine(ctx, i)
        local text = line and line:GetText()
        if type(text) == "string" and not ns.IsSecret(text) then
            local clean = StripColor(text)
            if accepted[clean] then
                line:SetText(ns.FactionColors:Wrap(clean, info.faction))
                return
            end
        end
    end
end
