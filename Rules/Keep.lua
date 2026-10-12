-- Items the player marked to keep (Alt+Right-click in the bags, or /kos keep): never junk, auction house or
-- disenchant, also without Scrap. Kept by item ID for the whole account in KeepOrSellDB.keep.
local _, ns = ...
local L = ns.L

local PREFIX = "|cffffd200KeepOrSell:|r "

local function List()
  KeepOrSellDB.keep = KeepOrSellDB.keep or {}
  return KeepOrSellDB.keep
end

function ns.IsKept(itemID)
  return itemID ~= nil and KeepOrSellDB ~= nil and KeepOrSellDB.keep ~= nil and KeepOrSellDB.keep[itemID] == true
end

local function ItemText(itemID)
  return select(2, (C_Item.GetItemInfo or GetItemInfo)(itemID)) or ("item:" .. itemID)
end

-- keep = true marks the item, false drops the mark; tells the player and sorts the bags again
function ns.SetKept(itemID, keep)
  if not itemID then return end
  List()[itemID] = keep and true or nil
  print(PREFIX .. (keep and L.KEEP_ON or L.KEEP_OFF):format(ItemText(itemID)))
  ns.SettingsChanged()
  if GameTooltip and GameTooltip:IsShown() and GameTooltip.RefreshData then GameTooltip:RefreshData() end
end

-- Drops every mark; returns how many there were
function ns.ForgetKept()
  local n = 0
  for _ in pairs(List()) do n = n + 1 end
  KeepOrSellDB.keep = {}
  print(PREFIX .. L.KEEP_FORGOTTEN:format(n))
  ns.SettingsChanged()
  return n
end

function ns.PrintKept()
  local links = {}
  for itemID in pairs(List()) do table.insert(links, ItemText(itemID)) end
  table.sort(links)
  print(PREFIX .. (#links > 0 and L.KEEP_LIST:format(table.concat(links, " ")) or L.KEEP_LIST_EMPTY))
end

-- true for the click that toggles the mark: Alt+Right-click without Ctrl or Shift. Pure.
function ns.IsKeepClick(button, alt, ctrl, shift)
  return button == "RightButton" and alt and not ctrl and not shift or false
end

-- Bag buttons (Blizzard's and Baganator's live bags, both from ContainerFrameItemButtonTemplate) call
-- HandleModifiedItemClick(link, itemLocation) on a modified click; Alt+Right-click does nothing else there
local function OnModifiedItemClick(link, location)
  if not (KeepOrSellDB and KeepOrSellDB.keepClick and link) then return end
  if not (location and location.IsBagAndSlot and location:IsBagAndSlot()) then return end
  local button = GetMouseButtonClicked and GetMouseButtonClicked()
  if not ns.IsKeepClick(button, IsAltKeyDown(), IsControlKeyDown(), IsShiftKeyDown()) then return end
  local itemID = C_Item.GetItemInfoInstant(link)
  if itemID then ns.SetKept(itemID, not ns.IsKept(itemID)) end
end

function ns.HookKeepClick()
  if HandleModifiedItemClick then hooksecurefunc("HandleModifiedItemClick", OnModifiedItemClick) end
end

local function ItemID(text)
  local id = text and (text:match("item:(%d+)") or text:match("^%s*(%d+)%s*$"))
  return id and tonumber(id)
end

-- /kos keep|unkeep <item link or ID>, /kos kept; returns true when msg was one of these
function ns.HandleKeepCommand(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  if cmd == "kept" then
    ns.PrintKept()
    return true
  end
  if cmd ~= "keep" and cmd ~= "unkeep" then return false end
  local itemID = ItemID(rest)
  if itemID then
    ns.SetKept(itemID, cmd == "keep")
  else
    print(PREFIX .. L.KEEP_USAGE:format(cmd))
  end
  return true
end
