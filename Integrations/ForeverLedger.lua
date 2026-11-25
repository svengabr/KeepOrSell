-- Auction prices from Forever Ledger's public API (ForeverLedgerAPI, since 0.29.0): its own scans only, with the
-- time of each scan. Used next to Auctionator or instead of it (ns.PickLedger in Prices.lua).
local _, ns = ...

local API_VERSION = 1 -- Forever Ledger raises it when a change breaks callers

local function Api()
  local api = ForeverLedgerAPI
  return type(api) == "table" and api.version == API_VERSION and api.GetPrice and api or nil
end

-- true when Forever Ledger is loaded with the API KeepOrSell knows
function ns.HasForeverLedger()
  return Api() ~= nil
end

-- {price, seen} or nil: the cheapest listing like Auctionator and when it was scanned. The API only knows item
-- IDs, so for gear with random stats it is the cheapest of all versions.
function ns.GetLedgerPrice(itemID)
  local api = Api()
  if not (api and itemID) then return nil end
  local ok, _, cheapest, _, seen = pcall(api.GetPrice, itemID)
  if not (ok and type(cheapest) == "number" and cheapest > 0 and type(seen) == "number") then return nil end
  return {price = cheapest, seen = seen}
end

-- true when Forever Ledger finished a full scan; it keeps one time for all auction houses
function ns.HasLedgerScan()
  local api = Api()
  if not (api and api.GetLastFullScan) then return false end
  local ok, when = pcall(api.GetLastFullScan)
  return ok and when ~= nil
end
