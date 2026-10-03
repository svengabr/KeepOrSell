-- Anbindung an Baganator, nur über dessen öffentliche API (Baganator.API.*)
local _, ns = ...

ns.SET_NAME = "Questziel"
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

  -- Eckmarkierung: gelb = noch offen, grün = Ziel erfüllt, Quest aber noch nicht abgegeben
  -- Rückgabe: true = zeigen, false = nicht zeigen, nil = später erneut fragen (Item-Cache)
  api.RegisterCornerWidget("Questziel", "bagquestmarks-objective", function(corner, details)
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

  -- Optional: Questziele als Set melden, damit die Suche sie erfasst
  if BagQuestMarksDB.setSource and api.RegisterItemSetSource then
    local info = {name = ns.SET_NAME, iconTexture = ICON}
    api.RegisterItemSetSource("BagQuestMarks", "bagquestmarks", function(_, guid)
      if ns.GetObjectiveState(ItemIDFromGUID(guid)) then return {info} end
    end, function()
      return {ns.SET_NAME}
    end)
  end
end

function ns.RefreshBaganator()
  if Baganator and Baganator.API and Baganator.API.RequestItemButtonsRefresh then
    Baganator.API.RequestItemButtonsRefresh()
  end
end
