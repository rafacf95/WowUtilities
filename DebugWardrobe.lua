-- ============================================================
--  DebugWardrobe.lua
--  /wu debug wardrobe [categoria]
--  Diagnóstico do sistema de transmog: quais APIs existem no cliente,
--  como é a interface aberta (árvore de frames podada, grade de
--  aparências, ScrollBox/DataProvider, métodos de filtro) e
--  se dá para descobrir o tipo de armadura (tecido/couro/malha/placa)
--  de cada aparência. Sem argumento, usa a categoria que a grade da
--  interface está mostrando.
--  Só lê; não altera nada. Separado em Report (monta as linhas) e o
--  comando (abre a janela de texto), para poder ser testado sem o jogo.
-- ============================================================

local _, ns = ...

local Wardrobe = {}
ns.DebugWardrobe = Wardrobe

local Show = ns.Debug.Show

local ARMOR_CLASS = 4
local SUBCLASS_NAMES = { [0] = "Misc", [1] = "Cloth", [2] = "Leather", [3] = "Mail",
                         [4] = "Plate", [5] = "Cosmetic", [6] = "Shield" }
local SAMPLE_LIMIT = 300  -- aparências analisadas por amostra
local DETAIL_LIMIT = 3    -- aparências detalhadas uma a uma
local TREE_DEPTH, TREE_LIMIT = 6, 200  -- profundidade e linhas por raiz
local VISIBLE_FRAMES_LIMIT = 80
local GRID_LIMIT = 3      -- grades detalhadas por relatório

-- Tipos que não têm filhos úteis e nomes de subárvores sem interesse (podados)
local LEAF_TYPES = { Button = true, CheckButton = true, EditBox = true, Slider = true,
                    Cooldown = true, StatusBar = true, ModelScene = true, Model = true }
local SKIP_LABELS = { [".NineSlice"] = true, [".ScrollBar"] = true, [".Shadows"] = true,
                      [".DragDelegate"] = true, [".Track"] = true, [".Controller"] = true }
-- Campos de identificação que uma entrada de aparência costuma ter
local ENTRY_ID_FIELDS = { "visualID", "sourceID", "itemModifiedAppearanceID", "appearanceID" }
-- Trechos de nome de método que interessam para plugar um filtro
local METHOD_HINTS = { "Filter", "Refresh", "Update", "Search", "Visual", "Appearance", "Category", "Source" }
local PROVIDER_ENTRIES_LIMIT = 2000

local ADDONS = { "Blizzard_Collections", "Blizzard_Transmog" }

local COLLECTION_FUNCTIONS = {
    "GetCategoryAppearances", "GetAppearanceSources", "GetAllAppearanceSources",
    "GetSourceInfo", "GetSourceItemID", "GetAppearanceSourceInfo", "GetCategoryInfo",
    "GetCategoryForItem", "GetClassFilter", "SetClassFilter", "GetCollectedShown",
    "GetUncollectedShown", "GetValidAppearanceSourcesForClass", "IsCategoryValidForItem",
    "SetSearchAndFilterCategory", "IsUsingDefaultFilters", "PlayerHasTransmog",
}

local FRAME_NAMES = { "CollectionsJournal", "WardrobeFrame", "WardrobeCollectionFrame",
                      "WardrobeTransmogFrame" }
local TREE_ROOTS = { "WardrobeTransmogFrame", "WardrobeCollectionFrame" }
local NAME_PATTERNS = { "Wardrobe", "Transmog", "Collection", "Outfit" }

-- Campos que uma grade de aparências costuma ter (2 ou mais = candidata)
local GRID_FIELDS = { "filteredVisualsList", "Models", "PagingFrame", "FilterVisuals",
                      "RefreshVisualsList", "GetFilteredVisualsList", "GetActiveCategory" }
local GRID_DETAIL_FIELDS = { "filteredVisualsList", "activeCategory", "PagingFrame", "Models",
                             "RefreshVisualsList", "UpdateItems", "GetActiveCategory",
                             "SetActiveCategory", "FilterVisuals", "GetFilteredVisualsList",
                             "UpdateWeaponDropdown", "OnShow" }

-- ----------------------------------------------------------------
-- Leitura segura (qualquer tabela do jogo pode ter metatable estranha)
-- ----------------------------------------------------------------

local function Field(table_, key)
    if type(table_) ~= "table" then return nil end
    local ok, value = pcall(function() return table_[key] end)
    if ok then return value end
end

local function CallMethod(object, method, ...)
    local fn = Field(object, method)
    if type(fn) ~= "function" then return nil end
    return ns.SafeCall(fn, object, ...)
end

local function Now()
    if debugprofilestop then return debugprofilestop() end
    return GetTime() * 1000
end

local function IsAddOnLoaded(name)
    local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if not fn then return "n/a" end
    return Show((ns.SafeCall(fn, name)))
end

local function IsFrame(value)
    return type(Field(value, "GetObjectType")) == "function"
end

local function FrameState(frame)
    return "shown=" .. Show(CallMethod(frame, "IsShown")) .. " visible=" .. Show(CallMethod(frame, "IsVisible"))
end

local function SortedKeys(set)
    local keys = {}
    for k in pairs(set) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

--- {a=true,b=true} -> "a/b"; vazio -> "-".
local function Join(set)
    local keys = SortedKeys(set)
    return #keys > 0 and table.concat(keys, "/") or "-"
end

local function Describe(value)
    local kind = type(value)
    if kind == "table" then return "table(" .. #value .. ")" end
    return kind
end

-- ----------------------------------------------------------------
-- Tipo de armadura
-- ----------------------------------------------------------------

local function ItemInfo(itemID)
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not fn or not itemID then return nil end
    local _, itemType, itemSubType, _, _, classID, subClassID = ns.SafeCall(fn, itemID)
    if classID == nil then return nil end
    return { classID = classID, subClassID = subClassID, type = itemType, subType = itemSubType }
end

--- Rótulo de tipo de armadura de um item; nil se não for armadura.
local function ArmorLabel(info)
    if not info or info.classID ~= ARMOR_CLASS then return nil end
    return SUBCLASS_NAMES[info.subClassID] or ("sub" .. tostring(info.subClassID))
end

--- itemIDs de uma aparência: só fontes conhecidas pelo jogador.
local function KnownItemIDs(visualID, category)
    local api = C_TransmogCollection
    local ids = {}
    if not api.GetAppearanceSources then return ids end
    local sources = ns.SafeCall(api.GetAppearanceSources, visualID, category)
    if type(sources) == "table" then
        for _, source in ipairs(sources) do
            if type(source) == "table" and source.itemID then ids[#ids + 1] = source.itemID end
        end
    end
    return ids
end

--- itemIDs de uma aparência: todas as fontes.
local function AllItemIDs(visualID)
    local api = C_TransmogCollection
    local ids = {}
    if not api.GetAllAppearanceSources then return ids end
    local sources = ns.SafeCall(api.GetAllAppearanceSources, visualID)
    if type(sources) ~= "table" then return ids end
    for _, source in ipairs(sources) do
        local itemID
        if type(source) == "table" then
            itemID = source.itemID
        elseif api.GetSourceItemID then
            itemID = (ns.SafeCall(api.GetSourceItemID, source))
        elseif api.GetSourceInfo then
            local info = ns.SafeCall(api.GetSourceInfo, source)
            itemID = type(info) == "table" and info.itemID or nil
        end
        if itemID then ids[#ids + 1] = itemID end
    end
    return ids
end

local function NewTally() return { labels = {}, none = 0, mixed = 0 } end

--- Conta os tipos de armadura de uma lista de itemIDs.
local function Classify(itemIDs, tally)
    local seen, count = {}, 0
    for _, itemID in ipairs(itemIDs) do
        local label = ArmorLabel(ItemInfo(itemID)) or "non-armor/unknown"
        if not seen[label] then seen[label] = true; count = count + 1 end
    end
    if next(seen) == nil then
        tally.none = tally.none + 1
    else
        for label in pairs(seen) do tally.labels[label] = (tally.labels[label] or 0) + 1 end
        if count > 1 then tally.mixed = tally.mixed + 1 end
    end
    return seen
end

local function TallyLine(name, tally)
    local parts = {}
    for _, label in ipairs(SortedKeys(tally.labels)) do parts[#parts + 1] = label .. "=" .. tally.labels[label] end
    return string.format("  %s: %s | no sources=%d | appearances with several types=%d",
        name, #parts > 0 and table.concat(parts, " ") or "nothing", tally.none, tally.mixed)
end

--- list = { {visualID=, isCollected=}, ... }
local function TallyList(add, title, list, category)
    local known, all = NewTally(), NewTally()
    local limit = math.min(#list, SAMPLE_LIMIT)
    local started = Now()
    for i = 1, limit do
        local visualID = list[i].visualID
        local knownSeen = Classify(KnownItemIDs(visualID, category), known)
        local allSeen = Classify(AllItemIDs(visualID), all)
        if i <= DETAIL_LIMIT then
            add(string.format("  #%d visualID=%s collected=%s | known: %s | all: %s", i, Show(visualID),
                Show(list[i].isCollected), Join(knownSeen), Join(allSeen)))
        end
    end
    add(string.format("%s — armor type of the first %d appearances (%.1f ms):", title, limit, Now() - started))
    add(TallyLine("GetAppearanceSources (known only)", known))
    add(TallyLine("GetAllAppearanceSources (all)", all))
end

-- ----------------------------------------------------------------
-- Seções do relatório; cada uma recebe `add(texto)`
-- ----------------------------------------------------------------

local function Environment(add)
    local toc = GetBuildInfo and select(4, GetBuildInfo())
    add("Client interface: " .. Show(toc))
    local parts = {}
    for _, name in ipairs(ADDONS) do parts[#parts + 1] = name .. "=" .. IsAddOnLoaded(name) end
    add("Interface addons loaded: " .. table.concat(parts, ", "))
end

local function Api(add)
    local api = C_TransmogCollection
    if type(api) ~= "table" then
        add("C_TransmogCollection: MISSING")
        return false
    end
    local present, missing = {}, {}
    for _, name in ipairs(COLLECTION_FUNCTIONS) do
        if type(api[name]) == "function" then present[#present + 1] = name else missing[#missing + 1] = name end
    end
    add("C_TransmogCollection present: " .. (#present > 0 and table.concat(present, ", ") or "none"))
    add("C_TransmogCollection missing: " .. (#missing > 0 and table.concat(missing, ", ") or "none"))

    local itemInfo = (C_Item and C_Item.GetItemInfoInstant) and "C_Item.GetItemInfoInstant"
        or (GetItemInfoInstant and "GetItemInfoInstant") or "MISSING"
    add("Item info API: " .. itemInfo)
    add("Enum.TransmogCollectionType: " .. ((Enum and Enum.TransmogCollectionType) and "present" or "MISSING"))
    return true
end

local function Filters(add)
    local api = C_TransmogCollection
    if type(api) ~= "table" then return end
    local playerClassID = select(3, ns.SafeCall(UnitClass, "player"))
    add("Player classID: " .. Show(playerClassID))
    if api.GetClassFilter then add("GetClassFilter: " .. Show((ns.SafeCall(api.GetClassFilter)))) end
    if api.GetCollectedShown then add("GetCollectedShown: " .. Show((ns.SafeCall(api.GetCollectedShown)))) end
    if api.GetUncollectedShown then add("GetUncollectedShown: " .. Show((ns.SafeCall(api.GetUncollectedShown)))) end
end

--- Frames conhecidos + todos os frames globais visíveis com nome de transmog.
--- (IsShown só olha o próprio frame; IsVisible considera os pais.)
local function Frames(add)
    local parts = {}
    for _, name in ipairs(FRAME_NAMES) do
        local frame = _G[name]
        parts[#parts + 1] = frame and (name .. " (" .. FrameState(frame) .. ")") or (name .. " (nil)")
    end
    add("Frames: " .. table.concat(parts, ", "))

    local total, frames, visible = 0, 0, {}
    for key, value in pairs(_G) do
        if type(key) == "string" then
            for _, pattern in ipairs(NAME_PATTERNS) do
                if key:find(pattern, 1, true) then
                    total = total + 1
                    if IsFrame(value) then
                        frames = frames + 1
                        if CallMethod(value, "IsVisible") == true then visible[#visible + 1] = key end
                    end
                    break
                end
            end
        end
    end
    table.sort(visible)
    local shownNames = {}
    for i = 1, math.min(#visible, VISIBLE_FRAMES_LIMIT) do shownNames[i] = visible[i] end
    local extra = #visible > VISIBLE_FRAMES_LIMIT and (" ... +" .. (#visible - VISIBLE_FRAMES_LIMIT) .. " more") or ""
    add(string.format("Globals matching %s: %d (%d are frames, %d visible now)",
        table.concat(NAME_PATTERNS, "/"), total, frames, #visible))
    add("Visible frames: " .. (#shownNames > 0 and table.concat(shownNames, ", ") or "none") .. extra)
end

-- ----------------------------------------------------------------
-- Descoberta de dados de aparência em um frame
-- ----------------------------------------------------------------

local function LooksLikeEntry(entry)
    if type(entry) ~= "table" then return false end
    for _, name in ipairs(ENTRY_ID_FIELDS) do
        if Field(entry, name) ~= nil then return true end
    end
    return false
end

local function SampleKeys(entry)
    if type(entry) ~= "table" then return type(entry) end
    local keys = {}
    pcall(function()
        for key in pairs(entry) do if type(key) == "string" then keys[key] = true end end
    end)
    local sorted, out = SortedKeys(keys), {}
    for i = 1, math.min(#sorted, 12) do out[i] = sorted[i] end
    return table.concat(out, ",")
end

--- Campos do frame que são listas de entradas de aparência.
local function DataFields(node)
    local found = {}
    pcall(function()
        for key, value in pairs(node) do
            if type(key) == "string" and type(value) == "table" and not IsFrame(value) and LooksLikeEntry(value[1]) then
                found[#found + 1] = { key = key, size = #value, sample = SampleKeys(value[1]) }
            end
        end
    end)
    table.sort(found, function(x, y) return x.key < y.key end)
    return found
end

--- ScrollBox com DataProvider: { provider, size, first } ou nil.
local function ProviderInfo(node)
    local provider = CallMethod(node, "GetDataProvider")
    if type(provider) ~= "table" then return nil end
    local size = CallMethod(provider, "GetSize")
    if type(size) ~= "number" then return nil end
    return { provider = provider, size = size, first = size > 0 and CallMethod(provider, "Find", 1) or nil }
end

--- Métodos do frame cujo nome sugere filtro/atualização de aparências.
local function InterestingMethods(node)
    local names = {}
    pcall(function()
        for key, value in pairs(node) do
            if type(key) == "string" and type(value) == "function" then
                for _, hint in ipairs(METHOD_HINTS) do
                    if key:find(hint, 1, true) then names[key] = true break end
                end
            end
        end
    end)
    return SortedKeys(names)
end

--- " {filteredVisualsList=table(45) Models=table(18)}" e quantos campos de grade tem.
local function GridMarks(node)
    local marks, hits = {}, 0
    for _, name in ipairs(GRID_FIELDS) do
        local value = Field(node, name)
        if value ~= nil then
            hits = hits + 1
            marks[#marks + 1] = name .. "=" .. Describe(value)
        end
    end
    return marks, hits
end

-- ----------------------------------------------------------------
-- Árvore de frames (em largura, podada)
-- ----------------------------------------------------------------

local function ChildLabel(parent, child)
    local name = CallMethod(child, "GetName")
    if type(name) == "string" and name ~= "" then return name end
    local key
    pcall(function()
        for k, v in pairs(parent) do
            if v == child and type(k) == "string" then key = k break end
        end
    end)
    return key and ("." .. key) or "(anonymous)"
end

local function ChildCount(node)
    local ok, count = pcall(function() return select("#", node:GetChildren()) end)
    return ok and count or 0
end

local function JoinPath(parentPath, label)
    if label:sub(1, 1) == "." then return parentPath .. label end
    return parentPath .. "/" .. label
end

--- Frames filhos, juntando irmãos anônimos seguidos e idênticos ("x7 similar").
local function GroupedChildren(node, path)
    local ok, children = pcall(function() return { node:GetChildren() } end)
    if not ok then return {} end
    local groups, last, lastSignature = {}, nil, nil
    for _, child in ipairs(children) do
        if IsFrame(child) then
            local label = ChildLabel(node, child)
            local kind = Show(CallMethod(child, "GetObjectType") or "?")
            local visible = CallMethod(child, "IsVisible") == true
            local signature = label == "(anonymous)" and (kind .. tostring(visible) .. ChildCount(child)) or nil
            if signature and signature == lastSignature then
                last.count = last.count + 1
            else
                last = { node = child, label = label, path = JoinPath(path, label), kind = kind, count = 1 }
                groups[#groups + 1] = last
                lastSignature = signature
            end
        end
    end
    return groups
end

local function ShouldDescend(entry, depth, visible)
    if depth >= TREE_DEPTH or LEAF_TYPES[entry.kind] or SKIP_LABELS[entry.label] then return false end
    return visible or depth <= 1 -- subárvores escondidas só até o 2º nível
end

--- Descreve um frame; devolve a linha e se ele parece uma grade de aparências.
local function VisitNode(entry)
    local node = entry.node
    local marks, hits = GridMarks(node)
    local dataFields = DataFields(node)
    local provider = ProviderInfo(node)

    local extras = {}
    if #marks > 0 then extras[#extras + 1] = "{" .. table.concat(marks, " ") .. "}" end
    for _, field in ipairs(dataFields) do
        extras[#extras + 1] = string.format("data:%s(%d)[%s]", field.key, field.size, field.sample)
    end
    local appearanceProvider = false
    if provider then
        appearanceProvider = LooksLikeEntry(provider.first)
        extras[#extras + 1] = string.format("provider(%d)[%s]", provider.size, SampleKeys(provider.first))
    end

    local candidate = hits >= 2 or #dataFields > 0 or appearanceProvider
    local line = string.format("%s [%s] %s%s%s%s", entry.path, entry.kind, FrameState(node),
        entry.count > 1 and (" x" .. entry.count .. " similar") or "",
        #extras > 0 and (" " .. table.concat(extras, " ")) or "",
        candidate and "  <== appearance grid candidate" or "")
    return line, candidate
end

--- Percorre a hierarquia dos frames raiz; devolve as grades candidatas.
local function Tree(add)
    local state = { seen = {}, grids = {} }
    for _, rootName in ipairs(TREE_ROOTS) do
        local root = _G[rootName]
        if IsFrame(root) then
            add("Frame tree: " .. rootName .. " (breadth-first, pruned)")
            local queue, head, printed = { { node = root, label = rootName, path = rootName, kind = Show(CallMethod(root, "GetObjectType") or "?"), count = 1, depth = 0 } }, 1, 0
            while queue[head] do
                local entry = queue[head]
                head = head + 1
                if not state.seen[entry.node] then
                    state.seen[entry.node] = true
                    if printed >= TREE_LIMIT then
                        add("  ... tree truncated at " .. TREE_LIMIT .. " lines")
                        break
                    end
                    printed = printed + 1
                    local line, candidate = VisitNode(entry)
                    add("  " .. line)
                    if candidate then state.grids[#state.grids + 1] = { label = entry.path, node = entry.node } end

                    local visible = CallMethod(entry.node, "IsVisible") == true
                    if ShouldDescend(entry, entry.depth, visible) then
                        for _, child in ipairs(GroupedChildren(entry.node, entry.path)) do
                            child.depth = entry.depth + 1
                            queue[#queue + 1] = child
                        end
                    end
                end
            end
        else
            add("Frame tree: " .. rootName .. " not found")
        end
    end

    -- Grades que não estão sob as raízes, mas são globais
    for key, value in pairs(_G) do
        if type(key) == "string" and not state.seen[value] and IsFrame(value)
           and (key:find("Wardrobe") or key:find("Transmog") or key:find("Collection")) then
            local _, hits = GridMarks(value)
            if hits >= 2 or #DataFields(value) > 0 then
                state.seen[value] = true
                state.grids[#state.grids + 1] = { label = key .. " (global)", node = value }
            end
        end
    end
    return state.grids
end

-- ----------------------------------------------------------------
-- Grade de aparências
-- ----------------------------------------------------------------

local function ActiveCategory(node)
    local value = CallMethod(node, "GetActiveCategory")
    if type(value) ~= "number" then value = Field(node, "activeCategory") end
    return type(value) == "number" and value or nil
end

--- Entrada qualquer -> { visualID=, isCollected= } (resolve sourceID se preciso).
local function NormalizeEntry(entry)
    if type(entry) == "number" then return { visualID = entry } end
    if type(entry) ~= "table" then return nil end
    local visualID = Field(entry, "visualID")
    if visualID == nil and Field(entry, "sourceID") and C_TransmogCollection and C_TransmogCollection.GetSourceInfo then
        local info = ns.SafeCall(C_TransmogCollection.GetSourceInfo, Field(entry, "sourceID"))
        visualID = type(info) == "table" and Field(info, "visualID") or nil
    end
    if visualID == nil then return nil end
    return { visualID = visualID, isCollected = Field(entry, "isCollected") }
end

local function NormalizeList(source)
    local list = {}
    for _, entry in ipairs(source) do
        local normalized = NormalizeEntry(entry)
        if normalized then list[#list + 1] = normalized end
    end
    return list
end

--- Lista de aparências que a interface mostra -> (lista, de onde veio).
local function UiList(node)
    local filtered = CallMethod(node, "GetFilteredVisualsList")
    if type(filtered) == "table" then return NormalizeList(filtered), "GetFilteredVisualsList()" end
    filtered = Field(node, "filteredVisualsList")
    if type(filtered) == "table" then return NormalizeList(filtered), "filteredVisualsList" end

    for _, field in ipairs(DataFields(node)) do
        local list = NormalizeList(Field(node, field.key))
        if #list > 0 then return list, "field " .. field.key end
    end

    local provider = ProviderInfo(node)
    if provider and provider.size > 0 and LooksLikeEntry(provider.first) then
        local list = {}
        for i = 1, math.min(provider.size, PROVIDER_ENTRIES_LIMIT) do
            local normalized = NormalizeEntry(CallMethod(provider.provider, "Find", i))
            if normalized then list[#list + 1] = normalized end
        end
        return list, "data provider"
    end
    return nil
end

local function GridDetails(add, grid, fallbackCategory)
    local node = grid.node
    add("Grid: " .. grid.label .. " (" .. FrameState(node) .. ")")

    local fields = {}
    for _, name in ipairs(GRID_DETAIL_FIELDS) do
        fields[#fields + 1] = name .. "=" .. Describe(Field(node, name))
    end
    add("  fields: " .. table.concat(fields, ", "))
    local methods = InterestingMethods(node)
    add("  methods of interest (" .. #methods .. "): " .. (#methods > 0 and table.concat(methods, ", ") or "none"))

    local keys = {}
    pcall(function()
        for key, value in pairs(node) do
            if type(key) == "string" then keys[key] = type(value) == "function" and "f" or type(value):sub(1, 1) end
        end
    end)
    local sorted, list = SortedKeys(keys), {}
    for i, key in ipairs(sorted) do list[i] = key .. ":" .. keys[key] end
    add("  keys (" .. #sorted .. ", f=function t=table n=number): " .. table.concat(list, " "))

    local category = ActiveCategory(node) or fallbackCategory
    add("  active category: " .. Show(ActiveCategory(node)) .. " | grid size: "
        .. Show(Field(node, "NUM_ROWS")) .. "x" .. Show(Field(node, "NUM_COLS")))

    local uiList, origin = UiList(node)
    if not uiList then
        add("  UI list: unavailable (select a slot/category first)")
        return
    end
    add("  UI list entries: " .. #uiList .. " (from " .. origin .. ")")

    local api = C_TransmogCollection
    if category and api and api.GetCategoryAppearances then
        local apiList = ns.SafeCall(api.GetCategoryAppearances, category)
        if type(apiList) == "table" then
            local inUi, inApi = {}, {}
            for _, a in ipairs(uiList) do inUi[a.visualID] = true end
            local hiddenByUi = 0
            for _, a in ipairs(apiList) do
                inApi[a.visualID] = true
                if not inUi[a.visualID] then hiddenByUi = hiddenByUi + 1 end
            end
            local onlyUi = 0
            for _, a in ipairs(uiList) do if not inApi[a.visualID] then onlyUi = onlyUi + 1 end end
            add(string.format("  API list for category %s: %d | in API but not in UI: %d | in UI but not in API: %d",
                Show(category), #apiList, hiddenByUi, onlyUi))
        end
    end
    if #uiList > 0 and api then TallyList(add, "  UI list", uiList, category) end
end

-- ----------------------------------------------------------------
-- Amostra pela API (independe da interface)
-- ----------------------------------------------------------------

local function CategoryName(category)
    local info = C_TransmogCollection.GetCategoryInfo
    if not info then return "n/a" end
    local values = { ns.SafeCall(info, category) }
    local first = values[1]
    local text = type(first) == "table" and (Field(first, "name") or "table") or Show(first)
    return text .. " | returns: " .. Show(values[1]) .. ", " .. Show(values[2]) .. ", " .. Show(values[3])
end

local function Sample(add, category)
    local api = C_TransmogCollection
    if type(api) ~= "table" or not api.GetCategoryAppearances then
        add("Sample: GetCategoryAppearances unavailable")
        return
    end
    local list = ns.SafeCall(api.GetCategoryAppearances, category)
    if type(list) ~= "table" then
        add("Sample: category " .. Show(category) .. " returned " .. Show(list))
        return
    end

    local collected = 0
    for _, appearance in ipairs(list) do if appearance.isCollected then collected = collected + 1 end end
    add(string.format("Category %s (%s): %d appearances, %d collected",
        Show(category), CategoryName(category), #list, collected))
    TallyList(add, "API list", list, category)
end

-- ----------------------------------------------------------------
-- API pública
-- ----------------------------------------------------------------

--- Categoria padrão: Head (1).
local function DefaultCategory()
    local enum = Enum and Enum.TransmogCollectionType
    return enum and enum.Head or 1
end

--- Dropdown de armas (referência de estilo) e o que o nosso filtro usou.
local function WeaponDropdown(add)
    local window = rawget(_G, "WardrobeCollectionFrame")
    local items = type(window) == "table" and window.ItemsCollectionFrame
    local weapon = type(items) == "table" and items.WeaponDropdown
    if type(weapon) ~= "table" then
        add("Weapon dropdown: not found")
    else
        local kind = "?"
        pcall(function() kind = weapon:GetObjectType() end)
        add(string.format("Weapon dropdown: %s | SetupMenu=%s GenerateMenu=%s width=%s",
            tostring(kind), tostring(type(weapon.SetupMenu) == "function"),
            tostring(type(weapon.GenerateMenu) == "function"),
            Show(ns.SafeCall(function() return weapon:GetWidth() end))))
    end
    add("Armor filter dropdown style: " .. tostring(ns.WardrobeIntegration and ns.WardrobeIntegration.dropdownStyle or "none")
        .. " | template " .. "WowStyle1DropdownTemplate")
end

--- Monta o relatório inteiro como lista de linhas.
--- Sem `category`, usa a da primeira grade com categoria ativa (ou Head).
function Wardrobe:Report(category)
    local lines = {}
    local function add(text) lines[#lines + 1] = text end

    add("WowUtilities debug — wardrobe")
    Environment(add)
    local hasApi = Api(add)
    if hasApi then Filters(add) end
    Frames(add)
    local grids = Tree(add)

    if not category then
        for _, grid in ipairs(grids) do
            category = ActiveCategory(grid.node)
            if category then break end
        end
    end
    category = category or DefaultCategory()

    WeaponDropdown(add)
    if #grids == 0 then add("Appearance grids: none found") end
    for i = 1, math.min(#grids, GRID_LIMIT) do GridDetails(add, grids[i], category) end
    if #grids > GRID_LIMIT then add("... " .. (#grids - GRID_LIMIT) .. " more grid candidates not detailed") end

    if hasApi then Sample(add, category) end
    return lines
end

ns.Debug:Register("wardrobe", function(arg)
    local ok, lines = pcall(Wardrobe.Report, Wardrobe, tonumber(arg))
    if not ok then lines = { "WowUtilities wardrobe debug failed: " .. tostring(lines) } end
    ns.Debug:Output("WowUtilities debug — wardrobe", lines)
end)
