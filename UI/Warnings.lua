-- Warns in chat and on screen when the player deletes or sells an item KeepOrSell would keep: a quest item,
-- a reagent, a keep mark, a class item or tool, gear saved in an equipment set. Only reads the game's own
-- calls (post-hooks), never blocks them.
local _, ns = ...
local L = ns.L

local KEPT_REASONS = {kept = true, classitem = true, tool = true, equipset = true}

-- true if losing an item with this verdict deserves a warning. Pure.
function ns.ShouldWarnLoss(verdict)
  if not verdict then return false end
  return verdict.kind == "quest" or verdict.kind == "profession" or KEPT_REASONS[verdict.reason] == true
end

local DELETE_POPUPS = {DELETE_ITEM = true, DELETE_GOOD_ITEM = true, DELETE_QUEST_ITEM = true, DELETE_GOOD_QUEST_ITEM = true}
local REPEAT_SECONDS = 2 -- selling several stacks of one item warns once
local lastWarned = {}

local function Warn(itemID, link, template, location)
  if not (KeepOrSellDB and KeepOrSellDB.lossWarnings and itemID and link) then return end
  local now = GetTime and GetTime() or 0
  if lastWarned[itemID] and now - lastWarned[itemID] < REPEAT_SECONDS then return end
  local verdict = ns.Classify(itemID, link, location)
  if not ns.ShouldWarnLoss(verdict) then return end
  local why = ns.TooltipText(verdict, nil, KeepOrSellDB)
  if not why then return end
  lastWarned[itemID] = now
  print(why .. " " .. template:format(link))
  if UIErrorsFrame then UIErrorsFrame:AddMessage(template:format(link), 1, 0.3, 0.1) end
end

-- the delete dialog opens with the item on the cursor
local function OnPopup(which)
  if not DELETE_POPUPS[which] or not GetCursorInfo then return end
  local kind, itemID, link = GetCursorInfo()
  if kind == "item" then Warn(itemID, link, L.WARN_DELETE) end
end

-- a click on a bag item while a merchant is open sells it; Scrap's own junk list is the player's choice
local function OnUse(bag, slot)
  if not (MerchantFrame and MerchantFrame:IsShown()) then return end
  local info = C_Container.GetContainerItemInfo(bag, slot)
  if not (info and info.itemID) then return end
  if Scrap and Scrap.IsJunk and Scrap:IsJunk(info.itemID, bag, slot) then return end
  local location = ItemLocation and ItemLocation:CreateFromBagAndSlot(bag, slot)
  Warn(info.itemID, info.hyperlink, L.WARN_SELL, location)
end

function ns.HookLossWarnings()
  if not hooksecurefunc then return end
  if StaticPopup_Show then hooksecurefunc("StaticPopup_Show", OnPopup) end
  if C_Container and C_Container.UseContainerItem and C_Container.GetContainerItemInfo then
    hooksecurefunc(C_Container, "UseContainerItem", OnUse)
  end
end
