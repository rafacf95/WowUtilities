-- ============================================================
--  TooltipModule.lua
--  Composition root do recurso de tooltip: registra os decorators
--  e conecta ao jogo. Único arquivo que conhece os decorators
--  concretos e o hook da tooltip.
-- ============================================================

local _, ns = ...

-- 1) Registra os decorators (a ordem define a ordem de execução)
ns.TooltipDecorator:Register(ns.Decorators.NameLine)
ns.TooltipDecorator:Register(ns.Decorators.ClassLine)
ns.TooltipDecorator:Register(ns.Decorators.FactionLine)

-- 2) Conecta ao jogo
local function OnUnitTooltip(tooltip)
    -- Só a tooltip principal; ignora tooltips embutidas e de comparação
    if tooltip ~= GameTooltip then return end
    ns.TooltipDecorator:Run(tooltip)
    pcall(ns.NpcBorder.Apply, ns.NpcBorder, tooltip)
end

ns.NpcBorder:Install(GameTooltip)

-- O Forever usa o sistema moderno de tooltips
if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
end
