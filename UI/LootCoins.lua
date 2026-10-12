-- Gold coins in Blizzard's loot window while the bags are full: loot worth more than the junk that would
-- make room for it. The loot tooltip names that junk; the destroy button glows.
local _, ns = ...
local L = ns.L

local COIN = "Interface\\MoneyFrame\\UI-GoldIcon"
local RETRY_DELAY, MAX_RETRIES = 0.1, 10 -- the loot window fills in a moment after LOOT_OPENED

local looting = false
local bySlot = {} -- loot slot -> pair (see ns.PairLoot) worth destroying its junk for
local coins = {}  -- loot row -> coin texture
local callbackOwner = {} -- owner of our callback on the loot list
local hooked, queued, retries = false, false, 0

-- loot slot shown by a loot row, or by the item button inside it
local function SlotOf(frame)
  if not frame then return nil end
  if frame.GetSlotIndex then return frame:GetSlotIndex() end
  local parent = frame.GetParent and frame:GetParent()
  return parent and parent.GetSlotIndex and parent:GetSlotIndex() or nil
end

-- Rows are reused while the list scrolls and after looting, so each one shows the coin of its current slot
local function UpdateRow(frame)
  local slot = SlotOf(frame)
  local show = slot ~= nil and bySlot[slot] ~= nil
  local coin = coins[frame]
  if not show then
    if coin then coin:Hide() end
    return
  end
  if not coin then
    coin = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    coin:SetTexture(COIN)
    coin:SetSize(18, 18)
    coin:SetPoint("CENTER", frame.Item or frame, "TOPRIGHT", -4, -4)
    coins[frame] = coin
  end
  coin:Show()
end

local function ScrollBox()
  return LootFrame and LootFrame.ScrollBox
end

local function UpdateRows()
  local box = ScrollBox()
  if box and box.ForEachFrame then box:ForEachFrame(UpdateRow) end
end

local function HookRows()
  local box = ScrollBox()
  if hooked or not (box and ScrollUtil and ScrollUtil.AddInitializedFrameCallback) then return end
  ScrollUtil.AddInitializedFrameCallback(box, function(_, frame) UpdateRow(frame) end, callbackOwner, false)
  hooked = true
end

-- true if an item in the loot window has no link yet (item data not loaded); money has no quantity
local function Incomplete()
  for slot = 1, GetNumLootItems() do
    local _, _, quantity, currencyID = GetLootSlotInfo(slot)
    if not GetLootSlotLink(slot) and (quantity or 0) > 0 and not currencyID then return true end
  end
  return false
end

local Schedule

local function Refresh()
  queued = false
  bySlot = {}
  local db = KeepOrSellDB
  if looting and db and (db.lootCoins or db.destroy) and GetNumLootItems then
    local paired = ns.PairLoot(ns.LootItems(), ns.DestroyCandidates(), ns.FreeSlots())
    local worth = false
    for _, pair in ipairs(paired) do
      if pair.target and pair.worth then
        worth = true
        if db.lootCoins then bySlot[pair.loot.slot] = pair end
      end
    end
    ns.SetDestroyGlow(worth)
    if Incomplete() and retries < MAX_RETRIES then
      retries = retries + 1
      C_Timer.After(RETRY_DELAY, Schedule)
    end
  end
  HookRows()
  UpdateRows()
end

-- once per frame: looting fires several events at once
Schedule = function()
  if queued then return end
  queued = true
  C_Timer.After(0, Refresh)
end

function ns.LootCoinsOpened()
  looting, retries = true, 0
  Schedule()
end

-- a slot was looted, or the bags changed (junk destroyed, loot stacked)
function ns.LootCoinsChanged()
  if looting then Schedule() end
end

function ns.LootCoinsClosed()
  looting = false
  bySlot = {}
  for _, coin in pairs(coins) do coin:Hide() end
end

-- Tooltip line for the loot row owning the tooltip, or nil
function ns.LootTooltipNote(owner)
  local pair = bySlot[SlotOf(owner)]
  if not pair then return nil end
  return L.LOOT_TIP:format(pair.target.link, GetMoneyString(pair.target.value))
end

-- loot slot -> pair, for the tests
function ns.LootCoinSlots()
  return bySlot
end
