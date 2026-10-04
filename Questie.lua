-- Items a quest the player hasn't done yet still needs, from QuestieDB's public API (LibQuestieDB).
local _, ns = ...

local CONTRACT = 2   -- QuestieDB contract version this file was written against
local LEVEL_RANGE = 5
local ITEM_OBJECTIVES = 3 -- objectives = {creature, object, item, reputation, killCredit, spell}

local function HasBit(mask, index)
  return math.floor(mask / 2 ^ (index - 1)) % 2 == 1
end

local function Allowed(mask, index)
  return not mask or mask == 0 or not index or HasBit(mask, index)
end

-- quests: {id, name, level, requiredLevel, races, classes, exclusiveTo}; level -1 scales with the player
-- player: {level, race, class, completed = function(questID)}
-- Returns the open quest within LEVEL_RANGE of the player's level that is closest in level, or nil. Pure.
function ns.PickQuestieQuest(quests, player)
  local best, bestDistance
  for _, q in ipairs(quests) do
    local level = q.level
    if level == -1 then level = player.level end
    if not level or level <= 0 then level = q.requiredLevel end
    local distance = level and math.abs(level - player.level)
    local open = distance and distance <= LEVEL_RANGE
      and Allowed(q.races, player.race) and Allowed(q.classes, player.class)
      and not player.completed(q.id)
    for _, other in ipairs(q.exclusiveTo or {}) do
      if open and player.completed(other) then open = false end
    end
    if open and (not best or distance < bestDistance) then best, bestDistance = q, distance end
  end
  return best
end

local db -- LibQuestieDB once its contract is confirmed, false when missing or incompatible

local function QuestieDB()
  if db == nil then
    local lib = LibQuestieDB
    db = lib and lib.RequireContract and lib.Quest and lib.Quest.GetAllIds and lib.RequireContract(CONTRACT) and lib or false
  end
  return db
end

-- true if QuestieDB is loaded with a contract this file understands
function ns.HasQuestieDB()
  return QuestieDB() ~= false
end

-- Calls fn(itemID) for every item the quest needs: item objectives and required source items
local function ForEachNeededItem(Quest, questID, fn)
  local objectives = Quest.objectives(questID)
  for _, objective in ipairs(objectives and objectives[ITEM_OBJECTIVES] or {}) do
    if objective[1] then fn(objective[1]) end
  end
  for _, itemID in ipairs(Quest.requiredSourceItems(questID) or {}) do fn(itemID) end
end

-- Adds ids[first..last] to index (itemID -> {questID, ...}); a quest that fails to read is skipped.
-- Pure apart from the Quest reads.
function ns.IndexQuestItems(Quest, ids, first, last, index)
  for i = first, math.min(last, #ids) do
    local questID = ids[i]
    pcall(ForEachNeededItem, Quest, questID, function(itemID)
      local list = index[itemID]
      if not list then list = {}; index[itemID] = list end
      if list[#list] ~= questID then list[#list + 1] = questID end
    end)
  end
end

-- QuestieDB's relatedQuests is empty on some clients, so the item -> quest index is built here,
-- a chunk per frame after login so it never stalls the game
local CHUNK = 250
local index -- itemID -> {questID, ...}, nil until complete

-- Builds the index in the background; done() runs once it is complete. Without QuestieDB nothing happens.
function ns.BuildQuestieIndex(done)
  local lib = QuestieDB()
  if not lib or index then return end
  local ok, ids = pcall(lib.Quest.GetAllIds)
  if not (ok and type(ids) == "table") then return end
  local building, first = {}, 1
  local function Step()
    ns.IndexQuestItems(lib.Quest, ids, first, first + CHUNK - 1, building)
    first = first + CHUNK
    if first > #ids then
      index = building
      if done then done() end
    else
      C_Timer.After(0, Step)
    end
  end
  Step()
end

local function Lookup(lib, itemID)
  local Quest, quests = lib.Quest, {}
  for _, questID in ipairs(index[itemID] or {}) do
    table.insert(quests, {
      id = questID, name = Quest.name(questID), level = Quest.questLevel(questID),
      requiredLevel = Quest.requiredLevel(questID), races = Quest.requiredRaces(questID),
      classes = Quest.requiredClasses(questID), exclusiveTo = Quest.exclusiveTo(questID),
    })
  end
  local player = {
    level = UnitLevel("player"),
    race = select(3, UnitRace("player")),
    class = select(3, UnitClass("player")),
    completed = function(id) return C_QuestLog.IsQuestFlaggedCompleted(id) end,
  }
  return ns.PickQuestieQuest(quests, player)
end

-- {name, level} of an upcoming quest that needs the item, or nil (also without QuestieDB)
function ns.GetQuestieQuest(itemID)
  local lib = itemID and index and QuestieDB()
  if not (lib and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) then return nil end
  -- in doubt the item just isn't protected; a database error must not break the bags
  local ok, q = pcall(Lookup, lib, itemID)
  return ok and q and q.name and {name = q.name, level = q.level} or nil
end
