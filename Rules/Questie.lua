-- Items a quest the player hasn't done yet still needs, from QuestieDB's public API (LibQuestieDB).
local _, ns = ...

local CONTRACT = 2   -- QuestieDB contract version this file was written against
local LEVEL_RANGE = 5
local ITEM_OBJECTIVES = 3 -- objectives = {creature, object, item, reputation, killCredit, spell}
local ITEM_STARTERS = 3   -- startedBy = {creature, object, item}

local function HasBit(mask, index)
  return math.floor(mask / 2 ^ (index - 1)) % 2 == 1
end

local function Allowed(mask, index)
  return not mask or mask == 0 or not index or HasBit(mask, index)
end

-- Race IDs up to 11 sit at bit raceID - 1 of QuestieDB's race mask; newer races (e.g. 95, High Order Skyborn)
-- get a high bit there that can't be derived from the ID, so the classic races of the player's faction decide
local LAST_CLASSIC_RACE = 11
local FACTION_RACES = {Alliance = {1, 3, 4, 7, 11}, Horde = {2, 5, 6, 8, 10}}

local function RaceAllowed(mask, player)
  if Allowed(mask, player.race) then return true end
  if not player.race or player.race <= LAST_CLASSIC_RACE then return false end
  for _, race in ipairs(FACTION_RACES[player.faction] or {}) do
    if HasBit(mask, race) then return true end
  end
  return false
end

-- quests: {id, name, level, requiredLevel, races, classes, exclusiveTo}; level -1 scales with the player
-- player: {level, race, faction, class, completed = function(questID)}
-- Returns the open quest within range (default LEVEL_RANGE) of the player's level that is closest in level,
-- or nil. Pure.
function ns.PickQuestieQuest(quests, player, range)
  range = range or LEVEL_RANGE
  local best, bestDistance
  for _, q in ipairs(quests) do
    local level = q.level
    if level == -1 then level = player.level end
    if not level or level <= 0 then level = q.requiredLevel end
    local distance = level and math.abs(level - player.level)
    local open = distance and distance <= range
      and RaceAllowed(q.races, player) and Allowed(q.classes, player.class)
      and not player.completed(q.id)
    for _, other in ipairs(q.exclusiveTo or {}) do
      if open and player.completed(other) then open = false end
    end
    if open and (not best or distance < bestDistance) then best, bestDistance = q, distance end
  end
  return best
end

-- For an item of the quest item class: the quest it belongs to, at any level. Prefers an open quest
-- (closest in level), otherwise one the player has done, marked done = true; nil if none. Pure.
function ns.PickQuestItemQuest(quests, player)
  local open = ns.PickQuestieQuest(quests, player, math.huge)
  if open then return open end
  for _, q in ipairs(quests) do
    if player.completed(q.id) then return {id = q.id, name = q.name, level = q.level, done = true} end
  end
  return nil
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

-- Calls fn(itemID, questOnly) for every item the quest needs: item objectives, required source items,
-- items that start it and the item it hands out. questOnly = the item exists only for this quest
-- (starter or handed out); an objective like Linen Cloth has other uses.
local function ForEachNeededItem(Quest, questID, fn)
  local objectives = Quest.objectives(questID)
  for _, objective in ipairs(objectives and objectives[ITEM_OBJECTIVES] or {}) do
    if objective[1] then fn(objective[1]) end
  end
  for _, itemID in ipairs(Quest.requiredSourceItems(questID) or {}) do fn(itemID) end
  local startedBy = Quest.startedBy and Quest.startedBy(questID)
  for _, itemID in ipairs(startedBy and startedBy[ITEM_STARTERS] or {}) do fn(itemID, true) end
  local sourceItem = Quest.sourceItemId and Quest.sourceItemId(questID)
  if sourceItem and sourceItem ~= 0 then fn(sourceItem, true) end
end

-- Adds ids[first..last] to index (itemID -> {questID, ...}) and items that exist only for a quest to
-- questOnly (itemID -> true); a quest that fails to read is skipped. Pure apart from the Quest reads.
function ns.IndexQuestItems(Quest, ids, first, last, index, questOnly)
  for i = first, math.min(last, #ids) do
    local questID = ids[i]
    pcall(ForEachNeededItem, Quest, questID, function(itemID, only)
      local list = index[itemID]
      if not list then list = {}; index[itemID] = list end
      if list[#list] ~= questID then list[#list + 1] = questID end
      if only and questOnly then questOnly[itemID] = true end
    end)
  end
end

-- QuestieDB's relatedQuests is empty on some clients, so the item -> quest index is built here,
-- a chunk per frame after login so it never stalls the game
local CHUNK = 250
local index -- itemID -> {questID, ...}, nil until complete
local questOnly = {} -- itemID -> true for quest starters and items a quest hands out, filled with index

-- Builds the index in the background; done() runs once it is complete. Without QuestieDB nothing happens.
function ns.BuildQuestieIndex(done)
  local lib = QuestieDB()
  if not lib or index then return end
  local ok, ids = pcall(lib.Quest.GetAllIds)
  if not (ok and type(ids) == "table") then return end
  local building, buildingOnly, first = {}, {}, 1
  local function Step()
    ns.IndexQuestItems(lib.Quest, ids, first, first + CHUNK - 1, building, buildingOnly)
    first = first + CHUNK
    if first > #ids then
      index, questOnly = building, buildingOnly
      if done then done() end
    else
      C_Timer.After(0, Step)
    end
  end
  Step()
end

local function Lookup(lib, itemID, pick)
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
    faction = UnitFactionGroup("player"),
    class = select(3, UnitClass("player")),
    completed = function(id) return C_QuestLog.IsQuestFlaggedCompleted(id) end,
  }
  return pick(quests, player)
end

local function Find(itemID, pick)
  local lib = itemID and index and QuestieDB()
  if not (lib and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) then return nil end
  -- in doubt the item just isn't protected; a database error must not break the bags
  local ok, q = pcall(Lookup, lib, itemID, pick)
  return ok and q and q.name and {name = q.name, level = q.level, done = q.done} or nil
end

-- {name, level} of an upcoming quest that needs the item, or nil (also without QuestieDB)
function ns.GetQuestieQuest(itemID)
  return Find(itemID, ns.PickQuestieQuest)
end

-- {name, level, done} of the quest a quest-class item belongs to, at any level, or nil
function ns.GetQuestItemQuest(itemID)
  return Find(itemID, ns.PickQuestItemQuest)
end

-- true if the item exists only for a quest (it starts one or a quest hands it out), per QuestieDB
function ns.IsQuestOnlyItem(itemID)
  return itemID ~= nil and questOnly[itemID] == true
end
