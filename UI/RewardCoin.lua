-- Gold coin on the quest reward choice that sells to a vendor for the most. KeepOrSell doesn't judge
-- upgrades; the coin only says which choice is worth the most gold. The reward tooltip says why.
local _, ns = ...
local L = ns.L

local COIN = "Interface\\MoneyFrame\\UI-GoldIcon"
local RETRY_DELAY, MAX_RETRIES = 0.2, 10 -- reward items may not be cached when the window opens

local coins = {}  -- reward button -> coin texture
local best = {}   -- reward button -> total vendor value, for the buttons with a coin
local hooked, retries = false, 0

-- Pure: the choices worth the most at a vendor (price × count), as a set of their indices, or {} when there
-- is nothing to choose (fewer than two choices), a price is still unknown, or no choice sells at all.
-- choices = {{index, price, count}}; ties all get the coin.
function ns.BestRewardChoices(choices)
  local result = {}
  if #choices < 2 then return result end
  local top = 0
  for _, choice in ipairs(choices) do
    if choice.price == nil then return {} end
    top = math.max(top, choice.price * (choice.count or 1))
  end
  if top <= 0 then return result end
  for _, choice in ipairs(choices) do
    if choice.price * (choice.count or 1) == top then result[choice.index] = top end
  end
  return result
end

local function VendorPrice(link)
  if not link then return nil end
  local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
  local name, _, _, _, _, _, _, _, _, _, price = getInfo(link)
  if not name then return nil end -- not cached yet
  return price or 0
end

-- shown choice buttons of the reward panel and what they offer
local function Choices(rewardsFrame, questLog)
  local choices, buttons = {}, {}
  for _, button in ipairs(rewardsFrame.RewardButtons or {}) do
    if button.type == "choice" and button:IsShown() then
      local i = button:GetID()
      local link, count
      if questLog then
        link = GetQuestLogItemLink("choice", i)
        count = select(3, GetQuestLogChoiceInfo(i))
      else
        link = GetQuestItemLink("choice", i)
        count = select(3, GetQuestItemInfo("choice", i))
      end
      table.insert(choices, {index = i, price = VendorPrice(link), count = count or 1})
      buttons[i] = button
    end
  end
  return choices, buttons
end

local function ShowCoin(button, show)
  local coin = coins[button]
  if not show then
    if coin then coin:Hide() end
    return
  end
  if not coin then
    coin = button:CreateTexture(nil, "OVERLAY", nil, 7)
    coin:SetTexture(COIN)
    coin:SetSize(18, 18)
    coin:SetPoint("CENTER", button.Icon or button, "TOPRIGHT", -4, -4)
    coins[button] = coin
  end
  coin:Show()
end

local Update

local function Retry()
  if retries >= MAX_RETRIES then return end
  retries = retries + 1
  C_Timer.After(RETRY_DELAY, Update)
end

Update = function()
  for button in pairs(coins) do ShowCoin(button, false) end
  best = {}
  local rewardsFrame = QuestInfoFrame and QuestInfoFrame.rewardsFrame
  if not (KeepOrSellDB and KeepOrSellDB.rewardCoin and rewardsFrame and rewardsFrame:IsShown()) then return end
  local choices, buttons = Choices(rewardsFrame, QuestInfoFrame.questLog)
  for _, choice in ipairs(choices) do
    if choice.price == nil then return Retry() end
  end
  for index, value in pairs(ns.BestRewardChoices(choices)) do
    local button = buttons[index]
    best[button] = value
    ShowCoin(button, true)
  end
end

-- QuestInfo_Display draws the rewards for the quest giver's panels and the quest log
function ns.HookRewardCoin()
  if hooked or not (hooksecurefunc and QuestInfo_Display) then return end
  hooksecurefunc("QuestInfo_Display", function()
    retries = 0
    Update()
  end)
  hooked = true
end

-- Tooltip line for a reward button with a coin, or nil
function ns.RewardTooltipNote(owner)
  local value = owner and best[owner]
  if not value then return nil end
  return L.REWARD_TIP:format(GetMoneyString(value))
end
