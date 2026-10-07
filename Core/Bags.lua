-- One pass over the bags, shared by the destroy button and the bag value.
local _, ns = ...

local BAGS = NUM_BAG_SLOTS or 4

-- Scrap decides when present (its list, "not junk" marks and our hook); otherwise grey items and
-- whatever KeepOrSell classifies as junk
local function IsJunk(info, bag, slot)
  if Scrap and Scrap.IsJunk then return Scrap:IsJunk(info.itemID, bag, slot) and true or false end
  return info.quality == 0 or ns.ShouldScrap(info.itemID, bag, slot)
end

local function VendorPrice(link)
  return select(11, (C_Item.GetItemInfo or GetItemInfo)(link)) or 0
end

local function Location(bag, slot)
  return ItemLocation and ItemLocation.CreateFromBagAndSlot and ItemLocation:CreateFromBagAndSlot(bag, slot)
end

-- Number of bag slots holding the item; each clam or box takes its own even when Baganator stacks them
function ns.CountSlots(itemID)
  local slots = 0
  if not (itemID and C_Container and C_Container.GetContainerItemInfo) then return slots end
  for bag = 0, BAGS do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID == itemID then slots = slots + 1 end
    end
  end
  return slots
end

-- Both buttons update on the same events; one scan per frame is enough
local scanned, scannedAt

-- Returns a list of {bag, slot, itemID, link, count, quality, locked, icon, junk, value, ah}:
-- value = vendor price x stack, ah = auction price x stack for items of the AuctionHouse group
function ns.ScanBags()
  local now = GetTime and GetTime()
  if now and scannedAt == now then return scanned end
  local items = {}
  if not (C_Container and C_Container.GetContainerItemInfo) then return items end
  for bag = 0, BAGS do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID and info.hyperlink then
        local count = info.stackCount or 1
        local item = {
          bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink, count = count,
          quality = info.quality, locked = info.isLocked, icon = info.iconFileID,
          junk = IsJunk(info, bag, slot), value = VendorPrice(info.hyperlink) * count,
        }
        if not item.junk and ns.Classify(info.itemID, info.hyperlink, Location(bag, slot)).kind == "ah" then
          item.ah = (ns.GetPrices(info.hyperlink).ah or 0) * count
        end
        table.insert(items, item)
      end
    end
  end
  scanned, scannedAt = items, now
  return items
end
