-- Shares auction prices within the group: members without a price ask, members with one answer.
local addonName, ns = ...

local VERSION = "1"
local MAX_MESSAGE = 255 -- SendAddonMessage limit
ns.MAX_SHARED_AGE = 21 -- Auctionator reports no age beyond this

-- Joins entries into "<version>|<kind>|e1,e2,..." messages of at most MAX_MESSAGE bytes. Pure.
local function Pack(kind, entries)
  local head = VERSION .. "|" .. kind .. "|"
  local messages, current = {}, nil
  for _, entry in ipairs(entries) do
    if current and #current + 1 + #entry <= MAX_MESSAGE then
      current = current .. "," .. entry
    else
      if current then table.insert(messages, current) end
      current = head .. entry
    end
  end
  if current then table.insert(messages, current) end
  return messages
end

-- ids = {itemID, ...}. Pure.
function ns.EncodeQuery(ids)
  local entries = {}
  for _, id in ipairs(ids) do table.insert(entries, ("%d"):format(id)) end
  return Pack("Q", entries)
end

-- entries = {{id, price (copper), age (days)}, ...}. Pure.
function ns.EncodeAnswer(entries)
  local packed = {}
  for _, e in ipairs(entries) do table.insert(packed, ("%d:%d:%d"):format(e.id, e.price, e.age)) end
  return Pack("A", packed)
end

-- {kind = "Q", ids} or {kind = "A", entries}; nil for unknown versions or kinds.
-- Only plain digits count, so "0x10", "-5" or "1.5" are dropped. Pure.
function ns.DecodeMessage(text)
  if type(text) ~= "string" then return nil end
  local version, kind, body = text:match("^(%d+)|(%u)|(.*)$")
  if version ~= VERSION then return nil end
  if kind == "Q" then
    local ids = {}
    for part in body:gmatch("[^,]+") do
      local id = part:match("^%d+$") and tonumber(part)
      if id and id > 0 then table.insert(ids, id) end
    end
    return {kind = "Q", ids = ids}
  elseif kind == "A" then
    local entries = {}
    for part in body:gmatch("[^,]+") do
      local id, price, age = part:match("^(%d+):(%d+):(%d+)$")
      if id then
        table.insert(entries, {id = tonumber(id), price = tonumber(price), age = tonumber(age)})
      end
    end
    return {kind = "A", entries = entries}
  end
end

local DAY = 86400

local function AgeInDays(seen, now)
  return math.max(0, math.floor((now - seen) / DAY))
end

-- stored = {price, seen, from} or nil. Returns the entry to store, or nil when the price is
-- invalid or not fresher (in whole days) than the stored one. Pure.
function ns.AcceptSharedPrice(stored, price, age, from, now)
  if not (price and price > 0 and age and age >= 0 and age <= ns.MAX_SHARED_AGE) then return nil end
  if stored and stored.seen and AgeInDays(stored.seen, now) <= age then return nil end
  return {price = price, seen = now - age * DAY, from = from}
end

-- Removes shared prices Auctionator would no longer report an age for. Pure.
function ns.PruneSharedPrices(db, now)
  for id, entry in pairs(db) do
    if type(entry) ~= "table" or not entry.seen or AgeInDays(entry.seen, now) > ns.MAX_SHARED_AGE then
      db[id] = nil
    end
  end
end

-- Answers for the asked ids: own price known, at most 21 days old and fresher than what another
-- member already answered (answered[id] = lowest age seen). lookup(id) returns price, age. Pure.
function ns.PickAnswers(ids, lookup, answered)
  local entries, seen = {}, {}
  for _, id in ipairs(ids) do
    if not seen[id] then
      seen[id] = true
      local price, age = lookup(id)
      local other = answered[id]
      if price and price > 0 and age and age <= ns.MAX_SHARED_AGE and not (other and other <= age) then
        table.insert(entries, {id = id, price = price, age = age})
      end
    end
  end
  return entries
end

-- Short name of the sender, nil when on another realm (auction houses are per realm). Pure.
function ns.ParseSender(sender, realm)
  if type(sender) ~= "string" then return nil end
  local name, senderRealm = sender:match("^([^-]+)-(.+)$")
  if not name then return sender end
  if senderRealm ~= realm then return nil end
  return name
end

-- "ok", "retry" (throttled, send again later) or "drop" for a SendAddonMessage result. Older clients
-- return a boolean or nothing. Pure.
function ns.SendOutcome(result, codes)
  if result == nil or result == true or (codes and result == codes.Success) then return "ok" end
  if codes and (result == codes.AddonMessageThrottle or result == codes.ChannelThrottle) then return "retry" end
  return "drop"
end

-- Everything below talks to the client: addon messages, timers, bags.

local PREFIX = "KeepOrSell"
local QUERY_DELAY = 5 -- seconds, so bursts of bag and roster updates send one query
local REASK_SECONDS = 600
local SEND_INTERVAL = 1 -- stays below the addon message throttle
local ANSWER_DELAY_MIN, ANSWER_DELAY_MAX = 0.5, 2
local REFRESH_DELAY = 1
local BAGS = NUM_BAG_SLOTS or 4

local asked = {}     -- itemID -> GetTime() of our last query (session only)
local pending = {}   -- itemIDs others asked for, answered after a random delay
local answered = {}  -- itemID -> lowest age another member answered with while we wait
local queue = {}
local sending, queryScheduled, answerScheduled, refreshScheduled = false, false, false, false
local registered = false
local members = 0

local function Channel()
  if IsInRaid and IsInRaid() then return "RAID" end
  if IsInGroup and IsInGroup() then return "PARTY" end
end

local function Enabled()
  return registered and KeepOrSellDB and KeepOrSellDB.share
    and not (C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown())
end

local function Pump()
  local channel = Channel()
  -- left the group or switched the option off: nothing to send any more
  if not channel or not (KeepOrSellDB and KeepOrSellDB.share) then queue = {} end
  local message = queue[1]
  if not message then sending = false return end
  local outcome = "retry"
  if Enabled() then
    outcome = ns.SendOutcome(C_ChatInfo.SendAddonMessage(PREFIX, message, channel),
      Enum and Enum.SendAddonMessageResult)
  end
  if outcome ~= "retry" then table.remove(queue, 1) end
  C_Timer.After(SEND_INTERVAL, Pump)
end

local function Send(messages)
  for _, message in ipairs(messages) do table.insert(queue, message) end
  if not sending and #queue > 0 then
    sending = true
    Pump()
  end
end

-- Auctionator price and age of an item in our own database
local function OwnPrice(id)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not (api and api.GetAuctionPriceByItemID and api.GetAuctionAgeByItemID) then return nil end
  local price = api.GetAuctionPriceByItemID(addonName, id)
  if not price then return nil end
  return price, api.GetAuctionAgeByItemID(addonName, id)
end

-- Bag items that stay only because their price is missing or too old, not asked for lately
local function MissingPrices(now)
  local ids, seen = {}, {}
  for bag = 0, BAGS do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      local id = info and info.itemID
      if id and not seen[id] then
        seen[id] = true
        local location = ItemLocation and ItemLocation:CreateFromBagAndSlot(bag, slot)
        if (not asked[id] or now - asked[id] >= REASK_SECONDS)
            and ns.Classify(id, info.hyperlink, location).needsPrice then
          table.insert(ids, id)
        end
      end
    end
  end
  return ids
end

local function Query()
  queryScheduled = false
  if not (Enabled() and Channel() and C_Container and C_Container.GetContainerItemInfo) then return end
  if InCombatLockdown and InCombatLockdown() then
    -- try again after the fight instead of losing the query
    ns.ScheduleShareQuery()
    return
  end
  local now = GetTime()
  local ids = MissingPrices(now)
  for _, id in ipairs(ids) do asked[id] = now end
  Send(ns.EncodeQuery(ids))
end

function ns.ScheduleShareQuery()
  if queryScheduled then return end
  queryScheduled = true
  C_Timer.After(QUERY_DELAY, Query)
end

-- New members may have prices we asked for in vain before
function ns.ShareRosterChanged()
  local count = GetNumGroupMembers and GetNumGroupMembers() or 0
  if count > members then asked = {} end
  members = count
  ns.ScheduleShareQuery()
end

local function Answer()
  answerScheduled = false
  local ids = {}
  for id in pairs(pending) do table.insert(ids, id) end
  table.sort(ids)
  local entries = ns.PickAnswers(ids, OwnPrice, answered)
  pending, answered = {}, {}
  if Enabled() and Channel() then Send(ns.EncodeAnswer(entries)) end
end

local function ScheduleRefresh()
  if refreshScheduled then return end
  refreshScheduled = true
  C_Timer.After(REFRESH_DELAY, function()
    refreshScheduled = false
    ns.SettingsChanged() -- also updates the "rescan prices" hint, not only Baganator
  end)
end

function ns.HandleShareMessage(prefix, text, channel, sender)
  if prefix ~= PREFIX or not (KeepOrSellDB and KeepOrSellDB.share) then return end
  if channel ~= "PARTY" and channel ~= "RAID" then return end
  local name = ns.ParseSender(sender, GetNormalizedRealmName and GetNormalizedRealmName())
  if not name or name == UnitName("player") then return end
  local message = ns.DecodeMessage(text)
  if not message then return end
  if message.kind == "Q" then
    -- without Auctionator there is nothing to answer with
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not (api and api.GetAuctionPriceByItemID) then return end
    for _, id in ipairs(message.ids) do pending[id] = true end
    if not answerScheduled and next(pending) then
      answerScheduled = true
      -- random wait, so not every member answers the same item
      C_Timer.After(ANSWER_DELAY_MIN + math.random() * (ANSWER_DELAY_MAX - ANSWER_DELAY_MIN), Answer)
    end
    return
  end
  KeepOrSellDB.sharedPrices = KeepOrSellDB.sharedPrices or {}
  local db, now, changed = KeepOrSellDB.sharedPrices, GetServerTime(), false
  for _, e in ipairs(message.entries) do
    if pending[e.id] and (answered[e.id] == nil or e.age < answered[e.id]) then answered[e.id] = e.age end
    local entry = ns.AcceptSharedPrice(db[e.id], e.price, e.age, name, now)
    if entry then
      db[e.id] = entry
      changed = true
    end
  end
  if changed then ScheduleRefresh() end
end

function ns.RegisterShare()
  if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix and C_ChatInfo.SendAddonMessage) then return end
  C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  registered = true
  members = GetNumGroupMembers and GetNumGroupMembers() or 0
end
