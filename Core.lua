-- Einstellungen, Ereignisse und /bqm
local addonName, ns = ...

local DEFAULTS = {setSource = true, factor = 2}

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

frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == addonName then
    BagQuestMarksDB = BagQuestMarksDB or {}
    for k, v in pairs(DEFAULTS) do
      if BagQuestMarksDB[k] == nil then BagQuestMarksDB[k] = v end
    end
  elseif event == "PLAYER_LOGIN" then
    ns.Refresh()
    ns.RegisterBaganator()
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

SLASH_BAGQUESTMARKS1 = "/bqm"
SlashCmdList.BAGQUESTMARKS = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  local factor = tonumber(msg:match("^faktor%s+([%d%.]+)$"))
  if factor and factor > 0 then
    BagQuestMarksDB.factor = factor
    ns.RefreshBaganator()
    print(("|cffffd200BagQuestMarks:|r Auktionshaus ab %sx Händlerpreis."):format(factor))
  elseif msg == "set" then
    BagQuestMarksDB.setSource = not BagQuestMarksDB.setSource
    print("|cffffd200BagQuestMarks:|r Questziele als Set " .. (BagQuestMarksDB.setSource and "an" or "aus") .. " – wirkt nach /reload.")
  else
    local n = 0
    for name, state in pairs(ns.items) do
      n = n + 1
      print(("  %s (%s)"):format(name, state == "open" and "offen" or "erfüllt"))
    end
    print(("|cffffd200BagQuestMarks:|r %d Questziel-Items. Set-Modus: %s (/bqm set), Auktionshaus ab %sx Händlerpreis (/bqm faktor 2)"):format(n, BagQuestMarksDB.setSource and "an" or "aus", BagQuestMarksDB.factor))
  end
end
