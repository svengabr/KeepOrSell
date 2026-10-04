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

local function CharacterRecipes()
  KeepOrSellDB.recipes = KeepOrSellDB.recipes or {}
  local key = CharacterKey()
  KeepOrSellDB.recipes[key] = KeepOrSellDB.recipes[key] or {}
  return KeepOrSellDB.recipes[key]
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
