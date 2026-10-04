-- Einstellungen, Ereignisse und /kos
local addonName, ns = ...

local DEFAULTS = {setSource = true, factor = 2, scrap = true}

local L = ns.L
local PREFIX = "|cffffd200KeepOrSell:|r "

local frame = CreateFrame("Frame")
local pending = false

-- QUEST_LOG_UPDATE feuert oft hintereinander; einmal pro Frame reicht
local function ScheduleRefresh()
  if pending then return end
  pending = true
  C_Timer.After(0, function()
    pending = false
    if ns.Refresh() then ns.RefreshBaganator() end
  end)
end

-- Ergebnis von ns.SetupBaganatorCategories im Chat melden (nil = nichts passiert)
local function ReportSetup(result)
  if result then
    print(PREFIX .. L.SETUP_DONE:format(L.CAT_QUEST, L.SET_AH))
  elseif result == false then
    print(PREFIX .. L.SETUP_FAILED)
  end
end

frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == addonName then
    KeepOrSellDB = KeepOrSellDB or {}
    for k, v in pairs(DEFAULTS) do
      if KeepOrSellDB[k] == nil then KeepOrSellDB[k] = v end
    end
    -- früh einhaken, bevor andere Addons Scrap:IsJunk abfragen
    ns.HookScrap()
  elseif event == "PLAYER_LOGIN" then
    ns.Refresh()
    ns.RegisterBaganator()
    ReportSetup(ns.SetupBaganatorCategories())
    frame:RegisterEvent("QUEST_LOG_UPDATE")
  elseif event == "QUEST_LOG_UPDATE" then
    ScheduleRefresh()
  elseif event == "AUCTION_HOUSE_CLOSED" then
    -- nach einem Auctionator-Scan gibt es neue Preise
    ns.RefreshBaganator()
  end
end)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")

local function OnOff(v) return v and L.ON or L.OFF end

SLASH_KEEPORSELL1 = "/kos"
SlashCmdList.KEEPORSELL = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  local factor = tonumber(msg:match("^fa[kc]tor%s+([%d%.]+)$"))
  local db = KeepOrSellDB
  if factor and factor > 0 then
    db.factor = factor
    ns.RefreshBaganator()
    print(PREFIX .. L.FACTOR_SET:format(factor))
  elseif msg == "scrap" then
    db.scrap = not db.scrap
    ns.RefreshBaganator()
    print(PREFIX .. L.SCRAP_TOGGLED:format(OnOff(db.scrap)))
  elseif msg == "setup" then
    if not (Baganator and Baganator.API) then
      print(PREFIX .. L.SETUP_NO_BAGANATOR)
    else
      ReportSetup(ns.SetupBaganatorCategories(true) or false)
    end
  elseif msg == "sets" then
    db.setSource = not db.setSource
    print(PREFIX .. L.SETS_TOGGLED:format(OnOff(db.setSource)))
  else
    local n = 0
    for name, state in pairs(ns.items) do
      n = n + 1
      print(("  %s (%s)"):format(name, state == "open" and L.OPEN or L.DONE))
    end
    print(PREFIX .. L.STATUS:format(n, db.factor, OnOff(db.scrap), OnOff(db.setSource)))
  end
end
