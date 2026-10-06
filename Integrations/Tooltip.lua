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

local RECIPE_TEXT = {recipe_known = "TIP_RECIPE_KNOWN", recipe_other = "TIP_RECIPE_OTHER"}

-- why an item nobody needs any more is useless: a recipe or a quest item of a done quest
local function UselessText(verdict)
  if verdict.reason == "questitem_done" then return L.TIP_QUEST_ITEM_USELESS:format(verdict.quest.name) end
  return RECIPE_TEXT[verdict.reason] and L[RECIPE_TEXT[verdict.reason]]
end

-- Tooltip text for a verdict (see ns.Decide), nil = nothing worth saying. Pure apart from money formatting.
function ns.TooltipText(verdict, prices, db)
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
  elseif kind == "profession" then
    text = reason == "recipe" and L.TIP_RECIPE or L.TIP_PROFESSION
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
  elseif reason == "tool" then
    text = L.TIP_KEEP .. " – " .. L.TIP_TOOL
  elseif reason == "upcoming" then
    text = L.TIP_KEEP .. " – " .. L.TIP_UPCOMING
  elseif verdict.needsPrice and verdict.priceReason == "noprice" then
    text = L.TIP_KEEP .. " – " .. L.TIP_NO_PRICE
  elseif verdict.needsPrice and verdict.priceReason == "stale" then
    text = L.TIP_KEEP .. " – " .. L.TIP_STALE:format(db.maxAge)
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
  local text = ns.TooltipText(ns.Decide(facts, KeepOrSellDB), facts.prices, KeepOrSellDB)
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
