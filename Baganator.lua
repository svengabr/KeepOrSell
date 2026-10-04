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

  -- Report quest items, profession reagents and items worth auctioning as item sets. Baganator shows each set as its
  -- own group in its equipment sets category, without any setup by the player.
  -- Cheap items are handled by Scrap (Scrap.lua).
  if KeepOrSellDB.setSource and api.RegisterItemSetSource then
    api.RegisterItemSetSource("KeepOrSell", "keeporsell", function(_, guid)
      local link = guid and C_Item.GetItemLinkByGUID and C_Item.GetItemLinkByGUID(guid)
      local location = guid and C_Item.GetItemLocation and C_Item.GetItemLocation(guid)
      return ns.ItemSets(ItemIDFromGUID(guid), link, location)
    end, function()
      return {ns.L.SET_QUEST, ns.L.SET_PROFESSION, ns.L.SET_AH}
    end)
  end
end

local INFO = {
  quest = {name = ns.L.SET_QUEST, iconTexture = ICON},
  profession = {name = ns.L.SET_PROFESSION, iconTexture = "Interface\\Icons\\INV_Misc_Note_01"},
  ah = {name = ns.L.SET_AH, iconTexture = "Interface\\Icons\\INV_Misc_Coin_01"},
}

-- Set for an item as a list, as Baganator expects; nil = none.
-- Regular quest items join the quest group too, so Baganator's own quest category stays empty.
function ns.ItemSets(itemID, itemLink, location)
  if not itemID then return nil end
  local info = INFO[ns.Classify(itemID, itemLink, location).kind]
  if info then return {info} end
end

function ns.RefreshBaganator()
  if Baganator and Baganator.API and Baganator.API.RequestItemButtonsRefresh then
    Baganator.API.RequestItemButtonsRefresh()
  end
end
