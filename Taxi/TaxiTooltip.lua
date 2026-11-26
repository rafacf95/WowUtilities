-- ============================================================
--  TaxiTooltip.lua
--  Acrescenta a duração do voo na tooltip dos destinos do mapa.
--  Responsabilidade única: apresentar o resultado do estimador.
-- ============================================================

local _, ns = ...
local L = ns.L

local function OnNodeHover(index)
    if not ns.Config:Get("taxi.tooltip") then return end
    if ns.TaxiCompat:NodeType(index) ~= "REACHABLE" then return end

    local seconds, kind = ns.TaxiEstimator:ForNode(index)
    if seconds then
        local prefix = (kind == "measured") and "" or "~"
        GameTooltip:AddLine(string.format(L["Duration: %s"], prefix .. ns.FormatTime(seconds)), 0.4, 0.8, 1)
    else
        GameTooltip:AddLine(L["Duration: unknown"], 0.6, 0.6, 0.6)
    end
    GameTooltip:Show() -- recalcula o tamanho com a linha nova
end

ns.Bus:Subscribe("READY", function()
    ns.TaxiCompat:InstallNodeHoverHook(OnNodeHover)
end)
