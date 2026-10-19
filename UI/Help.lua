-- A "? KoS" button in Baganator's bag window; hovering it lists KeepOrSell's shortcuts, a click opens the options.
local _, ns = ...
local L = ns.L

-- Returns {{key, text}} rows for the shortcuts that work with the current options. Pure.
function ns.HelpLines(db)
  local lines = {}
  if db.keepClick then table.insert(lines, {L.HELP_KEEP_KEY, L.HELP_KEEP}) end
  if db.destroy then table.insert(lines, {L.HELP_DESTROY_KEY, L.HELP_DESTROY}) end
  table.insert(lines, {"/kos", L.HELP_OPTIONS})
  table.insert(lines, {"/kos kept", L.HELP_KEPT})
  table.insert(lines, {L.HELP_KEEP_COMMAND_KEY, L.HELP_KEEP_COMMAND})
  table.insert(lines, {"/kos export", L.HELP_EXPORT})
  table.insert(lines, {"/kos import", L.HELP_IMPORT})
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

-- A small Blizzard button "? KoS", so it reads as a button and says whose help it is
local function CreateButton()
  local frame = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
  frame:SetText(L.HELP_BUTTON)
  frame:SetSize(frame:GetTextWidth() + 20, 20)
  frame:SetScript("OnEnter", ShowTooltip)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
  frame:SetScript("OnClick", function() ns.OpenOptions() end)
  return frame
end

-- Adds the button to Baganator's bag window; false when Baganator can't take it
function ns.RegisterHelp()
  local api = Baganator and Baganator.API
  if not (api and api.RegisterRegion) then return false end
  api.RegisterRegion("KeepOrSell", "keeporsell-help", "backpack", "bottom_left", CreateButton())
  return true
end
