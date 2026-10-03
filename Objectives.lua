-- Liest die Item-Questziele aus dem Questlog. Reine Logik, ohne Baganator.
local _, ns = ...

-- "6/10 Magere Wolfflanke" (Retail-Format) oder "Magere Wolfflanke: 6/10" (Classic-Format)
function ns.ParseObjectiveName(text)
  if type(text) ~= "string" then return nil end
  local name = text:match("^%s*%d+%s*/%s*%d+%s+(.-)%s*$")
    or text:match("^%s*(.-)%s*:%s*%d+%s*/%s*%d+%s*$")
    or text:match("^%s*(.-)%s*$")
  if name == "" then return nil end
  return name
end

-- Ruft fn(text, type, finished) für jedes Questziel im Log auf
local function ForEachObjective(fn)
  if C_QuestLog and C_QuestLog.GetInfo and C_QuestLog.GetQuestObjectives then
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
      local info = C_QuestLog.GetInfo(i)
      if info and not info.isHeader and info.questID then
        for _, o in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
          fn(o.text, o.type, o.finished)
        end
      end
    end
  elseif GetQuestLogTitle then
    for i = 1, GetNumQuestLogEntries() do
      local _, _, _, isHeader = GetQuestLogTitle(i)
      if not isHeader then
        for j = 1, GetNumQuestLeaderBoards(i) do
          fn(GetQuestLogLeaderBoard(j, i))
        end
      end
    end
  end
end

-- Liefert {[Itemname] = "open" | "done"}; "open" gewinnt, wenn mehrere Quests das Item brauchen
function ns.CollectObjectiveItems()
  local items = {}
  ForEachObjective(function(text, objType, finished)
    if objType ~= "item" then return end
    local name = ns.ParseObjectiveName(text)
    if name and items[name] ~= "open" then
      items[name] = finished and "done" or "open"
    end
  end)
  return items
end

ns.items = {}

-- Liest das Questlog neu ein; true, wenn sich etwas geändert hat
function ns.Refresh()
  local new = ns.CollectObjectiveItems()
  local changed = false
  for k, v in pairs(new) do
    if ns.items[k] ~= v then changed = true end
  end
  for k in pairs(ns.items) do
    if new[k] == nil then changed = true end
  end
  ns.items = new
  return changed
end

local function ItemName(itemID)
  if C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(itemID) end
  return (GetItemInfo(itemID))
end

-- "open" | "done" | false (kein Questziel) | nil (Itemname noch nicht im Cache)
function ns.GetObjectiveState(itemID)
  if not itemID then return false end
  local name = ItemName(itemID)
  if not name then return nil end
  return ns.items[name] or false
end
