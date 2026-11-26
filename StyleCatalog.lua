-- ============================================================
--  StyleCatalog.lua
--  Registro de texturas e bordas disponíveis para a barra.
--  Extensível: basta acrescentar entradas às listas. Se o addon
--  LibSharedMedia estiver instalado, suas texturas entram também.
-- ============================================================

local _, ns = ...
local L = ns.L

local Catalog = {}
ns.StyleCatalog = Catalog

local textures = {
    { id = "blizzard", label = "Blizzard (cast)", path = "Interface\\TargetingFrame\\UI-StatusBar" },
    { id = "raid",     label = "Raid",            path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
    { id = "skill",    label = L["Skills"],        path = "Interface\\PaperDoll\\UI-Character-Skills-Bar" },
    { id = "flat",     label = L["Flat"],            path = "Interface\\Buttons\\WHITE8X8" },
}

Catalog.borders = {
    { id = "none",    label = L["None"] },
    { id = "thin",    label = L["Thin"],    edgeFile = "Interface\\Buttons\\WHITE8X8",             defaultSize = 1 },
    { id = "tooltip", label = L["Tooltip"], edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",   defaultSize = 12 },
    { id = "dialog",  label = L["Dialog"], edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", defaultSize = 16 },
}

--- Procura um item pelo id; se não achar, devolve o primeiro da lista.
function Catalog:Find(list, id)
    for _, item in ipairs(list) do
        if item.id == id then return item end
    end
    return list[1]
end

--- Texturas builtin + as do LibSharedMedia, quando presente.
function Catalog:Textures()
    local list = {}
    for _, t in ipairs(textures) do list[#list + 1] = t end

    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        for _, name in ipairs(LSM:List("statusbar")) do
            list[#list + 1] = { id = "lsm:" .. name, label = name, path = LSM:Fetch("statusbar", name) }
        end
    end
    return list
end

function Catalog:TexturePath(id)
    return self:Find(self:Textures(), id).path
end
