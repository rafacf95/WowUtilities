-- ============================================================
--  ArmorDropdown.lua
--  Fábrica do dropdown do filtro. Estratégias, da mais fiel à
--  interface da Blizzard para a mais simples; a primeira que
--  funcionar vence:
--    1. Moderna — DropdownButton + WowStyle1DropdownTemplate +
--                 SetupMenu (o mesmo estilo do dropdown de armas).
--    2. Própria — ns.Widgets.Dropdown (não depende de template).
--  Todas devolvem um frame com :Refresh(), :SetShown() e :SetWidth().
--  Quem usa a fábrica não sabe qual estratégia respondeu.
-- ============================================================

local _, ns = ...

local ArmorDropdown = {}
ns.ArmorDropdown = ArmorDropdown

local TEMPLATE = "WowStyle1DropdownTemplate"

local strategies = {}

--- 1. Dropdown moderno da Blizzard.
strategies[#strategies + 1] = {
    name = "blizzard",
    create = function(parent, options, get, set, width)
        if type(CreateFrame) ~= "function" then return end
        local ok, frame = pcall(CreateFrame, "DropdownButton", nil, parent, TEMPLATE)
        if not ok or type(frame) ~= "table" or type(frame.SetupMenu) ~= "function" then
            -- Template ausente neste cliente: não deixa um frame solto para trás.
            if ok and type(frame) == "table" and type(frame.Hide) == "function" then frame:Hide() end
            return
        end

        if width and type(frame.SetWidth) == "function" then frame:SetWidth(width) end
        frame:SetupMenu(function(_, root)
            for _, option in ipairs(options) do
                root:CreateRadio(option.label,
                    function() return get() == option.id end,
                    function() set(option.id) end)
            end
        end)

        -- O menu relê o valor ao abrir; Refresh só refaz o texto do botão.
        function frame:Refresh()
            if type(self.GenerateMenu) == "function" then self:GenerateMenu() end
        end
        return frame
    end,
}

--- 2. Dropdown próprio (alternativa sem dependência de template).
strategies[#strategies + 1] = {
    name = "custom",
    create = function(parent, options, get, set, width)
        if not (ns.Widgets and ns.Widgets.Dropdown) then return end
        return ns.Widgets.Dropdown(parent, "", options, get, set, width, { compact = true })
    end,
}

--- Cria o dropdown. `options` = { {id=, label=}, ... }; get() -> id; set(id).
--- Devolve (frame, nomeDaEstratégia).
function ArmorDropdown:Create(parent, options, get, set, width)
    for _, strategy in ipairs(strategies) do
        local ok, frame = pcall(strategy.create, parent, options, get, set, width)
        if ok and frame then return frame, strategy.name end
    end
end
