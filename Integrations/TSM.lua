-- Auction prices from TradeSkillMaster's public API, used only when Auctionator has none.
local _, ns = ...

-- lowest current buyout like Auctionator, otherwise TSM's market value
local PRICE = "first(DBMinBuyout, DBMarket)"

-- copper or nil; nil without TSM, without data for this realm or when TSM raises
function ns.GetTSMPrice(itemLink)
  if not (itemLink and TSM_API and TSM_API.GetCustomPriceValue and TSM_API.ToItemString) then return nil end
  local ok, itemString = pcall(TSM_API.ToItemString, itemLink)
  if not (ok and itemString) then return nil end
  local found, price = pcall(TSM_API.GetCustomPriceValue, PRICE, itemString)
  if not (found and type(price) == "number" and price > 0) then return nil end
  return price
end
