-- The worth of the bags at a glance: junk at the vendor and the AuctionHouse group at auction.
-- Shown as a line in Baganator's bag window; the tooltip lists the most valuable auction items.
local _, ns = ...
local L = ns.L

local TOP = 3

-- items: list from ns.ScanBags. Returns {junk, ah, junkCount, ahCount, top}; top = the most
-- valuable auction items, best first. Pure.
function ns.SumBagValue(items)
  local total = {junk = 0, ah = 0, junkCount = 0, ahCount = 0, top = {}}
  local auction = {}
  for _, item in ipairs(items) do
    if item.junk then
      total.junk = total.junk + item.value
      total.junkCount = total.junkCount + 1
    elseif item.ah then
      total.ah = total.ah + item.ah
      total.ahCount = total.ahCount + 1
      table.insert(auction, item)
    end
  end
  table.sort(auction, function(a, b) return a.ah > b.ah end)
  for i = 1, math.min(TOP, #auction) do total.top[i] = auction[i] end
  return total
end

-- "Junk 1g 20s · AH 15g", leaving out a part worth nothing; nil when both are
function ns.FormatBagValue(total)
  local parts = {}
  if total.junk > 0 then table.insert(parts, L.VALUE_JUNK:format(GetMoneyString(total.junk))) end
  if total.ah > 0 then table.insert(parts, L.VALUE_AH:format(GetMoneyString(total.ah))) end
  if #parts == 0 then return nil end
  return table.concat(parts, " · ")
end

local frame

local function ShowTooltip(self)
  local total = self.total
  if not total then return end
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:SetText("KeepOrSell")
  GameTooltip:AddDoubleLine(L.VALUE_JUNK_TIP:format(total.junkCount), GetMoneyString(total.junk), 1, 1, 1, 1, 1, 1)
  GameTooltip:AddDoubleLine(L.VALUE_AH_TIP:format(total.ahCount), GetMoneyString(total.ah), 1, 1, 1, 1, 1, 1)
  for _, item in ipairs(total.top) do
    GameTooltip:AddDoubleLine("  " .. item.link .. (item.count > 1 and " ×" .. item.count or ""),
      GetMoneyString(item.ah), 1, 1, 1, 0.8, 0.8, 0.8)
  end
  GameTooltip:Show()
end

local function CreateLine()
  local line = CreateFrame("Frame", nil, UIParent)
  line:SetSize(20, 20)
  line.Text = line:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  line.Text:SetPoint("LEFT", 4, 0)
  line:SetScript("OnEnter", ShowTooltip)
  line:SetScript("OnLeave", function() GameTooltip:Hide() end)
  line:Hide()
  return line
end

-- Adds the line to Baganator's bag window; false when Baganator can't take it
function ns.RegisterBagValue()
  local api = Baganator and Baganator.API
  if not (api and api.RegisterRegion and api.RequestLayoutUpdate) then return false end
  frame = CreateLine()
  api.RegisterRegion("KeepOrSell", "keeporsell-value", "backpack", "bottom_left", frame)
  return true
end

function ns.UpdateBagValue()
  if not frame then return end
  local total = KeepOrSellDB.bagValue and ns.SumBagValue(ns.ScanBags()) or nil
  local text = total and ns.FormatBagValue(total)
  frame.total = total
  local shown = text ~= nil
  if shown and text == frame.text and frame:IsShown() then return end -- no relayout needed
  if not shown and not frame:IsShown() then return end
  frame.text = text
  frame.Text:SetText(text or "")
  -- a hidden region still takes its width in Baganator's row
  frame:SetWidth(shown and (8 + frame.Text:GetStringWidth()) or 1)
  frame:SetShown(shown)
  Baganator.API.RequestLayoutUpdate()
end
