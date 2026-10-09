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

-- what else to know about the prices: who shared the auction price, TSM as its source, and for junk the rule
-- that made the auction house not worth it; nil when there is nothing
local function PriceNote(prices, verdict, db)
  local notes = {}
  -- a price shared by a group member names who saw it and when
  if prices.from then
    table.insert(notes, (prices.age or 0) > 0 and L.TIP_SHARED:format(prices.from, prices.age)
      or L.TIP_SHARED_TODAY:format(prices.from))
  end
  if prices.source == "tsm" then table.insert(notes, L.TIP_TSM) end
  if verdict.kind == "junk" and verdict.priceReason == "factor" then
    table.insert(notes, L.TIP_BELOW_FACTOR:format(db.factor))
  elseif verdict.kind == "junk" and verdict.priceReason == "minprofit" then
    table.insert(notes, L.TIP_BELOW_PROFIT:format(Money(db.minProfit * 100)))
  end
  return #notes > 0 and table.concat(notes, " ") or nil
end

-- "Junk – plain gear, soulbound": the group, then every reason given, skipping nils
local function Headline(group, ...)
  local reasons = {}
  for i = 1, select("#", ...) do
    local reason = select(i, ...)
    if reason then table.insert(reasons, reason) end
  end
  return #reasons > 0 and group .. " – " .. table.concat(reasons, ", ") or group
end

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

-- headline, then one grey line per material (naming those that still give skill points); the value and
-- what selling would bring follow in the rows
local function DisenchantText(verdict)
  local text = verdict.forSkill and L.TIP_DISENCHANT_FOR_SKILL or L.TIP_DISENCHANT
  for _, o in ipairs(verdict.disenchant.outcomes or {}) do text = text .. DETAIL:format(OutcomeText(o)) end
  return text
end

local AH_CUT = 0.05

-- color of the way to get rid of an item, so it stands out from the stat lines above
local COLOR = {disenchant = "ffc78fff", ah = "ff66ccff", vendor = "ffffaa33"}
local GREY = "ffaaaaaa"
-- the way each group gets rid of an item; kept items have none
local CHOSEN = {ah = "ah", junk = "vendor", disenchant = "disenchant"}

-- Rows of {label, money, color} for two-column lines below the tooltip text (amounts line up on the right like
-- the price lines of other addons): the ways to get rid of the item. The group's own way comes first in its
-- color; for kept items the best one, as "Otherwise: …". The rest follow in grey, best first; the auction price
-- counts after the AH cut. nil when nothing is known. Pure apart from money formatting.
function ns.TooltipRows(verdict, prices)
  prices = prices or {}
  local chosen = CHOSEN[verdict.kind]
  local options = {}
  local deValue = verdict.disenchant and verdict.disenchant.value or verdict.deValue
  if deValue and deValue > 0 then
    table.insert(options, {deValue, "disenchant", L.TIP_DISENCHANT, "~" .. Money(deValue)})
  end
  if not verdict.bound and (verdict.ahTrusted or chosen == "ah") and prices.ah and prices.ah > 0 then
    table.insert(options, {prices.ah * (1 - AH_CUT), "ah", L.TIP_AH, Money(prices.ah)})
  end
  if prices.vendor and prices.vendor > 0 then
    table.insert(options, {prices.vendor, "vendor", L.TIP_VENDOR_NAME, Money(prices.vendor)})
  end
  if #options == 0 then return nil end
  table.sort(options, function(a, b)
    if (a[2] == chosen) ~= (b[2] == chosen) then return a[2] == chosen end
    return a[1] > b[1]
  end)
  local rows = {}
  for i, o in ipairs(options) do
    if i == 1 and o[2] == chosen then
      table.insert(rows, {"   » " .. o[3], o[4], COLOR[o[2]]})
    elseif i == 1 and not chosen then
      table.insert(rows, {"   » " .. L.TIP_OTHERWISE:format(o[3]), o[4], COLOR[o[2]]})
    else
      table.insert(rows, {"      " .. o[3], o[4], GREY})
    end
  end
  return rows
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
    text = Headline(L.TIP_AH, reason == "unusable" and L.TIP_UNUSABLE or nil, UselessText(verdict),
      PriceNote(prices, verdict, db))
  elseif kind == "junk" then
    local why = reason == "plain" and L.TIP_PLAIN or UselessText(verdict)
      or (reason == "unusable" or reason == "unusable_bound") and L.TIP_UNUSABLE or nil
    -- soulbound junk goes to the vendor whatever the prices say
    local note = not verdict.bound and PriceNote(prices, verdict, db) or nil
    text = Headline(L.TIP_JUNK, why, verdict.bound and L.TIP_BOUND or nil, note)
  elseif kind == "disenchant" then
    text = DisenchantText(verdict)
  elseif reason == "wearable" and not verdict.needsPrice and ns.TooltipRows(verdict, prices) then
    text = L.TIP_KEEP_WEARABLE
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
  local rows = ns.TooltipRows(verdict, facts.prices)
  if text then
    -- an empty line sets the verdict apart from the lines other addons add above it
    tooltip:AddLine(" ")
    tooltip:AddLine(text, 1, 1, 1, true)
    for _, row in ipairs(rows or {}) do
      tooltip:AddDoubleLine("|c" .. row[3] .. row[1] .. "|r", "|c" .. row[3] .. row[2] .. "|r", 1, 1, 1, 1, 1, 1)
    end
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
