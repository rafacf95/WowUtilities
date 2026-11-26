-- ============================================================
--  WardrobeIntegration.lua
--  Liga o filtro de armadura à janela de coleção da Blizzard
--  (WardrobeCollectionFrame.ItemsCollectionFrame). É o único arquivo
--  que conhece essa interface:
--    * gancho pós-FilterVisuals: filtra filteredVisualsList antes da
--      ordenação e do cálculo de páginas;
--    * dropdown de tipo, na posição do dropdown de armas (que só
--      aparece nas categorias de arma; o nosso, nas de armadura);
--    * redesenha a grade quando o filtro, o módulo ou a coleção mudam.
--  A janela é carregada sob demanda (Blizzard_Collections).
-- ============================================================

local _, ns = ...

local Integration = {}
ns.WardrobeIntegration = Integration

local ADDON = "Blizzard_Collections"
local DROPDOWN_WIDTH = 155
local FALLBACK_POINT = { "TOPRIGHT", -20, -78 }
local RETRY_SECONDS, MAX_RETRIES = 0.5, 6
local COALESCE_SECONDS = 0.2
-- Eventos que indicam que a coleção mudou (o tipo de uma aparência depende dela)
local COLLECTION_EVENTS = { "TRANSMOG_COLLECTION_UPDATED", "TRANSMOG_COLLECTION_SOURCE_ADDED",
                            "TRANSMOG_COLLECTION_SOURCE_REMOVED" }

local items, dropdown, installed, refreshQueued

local function Cfg(key) return ns.Config:Get("wardrobe." .. key) end

--- Erros do nosso código vão ao tratador de erros sem quebrar a janela da Blizzard.
local function Guard(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and geterrorhandler then geterrorhandler()(err) end
end

local function ActiveCategory()
    if not items then return nil end
    local ok, value = pcall(function() return items:GetActiveCategory() end)
    if ok and type(value) == "number" then return value end
    return type(items.activeCategory) == "number" and items.activeCategory or nil
end

-- ----------------------------------------------------------------
-- Filtro da lista
-- ----------------------------------------------------------------

local function OnFilterVisuals(self)
    if not Cfg("enabled") then return end
    local list = self.filteredVisualsList
    if type(list) ~= "table" then return end
    self.filteredVisualsList = ns.ArmorFilter:Apply(list, ActiveCategory(), Cfg("armorFilter"))
end

--- Mostra o dropdown só com o módulo ligado e numa categoria de armadura.
local function UpdateDropdownVisibility()
    if not dropdown then return end
    dropdown:SetShown(Cfg("enabled") and ns.ArmorType:IsArmorCategory(ActiveCategory()))
    if type(dropdown.Refresh) == "function" then dropdown:Refresh() end
end

--- A grade só pode ser redesenhada se estiver realmente visível (IsShown é só a
--- flag do próprio frame; fica true mesmo com a janela fechada) e se a Blizzard já
--- definiu a categoria ativa (transmogLocation é nil até uma categoria ser aberta).
local function CanRefresh()
    local visible
    if type(items.IsVisible) == "function" then visible = items:IsVisible() else visible = items:IsShown() end
    return visible and type(items.transmogLocation) == "table"
end

--- Refaz a lista e a grade (depois de mudar o filtro ou ligar/desligar o módulo).
local function Redraw()
    if not items then return end
    UpdateDropdownVisibility()
    if CanRefresh() then
        Guard(function()
            items:RefreshVisualsList()
            items:UpdateItems()
        end)
    end
end

-- ----------------------------------------------------------------
-- Dropdown
-- ----------------------------------------------------------------

--- Mesma posição do dropdown de armas, se ele existir; senão, canto fixo.
local function Anchor(frame)
    local weapon = items.WeaponDropdown
    local count = type(weapon) == "table" and type(weapon.GetNumPoints) == "function" and weapon:GetNumPoints() or 0
    frame:ClearAllPoints()
    if count > 0 then
        for i = 1, count do
            local point, relativeTo, relativePoint, x, y = weapon:GetPoint(i)
            frame:SetPoint(point, relativeTo, relativePoint, x, y)
        end
    else
        frame:SetPoint(FALLBACK_POINT[1], items, FALLBACK_POINT[1], FALLBACK_POINT[2], FALLBACK_POINT[3])
    end
end

--- Largura do dropdown de armas, se ele informar; senão, a padrão.
local function DropdownWidth()
    local weapon = items.WeaponDropdown
    if type(weapon) == "table" and type(weapon.GetWidth) == "function" then
        local ok, width = pcall(weapon.GetWidth, weapon)
        if ok and type(width) == "number" and width > 40 then return width end
    end
    return DROPDOWN_WIDTH
end

local function BuildDropdown()
    local get = function() return Cfg("armorFilter") end
    local set = function(value) ns.Config:Set("wardrobe.armorFilter", value) end
    dropdown, Integration.dropdownStyle = ns.ArmorDropdown:Create(items, ns.ArmorFilter.OPTIONS, get, set, DropdownWidth())
    if not dropdown then return end
    Anchor(dropdown)
    dropdown:SetFrameLevel((items:GetFrameLevel() or 1) + 10)
end

-- ----------------------------------------------------------------
-- Instalação
-- ----------------------------------------------------------------

local function Ready()
    local window = _G.WardrobeCollectionFrame
    local frame = type(window) == "table" and window.ItemsCollectionFrame
    if type(frame) == "table" and type(frame.FilterVisuals) == "function"
       and type(frame.GetActiveCategory) == "function" then
        return frame
    end
end

local function Install(attempt)
    if installed then return end
    local frame = Ready()
    if not frame then
        -- Os métodos da janela podem chegar um instante depois do carregamento
        if (attempt or 0) < MAX_RETRIES and C_Timer and C_Timer.After then
            C_Timer.After(RETRY_SECONDS, function() Install((attempt or 0) + 1) end)
        end
        return
    end

    installed, items = true, frame
    hooksecurefunc(items, "FilterVisuals", function(self) Guard(OnFilterVisuals, self) end)
    if type(items.SetActiveCategory) == "function" then
        hooksecurefunc(items, "SetActiveCategory", function() Guard(UpdateDropdownVisibility) end)
    end
    Guard(BuildDropdown)
    items:HookScript("OnShow", function() Guard(UpdateDropdownVisibility) end)
    -- Fechada a janela, o cache é descartado: a próxima abertura parte da coleção atual
    -- (cobre o caso de os eventos de coleção não existirem neste cliente).
    items:HookScript("OnHide", function() ns.ArmorType:Clear() end)
    Guard(UpdateDropdownVisibility)
end

--- Coleção mudou: descarta o cache e redesenha (vários eventos seguidos viram um redesenho).
local function OnCollectionChanged()
    ns.ArmorType:Clear()
    if refreshQueued then return end
    refreshQueued = true
    local function Run()
        refreshQueued = false
        Redraw()
    end
    if C_Timer and C_Timer.After then C_Timer.After(COALESCE_SECONDS, Run) else Run() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
for _, name in ipairs(COLLECTION_EVENTS) do
    pcall(events.RegisterEvent, events, name) -- um cliente pode não conhecer o evento
end
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == ADDON then Install() end
    else
        OnCollectionChanged()
    end
end)

ns.Bus:Subscribe("READY", function() Install() end) -- janela já carregada

ns.Bus:Subscribe("CONFIG_CHANGED", function(path)
    if path == "wardrobe" or (path and path:find("^wardrobe%.")) then Redraw() end
end)

function Integration:IsInstalled() return installed == true end
