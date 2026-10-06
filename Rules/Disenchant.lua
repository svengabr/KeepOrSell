-- What an enchanter gets from disenchanting an item and whether that beats selling it. Pure logic apart from
-- ns.IsSkillUpReagent.
local _, ns = ...

local WEAPON, ARMOR = 2, 4 -- Enum.ItemClass
local UNCOMMON, RARE, EPIC = 2, 3, 4 -- Enum.ItemQuality
local AH_CUT = 0.05
-- outcomes this unlikely may lack an auction price without making the whole value unknown
local MINOR_CHANCE = 0.1

local STRANGE, SOUL, VISION, DREAM, ILLUSION = 10940, 11083, 11137, 11176, 16204 -- dust
local LESSER_MAGIC, GREATER_MAGIC, LESSER_ASTRAL, GREATER_ASTRAL = 10938, 10939, 10998, 11082
local LESSER_MYSTIC, GREATER_MYSTIC, LESSER_NETHER, GREATER_NETHER = 11134, 11135, 11174, 11175
local LESSER_ETERNAL, GREATER_ETERNAL = 16202, 16203
local SMALL_GLIMMERING, LARGE_GLIMMERING, SMALL_GLOWING, LARGE_GLOWING = 10978, 11084, 11138, 11139
local SMALL_RADIANT, LARGE_RADIANT, SMALL_BRILLIANT, LARGE_BRILLIANT = 11177, 11178, 14343, 14344
local NEXUS = 20725

-- Classic disenchant tables by item level (Warcraft Wiki, "Disenchanting tables"); quantities are split
-- evenly. Each row covers item levels up to max; the last row also covers anything above.
-- Uncommon: dust and essence with quantities, an optional shard, and the chances for armor and weapons.
local UNCOMMON_ROWS = {
  {max = 15, dust = {STRANGE, 1, 2}, essence = {LESSER_MAGIC, 1, 2}, armor = {0.8, 0.2}, weapon = {0.2, 0.8}},
  {max = 20, dust = {STRANGE, 2, 3}, essence = {GREATER_MAGIC, 1, 2}, shard = SMALL_GLIMMERING,
    armor = {0.75, 0.2, 0.05}, weapon = {0.2, 0.75, 0.05}},
  {max = 25, dust = {STRANGE, 4, 6}, essence = {LESSER_ASTRAL, 1, 2}, shard = SMALL_GLIMMERING,
    armor = {0.75, 0.15, 0.1}, weapon = {0.15, 0.75, 0.1}},
  {max = 30, dust = {SOUL, 1, 2}, essence = {GREATER_ASTRAL, 1, 2}, shard = LARGE_GLIMMERING},
  {max = 35, dust = {SOUL, 2, 5}, essence = {LESSER_MYSTIC, 1, 2}, shard = SMALL_GLOWING},
  {max = 40, dust = {VISION, 1, 2}, essence = {GREATER_MYSTIC, 1, 2}, shard = LARGE_GLOWING},
  {max = 45, dust = {VISION, 2, 5}, essence = {LESSER_NETHER, 1, 2}, shard = SMALL_RADIANT},
  {max = 50, dust = {DREAM, 1, 2}, essence = {GREATER_NETHER, 1, 2}, shard = LARGE_RADIANT},
  {max = 55, dust = {DREAM, 2, 5}, essence = {LESSER_ETERNAL, 1, 2}, shard = SMALL_BRILLIANT,
    weapon = {0.22, 0.75, 0.03}},
  {max = 60, dust = {ILLUSION, 1, 2}, essence = {GREATER_ETERNAL, 1, 2}, shard = LARGE_BRILLIANT,
    weapon = {0.22, 0.75, 0.03}},
  {max = 65, dust = {ILLUSION, 2, 5}, essence = {GREATER_ETERNAL, 2, 3}, shard = LARGE_BRILLIANT,
    weapon = {0.22, 0.75, 0.03}},
}
local DEFAULT_ARMOR, DEFAULT_WEAPON = {0.75, 0.2, 0.05}, {0.2, 0.75, 0.05}

-- Rare: always one shard, at level 56 and above rarely a Nexus Crystal instead
local RARE_ROWS = {
  {max = 25, {SMALL_GLIMMERING, 1}}, {max = 30, {LARGE_GLIMMERING, 1}}, {max = 35, {SMALL_GLOWING, 1}},
  {max = 40, {LARGE_GLOWING, 1}}, {max = 45, {SMALL_RADIANT, 1}}, {max = 50, {LARGE_RADIANT, 1}},
  {max = 55, {SMALL_BRILLIANT, 1}}, {max = 65, {LARGE_BRILLIANT, 0.995}, {NEXUS, 0.005}},
}

-- Epic: weapons and armor alike
local EPIC_ROWS = {
  {max = 45, {SMALL_RADIANT, 1, 2, 4}}, {max = 50, {LARGE_RADIANT, 1, 2, 4}},
  {max = 55, {SMALL_BRILLIANT, 1, 2, 4}}, {max = 60, {NEXUS, 1, 1, 1}}, {max = 88, {NEXUS, 1, 1, 2}},
}

local function Row(rows, level)
  for _, row in ipairs(rows) do
    if level <= row.max then return row end
  end
  return rows[#rows]
end

local function Outcome(itemID, chance, min, max)
  return {itemID = itemID, chance = chance, min = min or 1, max = max or min or 1}
end

local function UncommonOutcomes(level, classID)
  local row = Row(UNCOMMON_ROWS, level)
  local chances = classID == WEAPON and (row.weapon or DEFAULT_WEAPON) or (row.armor or DEFAULT_ARMOR)
  local list = {
    Outcome(row.dust[1], chances[1], row.dust[2], row.dust[3]),
    Outcome(row.essence[1], chances[2], row.essence[2], row.essence[3]),
  }
  if row.shard and chances[3] then table.insert(list, Outcome(row.shard, chances[3], 1, 1)) end
  return list
end

-- Possible results of disenchanting, as a list of {itemID, chance, min, max}, most likely first;
-- nil if the item can't be disenchanted. Pure.
function ns.DisenchantOutcomes(quality, itemLevel, classID)
  if not itemLevel or (classID ~= WEAPON and classID ~= ARMOR) then return nil end
  local list
  if quality == UNCOMMON then
    list = UncommonOutcomes(itemLevel, classID)
  elseif quality == RARE or quality == EPIC then
    list = {}
    for _, o in ipairs(Row(quality == RARE and RARE_ROWS or EPIC_ROWS, itemLevel)) do
      table.insert(list, Outcome(o[1], o[2], o[3], o[4]))
    end
  else
    return nil
  end
  table.sort(list, function(a, b) return a.chance > b.chance end)
  return list
end

-- Average value in copper: chance x average quantity x price. priceOf(itemID) returns a trusted auction
-- price or nil. nil = unknown, because a likely outcome has no price. Pure.
function ns.DisenchantValue(outcomes, priceOf)
  if not outcomes then return nil end
  local value = 0
  for _, o in ipairs(outcomes) do
    local price = priceOf(o.itemID)
    if price and price > 0 then
      value = value + o.chance * (o.min + o.max) / 2 * price
    elseif o.chance >= MINOR_CHANCE then
      return nil
    end
  end
  return math.floor(value + 0.5)
end

-- true if a known recipe still gains skill from one of the materials; marks those outcomes (o.skillUp)
function ns.DisenchantSkillUp(outcomes)
  local any = false
  for _, o in ipairs(outcomes or {}) do
    o.skillUp = ns.IsSkillUpReagent(o.itemID) or nil
    any = any or o.skillUp == true
  end
  return any
end

-- Whether disenchanting beats the verdict, for an item the verdict would get rid of.
-- disenchant = {value, skillUp}; prices = {ah, vendor}; ahTrusted = the auction price is known and recent. Pure.
function ns.DisenchantWins(disenchant, prices, ahTrusted, bound)
  if disenchant.skillUp then return true end
  local value, vendor = disenchant.value, prices.vendor or 0
  if bound then return value == nil or value > vendor end
  if value == nil or value <= vendor then return false end
  local ah = ahTrusted and prices.ah or 0
  return value > ah * (1 - AH_CUT)
end
