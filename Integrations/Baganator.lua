-- Baganator integration, using only its public API (Baganator.API.*)
local _, ns = ...

local ICON = "Interface\\GossipFrame\\ActiveQuestIcon"

local function ItemIDFromDetails(details)
  if details.itemID then return details.itemID end
  if details.itemLink then return (C_Item.GetItemInfoInstant(details.itemLink)) end
end

local function ItemIDFromGUID(guid)
  if guid and C_Item.GetItemIDByGUID then return C_Item.GetItemIDByGUID(guid) end
end

function ns.RegisterBaganator()
  local api = Baganator and Baganator.API
  if not (api and api.RegisterCornerWidget) then return end

  -- Corner marker: yellow = objective still open, green = objective done but quest not turned in yet
  -- Returns true = show, false = hide, nil = ask again later (item cache)
  api.RegisterCornerWidget(ns.L.SET_QUEST, "keeporsell-objective", function(corner, details)
    local state = ns.GetObjectiveState(ItemIDFromDetails(details))
    if state == nil then return nil end
    if not state then return false end
    if state == "done" then
      corner:SetVertexColor(0.3, 1, 0.3)
    else
      corner:SetVertexColor(1, 1, 1)
    end
    return true
  end, function(itemButton)
    local tex = itemButton:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(ICON)
    tex:SetSize(14, 14)
    return tex
  end, {default_position = "top_left", priority = 1})

  -- Report quest items, items to open, copies that don't stack, profession reagents, items worth auctioning and items to disenchant as item sets. Baganator shows each set as its
  -- own group in its equipment sets category, without any setup by the player.
  -- Cheap items are handled by Scrap (Scrap.lua).
  if KeepOrSellDB.setSource and api.RegisterItemSetSource then
    api.RegisterItemSetSource("KeepOrSell", "keeporsell", function(_, guid)
      local link = guid and C_Item.GetItemLinkByGUID and C_Item.GetItemLinkByGUID(guid)
      local location = guid and C_Item.GetItemLocation and C_Item.GetItemLocation(guid)
      return ns.ItemSets(ItemIDFromGUID(guid), link, location)
    end, function()
      return {ns.L.SET_QUEST, ns.L.SET_OPEN, ns.L.SET_PROFESSION, ns.L.SET_AH, ns.L.SET_DISENCHANT, ns.L.SET_UNSTACKED}
    end)
  end
end

local INFO = {
  quest = {name = ns.L.SET_QUEST, iconTexture = ICON},
  open = {name = ns.L.SET_OPEN, iconTexture = "Interface\\Icons\\INV_Box_01"},
  profession = {name = ns.L.SET_PROFESSION, iconTexture = "Interface\\Icons\\INV_Misc_Note_01"},
  ah = {name = ns.L.SET_AH, iconTexture = "Interface\\Icons\\INV_Misc_Coin_01"},
  disenchant = {name = ns.L.SET_DISENCHANT, iconTexture = "Interface\\Icons\\INV_Enchant_Disenchant"},
}
local UNSTACKED = {name = ns.L.SET_UNSTACKED, iconTexture = "Interface\\Icons\\INV_Misc_Bag_10"}

local WEAPON, ARMOR = 2, 4 -- Enum.ItemClass

-- Baganator shows copies of an item as one stack unless the item is in a set. Copies that don't stack and sit
-- in several slots get their own group, so each slot shows. Only items without a group of their own; junk
-- goes to Baganator's junk category, gear stays with the gear. Pure.
function ns.IsUnstackedSet(kind, unstackable, slots, isGear)
  return kind == nil and unstackable and slots > 1 and not isGear or false
end

local function IsGear(itemID)
  local _, _, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(itemID)
  return (classID == WEAPON or classID == ARMOR) and (equipLoc or "") ~= ""
end

-- Set for an item as a list, as Baganator expects; nil = none.
-- Regular quest items join the quest group too, so Baganator's own quest category stays empty.
function ns.ItemSets(itemID, itemLink, location)
  if not itemID then return nil end
  local kind = ns.Classify(itemID, itemLink, location).kind
  if INFO[kind] then return {INFO[kind]} end
  if ns.IsUnstackedSet(kind, ns.IsUnstackable(itemID), ns.CountSlots(itemID), IsGear(itemID)) then
    return {UNSTACKED}
  end
end

function ns.RefreshBaganator()
  ns.ClearCache()
  if Baganator and Baganator.API and Baganator.API.RequestItemButtonsRefresh then
    Baganator.API.RequestItemButtonsRefresh()
  end
end
