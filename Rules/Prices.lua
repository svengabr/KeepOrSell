-- Compares auction price (Auctionator) with vendor price. Pure logic, no Baganator.
local addonName, ns = ...

local AH_CUT = 0.05 -- auction house fee on a sale
local MAX_AUCTIONATOR_AGE = 21 -- Auctionator reports no age beyond this
-- lowest auction house threshold: below it the AH cut can leave less than the vendor pays
ns.MIN_FACTOR = 1.1

-- "ah" = worth auctioning (at least factor x vendor price and at least minProfit copper more per item
-- after the AH cut), "vendor" = sell to vendor, nil = no known auction price (the item stays where it is).
-- Second value for "vendor": the rule that failed, "factor" or "minprofit".
function ns.ClassifyPrice(ahPrice, vendorPrice, factor, minProfit)
  if not ahPrice or ahPrice <= 0 then return nil end
  local vendorable = vendorPrice and vendorPrice > 0
  -- rounded to whole copper, so 100 x 1.1 is 110 and not 110.00000000000001
  if vendorable and ahPrice < math.floor(vendorPrice * factor + 0.5) then return "vendor", "factor" end
  if minProfit and minProfit > 0 and ahPrice * (1 - AH_CUT) - (vendorPrice or 0) < minProfit then
    -- not worth the trip; without vendor price it can't be sold there either, so keep it
    if vendorable then return "vendor", "minprofit" end
    return nil
  end
  return "ah"
end

-- prices = {ah, vendor, age}; db = {factor, minProfit (silver), maxAge (days)}
-- Returns the class and a reason: "noprice" or "stale" when the auction price is not trusted,
-- "factor" or "minprofit" when it is not worth auctioning
function ns.ClassifyPrices(prices, db)
  if not prices.ah or prices.ah <= 0 then return nil, "noprice" end
  if db.maxAge and db.maxAge < MAX_AUCTIONATOR_AGE and prices.hasAge
    and (prices.age == nil or prices.age > db.maxAge) then
    return nil, "stale"
  end
  local factor = math.max(db.factor or ns.MIN_FACTOR, ns.MIN_FACTOR)
  return ns.ClassifyPrice(prices.ah, prices.vendor, factor, (db.minProfit or 0) * 100)
end

local function Api()
  return Auctionator and Auctionator.API and Auctionator.API.v1
end

-- true once the player has opened the auction house with Auctionator loaded (Auctionator has no
-- public API telling whether it has scanned)
function ns.HasPriceData()
  return Api() ~= nil and KeepOrSellDB.ahVisited == true
end

local function VendorPrice(itemLink)
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  return (select(11, getInfo(itemLink)))
end

local DAY = 86400
local SCAN_MARGIN = 60 -- seconds; closer full scans count as the same one

-- Auction houses are per realm and faction, so full scan times and shared prices are kept per house
function ns.RealmKey()
  local realm = GetNormalizedRealmName and GetNormalizedRealmName() or "?"
  local faction = UnitFactionGroup and UnitFactionGroup("player") or "?"
  return realm .. "-" .. faction
end

-- itemID -> {price, seen, visit, from} shared for this auction house, nil when none yet
function ns.SharedPrices()
  local all = KeepOrSellDB and KeepOrSellDB.sharedPrices
  return all and all[ns.RealmKey()]
end

-- server time of our last full scan of this auction house
function ns.LastFullScan()
  local scans = KeepOrSellDB and KeepOrSellDB.fullScans
  return scans and scans[ns.RealmKey()]
end

-- How fresh a price is: {days = Auctionator's age in days, visit = server time of the full auction
-- house scan it came from}. Auctionator only knows days, so the full scan time can only break a tie
-- between two prices from today. nil = no usable price.

-- age = Auctionator's age in days, lastScan = server time of our last full scan. Pure.
function ns.OwnFreshness(age, lastScan, now)
  if not age then return nil end
  local visit = age == 0 and lastScan and now - lastScan < DAY and lastScan or nil
  return {days = age, visit = visit}
end

-- entry = a stored shared price {price, seen, visit}. Pure.
function ns.SharedFreshness(entry, now)
  local days = math.max(0, math.floor((now - entry.seen) / DAY))
  return {days = days, visit = days == 0 and entry.visit or nil}
end

-- true when a is fresher than b: fewer days old, or both from today and a's full scan at least a
-- minute later. Without a full scan time on both sides, the same day is a tie. Pure.
function ns.IsFresher(a, b)
  if not a then return false end
  if not b then return true end
  if a.days ~= b.days then return a.days < b.days end
  return a.days == 0 and a.visit ~= nil and b.visit ~= nil and a.visit >= b.visit + SCAN_MARGIN
end

-- own = {ah, vendor, age, hasAge} from Auctionator; shared = {price, seen, visit, from} from a group
-- member; lastScan = our last full scan. The shared price wins when the own one is missing or older. Pure.
function ns.PickPrice(own, shared, now, lastScan)
  if not (shared and shared.price and shared.seen) then return own end
  local fresh = ns.SharedFreshness(shared, now)
  if own.ah and own.ah > 0 then
    -- without an age API the own price is trusted as before
    if not own.hasAge then return own end
    if own.age and not ns.IsFresher(fresh, ns.OwnFreshness(own.age, lastScan, now)) then return own end
  end
  return {ah = shared.price, vendor = own.vendor, age = fresh.days, hasAge = true, from = shared.from}
end

-- Fills a missing auction price from a secondary source (TSM). An own or shared price always wins,
-- even a stale one. The fallback has no age, so maxAge doesn't apply to it. Pure.
function ns.MergeFallback(prices, fallbackPrice, source)
  if (prices.ah and prices.ah > 0) or not fallbackPrice or fallbackPrice <= 0 then return prices end
  return {ah = fallbackPrice, vendor = prices.vendor, hasAge = false, source = source}
end

-- {ah, vendor, age, hasAge, from, source}; age = days since last seen on the AH (nil = never or older than
-- 21 days), from = the group member who shared the price (nil for the own Auctionator price),
-- source = "tsm" when the price came from TradeSkillMaster
function ns.GetPrices(itemLink)
  local api = Api()
  local prices = {}
  if not itemLink then return prices end
  if api and api.GetAuctionPriceByItemLink then
    prices.ah = api.GetAuctionPriceByItemLink(addonName, itemLink)
  end
  if prices.ah and api.GetAuctionAgeByItemLink then
    prices.hasAge = true
    prices.age = api.GetAuctionAgeByItemLink(addonName, itemLink)
  end
  prices.vendor = VendorPrice(itemLink)
  local shared = KeepOrSellDB and KeepOrSellDB.share and ns.SharedPrices()
  local id = shared and C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(itemLink)
  if id and shared[id] and GetServerTime then
    prices = ns.PickPrice(prices, shared[id], GetServerTime(), ns.LastFullScan())
  end
  -- TSM only fills gaps, so it is never asked for items Auctionator or the group knows
  if not (prices.ah and prices.ah > 0) and ns.GetTSMPrice then
    prices = ns.MergeFallback(prices, ns.GetTSMPrice(itemLink), "tsm")
  end
  return prices
end
