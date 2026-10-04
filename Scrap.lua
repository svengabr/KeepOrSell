-- Extends Scrap: cheap trade goods (auction price < factor x vendor price) count as junk.
-- Uses Scrap's public API Scrap:IsJunk(id, bag, slot); Scrap's own list takes precedence.
local _, ns = ...

local TRADEGOODS = 7 -- Enum.ItemClass.Tradegoods

local function ItemLink(id, bag, slot)
  if bag and slot and C_Container and C_Container.GetContainerItemLink then
    local link = C_Container.GetContainerItemLink(bag, slot)
    if link then return link end
  end
  return (select(2, C_Item.GetItemInfo(id)))
end

function ns.ShouldScrap(id, bag, slot)
  if not KeepOrSellDB.scrap then return false end
  local classID = select(6, C_Item.GetItemInfoInstant(id))
  if classID ~= TRADEGOODS then return false end
  if ns.GetObjectiveState(id) ~= false then return false end -- quest objective or name unknown
  return ns.GetPriceClass(ItemLink(id, bag, slot), KeepOrSellDB.factor) == "vendor"
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
