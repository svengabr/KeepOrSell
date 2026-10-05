-- Remembers reagents of known recipes that still give skill points. Read whenever the player opens
-- one of their own professions; stored per character and recipe in KeepOrSellDB.recipes.
local _, ns = ...

local TRIVIAL = Enum and Enum.TradeskillRelativeDifficulty and Enum.TradeskillRelativeDifficulty.Trivial or 3

-- {[recipeID] = {itemID, ...} | false}; false = learned but grey, no skill points anymore.
-- Recipes not learned are left out. Pure, gets the API as argument.
function ns.CollectRecipes(api, recipeIDs)
  local recipes = {}
  for _, recipeID in ipairs(recipeIDs or {}) do
    local info = api.GetRecipeInfo(recipeID)
    if info and info.learned and info.relativeDifficulty ~= nil then
      if info.relativeDifficulty == TRIVIAL then
        recipes[recipeID] = false
      else
        local reagents = {}
        local schematic = api.GetRecipeSchematic(recipeID, false)
        for _, slot in ipairs(schematic and schematic.reagentSlotSchematics or {}) do
          for _, reagent in ipairs(slot.reagents or {}) do
            if reagent.itemID then table.insert(reagents, reagent.itemID) end
          end
        end
        recipes[recipeID] = reagents
      end
    end
  end
  return recipes
end

local index -- {[itemID] = true}, rebuilt after a change

local function CharacterKey()
  return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function CharacterTable(name)
  KeepOrSellDB[name] = KeepOrSellDB[name] or {}
  local key = CharacterKey()
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

  local stored = CharacterRecipes()
  local changed = false
  for recipeID, reagents in pairs(ns.CollectRecipes(api, getIDs())) do
    local old = stored[recipeID]
    if old == nil or (old == false) ~= (reagents == false) then changed = true end
    stored[recipeID] = reagents
  end
  if changed then index = nil end
  return changed
end

-- true if a known recipe of this character still gains skill from the item
function ns.IsSkillUpReagent(itemID)
  if not itemID then return false end
  if not index then
    index = {}
    for _, reagents in pairs(CharacterRecipes()) do
      for _, id in ipairs(reagents or {}) do index[id] = true end
    end
  end
  return index[itemID] == true
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
