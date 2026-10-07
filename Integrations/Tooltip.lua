-- One line in the item tooltip that explains the decision
local _, ns = ...
local L = ns.L

local PREFIX = "|cffffd200KeepOrSell:|r "

local function Money(copper)
  if not copper or copper <= 0 then return "–" end
  if GetMoneyString then return GetMoneyString(copper) end
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local text = c .. "c"
  if s > 0 or g > 0 then text = s .. "s " .. text end
  if g > 0 then text = g .. "g " .. text end
  return text
end

local function PriceText(prices, verdict, db)
  local text = L.TIP_PRICES:format(Money(prices.ah), Money(prices.vendor))
  -- a price shared by a group member names who saw it and when
  if prices.from then
    local shared = (prices.age or 0) > 0 and L.TIP_SHARED:format(prices.from, prices.age)
      or L.TIP_SHARED_TODAY:format(prices.from)
    text = text .. " " .. shared
  end
  if prices.source == "tsm" then text = text .. " " .. L.TIP_TSM end
  -- for junk, name the rule that made the auction house not worth it
  if verdict.kind == "junk" and verdict.priceReason == "factor" then
    text = text .. " " .. L.TIP_BELOW_FACTOR:format(db.factor)
  elseif verdict.kind == "junk" and verdict.priceReason == "minprofit" then
    text = text .. " " .. L.TIP_BELOW_PROFIT:format(Money(db.minProfit * 100))
  end
  return text
end

-- "80% Strange Dust ×1–2"; names not cached yet are requested and show up next time
local function OutcomeText(o)
  local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(o.itemID)
  if not name and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(o.itemID) end
  local text = ("%g%%"):format(math.floor(o.chance * 1000 + 0.5) / 10)
  if name then text = text .. " " .. name end
  if o.max > 1 then text = text .. (o.min == o.max and " ×%d" or " ×%d–%d"):format(o.min, o.max) end
  if o.skillUp then text = text .. " – " .. L.TIP_DISENCHANT_SKILL end
  return text
end

local DETAIL = "\n    |cffaaaaaa%s|r"

-- headline with the value, then one grey line per material (naming those that still give skill points)
-- and one comparing with selling
local function DisenchantText(verdict, prices)
  local de = verdict.disenchant
  local text = verdict.forSkill and L.TIP_DISENCHANT_FOR_SKILL:format(Money(de.value))
    or de.value and L.TIP_DISENCHANT_VALUE:format(Money(de.value)) or L.TIP_DISENCHANT
  for _, o in ipairs(de.outcomes or {}) do text = text .. DETAIL:format(OutcomeText(o)) end
  local compare = verdict.bound and L.TIP_BOUND .. ", " .. L.TIP_VENDOR:format(Money(prices.vendor))
    or L.TIP_PRICES:format(Money(prices.ah), Money(prices.vendor))
  return text .. DETAIL:format(compare)
end

local AH_CUT = 0.05

-- kept gear: the best way to get rid of it once the player no longer needs it, the others for comparison;
-- the auction price counts after the AH cut. nil when nothing is known.
local function WearableText(verdict, prices)
  local options = {}
  local de = verdict.disenchant
  if de and de.value and de.value > 0 then
    table.insert(options, {de.value, L.TIP_DISENCHANT_VALUE:format(Money(de.value))})
  end
  if not verdict.bound and verdict.ahTrusted and prices.ah and prices.ah > 0 then
    table.insert(options, {prices.ah * (1 - AH_CUT), L.TIP_AH_PRICE:format(Money(prices.ah))})
  end
  if prices.vendor and prices.vendor > 0 then
    table.insert(options, {prices.vendor, L.TIP_VENDOR:format(Money(prices.vendor))})
  end
  if #options == 0 then return nil end
  table.sort(options, function(a, b) return a[1] > b[1] end)
  local best = options[1][2]
  if #options > 1 then
    local others = {}
    for i = 2, #options do table.insert(others, options[i][2]) end
    best = best .. " (" .. table.concat(others, ", ") .. ")"
  end
  return L.TIP_KEEP .. " – " .. L.TIP_WEARABLE .. DETAIL:format(L.TIP_IF_UNNEEDED:format(best))
end

local RECIPE_TEXT = {recipe_known = "TIP_RECIPE_KNOWN", recipe_other = "TIP_RECIPE_OTHER"}

-- why an item nobody needs any more is useless: a recipe or a quest item of a done quest
local function UselessText(verdict)
  if verdict.reason == "questitem_done" then return L.TIP_QUEST_ITEM_USELESS:format(verdict.quest.name) end
  return RECIPE_TEXT[verdict.reason] and L[RECIPE_TEXT[verdict.reason]]
end

-- Tooltip text for a verdict (see ns.Decide), nil = nothing worth saying; slots = bag slots the item takes,
-- unstacked = it never stacks, so each copy takes its own slot. Pure apart from money formatting.
function ns.TooltipText(verdict, prices, db, slots, unstacked)
  prices = prices or {}
  local kind, reason = verdict.kind, verdict.reason
  local text
  if kind == "quest" and reason == "questie" then
    local q = verdict.quest
    text = q.level and q.level > 0 and L.TIP_QUESTIE:format(q.name, q.level) or L.TIP_QUESTIE_SCALING:format(q.name)
  elseif kind == "quest" and reason == "questitem" and verdict.quest then
    local q = verdict.quest
    if q.done then
      text = L.TIP_QUEST_ITEM_DONE:format(q.name)
    else
      text = q.level and q.level > 0 and L.TIP_QUEST_ITEM_FOR:format(q.name, q.level)
        or L.TIP_QUEST_ITEM_FOR_SCALING:format(q.name)
    end
  elseif kind == "quest" then
    text = reason == "done" and L.TIP_QUEST_DONE or reason == "open" and L.TIP_QUEST_OPEN or L.TIP_QUEST_ITEM
  elseif kind == "open" then
    text = (slots or 0) > 1 and L.TIP_OPEN_SLOTS:format(slots) or L.TIP_OPEN
  elseif kind == "profession" then
    text = reason == "recipe" and L.TIP_RECIPE or reason == "upcoming" and L.TIP_UPCOMING or L.TIP_PROFESSION
  elseif kind == "ah" then
    text = L.TIP_AH .. " – " .. PriceText(prices, verdict, db)
    if reason == "unusable" then text = text .. ", " .. L.TIP_UNUSABLE end
    if UselessText(verdict) then text = text .. ", " .. UselessText(verdict) end
  elseif kind == "junk" then
    if reason == "plain" then
      text = L.TIP_JUNK .. " – " .. L.TIP_PLAIN .. ", " .. PriceText(prices, verdict, db)
    elseif reason == "unusable_bound" then
      text = L.TIP_JUNK .. " – " .. L.TIP_UNUSABLE .. ", " .. L.TIP_BOUND
    elseif UselessText(verdict) then
      local detail = verdict.bound and L.TIP_BOUND or PriceText(prices, verdict, db)
      text = L.TIP_JUNK .. " – " .. UselessText(verdict) .. ", " .. detail
    elseif reason == "unusable" then
      text = L.TIP_JUNK .. " – " .. L.TIP_UNUSABLE .. ", " .. PriceText(prices, verdict, db)
    else
      text = L.TIP_JUNK .. " – " .. PriceText(prices, verdict, db)
    end
  elseif kind == "disenchant" then
    text = DisenchantText(verdict, prices)
  elseif reason == "wearable" and not verdict.needsPrice then
    text = WearableText(verdict, prices)
  elseif reason == "tool" then
    text = L.TIP_KEEP .. " – " .. L.TIP_TOOL
  elseif reason == "classitem" then
    text = L.TIP_KEEP .. " – " .. L.TIP_CLASS_ITEM
  elseif verdict.needsPrice and verdict.priceReason == "noprice" then
    text = L.TIP_KEEP .. " – " .. L.TIP_NO_PRICE
  elseif verdict.needsPrice and verdict.priceReason == "stale" then
    text = L.TIP_KEEP .. " – " .. L.TIP_STALE:format(db.maxAge)
  end
  -- Baganator may show copies as one stack; say how many slots they really take
  if unstacked and kind ~= "open" and (slots or 0) > 1 then
    text = text and text .. ", " .. L.TIP_UNSTACKED:format(slots) or L.TIP_UNSTACKED_ALONE:format(slots)
  end
  return text and PREFIX .. text
end

local function ItemIDFromLink(link)
  return link and (C_Item.GetItemInfoInstant(link))
end

local function AddLine(tooltip, data)
  if not (KeepOrSellDB and KeepOrSellDB.tooltip) then return end
  if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end -- no comparison tooltips
  local _, link = tooltip:GetItem()
  local id = ItemIDFromLink(link)
  if not id then return end
  local location = data and data.guid and C_Item.GetItemLocation and C_Item.GetItemLocation(data.guid)
  -- worn items are not for sale; Scrap only sells from the bags anyway
  if location and location.IsEquipmentSlot and location:IsEquipmentSlot() then return end
  -- buyback/merchant items have a GUID but an empty location, which IsValid() rejects with an error
  if location and not (location.IsBagAndSlot and location:IsBagAndSlot()) then location = nil end
  local facts = ns.ItemFacts(id, link, location)
  local verdict = ns.Decide(facts, KeepOrSellDB)
  local unstacked = ns.IsUnstackable(id)
  local slots = (verdict.kind == "open" or unstacked) and ns.CountSlots(id) or nil
  local text = ns.TooltipText(verdict, facts.prices, KeepOrSellDB, slots, unstacked)
  if text then
    tooltip:AddLine(text, 1, 1, 1, true)
    tooltip:Show()
  end
end

function ns.HookTooltip()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, AddLine)
  elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetItem", AddLine)
    if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetItem", AddLine) end
  end
end
