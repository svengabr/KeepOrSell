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

-- own = {ah, vendor, age, hasAge} from Auctionator; shared = {price, seen, from} from a group member.
-- The shared price wins when the own one is missing or older. Pure.
function ns.PickPrice(own, shared, now)
  if not (shared and shared.price and shared.seen) then return own end
  local sharedAge = math.max(0, math.floor((now - shared.seen) / DAY))
  if own.ah and own.ah > 0 then
    -- without an age API the own price is trusted as before
    if not own.hasAge then return own end
    if own.age and own.age <= sharedAge then return own end
  end
  return {ah = shared.price, vendor = own.vendor, age = sharedAge, hasAge = true, from = shared.from}
end

-- {ah, vendor, age, hasAge, from}; age = days since last seen on the AH (nil = never or older than 21 days),
-- from = the group member who shared the price (nil for the own Auctionator price)
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
  local shared = KeepOrSellDB and KeepOrSellDB.share and KeepOrSellDB.sharedPrices
  local id = shared and C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(itemLink)
  if id and shared[id] and GetServerTime then
    return ns.PickPrice(prices, shared[id], GetServerTime())
  end
  return prices
end
