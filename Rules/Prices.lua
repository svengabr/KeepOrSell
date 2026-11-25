-- Compares auction price (Auctionator, Forever Ledger) with vendor price. Pure logic, no Baganator.
local addonName, ns = ...

local AH_CUT = 0.05 -- auction house fee on a sale
local MAX_AUCTIONATOR_AGE = 21 -- Auctionator reports no age beyond this
-- deposit, measured on Forever: 5% of the vendor price per 2 hours, rounded down per 2 hours, at least
-- 1 silver per auction (Moss Agate 4s: 1s at 2 and 8 h, 2s 40c at 24 h; Wild Leather Leggings 15s 32c: 3s 4c at 8 h)
local DEPOSIT_RATE = 0.05
local MIN_DEPOSIT = 100
-- the duration KeepOrSell assumes when it weighs the deposit
ns.DEPOSIT_HOURS = 8
-- lowest auction house threshold: below it the AH cut can leave less than the vendor pays
ns.MIN_FACTOR = 1.1

-- Deposit in copper for one auction of count items with this vendor price each and a duration in hours (2, 8
-- or 24); nil without a vendor price (not measured). It comes back when the auction sells. Pure.
function ns.AuctionDeposit(vendorPrice, count, hours)
  if not vendorPrice or vendorPrice <= 0 then return nil end
  local perTwoHours = math.floor(vendorPrice * (count or 1) * DEPOSIT_RATE)
  return math.max(perTwoHours * math.floor((hours or ns.DEPOSIT_HOURS) / 2), MIN_DEPOSIT)
end

-- Deposit per item when every copy in the bags goes into one auction (count nil = 1): the 1s minimum is per
-- auction, so 21 Linen Cloth cost 1s like a single one (measured on Forever). Pure.
function ns.ItemDeposit(vendorPrice, count)
  count = math.max(count or 1, 1)
  local deposit = ns.AuctionDeposit(vendorPrice, count, ns.DEPOSIT_HOURS)
  return deposit and deposit / count
end

-- "ah" = worth auctioning (at least factor x vendor price, at least minProfit copper more per item
-- after the AH cut, and still more than the vendor pays when one auction doesn't sell and its deposit per item is
-- lost), "vendor" = sell to vendor, nil = no known auction price (the item stays where it is).
-- Second value for "vendor": the rule that failed, "factor", "minprofit" or "deposit".
function ns.ClassifyPrice(ahPrice, vendorPrice, factor, minProfit, deposit)
  if not ahPrice or ahPrice <= 0 then return nil end
  local vendorable = vendorPrice and vendorPrice > 0
  -- rounded to whole copper, so 100 x 1.1 is 110 and not 110.00000000000001
  if vendorable and ahPrice < math.floor(vendorPrice * factor + 0.5) then return "vendor", "factor" end
  if minProfit and minProfit > 0 and ahPrice * (1 - AH_CUT) - (vendorPrice or 0) < minProfit then
    -- not worth the trip; without vendor price it can't be sold there either, so keep it
    if vendorable then return "vendor", "minprofit" end
    return nil
  end
  if vendorable and deposit and ahPrice * (1 - AH_CUT) - deposit < vendorPrice then return "vendor", "deposit" end
  return "ah"
end

-- true if the auction price is older than the player accepts (db.maxAge); prices without an age (TSM) never are
function ns.IsStale(prices, db)
  return db.maxAge ~= nil and db.maxAge < MAX_AUCTIONATOR_AGE and prices.hasAge == true
    and (prices.age == nil or prices.age > db.maxAge)
end

-- prices = {ah, vendor, age, count}; db = {factor, minProfit (silver), maxAge (days)}
-- Returns the class and a reason: "noprice" or "stale" when the auction price is not trusted,
-- "factor", "minprofit" or "deposit" when it is not worth auctioning
function ns.ClassifyPrices(prices, db)
  if not prices.ah or prices.ah <= 0 then return nil, "noprice" end
  if ns.IsStale(prices, db) then return nil, "stale" end
  local factor = math.max(db.factor or ns.MIN_FACTOR, ns.MIN_FACTOR)
  return ns.ClassifyPrice(prices.ah, prices.vendor, factor, (db.minProfit or 0) * 100,
    ns.ItemDeposit(prices.vendor, prices.count))
end

local function Api()
  return Auctionator and Auctionator.API and Auctionator.API.v1
end

-- true when a missing price means nobody sells the item: once the player has opened the auction house with
-- Auctionator loaded (Auctionator has no public API telling whether it has scanned), or after a full scan of this
-- auction house with Forever Ledger (its own scan time doesn't tell which house it was)
function ns.HasPriceData()
  if Api() ~= nil and KeepOrSellDB.ahVisited == true then return true end
  return ns.HasLedgerScan ~= nil and ns.HasLedgerScan() and ns.LastFullScan() ~= nil
end

local function VendorPrice(itemLink)
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  return (select(11, getInfo(itemLink)))
end

local DAY = 86400
local SCAN_MARGIN = 60 -- seconds; closer full scans count as the same one

-- Auction houses are per realm and faction, so full scan times and shared prices are kept per house: "PvP-Horde"
-- (ns.PoolName in Ruleset.lua: Forever has one realm per ruleset and no longer tells addons the realm).
function ns.HouseKey()
  local faction = UnitFactionGroup and UnitFactionGroup("player") or "?"
  return ns.PoolName() .. "-" .. faction
end

-- itemID -> {price, seen, visit, from} shared for this auction house, nil when none yet
function ns.SharedPrices()
  local all = KeepOrSellDB and KeepOrSellDB.sharedPrices
  return all and all[ns.HouseKey()]
end

-- server time of our last full scan of this auction house
function ns.LastFullScan()
  local scans = KeepOrSellDB and KeepOrSellDB.fullScans
  return scans and scans[ns.HouseKey()]
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

-- own = {ah, age, hasAge} from Auctionator, plus vendor and count; ledger = {price, seen} from Forever Ledger or nil.
-- Forever Ledger wins when Auctionator has no price or one from an earlier day. On the same day Auctionator stays:
-- it tells the versions of random-stat gear apart, Forever Ledger's API doesn't. seen = server time the price was
-- seen, never later than now (Forever Ledger uses the computer's clock). Pure.
function ns.PickLedger(own, ledger, now)
  if not ledger then return own end
  local seen = math.min(ledger.seen, now)
  local days = math.floor((now - seen) / DAY)
  if own.ah and own.ah > 0 and (not own.hasAge or (own.age and own.age <= days)) then return own end
  return {ah = ledger.price, vendor = own.vendor, count = own.count, age = days, hasAge = true, seen = seen,
    source = "ledger"}
end

-- own = {ah, vendor, age, hasAge, seen} from Auctionator or Forever Ledger (only Forever Ledger knows seen);
-- shared = {price, seen, visit, from} from a group member; lastScan = our last full scan. The shared price wins when the own one is missing or older. Pure.
function ns.PickPrice(own, shared, now, lastScan)
  if not (shared and shared.price and shared.seen) then return own end
  local fresh = ns.SharedFreshness(shared, now)
  if own.ah and own.ah > 0 then
    -- without an age API the own price is trusted as before
    if not own.hasAge then return own end
    if own.age and not ns.IsFresher(fresh, ns.OwnFreshness(own.age, own.seen or lastScan, now)) then return own end
  end
  return {ah = shared.price, vendor = own.vendor, count = own.count, age = fresh.days, hasAge = true, from = shared.from}
end

-- Fills a missing auction price from a secondary source (TSM). An own or shared price always wins,
-- even a stale one. The fallback has no age, so maxAge doesn't apply to it. Pure.
function ns.MergeFallback(prices, fallbackPrice, source)
  if (prices.ah and prices.ah > 0) or not fallbackPrice or fallbackPrice <= 0 then return prices end
  return {ah = fallbackPrice, vendor = prices.vendor, count = prices.count, hasAge = false, source = source}
end

-- a price shared by a group member wins when the own one is missing or older
local function WithShared(prices, id)
  local shared = id and KeepOrSellDB and KeepOrSellDB.share and ns.SharedPrices()
  if shared and shared[id] and GetServerTime then
    return ns.PickPrice(prices, shared[id], GetServerTime(), ns.LastFullScan())
  end
  return prices
end

-- Forever Ledger's price next to the one from Auctionator
local function WithLedger(prices, id)
  if not (id and ns.GetLedgerPrice and GetServerTime) then return prices end
  return ns.PickLedger(prices, ns.GetLedgerPrice(id), GetServerTime())
end

-- {ah, age, hasAge, seen, source}: our own price of an item by its ID, from Auctionator or (unless noLedger) Forever Ledger
function ns.GetOwnPricesByID(itemID, noLedger)
  local api = Api()
  local prices = {}
  if api and api.GetAuctionPriceByItemID then prices.ah = api.GetAuctionPriceByItemID(addonName, itemID) end
  if prices.ah and api.GetAuctionAgeByItemID then
    prices.hasAge = true
    prices.age = api.GetAuctionAgeByItemID(addonName, itemID)
  end
  return noLedger and prices or WithLedger(prices, itemID)
end

-- {ah, age, hasAge, seen, from, source} of an item known only by its ID (disenchanting materials): our own and
-- shared group prices, no TSM and no vendor price
function ns.GetPricesByID(itemID)
  return WithShared(ns.GetOwnPricesByID(itemID), itemID)
end

-- {ah, vendor, count, age, hasAge, seen, from, source}; count = copies in the bags; age = days since last seen on the AH (nil = never or older than
-- 21 days), from = the group member who shared the price (nil for an own price), seen = server time
-- of a Forever Ledger price, source = "ledger" when the price came from Forever Ledger, "tsm" from TradeSkillMaster
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
  prices.count = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(itemLink)
  local id = C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(itemLink)
  prices = WithShared(WithLedger(prices, id), id)
  -- TSM only fills gaps, so it is never asked for items Auctionator, Forever Ledger or the group knows
  if not (prices.ah and prices.ah > 0) and ns.GetTSMPrice then
    prices = ns.MergeFallback(prices, ns.GetTSMPrice(itemLink), "tsm")
  end
  return prices
end
