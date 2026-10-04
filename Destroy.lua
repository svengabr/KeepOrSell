-- Destroys the cheapest junk item on a click, for small bags far from a vendor.
-- Shown as a button in Baganator's bag window; the tooltip names the item before it is destroyed.
local _, ns = ...
local L = ns.L

local PREFIX = "|cffffd200KeepOrSell:|r "
local RARE = 3 -- Enum.ItemQuality; the client asks to type DELETE from here on

-- candidates: list of {bag, slot, value, quality, locked}. Returns the cheapest one that may be
-- destroyed, the first slot on a tie, or nil. Pure.
function ns.PickCheapest(candidates)
  local best
  for _, item in ipairs(candidates) do
    if not item.locked and (item.quality or 0) < RARE and (not best or item.value < best.value) then
      best = item
    end
  end
  return best
end

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

-- Returns {bag, slot, itemID, link, count, value, icon} of the junk to destroy, or nil
function ns.FindDestroyTarget()
  if not (C_Container and C_Container.GetContainerItemInfo) then return nil end
  local candidates = {}
  for bag = 0, BAGS do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID and info.hyperlink and IsJunk(info, bag, slot) then
        local count = info.stackCount or 1
        table.insert(candidates, {
          bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink, count = count,
          value = VendorPrice(info.hyperlink) * count, quality = info.quality, locked = info.isLocked,
          icon = info.iconFileID,
        })
      end
    end
  end
  return ns.PickCheapest(candidates)
end

-- Destroys target only if it still sits unchanged in its slot and the cursor is free. Returns true on success.
function ns.DestroyTarget(target)
  if not target or CursorHasItem() then return false end
  local info = C_Container.GetContainerItemInfo(target.bag, target.slot)
  if not (info and info.hyperlink == target.link and (info.stackCount or 1) == target.count) or info.isLocked then
    return false
  end
  C_Container.PickupContainerItem(target.bag, target.slot)
  local kind, itemID = GetCursorInfo()
  if kind ~= "item" or itemID ~= target.itemID then
    ClearCursor()
    return false
  end
  DeleteCursorItem()
  print(PREFIX .. L.DESTROY_DONE:format(target.link, target.count))
  return true
end

-- loot: list of {link, count, value, keep}; keep = KeepOrSell would keep it (quest, profession).
-- Returns the loot item worth destroying target for, or nil. Pure.
function ns.LootWorthMore(loot, target)
  if not target then return nil end
  local best
  for _, item in ipairs(loot) do
    if item.keep or item.value > target.value then
      if not best or (item.keep and not best.keep) or (item.keep == best.keep and item.value > best.value) then
        best = item
      end
    end
  end
  return best
end

-- The items in the open loot window, valued at the better of auction and vendor price
function ns.LootItems()
  local items = {}
  if not (GetNumLootItems and GetLootSlotLink and GetLootSlotInfo) then return items end
  for slot = 1, GetNumLootItems() do
    local link = GetLootSlotLink(slot)
    if link then
      local count = select(3, GetLootSlotInfo(slot)) or 1
      local prices = ns.GetPrices(link)
      local kind = ns.Classify(C_Item.GetItemInfoInstant(link), link).kind
      table.insert(items, {
        link = link, count = count, value = math.max(prices.ah or 0, prices.vendor or 0) * count,
        keep = kind == "quest" or kind == "profession",
      })
    end
  end
  return items
end

local button
local looting, told = false, false

local function SetGlow(on)
  if not button then return end
  if on then button.Pulse:Play() else button.Pulse:Stop() end
  button.Glow:SetShown(on)
end

function ns.IsDestroyGlowing()
  return button ~= nil and button.Pulse:IsPlaying()
end

function ns.LootOpened()
  looting, told = true, false
end

function ns.LootClosed()
  looting = false
  SetGlow(false)
end

-- UI_ERROR_MESSAGE while looting: when the bags are full and the loot is worth more than the
-- cheapest junk, the destroy button glows and one chat line per loot window says why
function ns.InventoryFull(message)
  if not (looting and button and KeepOrSellDB.destroy and message == ERR_INV_FULL) then return end
  local target = ns.FindDestroyTarget()
  local best = ns.LootWorthMore(ns.LootItems(), target)
  if not best then return end
  SetGlow(true)
  if told then return end
  told = true
  print(PREFIX .. L.DESTROY_LOOT:format(best.link, GetMoneyString(best.value), target.link, GetMoneyString(target.value)))
end

local function ShowTooltip(self)
  local target = self.target
  if not target then return end
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:SetText("KeepOrSell")
  GameTooltip:AddLine(L.DESTROY_TIP:format(target.link, target.count, GetMoneyString(target.value)), 1, 1, 1, true)
  GameTooltip:AddLine(L.DESTROY_CLICK, 0.6, 0.6, 0.6, true)
  GameTooltip:Show()
end

local function CreateButton()
  local frame = CreateFrame("Button", nil, UIParent)
  frame:SetSize(20, 20)
  frame.Icon = frame:CreateTexture(nil, "ARTWORK")
  frame.Icon:SetAllPoints()
  frame.Cross = frame:CreateTexture(nil, "OVERLAY")
  frame.Cross:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
  frame.Cross:SetSize(12, 12)
  frame.Cross:SetPoint("BOTTOMRIGHT", 2, -2)
  frame:SetScript("OnEnter", ShowTooltip)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
  frame.Glow = frame:CreateTexture(nil, "OVERLAY")
  frame.Glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
  frame.Glow:SetBlendMode("ADD")
  frame.Glow:SetPoint("CENTER")
  frame.Glow:SetSize(28, 28)
  frame.Glow:Hide()
  frame.Pulse = frame.Glow:CreateAnimationGroup()
  frame.Pulse:SetLooping("BOUNCE")
  local fade = frame.Pulse:CreateAnimation("Alpha")
  fade:SetFromAlpha(1)
  fade:SetToAlpha(0.2)
  fade:SetDuration(0.6)
  frame:SetScript("OnClick", function(self)
    if ns.DestroyTarget(self.target) then
      GameTooltip:Hide()
      SetGlow(false)
    end
  end)
  frame:Hide()
  return frame
end

-- Adds the button to Baganator's bag window; false when Baganator can't take it
function ns.RegisterDestroy()
  local api = Baganator and Baganator.API
  if not (api and api.RegisterRegion and api.RequestLayoutUpdate) then return false end
  button = CreateButton()
  api.RegisterRegion("KeepOrSell", "keeporsell-destroy", "backpack", "bottom_left", button)
  return true
end

function ns.UpdateDestroy()
  if not button then return end
  local target = KeepOrSellDB.destroy and ns.FindDestroyTarget() or nil
  button.target = target
  if target then button.Icon:SetTexture(target.icon) end
  if button:IsMouseOver() and button:IsShown() then
    if target then ShowTooltip(button) else GameTooltip:Hide() end
  end
  local shown = target ~= nil
  if shown == button:IsShown() then return end -- no relayout needed
  -- a hidden region still takes its width in Baganator's row
  button:SetWidth(shown and 20 or 1)
  button:SetShown(shown)
  Baganator.API.RequestLayoutUpdate()
end
