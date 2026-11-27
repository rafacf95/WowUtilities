-- ============================================================
--  PowerSource.lua
--  Adapter: tudo o que a barra de recurso lê do jogo, num lugar só.
--  No Forever o valor atual do recurso principal (mana, rage, energy)
--  é um VALOR SECRETO (/wu debug power): não dá para fazer contas nem
--  comparações com ele, só repassá-lo à StatusBar e ao texto. Por isso
--  Value e Percent devolvem o valor cru (sem SafeCall, que o apagaria);
--  máximo, tipo do recurso e pontos de combo não são secretos.
-- ============================================================

local _, ns = ...

local Source = {}
ns.PowerSource = Source

local function PowerEnum(name, fallback)
    local enum = rawget(_G, "Enum")
    local value = type(enum) == "table" and type(enum.PowerType) == "table" and enum.PowerType[name]
    return type(value) == "number" and value or fallback
end

Source.MANA = PowerEnum("Mana", 0)
Source.ENERGY = PowerEnum("Energy", 3)
Source.COMBO = PowerEnum("ComboPoints", 4)

local DEFAULT_COLOR = { r = 0, g = 0, b = 1 }
local MAX_COMBO = 10

local function Fn(name)
    local fn = rawget(_G, name)
    return type(fn) == "function" and fn or nil
end

--- Tipo do recurso atual do jogador (segue a forma do druida) e o token ("MANA").
function Source:PowerType()
    local powerType, token = ns.SafeCall(Fn("UnitPowerType"), "player")
    return type(powerType) == "number" and powerType or self.MANA, token
end

--- Valor atual, cru (pode ser secreto). nil se a API falhar.
function Source:Value(powerType)
    local fn = Fn("UnitPower")
    if not fn then return nil end
    local ok, value = pcall(fn, "player", powerType)
    if ok then return value end
end

--- Máximo (número comum) ou nil.
function Source:Max(powerType)
    local max = ns.SafeCall(Fn("UnitPowerMax"), "player", powerType)
    return (type(max) == "number" and max > 0) and max or nil
end

--- Porcentagem de 0 a 100, crua (pode ser secreta). nil se a API não existir.
function Source:Percent(powerType)
    local fn = Fn("UnitPowerPercent")
    if not fn then return nil end
    local constants = rawget(_G, "CurveConstants")
    local curve = type(constants) == "table" and constants.ScaleTo100 or nil
    local ok, value = pcall(fn, "player", powerType, false, curve)
    if ok then return value end
end

--- Cor do jogo para o recurso (PowerBarColor), por token ou por número.
function Source:Color(powerType, token)
    local colors = rawget(_G, "PowerBarColor")
    local c = type(colors) == "table" and ((token and colors[token]) or colors[powerType]) or nil
    if type(c) ~= "table" or type(c.r) ~= "number" then c = DEFAULT_COLOR end
    return c.r, c.g, c.b
end

--- Esta classe/forma usa pontos de combo? Ladino sempre; druida só com energia (Forma de Felino).
function Source:HasComboPoints(powerType)
    local _, class = ns.SafeCall(Fn("UnitClass"), "player")
    return class == "ROGUE" or (class == "DRUID" and powerType == self.ENERGY)
end

--- Pontos de combo atuais (UnitPower; na falta, GetComboPoints no alvo).
function Source:ComboPoints()
    local value = ns.SafeCall(Fn("UnitPower"), "player", self.COMBO)
    if type(value) ~= "number" then value = ns.SafeCall(Fn("GetComboPoints"), "player", "target") end
    return type(value) == "number" and value or 0
end

--- Máximo de pontos de combo (5 se a API não responder).
function Source:ComboMax()
    local max = ns.SafeCall(Fn("UnitPowerMax"), "player", self.COMBO)
    if type(max) ~= "number" or max <= 0 then return 5 end
    return math.min(max, MAX_COMBO)
end

--- O jogador está em combate?
function Source:InCombat()
    return ns.SafeCall(Fn("UnitAffectingCombat"), "player") == true
end

--- O alvo atual é algo que dá para atacar (e está vivo)?
function Source:HasHostileTarget()
    if ns.SafeCall(Fn("UnitExists"), "target") ~= true then return false end
    if ns.SafeCall(Fn("UnitIsDead"), "target") == true then return false end
    return ns.SafeCall(Fn("UnitCanAttack"), "player", "target") == true
end
