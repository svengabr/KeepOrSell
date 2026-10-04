-- Saved variables, events and /kos
local addonName, ns = ...

local DEFAULTS = {
  setSource = true, factor = 2, scrap = true, minProfit = 0, maxAge = 7,
  profession = true, gear = true, plainGear = true, recipeJunk = true, questie = true, tooltip = true, hints = true, share = true,
}

local frame = CreateFrame("Frame")

-- QUEST_LOG_UPDATE and TRADE_SKILL_LIST_UPDATE often fire in bursts; once per frame is enough.
-- update returns true when something changed.
local function OncePerFrame(update)
  local pending = false
  return function()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
      pending = false
      if update() then ns.RefreshBaganator() end
    end)
  end
end

local ScheduleQuests = OncePerFrame(function() return ns.Refresh() end)
local ScheduleProfession = OncePerFrame(function() return ns.ScanProfession() end)
local ScheduleHints = OncePerFrame(function() ns.UpdateHints() end)

local HINT_DELAY = 5 -- seconds after login, so bags and item data are loaded

-- Called by the options panel
function ns.SettingsChanged()
  ns.RefreshBaganator()
  ScheduleHints()
end

frame:SetScript("OnEvent", function(_, event, arg1, ...)
  if event == "ADDON_LOADED" and arg1 == addonName then
    KeepOrSellDB = KeepOrSellDB or {}
    for k, v in pairs(DEFAULTS) do
      if KeepOrSellDB[k] == nil then KeepOrSellDB[k] = v end
    end
    -- not in DEFAULTS: a table there would be shared by reference; both are kept per auction house
    KeepOrSellDB.sharedPrices = KeepOrSellDB.sharedPrices or {}
    KeepOrSellDB.fullScans = KeepOrSellDB.fullScans or {}
    -- 0.8.0/0.8.1 kept shared prices by item ID for all realms; without a realm they can't be trusted
    for key in pairs(KeepOrSellDB.sharedPrices) do
      if type(key) ~= "string" then KeepOrSellDB.sharedPrices[key] = nil end
    end
    -- older versions allowed a lower threshold
    KeepOrSellDB.factor = math.max(KeepOrSellDB.factor, ns.MIN_FACTOR)
    ns.RegisterOptions(KeepOrSellDB, DEFAULTS)
    -- hook early, before other addons query Scrap:IsJunk
    ns.HookScrap()
  elseif event == "PLAYER_LOGIN" then
    ns.Refresh()
    ns.RegisterBaganator()
    ns.HookTooltip()
    for _, prices in pairs(KeepOrSellDB.sharedPrices) do ns.PruneSharedPrices(prices, GetServerTime()) end
    ns.RegisterShare()
    ns.ScheduleShareQuery()
    ns.BuildQuestieIndex(ns.RefreshBaganator)
    local inBags = ns.RegisterHints()
    C_Timer.After(HINT_DELAY, inBags and ScheduleHints or ns.PrintHints)
    frame:RegisterEvent("QUEST_LOG_UPDATE")
    frame:RegisterEvent("TRADE_SKILL_SHOW")
    frame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
    frame:RegisterEvent("BAG_UPDATE_DELAYED")
    frame:RegisterEvent("SKILL_LINES_CHANGED")
    frame:RegisterEvent("PLAYER_LEVEL_UP")
    frame:RegisterEvent("QUEST_TURNED_IN")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("CHAT_MSG_ADDON")
  elseif event == "QUEST_LOG_UPDATE" then
    ScheduleQuests()
  elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" then
    ScheduleProfession()
    ScheduleHints()
  elseif event == "BAG_UPDATE_DELAYED" then
    ScheduleHints()
    ns.ScheduleShareQuery()
  elseif event == "SKILL_LINES_CHANGED" then
    ScheduleHints()
  elseif event == "GROUP_ROSTER_UPDATE" then
    ns.ShareRosterChanged()
  elseif event == "CHAT_MSG_ADDON" then
    ns.HandleShareMessage(arg1, ...)
  elseif event == "PLAYER_LEVEL_UP" or event == "QUEST_TURNED_IN" then
    -- moves the level window for upcoming Questie quests or completes one of them
    ns.RefreshBaganator()
  elseif event == "AUCTION_HOUSE_SHOW" then
    KeepOrSellDB.ahVisited = true
    ns.ShareAuctionHouseShown()
  elseif event == "AUCTION_HOUSE_CLOSED" then
    -- an Auctionator scan brings new prices
    ns.RefreshBaganator()
    ScheduleHints()
    ns.ShareAuctionHouseClosed()
  elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
    ns.ShareFullScanArrived()
  end
end)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("AUCTION_HOUSE_SHOW")
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
-- full scan data; clients with the legacy auction house don't know this event
if C_AuctionHouse and C_AuctionHouse.ReplicateItems then frame:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE") end

SLASH_KEEPORSELL1 = "/kos"
SlashCmdList.KEEPORSELL = function() ns.OpenOptions() end
