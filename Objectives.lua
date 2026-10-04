-- Reads item quest objectives from the quest log. Pure logic, no Baganator.
local _, ns = ...

-- "6/10 Lean Wolf Flank" (retail format) or "Lean Wolf Flank: 6/10" (classic format)
function ns.ParseObjectiveName(text)
  if type(text) ~= "string" then return nil end
  local name = text:match("^%s*%d+%s*/%s*%d+%s+(.-)%s*$")
    or text:match("^%s*(.-)%s*:%s*%d+%s*/%s*%d+%s*$")
    or text:match("^%s*(.-)%s*$")
  if name == "" then return nil end
  return name
end

-- Calls fn(text, type, finished) for every objective in the quest log
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

-- Returns {[itemName] = "open" | "done"}; "open" wins when several quests need the item
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

-- Rereads the quest log; true if anything changed
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

-- "open" | "done" | false (no objective) | nil (item name not cached yet)
function ns.GetObjectiveState(itemID)
  if not itemID then return false end
  local name = ItemName(itemID)
  if not name then return nil end
  return ns.items[name] or false
end
