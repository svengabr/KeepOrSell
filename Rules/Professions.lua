-- Remembers reagents of known recipes that still give skill points. Read whenever the player opens
-- one of their own professions; stored per character and recipe in KeepOrSellDB.recipes.
local _, ns = ...

local TRIVIAL = Enum and Enum.TradeskillRelativeDifficulty and Enum.TradeskillRelativeDifficulty.Trivial or 3

local function Reagents(api, recipeID)
  local reagents = {}
  local schematic = api.GetRecipeSchematic(recipeID, false)
  for _, slot in ipairs(schematic and schematic.reagentSlotSchematics or {}) do
    for _, reagent in ipairs(slot.reagents or {}) do
      if reagent.itemID then table.insert(reagents, reagent.itemID) end
    end
  end
  return reagents
end

-- Two tables {[recipeID] = {itemID, ...} | false}; false = grey, no skill points anymore.
-- recipes holds the learned recipes, upcoming the ones not learned yet (a trainer or recipe teaches them
-- later; their difficulty may be unknown, which counts as not grey). The third table holds what learned
-- recipes make, grey or not: {[recipeID] = {output = itemID, reagents = {itemID, ...}}}, so a reagent that
-- first has to be turned into another one (dust into particles) is found too. Pure, gets the API as argument.
function ns.CollectRecipes(api, recipeIDs)
  local recipes, upcoming, crafts = {}, {}, {}
  for _, recipeID in ipairs(recipeIDs or {}) do
    local info = api.GetRecipeInfo(recipeID)
    if info and info.learned and info.relativeDifficulty ~= nil then
      recipes[recipeID] = info.relativeDifficulty ~= TRIVIAL and Reagents(api, recipeID)
      local schematic = api.GetRecipeSchematic(recipeID, false)
      if schematic and schematic.outputItemID then
        crafts[recipeID] = {output = schematic.outputItemID, reagents = Reagents(api, recipeID)}
      end
    elseif info and info.learned == false then
      upcoming[recipeID] = info.relativeDifficulty ~= TRIVIAL and Reagents(api, recipeID)
    end
  end
  return recipes, upcoming, crafts
end

-- {[itemID] = true} of the reagents in reagentLists ({[recipeID] = {itemID, ...} | false}), plus everything a
-- learned recipe in crafts turns into one of them, over any number of steps. Pure.
function ns.ReagentIndex(reagentLists, crafts)
  local result = {}
  for _, reagents in pairs(reagentLists or {}) do
    for _, id in ipairs(reagents or {}) do result[id] = true end
  end
  local added = true
  while added do
    added = false
    for _, craft in pairs(crafts or {}) do
      if result[craft.output] then
        for _, id in ipairs(craft.reagents or {}) do
          if not result[id] then result[id], added = true, true end
        end
      end
    end
  end
  return result
end

local index, upcomingIndex -- {[itemID] = true}, rebuilt after a change

-- "Name-Realm", for data KeepOrSell keeps per character
function ns.CharacterKey()
  return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function CharacterTable(name)
  KeepOrSellDB[name] = KeepOrSellDB[name] or {}
  local key = ns.CharacterKey()
  KeepOrSellDB[name][key] = KeepOrSellDB[name][key] or {}
  return KeepOrSellDB[name][key]
end

local function CharacterRecipes()
  return CharacterTable("recipes")
end

-- Rereads the open profession; true if anything changed. The window may show a filtered list, so only
-- the recipes seen are updated, the others keep their last known state.
function ns.ScanProfession()
  local api = C_TradeSkillUI
  if not (api and api.GetRecipeInfo and api.GetRecipeSchematic) then return false end
  -- someone else's profession (link, guild, NPC) says nothing about ours
  for _, check in ipairs({"IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting", "IsRuneforging"}) do
    if api[check] and api[check]() then return false end
  end
  local getIDs = api.GetAllRecipeIDs or api.GetFilteredRecipeIDs
  if not getIDs then return false end
  local profession = api.GetBaseProfessionInfo and api.GetBaseProfessionInfo()
  if profession and profession.professionName then CharacterTable("opened")[profession.professionName] = true end

  local stored, storedUpcoming, storedCrafts = CharacterRecipes(), CharacterTable("upcoming"), CharacterTable("crafts")
  local recipes, upcoming, crafts = ns.CollectRecipes(api, getIDs())
  local changed = false
  local function Store(target, recipeID, reagents)
    local old = target[recipeID]
    if (old == nil) ~= (reagents == nil) or (old == false) ~= (reagents == false) then changed = true end
    target[recipeID] = reagents
  end
  for recipeID, reagents in pairs(recipes) do
    Store(stored, recipeID, reagents)
    Store(storedUpcoming, recipeID, nil) -- learned now
  end
  for recipeID, reagents in pairs(upcoming) do Store(storedUpcoming, recipeID, reagents) end
  for recipeID, craft in pairs(crafts) do
    if not storedCrafts[recipeID] then changed = true end
    storedCrafts[recipeID] = craft
  end
  if changed then index, upcomingIndex = nil, nil end
  return changed
end

-- true if a known recipe of this character still gains skill from the item, directly or after crafting it
-- into another reagent
function ns.IsSkillUpReagent(itemID)
  if not itemID then return false end
  if not index then index = ns.ReagentIndex(CharacterRecipes(), CharacterTable("crafts")) end
  return index[itemID] == true
end

-- true if a recipe of this character's professions not learned yet uses the item (and isn't grey)
function ns.IsUpcomingReagent(itemID)
  if not itemID then return false end
  if not upcomingIndex then upcomingIndex = ns.ReagentIndex(CharacterTable("upcoming"), CharacterTable("crafts")) end
  return upcomingIndex[itemID] == true
end

local NO_RECIPES = {[356] = true, [794] = true} -- fishing, archaeology

-- Names of the player's professions whose window was never opened; empty if the client can't tell
function ns.UnopenedProfessions()
  local missing = {}
  if not (GetProfessions and GetProfessionInfo) then return missing end
  local opened = CharacterTable("opened")
  for _, profIndex in pairs({GetProfessions()}) do
    local name, _, _, _, _, _, skillLine = GetProfessionInfo(profIndex)
    if name and not NO_RECIPES[skillLine] and not opened[name] then table.insert(missing, name) end
  end
  table.sort(missing)
  return missing
end

-- Enum.ItemRecipeSubclass -> profession skill line
local RECIPE_SKILL_LINES = {
  [1] = 165, [2] = 197, [3] = 202, [4] = 164, [5] = 185, [6] = 171,
  [7] = 129, [8] = 333, [9] = 356, [10] = 755, [11] = 773,
}

-- true / false when the player's professions are known, nil if the client can't tell
local function HasProfession(skillLine)
  if not (GetProfessions and GetProfessionInfo) then return nil end
  for _, profIndex in pairs({GetProfessions()}) do
    if select(7, GetProfessionInfo(profIndex)) == skillLine then return true end
  end
  return false
end

local ENCHANTING = 333

-- true if the character has learned Enchanting
function ns.IsEnchanter()
  return HasProfession(ENCHANTING) == true
end

local RED_TEXT = 0.5

-- Tooltip requirement lines the player doesn't meet are red (1, 0.125, 0.125)
function ns.IsRedText(color)
  return color ~= nil and color.r > RED_TEXT and color.g < RED_TEXT and color.b < RED_TEXT
end
local IsRed = ns.IsRedText

-- "learn" = recipe for one of the player's professions, not known yet; "known" = already learned;
-- "other" = for a profession the player doesn't have; nil = can't tell. lines are the item's tooltip lines, hasProfession from HasProfession,
-- types = {line, skill, notKnown, knownText}. Pure.
function ns.RecipeState(lines, hasProfession, types)
  local skillMet
  for _, line in ipairs(lines or {}) do
    if line.type == types.line and line.requirementType == types.notKnown and IsRed(line.leftColor) then
      return "known"
    end
    if types.knownText and line.leftText == types.knownText and IsRed(line.leftColor) then return "known" end
    if line.type == types.line and line.requirementType == types.skill then skillMet = not IsRed(line.leftColor) end
  end
  if hasProfession == true or (hasProfession == nil and skillMet) then return "learn" end
  if hasProfession == false then return "other" end
  return nil
end

local RECIPE = 9 -- Enum.ItemClass.Recipe

-- Recipe state of an item (see ns.RecipeState); nil for anything that isn't a profession recipe
function ns.GetRecipeState(itemID, classID, subclassID)
  local skillLine = classID == RECIPE and RECIPE_SKILL_LINES[subclassID]
  if not skillLine then return nil end
  local lineTypes = Enum and Enum.TooltipDataLineType
  local reqTypes = Enum and Enum.TooltipDataUsageRequirementType
  if not (lineTypes and reqTypes and C_TooltipInfo and C_TooltipInfo.GetItemByID) then return nil end
  local data = C_TooltipInfo.GetItemByID(itemID)
  if not (data and data.lines) then return nil end
  return ns.RecipeState(data.lines, HasProfession(skillLine), {
    line = lineTypes.UsageRequirement, skill = reqTypes.Skill,
    notKnown = reqTypes.NotAlreadyKnown, knownText = ITEM_SPELL_KNOWN,
  })
end
