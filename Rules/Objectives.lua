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

-- Calls fn(text, type, finished, quest) for every objective in the quest log; quest = {questID, title, level}
-- on clients with C_QuestLog.GetInfo
local function ForEachObjective(fn)
  if C_QuestLog and C_QuestLog.GetInfo and C_QuestLog.GetQuestObjectives then
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
      local info = C_QuestLog.GetInfo(i)
      if info and not info.isHeader and info.questID then
        for _, o in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
          fn(o.text, o.type, o.finished, info)
        end
        -- the item the quest tracker shows a button for: the quest is done by using it
        local link = GetQuestLogSpecialItemInfo and GetQuestLogSpecialItemInfo(i)
        local name = type(link) == "string" and link:match("|h%[(.-)%]|h")
        if name then fn(name, "use", false, info) end
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

-- quests: {[questID] = {name, level, faction}} remembered for one item name; player: {faction, completed}.
-- Returns the open quest of the player's faction with the lowest level, or nil. Pure.
function ns.PickLearnedQuest(quests, player)
  local best
  for questID, q in pairs(quests or {}) do
    if q.faction == player.faction and not player.completed(questID)
        and (not best or (q.level or 0) < (best.level or 0)) then
      best = q
    end
  end
  return best
end

-- Quests in the log that QuestieDB doesn't know (Forever added them) are remembered account-wide by item
-- name in KeepOrSellDB.learnedQuests, so the player's other characters keep the item too. Only with
-- QuestieDB: without it every objective would look unknown, Linen Cloth included.
local function LearnQuests()
  if not (KeepOrSellDB and ns.QuestieKnowsQuest) then return end
  local faction = UnitFactionGroup and UnitFactionGroup("player")
  ForEachObjective(function(text, objType, _, quest)
    if not (quest and faction) or (objType ~= "item" and objType ~= "use") then return end
    local name = objType == "use" and text or ns.ParseObjectiveName(text)
    if not name or ns.QuestieKnowsQuest(quest.questID) ~= false then return end
    KeepOrSellDB.learnedQuests = KeepOrSellDB.learnedQuests or {}
    local learned = KeepOrSellDB.learnedQuests
    learned[name] = learned[name] or {}
    learned[name][quest.questID] = {name = quest.title, level = quest.level, faction = faction}
  end)
end

-- Rereads the quest log; true if anything changed
function ns.Refresh()
  LearnQuests()
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

-- {name, level} of a remembered quest this character hasn't done that needs the item, or nil
function ns.GetLearnedQuest(itemID)
  local learned = itemID and KeepOrSellDB and KeepOrSellDB.learnedQuests
  local name = learned and ItemName(itemID)
  if not (name and learned[name] and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) then return nil end
  return ns.PickLearnedQuest(learned[name], {
    faction = UnitFactionGroup and UnitFactionGroup("player"),
    completed = function(id) return C_QuestLog.IsQuestFlaggedCompleted(id) end,
  })
end
