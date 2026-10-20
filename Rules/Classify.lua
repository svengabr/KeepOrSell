-- One decision per item, shared by the Baganator groups, Scrap and the tooltip.
local _, ns = ...

local WEAPON, ARMOR, TRADEGOODS, QUESTITEM = 2, 4, 7, 12 -- Enum.ItemClass
local BIND_ON_PICKUP, BIND_QUEST = 1, 4 -- Enum.ItemBind

-- The built-in verdict for an item no rule and no earlier check decided: by price, gear and usefulness.
local function BuiltInVerdict(facts, db, priceClass, priceReason, isGear, doneQuestItem, questFor)
  local verdict = {priceReason = priceReason}
  local uselessRecipe = db.recipeJunk and (facts.recipe == "known" or facts.recipe == "other")

  if (db.gear and facts.unusable) or uselessRecipe or doneQuestItem then
    -- nothing the player can use: auction it when worth it, otherwise sell it
    if doneQuestItem then
      verdict.reason, verdict.quest, verdict.bound = "questitem_done", questFor.name and questFor or nil, facts.bound
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
  return verdict
end

-- The verdict of a filter rule (Filter.lua) naming group for the item, or nil when the rule doesn't apply and the
-- built-in logic decides. rule = "item" | "category". Existing toggles gate rules of their group; a category
-- rule only makes junk what "when in doubt, keep" allows: grey, white bound items with a vendor price, or a known
-- recent price not worth auctioning; never green-or-better wearable gear, never a bound item above white or one
-- the vendor pays nothing for.
local function RuleVerdict(group, rule, facts, db, priceClass, priceReason, isGear)
  if not group then return nil end
  local verdict = {reason = "filter", rule = rule, priceReason = priceReason}
  if group == "keep" then return verdict end
  if group == "profession" then
    if not db.profession then return nil end
    verdict.kind = "profession"
  elseif group == "ah" then
    if facts.bound then return nil end
    verdict.kind = "ah"
  elseif group == "disenchant" then
    if not (db.disenchant and facts.disenchant) then return nil end
    verdict.kind, verdict.disenchant, verdict.bound = "disenchant", facts.disenchant, facts.bound
  elseif group == "junk" and rule == "item" then
    verdict.kind = "junk"
  elseif group == "junk" then
    -- green or better, or quality not known yet
    if isGear and (facts.quality == nil or facts.quality >= 2) then return nil end
    if facts.bound then
      -- can't be auctioned: only grey or white with a vendor price may go (never the Hearthstone)
      local vendor = (facts.prices or {}).vendor
      if not (facts.quality and facts.quality <= 1 and vendor and vendor > 0) then return nil end
      verdict.kind = "junk"
    elseif facts.quality == 0 or priceClass == "vendor" then
      verdict.kind = "junk"
    elseif priceClass == nil then
      verdict.needsPrice = true
    else
      return nil -- worth auctioning
    end
  else
    return nil
  end
  return verdict
end

-- facts: {quest, questie, questOnly, questItemFor, itemID, classID, subclassID, quality, equipLoc, tool, classItem,
-- unusable, plain, bound, reagent, upcoming, recipe, prices, priceData, disenchant, openable, kept, equipSet}
-- itemID, classID, subclassID, quality (nil when not cached yet) = what the filter rules match on (db.filter)
-- questie = {name, level} of a quest not done yet that needs the item (QuestieDB)
-- questOnly = the item exists only for a quest: it starts one or a quest hands it out (QuestieDB)
-- questItemFor = {name, level, done} of the quest a quest item belongs to, at any level (QuestieDB)
-- starter = {name, done} of the quest the item begins per the game's item table (Data/Starts.lua)
-- newItem = original Classic didn't have the item (Data/NewItems.lua): never junk for a low price alone
-- learned = {name, level} of a quest QuestieDB lacks that some character's quest log asked for, not done here
-- recipe = "learn" for a recipe of the player's profession they don't know yet, "known" when already
-- learned, "other" for a profession the player doesn't have
-- upcoming = a recipe of the player's profession not learned yet (and not grey) needs the item: Profession
-- group like a reagent of a known recipe, even when worth auctioning (option upcomingReagents)
-- alts = {alt, ...} other characters of the account that need the item (ns.AltsNeedingItem): with account mode on
-- (ns.FilterAlts) the group "For alts" unless bound, after the player's own needs
-- tool = a profession tool (mining pick, skinning knife ...), kept no matter what
-- classItem = a spell reagent or tool of the player's class (Thieves' Tools, Light Feather ...), kept no matter
-- what, even when the class quest that handed it out is done
-- unusable = the player's class can never use it (gear type or a "Classes:" restriction)
-- plain = grey or white gear; priceData = Auctionator has seen the auction house, so a missing
-- price means nobody sells the item there
-- disenchant = {outcomes, value, skillUp} when the player is an enchanter and can disenchant the item;
-- skillUp = disenchanting itself still raises Enchanting
-- openable = the bag slot has loot or the tooltip says "<Right Click to Open>", and the tooltip doesn't
-- say "Locked" (clams, boxes): each takes its own bag slot even when
-- Baganator shows them stacked, so they go to the Open group to be opened
-- kept = the player marked the item to keep (Keep.lua); equipSet = this copy is saved in an equipment set;
-- both are kept no matter what, after the quest checks
-- Returns {kind = "quest" | "open" | "profession" | "ah" | "junk" | "disenchant" | nil, reason, priceReason, needsPrice}.
-- For "disenchant" also {disenchant, bound, forSkill}: forSkill = worth it only for the skill points.
-- Kept wearable gear also gets {disenchant}. Every verdict gets {bound, ahTrusted, ahWorth, deValue} for the
-- tooltip rows comparing the ways to get rid of the item: ahTrusted = the auction price is known and recent,
-- ahWorth = it passes the factor, minimum profit and deposit, deValue = what disenchanting brings (enchanters only).
-- needsPrice = the item stays only because its auction price is missing or too old.
-- reason = "filter" with rule = "item" | "category": a rule of the player's filter (db.filter) decided; an item
-- rule comes after the safeguards (quest, keep marks, equipment sets, items to open, tools, class items) and
-- before the profession checks, a category rule after them. Pure.
local function Decide(facts, db)
  if facts.quest == "open" or facts.quest == "done" then return {kind = "quest", reason = facts.quest} end
  if db.questie and facts.questie then return {kind = "quest", reason = "questie", quest = facts.questie} end
  if db.questie and facts.learned then return {kind = "quest", reason = "learned", quest = facts.learned} end
  -- a quest item stays unless every quest the player could do with it is done; besides the quest item
  -- class, QuestieDB knows quest starters and handed-out items of any class
  -- the game's own item table knows every quest starter, also those QuestieDB lacks (facts.starter)
  local questItem = facts.classID == QUESTITEM or (db.questie and facts.questOnly) or facts.starter ~= nil
  local questFor = facts.questItemFor or facts.starter
  local doneQuestItem = questItem and db.questie and questFor and questFor.done
  if questItem and not doneQuestItem then
    return {kind = "quest", reason = "questitem", quest = questFor and questFor.name and questFor or nil}
  end
  if facts.kept then return {reason = "kept"} end
  if facts.equipSet then return {reason = "equipset"} end
  if db.openable and facts.openable then return {kind = "open"} end
  if facts.tool then return {reason = "tool"} end
  if facts.classItem then return {reason = "classitem"} end

  local priceClass, priceReason = ns.ClassifyPrices(facts.prices or {}, db)
  local isGear = (facts.classID == WEAPON or facts.classID == ARMOR) and (facts.equipLoc or "") ~= ""
  -- the filter author named this item: it beats the profession checks
  local verdict = RuleVerdict(ns.FilterItemRule(db.filter, facts.itemID), "item", facts, db, priceClass, priceReason, isGear)
  if not verdict then
    if db.profession and facts.reagent then return {kind = "profession"} end
    if db.profession and db.upcomingReagents and facts.upcoming then return {kind = "profession", reason = "upcoming"} end
    -- another character of the account needs it; only worth it when it can be mailed
    local alts = not facts.bound and ns.FilterAlts(facts.alts, db)
    if alts then return {kind = "alt", alts = alts} end
    if db.profession and facts.recipe == "learn" then return {kind = "profession", reason = "recipe"} end
    -- after the profession checks: a broad rule never takes a reagent that still gives skill
    verdict = RuleVerdict(ns.FilterCategoryRule(db.filter, facts.classID, facts.subclassID, facts.quality),
      "category", facts, db, priceClass, priceReason, isGear)
  end
  if not verdict then verdict = BuiltInVerdict(facts, db, priceClass, priceReason, isGear, doneQuestItem, questFor) end

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
  if verdict.kind == "junk" and facts.quest == nil then
    verdict.kind = nil
    -- don't claim the filter keeps it
    if verdict.reason == "filter" then verdict.reason, verdict.rule = nil, nil end
  end
  -- Forever added the item and only its low price speaks against it: KeepOrSell can't judge it yet. Gear the
  -- class can't wear, known recipes and done quest items carry their own reason and stay junk; an item rule
  -- names the item, a category rule doesn't.
  if verdict.kind == "junk" and facts.newItem and (verdict.reason == nil or verdict.rule == "category") then
    verdict.kind, verdict.reason, verdict.rule = nil, "new", nil
  end
  return verdict
end

-- true if the item ID lies in one of the runs {first, last, first, last ...} (Data/NewItems.lua: items
-- original Classic didn't have). Binary search over the sorted runs. Pure.
function ns.IsNewItem(itemID, runs)
  runs = runs or ns.NEW_ITEM_RUNS
  if not (itemID and runs) then return false end
  local low, high = 1, #runs / 2
  while low <= high do
    local mid = math.floor((low + high) / 2)
    local first, last = runs[2 * mid - 1], runs[2 * mid]
    if itemID < first then
      high = mid - 1
    elseif itemID > last then
      low = mid + 1
    else
      return true
    end
  end
  return false
end

function ns.Decide(facts, db)
  local verdict = Decide(facts, db)
  verdict.also = ns.OtherReasons(verdict, facts, db)
  local priceClass, priceReason = ns.ClassifyPrices(facts.prices or {}, db)
  verdict.bound = facts.bound or nil
  verdict.ahTrusted = priceReason ~= "noprice" and priceReason ~= "stale"
  verdict.ahWorth = priceClass == "ah"
  verdict.deValue = db.disenchant and facts.disenchant and facts.disenchant.value or nil
  return verdict
end

local GOES = {junk = true, ah = true, disenchant = true}

-- What else speaks for keeping an item the verdict keeps anyway (the tooltip names only the first reason):
-- {{kind = "profession"}, {kind = "alt", alts = {...}}} or nil. Nothing for items that go. Pure.
function ns.OtherReasons(verdict, facts, db)
  if GOES[verdict.kind] then return nil end
  local also = {}
  if verdict.kind ~= "profession" and db.profession
    and (facts.reagent or (db.upcomingReagents and facts.upcoming)) then
    table.insert(also, {kind = "profession"})
  end
  local alts = verdict.kind ~= "alt" and not facts.bound and ns.FilterAlts(facts.alts, db)
  if alts then table.insert(also, {kind = "alt", alts = alts}) end
  return #also > 0 and also or nil
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
    skillUp = ns.DisenchantGivesSkill(ns.GetEnchantingSkill()),
  }
end

-- the bag slot holds a copy saved in an equipment set; only a bag slot can tell
local function InEquipmentSet(location)
  if not (location and location.IsBagAndSlot and location:IsBagAndSlot() and location.GetBagAndSlot) then return false end
  if location.IsValid and not location:IsValid() then return false end
  if not (C_Container and C_Container.GetContainerItemEquipmentSetInfo) then return false end
  return C_Container.GetContainerItemEquipmentSetInfo(location:GetBagAndSlot()) and true or false
end

local function IsBound(itemLink, location)
  if location and C_Item.IsBound and (not location.IsBagAndSlot or location:IsBagAndSlot()) and (not location.IsValid or location:IsValid()) then
    return C_Item.IsBound(location)
  end
  local getInfo = C_Item.GetItemInfo or GetItemInfo
  local bindType = itemLink and select(14, getInfo(itemLink))
  return bindType == BIND_ON_PICKUP or bindType == BIND_QUEST
end

local function ItemSpellName(itemID)
  return C_Item.GetItemSpell and (C_Item.GetItemSpell(itemID))
end

local drinkName
local function DrinkName()
  if drinkName == nil then
    drinkName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(ns.DRINK_SPELL) or false
  end
  return drinkName or nil
end

-- Gathers the facts for an item; location (ItemLocation) is optional and makes "bound" exact
function ns.ItemFacts(itemID, itemLink, location)
  local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
  local playerClass = UnitClass and select(2, UnitClass("player"))
  local questOnly = ns.IsQuestOnlyItem(itemID)
  local fromTooltip = TooltipFacts(itemID)
  local quality = Quality(itemID, itemLink)
  return {
    quest = ns.GetObjectiveState(itemID),
    questie = ns.GetQuestieQuest(itemID),
    questOnly = questOnly,
    questItemFor = (classID == QUESTITEM or questOnly) and ns.GetQuestItemQuest(itemID) or nil,
    starter = ns.GetStarterQuest(itemID),
    learned = ns.GetLearnedQuest(itemID),
    newItem = ns.IsNewItem(itemID),
    itemID = itemID,
    classID = classID,
    subclassID = subclassID,
    quality = quality,
    equipLoc = equipLoc,
    tool = ns.IsProfessionTool(itemID, classID, subclassID),
    classItem = ns.IsClassItem(playerClass, itemID, ns.HasReagentEconomy()),
    unusable = ns.IsUnusableGear(playerClass, classID, subclassID, equipLoc) or fromTooltip.forOtherClass
      or ns.IsUselessDrink(playerClass, classID, ItemSpellName(itemID), DrinkName()) or false,
    alts = ns.AltsNeedingItem(itemID),
    plain = ns.IsPlainGear(quality, classID, subclassID, equipLoc),
    bound = IsBound(itemLink, location),
    reagent = ns.IsSkillUpReagent(itemID),
    upcoming = ns.IsUpcomingReagent(itemID),
    recipe = ns.GetRecipeState(itemID, classID, subclassID),
    prices = ns.GetPrices(itemLink),
    priceData = ns.HasPriceData(),
    disenchant = DisenchantFacts(itemID, itemLink, classID),
    openable = ns.IsOpenable(fromTooltip.lines, ITEM_OPENABLE, LOCKED, HasLoot(location)),
    kept = ns.IsKept(itemID),
    equipSet = InEquipmentSet(location),
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
    .. (InEquipmentSet(location) and "|set" or "")
    -- the deposit per item depends on how many copies go into one auction
    .. "|" .. tostring(C_Item and C_Item.GetItemCount and C_Item.GetItemCount(itemLink or itemID) or 1)
  if cache[key] then return cache[key] end
  local facts = ns.ItemFacts(itemID, itemLink, location)
  local verdict = ns.Decide(facts, KeepOrSellDB)
  -- item name not loaded yet: ask again next time
  if facts.quest ~= nil then cache[key] = verdict end
  return verdict
end
