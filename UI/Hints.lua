-- Hints on what the player can do so KeepOrSell sorts better: open professions, rescan prices.
-- Shown as a small button in Baganator's bag window, otherwise once in chat after login.
local _, ns = ...
local L = ns.L

local PREFIX = "|cffffd200KeepOrSell:|r "

-- state: {auctionator, tsm, ahVisited, stale, unopened = {names}}. Returns a list of texts. Pure.
-- A missing price after a scan is no hint: nobody sells the item on the auction house.
function ns.CollectHints(state, db)
  local hints = {}
  if not state.auctionator then
    -- with TSM alone there are prices, just no scan or age to hint at
    if not state.tsm then table.insert(hints, L.HINT_NO_AUCTIONATOR) end
  elseif not state.ahVisited then
    table.insert(hints, L.HINT_NO_SCAN)
  elseif state.stale > 0 then
    table.insert(hints, L.HINT_STALE:format(db.maxAge, state.stale))
  end
  if db.profession and #state.unopened > 0 then
    table.insert(hints, L.HINT_PROFESSIONS:format(table.concat(state.unopened, ", ")))
  end
  return hints
end

local BAGS = NUM_BAG_SLOTS or 4

-- Counts bag items that stay only because their auction price is too old
local function CountStale()
  local stale = 0
  if not (C_Container and C_Container.GetContainerItemInfo) then return stale end
  for bag = 0, BAGS do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID then
        local location = ItemLocation and ItemLocation:CreateFromBagAndSlot(bag, slot)
        local verdict = ns.Classify(info.itemID, info.hyperlink, location)
        if verdict.needsPrice and verdict.priceReason == "stale" then stale = stale + 1 end
      end
    end
  end
  return stale
end

function ns.GetHints()
  return ns.CollectHints({
    auctionator = Auctionator and Auctionator.API and Auctionator.API.v1 and true or false,
    tsm = TSM_API and TSM_API.GetCustomPriceValue and true or false,
    ahVisited = KeepOrSellDB.ahVisited == true,
    stale = CountStale(),
    unopened = ns.UnopenedProfessions(),
  }, KeepOrSellDB)
end

local button

local function ShowTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:SetText("KeepOrSell")
  for _, hint in ipairs(self.hints or {}) do GameTooltip:AddLine(hint, 1, 1, 1, true) end
  GameTooltip:AddLine(ns.IsSetupComplete() and L.HINT_CLICK or L.HINT_CLICK_SETUP, 0.6, 0.6, 0.6, true)
  GameTooltip:Show()
end

local function CreateButton()
  local frame = CreateFrame("Button", nil, UIParent)
  frame:SetSize(20, 20)
  frame.Icon = frame:CreateTexture(nil, "ARTWORK")
  frame.Icon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
  frame.Icon:SetSize(18, 18)
  frame.Icon:SetPoint("LEFT")
  frame.Text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  frame.Text:SetPoint("LEFT", frame.Icon, "RIGHT", 2, 0)
  frame:SetScript("OnEnter", ShowTooltip)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- leads to the setup while required steps are open, otherwise to the options
  frame:SetScript("OnClick", function()
    if ns.IsSetupComplete() then ns.OpenOptions() else ns.ShowSetup() end
  end)
  frame:Hide()
  return frame
end

-- Adds the button to Baganator's bag window; false when Baganator can't take it
function ns.RegisterHints()
  local api = Baganator and Baganator.API
  if not (api and api.RegisterRegion and api.RequestLayoutUpdate) then return false end
  button = CreateButton()
  api.RegisterRegion("KeepOrSell", "keeporsell-hints", "backpack", "bottom_left", button)
  return true
end

function ns.UpdateHints()
  if not button then return end
  local hints = KeepOrSellDB.hints and ns.GetHints() or {}
  button.hints = hints
  local shown = #hints > 0
  if shown == button:IsShown() and #hints == button.count then return end -- no relayout needed
  button.count = #hints
  button.Text:SetText(L.HINT_COUNT:format(#hints))
  -- a hidden region still takes its width in Baganator's row
  button:SetWidth(shown and (22 + button.Text:GetStringWidth()) or 1)
  button:SetShown(shown)
  Baganator.API.RequestLayoutUpdate()
end

function ns.PrintHints()
  if not KeepOrSellDB.hints then return end
  for _, hint in ipairs(ns.GetHints()) do print(PREFIX .. hint) end
end
