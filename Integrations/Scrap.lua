-- Extends Scrap: whatever KeepOrSell classifies as junk (cheap trade goods, gear the class can never wear).
-- Uses Scrap's public API Scrap:IsJunk(id, bag, slot); Scrap's own list takes precedence.
local _, ns = ...

local function ItemLink(id, bag, slot)
  if bag and slot and C_Container and C_Container.GetContainerItemLink then
    local link = C_Container.GetContainerItemLink(bag, slot)
    if link then return link end
  end
  return (select(2, C_Item.GetItemInfo(id)))
end

local function Location(bag, slot)
  if bag and slot and ItemLocation and ItemLocation.CreateFromBagAndSlot then
    return ItemLocation:CreateFromBagAndSlot(bag, slot)
  end
end

function ns.ShouldScrap(id, bag, slot)
  return ns.Classify(id, ItemLink(id, bag, slot), Location(bag, slot)).kind == "junk"
end

function ns.HookScrap()
  if not (Scrap and Scrap.IsJunk) then return end
  local original = Scrap.IsJunk
  Scrap.IsJunk = function(self, id, ...)
    local junk = original(self, id, ...)
    if junk then return junk end
    -- explicitly marked as "not junk" in Scrap by the player
    if not id or (self.junk and self.junk[id] == false) then return junk end
    if ns.ShouldScrap(id, ...) then return true end
    return junk
  end
end
