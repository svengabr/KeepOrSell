-- One decision per item, shared by the Baganator groups, Scrap and the tooltip.
local _, ns = ...

local WEAPON, ARMOR, TRADEGOODS, QUESTITEM = 2, 4, 7, 12 -- Enum.ItemClass
local BIND_ON_PICKUP, BIND_QUEST = 1, 4 -- Enum.ItemBind

-- facts: {quest, questie, questOnly, questItemFor, classID, equipLoc, tool, classItem, unusable, plain, bound, reagent, upcoming,
-- recipe, prices, priceData, disenchant, openable}
-- questie = {name, level} of a quest not done yet that needs the item (QuestieDB)
-- questOnly = the item exists only for a quest: it starts one or a quest hands it out (QuestieDB)
-- questItemFor = {name, level, done} of the quest a quest item belongs to, at any level (QuestieDB)
-- recipe = "learn" for a recipe of the player's profession they don't know yet, "known" when already
-- learned, "other" for a profession the player doesn't have
-- upcoming = a recipe of the player's profession not learned yet (and not grey) needs the item: Profession
-- group like a reagent of a known recipe, even when worth auctioning
-- tool = a profession tool (mining pick, skinning knife ...), kept no matter what
-- classItem = a spell reagent or tool of the player's class (Thieves' Tools, Light Feather ...), kept no matter
-- what, even when the class quest that handed it out is done
-- unusable = the player's class can never use it (gear type or a "Classes:" restriction)
-- plain = grey or white gear; priceData = Auctionator has seen the auction house, so a missing
-- price means nobody sells the item there
-- disenchant = {outcomes, value, skillUp} when the player is an enchanter and can disenchant the item
-- openable = the bag slot has loot or the tooltip says "<Right Click to Open>", and the tooltip doesn't
-- say "Locked" (clams, boxes): each takes its own bag slot even when
-- Baganator shows them stacked, so they go to the Open group to be opened
-- Returns {kind = "quest" | "open" | "profession" | "ah" | "junk" | "disenchant" | nil, reason, priceReason, needsPrice}.
-- For "disenchant" also {disenchant, bound, forSkill}: forSkill = worth it only for the skill points.
-- Kept wearable gear also gets {disenchant}. Every verdict gets {bound, ahTrusted, deValue} for the tooltip rows
-- comparing the ways to get rid of the item: ahTrusted = the auction price is known and recent, deValue = what
-- disenchanting brings (enchanters only).
-- needsPrice = the item stays only because its auction price is missing or too old. Pure.
local function Decide(facts, db)
  if facts.quest == "open" or facts.quest == "done" then return {kind = "quest", reason = facts.quest} end
  if db.questie and facts.questie then return {kind = "quest", reason = "questie", quest = facts.questie} end
  -- a quest item stays unless every quest the player could do with it is done; besides the quest item
  -- class, QuestieDB knows quest starters and handed-out items of any class
  local questItem = facts.classID == QUESTITEM or (db.questie and facts.questOnly)
  local doneQuestItem = questItem and db.questie and facts.questItemFor and facts.questItemFor.done
  if questItem and not doneQuestItem then
    return {kind = "quest", reason = "questitem", quest = facts.questItemFor}
  end
  if db.openable and facts.openable then return {kind = "open"} end
  if facts.tool then return {reason = "tool"} end
  if facts.classItem then return {reason = "classitem"} end
  if db.profession and facts.reagent then return {kind = "profession"} end
  if db.profession and facts.upcoming then return {kind = "profession", reason = "upcoming"} end
  if db.profession and facts.recipe == "learn" then return {kind = "profession", reason = "recipe"} end

  local priceClass, priceReason = ns.ClassifyPrices(facts.prices or {}, db)
  local verdict = {priceReason = priceReason}
  local isGear = (facts.classID == WEAPON or facts.classID == ARMOR) and (facts.equipLoc or "") ~= ""
  local uselessRecipe = db.recipeJunk and (facts.recipe == "known" or facts.recipe == "other")

  if (db.gear and facts.unusable) or uselessRecipe or doneQuestItem then
    -- nothing the player can use: auction it when worth it, otherwise sell it
    if doneQuestItem then
      verdict.reason, verdict.quest, verdict.bound = "questitem_done", facts.questItemFor, facts.bound
    elseif uselessRecipe then
      verdict.reason = "recipe_" .. facts.recipe
      verdict.bound = facts.bound
    else
      verdict.reason = facts.bound and "unusable_bound" or "unusable"
    end
    if facts.bound or priceClass == "vendor" then
      verdict.kind = "junk"
    elseif priceClass == "ah" then
      verdict.kind = "ah"
    else
      verdict.needsPrice = true
    end
  elseif isGear then
    -- gear the player could wear is never junk unless plain; it may still be worth auctioning
    verdict.reason = "wearable"
    if priceClass == "ah" and not facts.bound then
      verdict.kind = "ah"
    elseif db.plainGear and facts.plain and (facts.bound or priceClass == "vendor"
        or (priceReason == "noprice" and facts.priceData)) then
      -- grey or white gear that isn't worth auctioning; a stale price still means "keep"
      verdict.kind, verdict.reason = "junk", "plain"
    elseif db.plainGear and facts.plain and priceClass == nil then
      verdict.needsPrice = true
    end
  elseif priceClass == "ah" and not facts.bound then
    verdict.kind = "ah"
  elseif facts.classID == TRADEGOODS and db.scrap then
    if priceClass == "vendor" then verdict.kind = "junk" else verdict.needsPrice = priceClass == nil end
  end
  -- an outdated price may hide an auction house item; say so instead of staying silent
  if not verdict.kind and priceReason == "stale" and not facts.bound then verdict.needsPrice = true end

  -- an enchanter may get more out of an item that would be sold, auctioned or kept only for a missing price
  local disenchant = db.disenchant and facts.disenchant
  local disposable = verdict.kind == "junk" or verdict.kind == "ah"
    or (verdict.needsPrice and verdict.reason == "unusable")
  local ahTrusted = priceReason ~= "noprice" and priceReason ~= "stale"
  if not verdict.kind and verdict.reason == "wearable" and not verdict.needsPrice then
    -- kept gear: the tooltip names what it would bring once the player no longer needs it
    verdict.bound, verdict.ahTrusted, verdict.disenchant = facts.bound, ahTrusted, disenchant or nil
  elseif disenchant and disposable then
    if ns.DisenchantWins(disenchant, facts.prices or {}, ahTrusted, facts.bound) then
      verdict.kind, verdict.disenchant, verdict.bound, verdict.needsPrice = "disenchant", disenchant, facts.bound, nil
      -- only the skill points speak for it: selling is known to pay more
      local byValue = {value = disenchant.value}
      verdict.forSkill = disenchant.skillUp and disenchant.value ~= nil
        and not ns.DisenchantWins(byValue, facts.prices or {}, ahTrusted, facts.bound) or nil
    end
  end

  -- item name not cached yet: it might be a quest objective
  if verdict.kind == "junk" and facts.quest == nil then verdict.kind = nil end
  return verdict
end

function ns.Decide(facts, db)
  local verdict = Decide(facts, db)
  local _, priceReason = ns.ClassifyPrices(facts.prices or {}, db)
  verdict.bound = facts.bound or nil
  verdict.ahTrusted = priceReason ~= "noprice" and priceReason ~= "stale"
  verdict.deValue = db.disenchant and facts.disenchant and facts.disenchant.value or nil
  return verdict
end

-- true if the tooltip lines contain a class or race requirement the player doesn't meet. Pure.
function ns.HasUnmetClassRequirement(lines, lineType, raceClassType)
  for _, line in ipairs(lines or {}) do
    if line.type == lineType and line.requirementType == raceClassType and ns.IsRedText(line.leftColor) then
      return true
    end
  end
  return false
end

local function Uncolored(text)
  return type(text) == "string" and (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) or nil
end

-- true if the item can be opened and isn't locked: hasLoot from the bag slot, or the tooltip line
-- "<Right Click to Open>"; a "Locked" line always wins. Pure.
function ns.IsOpenable(lines, openText, lockedText, hasLoot)
  local openable = hasLoot and true or false
  for _, line in ipairs(lines or {}) do
    local text = Uncolored(line.leftText)
    if lockedText and text == lockedText then return false end
    if openText and text == openText then openable = true end
  end
  return openable
end

-- itemID -> {forOtherClass, lines}; neither changes during a session
local tooltipFacts = {}

local function TooltipFacts(itemID)
  if tooltipFacts[itemID] then return tooltipFacts[itemID] end
  if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return {} end
  local data = C_TooltipInfo.GetItemByID(itemID)
  if not (data and data.lines and #data.lines > 0) then return {} end -- not loaded yet, ask again later
  local lineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.UsageRequirement
  local raceClass = Enum and Enum.TooltipDataUsageRequirementType and Enum.TooltipDataUsageRequirementType.RaceClass
  tooltipFacts[itemID] = {
    forOtherClass = lineType and raceClass and ns.HasUnmetClassRequirement(data.lines, lineType, raceClass) or false,
    lines = data.lines,
  }
  return tooltipFacts[itemID]
end

-- the bag slot says the item has loot (clams, boxes); works in every client language
local function HasLoot(location)
  if not (location and location.IsBagAndSlot and location:IsBagAndSlot() and location.GetBagAndSlot) then return false end
  if location.IsValid and not location:IsValid() then return false end
  if not (C_Container and C_Container.GetContainerItemInfo) then return false end
  local info = C_Container.GetContainerItemInfo(location:GetBagAndSlot())
  return info and info.hasLoot or false
end

local function Quality(itemID, itemLink)
  if itemLink then
    local quality = select(3, (C_Item.GetItemInfo or GetItemInfo)(itemLink))
    if quality then return quality end
  end
  return C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID)
end

local function ItemLevel(itemLink)
  return itemLink and select(4, (C_Item.GetItemInfo or GetItemInfo)(itemLink))
end

-- trusted auction price of a disenchanting material, nil when missing or too old
local function MaterialPrice(itemID)
  local prices = ns.GetPricesByID(itemID)
  if prices.ah and prices.ah > 0 and not ns.IsStale(prices, KeepOrSellDB) then return prices.ah end
end

local function DisenchantFacts(itemID, itemLink, classID)
  if not (KeepOrSellDB.disenchant and ns.IsEnchanter()) then return nil end
  local outcomes = ns.DisenchantOutcomes(Quality(itemID, itemLink), ItemLevel(itemLink), classID)
  if not outcomes then return nil end
  return {
    outcomes = outcomes,
    value = ns.DisenchantValue(outcomes, MaterialPrice),
    skillUp = ns.DisenchantSkillUp(outcomes),
  }
end

local function IsBound(itemLink, location)
  if location and C_Item.IsBound and (not location.IsBagAndSlot or location:IsBagAndSlot()) and (not location.IsValid or location:IsValid()) then
    return C_Item.IsBound(location)
  end
  local getInfo = C_Item.GetItemInfo or GetItemInfo
  local bindType = itemLink and select(14, getInfo(itemLink))
  return bindType == BIND_ON_PICKUP or bindType == BIND_QUEST
end

-- Gathers the facts for an item; location (ItemLocation) is optional and makes "bound" exact
function ns.ItemFacts(itemID, itemLink, location)
  local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
  local playerClass = UnitClass and select(2, UnitClass("player"))
  local questOnly = ns.IsQuestOnlyItem(itemID)
  local fromTooltip = TooltipFacts(itemID)
  return {
    quest = ns.GetObjectiveState(itemID),
    questie = ns.GetQuestieQuest(itemID),
    questOnly = questOnly,
    questItemFor = (classID == QUESTITEM or questOnly) and ns.GetQuestItemQuest(itemID) or nil,
    classID = classID,
    equipLoc = equipLoc,
    tool = ns.IsProfessionTool(itemID),
    classItem = ns.IsClassItem(playerClass, itemID, ns.HasReagentEconomy()),
    unusable = ns.IsUnusableGear(playerClass, classID, subclassID, equipLoc) or fromTooltip.forOtherClass or false,
    plain = ns.IsPlainGear(Quality(itemID, itemLink), classID, subclassID, equipLoc),
    bound = IsBound(itemLink, location),
    reagent = ns.IsSkillUpReagent(itemID),
    upcoming = ns.IsUpcomingReagent(itemID),
    recipe = ns.GetRecipeState(itemID, classID, subclassID),
    prices = ns.GetPrices(itemLink),
    priceData = ns.HasPriceData(),
    disenchant = DisenchantFacts(itemID, itemLink, classID),
    openable = ns.IsOpenable(fromTooltip.lines, ITEM_OPENABLE, LOCKED, HasLoot(location)),
  }
end

-- Baganator asks for every item on each button refresh, so decisions are cached. The cache is cleared
-- whenever something they depend on changes (ns.ClearCache) and every few minutes, as prices age.
local CACHE_SECONDS = 300
local cache, cacheTime = {}, 0

function ns.ClearCache()
  cache = {}
end

function ns.Classify(itemID, itemLink, location)
  if not itemID then return {} end
  local now = GetTime and GetTime() or 0
  if now - cacheTime > CACHE_SECONDS then cache, cacheTime = {}, now end
  local key = tostring(itemLink or itemID) .. (IsBound(itemLink, location) and "|bound" or "")
  if cache[key] then return cache[key] end
  local facts = ns.ItemFacts(itemID, itemLink, location)
  local verdict = ns.Decide(facts, KeepOrSellDB)
  -- item name not loaded yet: ask again next time
  if facts.quest ~= nil then cache[key] = verdict end
  return verdict
end
