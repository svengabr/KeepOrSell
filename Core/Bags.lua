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

-- true if the item never stacks (scrolls, clams, gear): Baganator may still show copies as one stack
function ns.IsUnstackable(itemID)
  local size = itemID and C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(itemID)
  return size == 1
end

-- Baganator asks for every item on a refresh; count all bags once per frame
local counts, countedAt

-- Number of bag slots holding the item; each clam or box takes its own even when Baganator stacks them
function ns.CountSlots(itemID)
  if not (itemID and C_Container and C_Container.GetContainerItemInfo) then return 0 end
  local now = GetTime and GetTime()
  if not (now and countedAt == now) then
    counts = {}
    for bag = 0, BAGS do
      for slot = 1, C_Container.GetContainerNumSlots(bag) do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info and info.itemID then counts[info.itemID] = (counts[info.itemID] or 0) + 1 end
      end
    end
    countedAt = now
  end
  return counts[itemID] or 0
end

-- Bag type of a bag: 0 for regular bags, else the item families it takes (herb bag, quiver …)
local function BagFamily(bag)
  if not C_Container.GetContainerNumFreeSlots then return 0 end
  local _, family = C_Container.GetContainerNumFreeSlots(bag)
  return family or 0
end

-- Free slots in the regular bags; a free slot in a profession bag takes only its own kind of item
function ns.FreeSlots()
  local free = 0
  if not (C_Container and C_Container.GetContainerNumFreeSlots) then return free end
  for bag = 0, BAGS do
    local n, family = C_Container.GetContainerNumFreeSlots(bag)
    if (family or 0) == 0 then free = free + (n or 0) end
  end
  return free
end

-- bit.band in the client, plain arithmetic elsewhere (tests)
local function BitAnd(a, b)
  if bit and bit.band then return bit.band(a, b) end
  local result, value = 0, 1
  while a > 0 and b > 0 do
    if a % 2 == 1 and b % 2 == 1 then result = result + value end
    a, b, value = math.floor(a / 2), math.floor(b / 2), value * 2
  end
  return result
end

-- true if an item of itemFamily may go into a bag of bagFamily (both bit masks, 0 = regular). Pure.
function ns.FamilyMatches(itemFamily, bagFamily)
  return (itemFamily or 0) ~= 0 and (bagFamily or 0) ~= 0 and BitAnd(itemFamily, bagFamily) ~= 0
end

-- true if quantity more items fit onto the stacks already in the bags: slots stacks holding total items,
-- each up to maxStack. Loot fills every stack with room, not just one. Pure.
function ns.FitsOnStacks(quantity, maxStack, slots, total)
  return (maxStack or 1) > 1 and (slots or 0) > 0 and slots * maxStack - (total or 0) >= (quantity or 1)
end

-- true if loot needs no free regular slot: it fits onto existing stacks or into a profession bag
function ns.LootFits(itemID, quantity)
  if not (itemID and C_Container and C_Container.GetContainerItemInfo) then return false end
  local itemFamily = C_Item.GetItemFamily and C_Item.GetItemFamily(itemID) or 0
  local slots, total = 0, 0
  for bag = 0, BAGS do
    local family = BagFamily(bag)
    if ns.FamilyMatches(itemFamily, family) and (C_Container.GetContainerNumFreeSlots(bag) or 0) > 0 then
      return true
    end
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID == itemID then slots, total = slots + 1, total + (info.stackCount or 1) end
    end
  end
  local maxStack = C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(itemID)
  return ns.FitsOnStacks(quantity, maxStack, slots, total)
end

-- Both buttons update on the same events; one scan per frame is enough
local scanned, scannedAt

-- Returns a list of {bag, slot, itemID, link, count, quality, locked, icon, junk, value, ah, special}:
-- value = vendor price x stack, ah = auction price x stack for items of the AuctionHouse group,
-- special = it sits in a profession bag, where destroying it frees no regular slot
function ns.ScanBags()
  local now = GetTime and GetTime()
  if now and scannedAt == now then return scanned end
  local items = {}
  if not (C_Container and C_Container.GetContainerItemInfo) then return items end
  for bag = 0, BAGS do
    local special = BagFamily(bag) ~= 0
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID and info.hyperlink then
        local count = info.stackCount or 1
        local item = {
          bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink, count = count,
          quality = info.quality, locked = info.isLocked, icon = info.iconFileID,
          junk = IsJunk(info, bag, slot), value = VendorPrice(info.hyperlink) * count, special = special,
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
