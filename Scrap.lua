-- Erweitert Scrap: billige Handwerkswaren (Auktionspreis < Faktor x Händlerpreis) gelten als Schrott.
-- Nutzt Scraps öffentliche API Scrap:IsJunk(id, bag, slot); Scraps eigene Liste hat Vorrang.
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
  if not BagQuestMarksDB.scrap then return false end
  local classID = select(6, C_Item.GetItemInfoInstant(id))
  if classID ~= TRADEGOODS then return false end
  if ns.GetObjectiveState(id) ~= false then return false end -- Questziel oder Name unbekannt
  return ns.GetPriceClass(ItemLink(id, bag, slot), BagQuestMarksDB.factor) == "vendor"
end

function ns.HookScrap()
  if not (Scrap and Scrap.IsJunk) then return end
  local original = Scrap.IsJunk
  Scrap.IsJunk = function(self, id, ...)
    local junk = original(self, id, ...)
    if junk then return junk end
    -- vom Spieler in Scrap ausdrücklich als "kein Schrott" markiert
    if not id or (self.junk and self.junk[id] == false) then return junk end
    if ns.ShouldScrap(id, ...) then return true end
    return junk
  end
end
