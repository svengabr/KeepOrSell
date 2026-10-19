-- A question mark in Baganator's bag window; hovering it lists KeepOrSell's shortcuts, a click opens the options.
local _, ns = ...
local L = ns.L

-- Returns {{key, text}} rows for the shortcuts that work with the current options. Pure.
function ns.HelpLines(db)
  local lines = {}
  if db.keepClick then table.insert(lines, {L.HELP_KEEP_KEY, L.HELP_KEEP}) end
  if db.destroy then table.insert(lines, {L.HELP_DESTROY_KEY, L.HELP_DESTROY}) end
  table.insert(lines, {"/kos", L.HELP_OPTIONS})
  table.insert(lines, {"/kos kept", L.HELP_KEPT})
  table.insert(lines, {"/kos keep <item>", L.HELP_KEEP_COMMAND})
  table.insert(lines, {"/kos setup", L.HELP_SETUP})
  return lines
end

local function ShowTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:SetText("KeepOrSell")
  for _, line in ipairs(ns.HelpLines(KeepOrSellDB)) do
    GameTooltip:AddDoubleLine(line[1], line[2], 1, 0.82, 0, 1, 1, 1)
  end
  GameTooltip:AddLine(L.HINT_CLICK, 0.6, 0.6, 0.6, true)
  GameTooltip:Show()
end

-- a plain "?" in the game font, so no texture has to exist on the client
local function CreateButton()
  local frame = CreateFrame("Button", nil, UIParent)
  frame:SetSize(14, 20)
  frame.Text = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  frame.Text:SetPoint("CENTER")
  frame.Text:SetText("?")
  frame:SetScript("OnEnter", function(self)
    self.Text:SetTextColor(1, 1, 1)
    ShowTooltip(self)
  end)
  frame:SetScript("OnLeave", function(self)
    self.Text:SetTextColor(1, 0.82, 0)
    GameTooltip:Hide()
  end)
  frame:SetScript("OnClick", function() ns.OpenOptions() end)
  return frame
end

-- Adds the question mark to Baganator's bag window; false when Baganator can't take it
function ns.RegisterHelp()
  local api = Baganator and Baganator.API
  if not (api and api.RegisterRegion) then return false end
  api.RegisterRegion("KeepOrSell", "keeporsell-help", "backpack", "bottom_left", CreateButton())
  return true
end
