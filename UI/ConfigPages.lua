-- ============================================================
--  ConfigPages.lua
--  Conteúdo da janela /wu, descrito como dados: grupos da lista à
--  esquerda e, para cada página, as linhas que o PageBuilder monta.
--  Opção nova = uma linha aqui. Limites e rótulos compartilhados com o
--  Edit Mode vêm do SettingSpecs (sliders sem min/max).
--  `sections` = seções da configuração que o "Defaults" da página restaura.
-- ============================================================

local _, ns = ...
local L = ns.L

local Pages = {}
ns.ConfigPages = Pages

local function Get(path) return ns.Config:Get(path) end
local function Off(path) return function() return not Get(path) end end
local function Items(list) return function() return list end end

local function EditModeRows(sample, label)
    -- Caixa "Forçar edição" e aviso, só quando o Edit Mode edita opções desta página
    return {
        { toggle = L["Force edit"], visible = function() return ns.Positioner.HasEditModeSettings() end,
          get = function() return Get("ui.allowWindowEdit") end,
          set = function(value) ns.Config:Set("ui.allowWindowEdit", value) end },
        { text = L["Edit these options in Edit Mode."], font = "GameFontDisableSmall",
          visible = function() return ns.Positioner.IsEditedInEditMode(sample) and not Get("ui.allowWindowEdit") end },
    }
end

local function EditModePosition(positioner)
    return positioner ~= nil and positioner:Mode() == "editmode"
end

local function Append(list, extra)
    for _, row in ipairs(extra) do list[#list + 1] = row end
    return list
end

-- ----------------------------------------------------------------
-- Interface
-- ----------------------------------------------------------------

local tooltip = {
    { header = L["Colors on player tooltips"] },
    { checkbox = "tooltip.name", label = L["Name (with title) in class color"] },
    { checkbox = "tooltip.class", label = L["Class and specialization in class color"] },
    { checkbox = "tooltip.faction", label = L["Faction (Horde red, Alliance blue)"] },
    { header = L["Border on NPC tooltips"] },
    { checkbox = "tooltip.eliteBorder", label = L["Elite NPCs and world bosses (gold)"] },
    { color = "tooltip.eliteColor", label = L["Border color"], indent = 1, disabled = Off("tooltip.eliteBorder") },
    { checkbox = "tooltip.rareBorder", label = L["Rare NPCs (silver)"] },
    { color = "tooltip.rareColor", label = L["Border color"], indent = 1, disabled = Off("tooltip.rareBorder") },
}

local function LevelRows(prefix, title, enable, hint, inspect)
    local base = "items." .. prefix .. "."
    local function NotFixed() return not Get(base .. "enabled") or Get(base .. "colorMode") ~= "fixed" end
    local rows = {
        { header = title },
        { checkbox = base .. "enabled", label = enable },
        { dropdown = base .. "colorMode", label = L["Color"], indent = 1, items = Items({
            { id = "quality", label = L["Item quality"] },
            { id = "fixed", label = L["Fixed color"] },
        }) },
        { color = base .. "color", label = L["Text color"], indent = 1, disabled = NotFixed },
        { dropdown = base .. "anchor", label = L["Position on the icon"], indent = 1, items = Items({
            { id = "TOPLEFT", label = L["Top left"] },
            { id = "TOPRIGHT", label = L["Top right"] },
            { id = "BOTTOMLEFT", label = L["Bottom left"] },
            { id = "BOTTOMRIGHT", label = L["Bottom right"] },
        }) },
        { slider = base .. "fontSize", label = L["Text size"], indent = 1, min = 8, max = 20, step = 1, format = "%d" },
        { text = hint, font = "GameFontDisableSmall" },
    }
    if inspect then
        table.insert(rows, 3, { checkbox = base .. "inspect", label = L["Also on the Inspect window"], indent = 1 })
    end
    return rows
end

local items = Append(Append(
    LevelRows("itemLevel", L["Item level on bags"], L["Show item level on equipment in your bags"],
        L["Default game bags only. Open your bags to see the change."]),
    LevelRows("characterLevel", L["Item level on the character window"], L["Show item level on your equipped items"],
        L["Open your character window to see the change."], true)), {
    { header = L["Enchants on the character window"] },
    { checkbox = "items.characterEnchants.enabled", label = L["Show which items are enchanted"] },
    { checkbox = "items.characterEnchants.showEnchanted", label = L["Also show the enchanted items"], indent = 1 },
    { checkbox = "items.characterEnchants.countRings", label = L["Count rings (Enchanting only)"], indent = 1 },
    { checkbox = "items.characterEnchants.inspect", label = L["Also on the Inspect window"], indent = 1 },
    { checkbox = "items.characterEnchants.inspectCountRings", label = L["Count rings when inspecting"], indent = 2 },
    { dropdown = "items.characterEnchants.nameMode", label = L["Enchant name"], indent = 1, items = Items({
        { id = "full", label = L["Full name"] },
        { id = "short", label = L["Abbreviated"] },
        { id = "value", label = L["Value only"] },
    }) },
    { color = "items.characterEnchants.enchantedColor", label = L["Enchanted color"], indent = 1,
      disabled = Off("items.characterEnchants.enabled") },
    { color = "items.characterEnchants.missingColor", label = L["No enchant color"], indent = 1,
      disabled = Off("items.characterEnchants.enabled") },
    { slider = "items.characterEnchants.fontSize", label = L["Text size"], indent = 1, min = 8, max = 16, step = 1, format = "%d" },
})

--- Itens de um dropdown descrito no SettingSpecs.
local function SpecItems(path) return function() return ns.SettingSpecs:Get(path).values end end

local function ResourcePositioner() return ns.ResourceBar.positioner end

local resource = Append({
    { header = L["Resource bar"] },
}, EditModeRows("resource.width"))
Append(resource, {
    { checkbox = "resource.enabled", label = L["Show the resource bar"] },
    { text = L["Follows your class and form: mana, rage or energy, plus combo points for Rogues and for Druids in Cat Form."],
      font = "GameFontDisableSmall" },
    { dropdown = "resource.visibility", label = L["Visibility"], items = SpecItems("resource.visibility") },
    { header = L["Bar"] },
    { dropdown = "resource.texture", label = L["Texture"],
      items = function() return ns.StyleCatalog:Textures() end,
      preview = function(item) return item.path, ns.ResourceBar:FillColor() end },
    { dropdown = "resource.border", label = L["Border"], items = Items(ns.StyleCatalog.borders) },
    { slider = "resource.borderSize", label = L["Border thickness"] },
    { color = "resource.borderColor", label = L["Border color"] },
    { dropdown = "resource.colorMode", label = L["Color"], items = SpecItems("resource.colorMode") },
    { color = "resource.fillColor", label = L["Bar color"], indent = 1,
      disabled = function() return Get("resource.colorMode") ~= "fixed" end },
    { dropdown = "resource.text", label = L["Text"], items = SpecItems("resource.text") },
    { slider = "resource.fontSize", label = L["Text size"] },
    { checkbox = "resource.smooth", label = L["Smooth animation"] },
    { slider = "resource.width", label = L["Width"] },
    { slider = "resource.height", label = L["Height"] },
    { slider = "resource.scale", label = L["Scale"] },
    { header = L["Combo points"] },
    { checkbox = "resource.comboPoints", label = L["Show combo points (Rogues and Druids in Cat Form)"] },
    { dropdown = "resource.comboPosition", label = L["Combo points position"], indent = 1,
      items = SpecItems("resource.comboPosition") },
    { slider = "resource.comboHeight", label = L["Combo points height"], indent = 1 },
    { slider = "resource.comboSpacing", label = L["Combo points spacing"], indent = 1 },
    { color = "resource.comboColor", label = L["Combo point color"], indent = 1 },
    { color = "resource.comboEmptyColor", label = L["Empty point color"], indent = 1 },
    { header = L["Position"] },
    { text = string.format(L["Position: Esc > Edit Mode, then drag \"%s\"."], L["Resource bar"]),
      when = function() return EditModePosition(ResourcePositioner()) end },
    { toggle = L["Move bar (drag with the mouse)"],
      when = function() return ResourcePositioner() ~= nil and not EditModePosition(ResourcePositioner()) end,
      get = function() return ns.ResourceBar:IsUnlocked() end,
      set = function(value) ns.ResourceBar:SetUnlocked(value) end },
    { text = L["Install the LibEditMode addon to position via Edit Mode."], font = "GameFontDisableSmall",
      when = function() return not EditModePosition(ResourcePositioner()) end },
    { buttons = {
        { text = L["Preview"], width = 130,
          onClick = function() ns.ResourceBar:Preview(not ns.ResourceBar:IsPreviewing()) end },
        { text = L["Reset position"], width = 130, onClick = function() ns.ResourceBar:ResetPosition() end },
    } },
})

local wardrobe = {
    { header = L["Appearance collection"] },
    { checkbox = "wardrobe.enabled", label = L["Show the armor type filter in the collection window"] },
    { text = L["Adds a dropdown to the Items tab of the Appearances window."], font = "GameFontDisableSmall" },
}

-- ----------------------------------------------------------------
-- Ferramentas
-- ----------------------------------------------------------------


local flight = Append({
    { header = L["Flight durations"] },
    { checkbox = "taxi.tooltip", label = L["Show duration on the flight map tooltip"] },
    { checkbox = "taxi.bar", label = L["Show the flight bar during flights"] },
    { header = L["Flight bar"] },
}, EditModeRows("bar.width"))
Append(flight, {
    { dropdown = "bar.texture", label = L["Texture"],
      items = function() return ns.StyleCatalog:Textures() end,
      preview = function(item) return item.path, ns.FlightCastBar:FillColor() end },
    { dropdown = "bar.border", label = L["Border"], items = Items(ns.StyleCatalog.borders) },
    { slider = "bar.borderSize", label = L["Border thickness"] },
    { color = "bar.borderColor", label = L["Border color"] },
    { checkbox = "bar.classColor", label = L["Class color"] },
    { color = "bar.fillColor", label = L["Bar color"], disabled = function() return Get("bar.classColor") end },
    { slider = "bar.fontSize", label = L["Text size"] },
    { slider = "bar.width", label = L["Width"] },
    { slider = "bar.height", label = L["Height"] },
    { slider = "bar.scale", label = L["Scale"] },
    { checkbox = "bar.drain", label = L["Drain bar (like a channel)"] },
    { text = string.format(L["Position: Esc > Edit Mode, then drag \"%s\"."], L["Flight bar"]),
      when = function() return EditModePosition(ns.Positioner) end },
    { toggle = L["Move bar (drag with the mouse)"], when = function() return not EditModePosition(ns.Positioner) end,
      get = function() return ns.Positioner:IsUnlocked() end,
      set = function(value) ns.Positioner:SetUnlocked(value) end },
    { text = L["Install the LibEditMode addon to position via Edit Mode."], font = "GameFontDisableSmall",
      when = function() return not EditModePosition(ns.Positioner) end },
    { buttons = { { text = L["Preview"], width = 130,
                    onClick = function() ns.FlightCastBar:Preview(not ns.FlightCastBar:IsPreviewing()) end } } },
    { header = L["Recorded times"] },
    { text = function() return string.format(L["Recorded routes: %d"], ns.TaxiDatabase:Count()) end,
      font = "GameFontHighlight" },
    { text = L["Times are measured from your real flights; \"~\" marks an estimate."], font = "GameFontDisableSmall" },
    { buttons = { { text = L["Delete recorded times"], width = 180,
                    onClick = function() ns.TaxiClearConfirm:Request({ onDone = function() ns.ConfigWindow:Refresh() end }) end } } },
    -- Teste da confirmação (validado no jogo e desativado; Request({ dryRun = true }) continua no código):
    -- { buttons = { { text = L["Test confirmation (deletes nothing)"], width = 230,
    --                 onClick = function() ns.TaxiClearConfirm:Request({ dryRun = true }) end } } },
})

local vendor = {
    { header = L["Gold spent and earned with vendors"] },
    { checkbox = "vendor.enabled", label = L["Show gold messages when using vendors"] },
    { checkbox = "vendor.onClose", label = L["Summary when closing the vendor"], indent = 1 },
    { checkbox = "vendor.perTransaction", label = L["Message after each transaction"], indent = 1 },
    { checkbox = "vendor.showZero", label = L["Also show when nothing changed"], indent = 1 },
}

local function TrinketPositioner() return ns.TrinketSelector.positioner end

local trinkets = Append({
    { header = L["Trinket selector"] },
}, EditModeRows("trinkets.scale"))
Append(trinkets, {
    { checkbox = "trinkets.enabled", label = L["Show the trinket selector on screen"] },
    { text = L["Click a slot to list the trinkets in your bags."] .. " "
             .. L["Click one to equip it in that slot (not in combat)."], font = "GameFontDisableSmall" },
    { checkbox = "trinkets.showItemLevel", label = L["Show item level on icons"] },
    { slider = "trinkets.scale", label = L["Scale"] },
    { header = L["Buttons"] },
    { slider = "trinkets.slotSize", label = L["Button size"] },
    { slider = "trinkets.gap", label = L["Button spacing"] },
    { dropdown = "trinkets.orientation", label = L["Layout"], items = Items({
        { id = "vertical", label = L["Vertical"] },
        { id = "horizontal", label = L["Horizontal"] },
    }) },
    { checkbox = "trinkets.hideInCombat", label = L["Hide the selector in combat"] },
    { text = string.format(L["Position: Esc > Edit Mode, then drag \"%s\"."], L["Trinket selector"]),
      when = function() return EditModePosition(TrinketPositioner()) end },
    { toggle = L["Move selector (drag with the mouse)"],
      when = function() return TrinketPositioner() ~= nil and not EditModePosition(TrinketPositioner()) end,
      get = function() return TrinketPositioner():IsUnlocked() end,
      set = function(value) TrinketPositioner():SetUnlocked(value) end },
    { buttons = { { text = L["Reset position"], width = 130,
                    onClick = function() ns.TrinketSelector:ResetPosition() end } } },
    { header = L["Selection grid"] },
    { slider = "trinkets.columns", label = L["Grid columns"] },
    { slider = "trinkets.itemSize", label = L["Icon size"] },
    { slider = "trinkets.itemGap", label = L["Icon spacing"] },
})

-- ----------------------------------------------------------------
-- Grupos (ordem da lista à esquerda)
-- ----------------------------------------------------------------

Pages.GROUPS = {
    { title = L["Interface"], pages = {
        { id = "tooltip",  title = L["Tooltip"],  sections = { "tooltip" },        rows = tooltip },
        { id = "items",    title = L["Items"],    sections = { "items" },          rows = items },
        { id = "resource", title = L["Resource bar"], sections = { "resource" },   rows = resource },
        { id = "wardrobe", title = L["Wardrobe"], sections = { "wardrobe" },       rows = wardrobe },
    } },
    { title = L["Tools"], pages = {
        { id = "flight",   title = L["Flight"],   sections = { "taxi", "bar" },    rows = flight },
        { id = "vendor",   title = L["Vendor"],   sections = { "vendor" },         rows = vendor },
        { id = "trinkets", title = L["Trinkets"], sections = { "trinkets" },       rows = trinkets },
    } },
}
