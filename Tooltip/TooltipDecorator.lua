-- ============================================================
--  TooltipDecorator.lua
--  Orquestrador: resolve o jogador e executa os decorators
--  registrados, em ordem.
--  Depende apenas das abstrações (UnitResolver e o contrato Apply),
--  não de decorators concretos (Dependency Inversion).
-- ============================================================

local _, ns = ...

local TooltipDecorator = {}
ns.TooltipDecorator = TooltipDecorator

local registered = {}

--- Registra um decorator (qualquer tabela com método Apply).
function TooltipDecorator:Register(decorator)
    registered[#registered + 1] = decorator
end

--- Ponto de entrada chamado pelo hook da tooltip.
function TooltipDecorator:Run(tooltip)
    local prefix = tooltip:GetName()
    if not prefix then return end

    local unit = ns.UnitResolver:GetUnit(tooltip)
    if not unit then return end

    local info = ns.UnitResolver:Describe(unit)
    if not info then return end

    local ctx = { tooltip = tooltip, prefix = prefix, info = info }

    for _, decorator in ipairs(registered) do
        -- Cada decorator pode ser ligado/desligado na configuração ("tooltip.<key>")
        local enabled = not decorator.key or ns.Config:Get("tooltip." .. decorator.key)
        if enabled then
            -- Um decorator com erro não derruba os demais nem gera erro na tela
            pcall(decorator.Apply, decorator, ctx)
        end
    end
end
