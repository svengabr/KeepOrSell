-- Saved variables, events and /kos
local addonName, ns = ...

local DEFAULTS = {
  setSource = true, factor = 2, scrap = true, minProfit = 0, maxAge = 7,
  profession = true, gear = true, plainGear = true, tooltip = true, hints = true,
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

frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == addonName then
    KeepOrSellDB = KeepOrSellDB or {}
    for k, v in pairs(DEFAULTS) do
      if KeepOrSellDB[k] == nil then KeepOrSellDB[k] = v end
    end
    ns.RegisterOptions(KeepOrSellDB, DEFAULTS)
    -- hook early, before other addons query Scrap:IsJunk
    ns.HookScrap()
  elseif event == "PLAYER_LOGIN" then
    ns.Refresh()
    ns.RegisterBaganator()
    ns.HookTooltip()
    local inBags = ns.RegisterHints()
    C_Timer.After(HINT_DELAY, inBags and ScheduleHints or ns.PrintHints)
    frame:RegisterEvent("QUEST_LOG_UPDATE")
    frame:RegisterEvent("TRADE_SKILL_SHOW")
    frame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
    frame:RegisterEvent("BAG_UPDATE_DELAYED")
    frame:RegisterEvent("SKILL_LINES_CHANGED")
  elseif event == "QUEST_LOG_UPDATE" then
    ScheduleQuests()
  elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" then
    ScheduleProfession()
    ScheduleHints()
  elseif event == "BAG_UPDATE_DELAYED" or event == "SKILL_LINES_CHANGED" then
    ScheduleHints()
  elseif event == "AUCTION_HOUSE_SHOW" then
    KeepOrSellDB.ahVisited = true
  elseif event == "AUCTION_HOUSE_CLOSED" then
    -- an Auctionator scan brings new prices
    ns.RefreshBaganator()
    ScheduleHints()
  end
end)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("AUCTION_HOUSE_SHOW")
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")

SLASH_KEEPORSELL1 = "/kos"
SlashCmdList.KEEPORSELL = function() ns.OpenOptions() end
