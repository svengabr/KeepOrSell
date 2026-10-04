-- Compares auction price (Auctionator) with vendor price. Pure logic, no Baganator.
local addonName, ns = ...

-- "ah" = worth auctioning (at least factor x vendor price), "vendor" = sell to vendor,
-- nil = no known auction price (the item stays where it is)
function ns.ClassifyPrice(ahPrice, vendorPrice, factor)
  if not ahPrice or ahPrice <= 0 then return nil end
  if not vendorPrice or vendorPrice <= 0 then return "ah" end
  if ahPrice >= vendorPrice * factor then return "ah" end
  return "vendor"
end

local function AuctionPrice(itemLink)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not (api and api.GetAuctionPriceByItemLink) then return nil end
  return api.GetAuctionPriceByItemLink(addonName, itemLink)
end

local function VendorPrice(itemLink)
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  return (select(11, getInfo(itemLink)))
end

function ns.GetPriceClass(itemLink, factor)
  if not itemLink then return nil end
  local ahPrice = AuctionPrice(itemLink)
  if not ahPrice then return nil end
  return ns.ClassifyPrice(ahPrice, VendorPrice(itemLink), factor)
end
