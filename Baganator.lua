-- Anbindung an Baganator, nur über dessen öffentliche API (Baganator.API.*)
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

  -- Eckmarkierung: gelb = noch offen, grün = Ziel erfüllt, Quest aber noch nicht abgegeben
  -- Rückgabe: true = zeigen, false = nicht zeigen, nil = später erneut fragen (Item-Cache)
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

  -- Optional: Questziele und lohnende Auktionshaus-Items als Sets melden, damit die Suche sie erfasst.
  -- Billige Items übernimmt Scrap (Scrap.lua).
  if KeepOrSellDB.setSource and api.RegisterItemSetSource then
    local questInfo = {name = ns.L.SET_QUEST, iconTexture = ICON}
    local ahInfo = {name = ns.L.SET_AH, iconTexture = "Interface\\Icons\\INV_Misc_Coin_01"}
    api.RegisterItemSetSource("KeepOrSell", "keeporsell", function(_, guid)
      local sets = {}
      if ns.GetObjectiveState(ItemIDFromGUID(guid)) then table.insert(sets, questInfo) end
      local link = guid and C_Item.GetItemLinkByGUID and C_Item.GetItemLinkByGUID(guid)
      if ns.GetPriceClass(link, KeepOrSellDB.factor) == "ah" then table.insert(sets, ahInfo) end
      if #sets > 0 then return sets end
    end, function()
      return {ns.L.SET_QUEST, ns.L.SET_AH}
    end)
  end
end

function ns.RefreshBaganator()
  if Baganator and Baganator.API and Baganator.API.RequestItemButtonsRefresh then
    Baganator.API.RequestItemButtonsRefresh()
  end
end

-- Kategorien Quest und AuctionHouse automatisch anlegen, über Baganator.API.ImportString.
-- Ohne "order" stellt Baganator sie nur vorne an und lässt das übrige Layout des Spielers in Ruhe.
-- Eigene Kategorien schlagen mit Priorität 1 sicher die eingebauten (Equipment-Sets, Questitems).
local PRIORITY = 1

local function JSONString(s)
  return '"' .. s:gsub('[%c"\\]', function(c) return ("\\u%04x"):format(c:byte()) end) .. '"'
end

function ns.CategoryImportJSON()
  local L = ns.L
  local categories = {
    {source = "keeporsell_quest", name = L.CAT_QUEST, search = "quest"},
    {source = "keeporsell_ah", name = L.SET_AH, search = L.SET_AH:lower() .. " & ~quest"},
  }
  local cats, mods = {}, {}
  for _, c in ipairs(categories) do
    table.insert(cats, ('{"source":%s,"name":%s,"search":%s}'):format(
      JSONString(c.source), JSONString(c.name), JSONString(c.search)))
    table.insert(mods, ('{"source":%s,"priority":%d}'):format(JSONString(c.source), PRIORITY))
  end
  return ('{"addon":"Baganator","version":3,"kind":"categories","categories":[%s],"modifications":[%s]}'):format(
    table.concat(cats, ","), table.concat(mods, ","))
end

-- Legt die Kategorien einmalig an (force = erneut). Jeder Import fügt neue Kategorien hinzu,
-- deshalb merkt sich KeepOrSellDB.categoriesImported den ersten Erfolg.
-- true = angelegt, false = Import gescheitert, nil = nichts zu tun bzw. Baganator fehlt
function ns.SetupBaganatorCategories(force)
  if KeepOrSellDB.categoriesImported and not force then return nil end
  local api = Baganator and Baganator.API
  if not (api and api.ImportString) then return nil end
  if not pcall(api.ImportString, ns.CategoryImportJSON()) then return false end
  KeepOrSellDB.categoriesImported = true
  return true
end
