-- Compares auction price (Auctionator) with vendor price. Pure logic, no Baganator.
local addonName, ns = ...

local AH_CUT = 0.05 -- auction house fee on a sale
local MAX_AUCTIONATOR_AGE = 21 -- Auctionator reports no age beyond this

-- "ah" = worth auctioning (at least factor x vendor price and at least minProfit copper more per item
-- after the AH cut), "vendor" = sell to vendor, nil = no known auction price (the item stays where it is).
-- Second value for "vendor": the rule that failed, "factor" or "minprofit".
function ns.ClassifyPrice(ahPrice, vendorPrice, factor, minProfit)
  if not ahPrice or ahPrice <= 0 then return nil end
  local vendorable = vendorPrice and vendorPrice > 0
  if vendorable and ahPrice < vendorPrice * factor then return "vendor", "factor" end
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
  return ns.ClassifyPrice(prices.ah, prices.vendor, db.factor, (db.minProfit or 0) * 100)
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

-- {ah, vendor, age, hasAge}; age = days since last seen on the AH (nil = never or older than 21 days)
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
  return prices
end
