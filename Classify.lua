-- One decision per item, shared by the Baganator groups, Scrap and the tooltip.
local _, ns = ...

local WEAPON, ARMOR, TRADEGOODS, QUESTITEM = 2, 4, 7, 12 -- Enum.ItemClass
local BIND_ON_PICKUP, BIND_QUEST = 1, 4 -- Enum.ItemBind

-- facts: {quest, classID, equipLoc, unusable, plain, bound, reagent, recipe, prices, priceData}
-- recipe = "learn" for a recipe of the player's profession they don't know yet, "known" when already
-- learned, "other" for a profession the player doesn't have
-- unusable = the player's class can never use it (gear type or a "Classes:" restriction)
-- plain = grey or white gear; priceData = Auctionator has seen the auction house, so a missing
-- price means nobody sells the item there
-- Returns {kind = "quest" | "profession" | "ah" | "junk" | nil, reason, priceReason, needsPrice}.
-- needsPrice = the item stays only because its auction price is missing or too old. Pure.
function ns.Decide(facts, db)
  if facts.quest == "open" or facts.quest == "done" then return {kind = "quest", reason = facts.quest} end
  if facts.classID == QUESTITEM then return {kind = "quest", reason = "questitem"} end
  if db.profession and facts.reagent then return {kind = "profession"} end
  if db.profession and facts.recipe == "learn" then return {kind = "profession", reason = "recipe"} end

  local priceClass, priceReason = ns.ClassifyPrices(facts.prices or {}, db)
  local verdict = {priceReason = priceReason}
  local isGear = (facts.classID == WEAPON or facts.classID == ARMOR) and (facts.equipLoc or "") ~= ""
  local uselessRecipe = db.recipeJunk and (facts.recipe == "known" or facts.recipe == "other")

  if (db.gear and facts.unusable) or uselessRecipe then
    -- nothing the player can use: auction it when worth it, otherwise sell it
    if uselessRecipe then
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

  -- item name not cached yet: it might be a quest objective
  if verdict.kind == "junk" and facts.quest == nil then verdict.kind = nil end
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

local restricted = {} -- itemID -> bool; a class restriction never changes during a session

local function ForOtherClass(itemID)
  if restricted[itemID] ~= nil then return restricted[itemID] end
  local lineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.UsageRequirement
  local raceClass = Enum and Enum.TooltipDataUsageRequirementType and Enum.TooltipDataUsageRequirementType.RaceClass
  if not (lineType and raceClass and C_TooltipInfo and C_TooltipInfo.GetItemByID) then return false end
  local data = C_TooltipInfo.GetItemByID(itemID)
  if not (data and data.lines and #data.lines > 0) then return false end -- not loaded yet, ask again later
  restricted[itemID] = ns.HasUnmetClassRequirement(data.lines, lineType, raceClass)
  return restricted[itemID]
end

local function Quality(itemID, itemLink)
  if itemLink then
    local quality = select(3, (C_Item.GetItemInfo or GetItemInfo)(itemLink))
    if quality then return quality end
  end
  return C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID)
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
  return {
    quest = ns.GetObjectiveState(itemID),
    classID = classID,
    equipLoc = equipLoc,
    unusable = ns.IsUnusableGear(playerClass, classID, subclassID, equipLoc) or ForOtherClass(itemID),
    plain = ns.IsPlainGear(Quality(itemID, itemLink), classID, subclassID, equipLoc),
    bound = IsBound(itemLink, location),
    reagent = ns.IsSkillUpReagent(itemID),
    recipe = ns.GetRecipeState(itemID, classID, subclassID),
    prices = ns.GetPrices(itemLink),
    priceData = ns.HasPriceData(),
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
