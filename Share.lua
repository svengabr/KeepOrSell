-- Shares auction prices within the group: members ask for their bag items with the age of their
-- price, members with a fresher price answer. Freshness: see ns.IsFresher (Prices.lua).
local addonName, ns = ...

local VERSION = "2" -- 2: ages carry the time of the last full scan; 1 (0.8.0) is ignored
local MAX_MESSAGE = 255 -- SendAddonMessage limit
ns.MAX_SHARED_AGE = 21 -- Auctionator reports no age beyond this

local DAY = 86400
local NO_PRICE = {days = math.huge} -- an asker without a price: anything is fresher

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

-- Joins numbers with ":", leaving out trailing nils. Pure.
local function Fields(...)
  local parts = {}
  for i = 1, select("#", ...) do
    local value = select(i, ...)
    if value == nil then break end
    table.insert(parts, ("%d"):format(value))
  end
  return table.concat(parts, ":")
end

-- items = {{id, days, visit}, ...}; days = age of the asker's price (nil = none), visit = server time
-- of the full scan it came from (only for prices from today). The server clock is the same for
-- everyone on the realm, so the absolute time travels without rounding or queue delays. Pure.
function ns.EncodeQuery(items)
  local entries = {}
  for _, item in ipairs(items) do table.insert(entries, Fields(item.id, item.days, item.visit)) end
  return Pack("Q", entries)
end

-- entries = {{id, price (copper), days, visit}, ...}. Pure.
function ns.EncodeAnswer(entries)
  local packed = {}
  for _, e in ipairs(entries) do table.insert(packed, Fields(e.id, e.price, e.days, e.visit)) end
  return Pack("A", packed)
end

-- "I just finished a full scan": the others ask again. Pure.
function ns.EncodeNotice()
  return {VERSION .. "|N|"}
end

-- The numbers of "1:2:3", nil when a field is not plain digits ("0x10", "-5", "1.5", "1e3"). Pure.
local function Numbers(part)
  local values = {}
  for field in (part .. ":"):gmatch("([^:]*):") do
    if not field:match("^%d+$") then return nil end
    table.insert(values, tonumber(field))
  end
  return values
end

-- {kind = "Q", items}, {kind = "A", entries} or {kind = "N"}; nil for unknown versions or kinds.
-- Malformed entries are dropped. Pure.
function ns.DecodeMessage(text)
  if type(text) ~= "string" then return nil end
  local version, kind, body = text:match("^(%d+)|(%u)|(.*)$")
  if version ~= VERSION then return nil end
  if kind == "N" then return {kind = "N"} end
  if kind ~= "Q" and kind ~= "A" then return nil end
  local list = {}
  for part in body:gmatch("[^,]+") do
    local v = Numbers(part)
    if kind == "Q" and v and #v <= 3 and v[1] > 0 then
      table.insert(list, {id = v[1], days = v[2], visit = v[3]})
    elseif kind == "A" and v and (#v == 3 or #v == 4) then
      table.insert(list, {id = v[1], price = v[2], days = v[3], visit = v[4]})
    end
  end
  if kind == "Q" then return {kind = "Q", items = list} end
  return {kind = "A", entries = list}
end

local CLOCK_SLACK = 300 -- seconds a scan time may lie in the future

-- Freshness from a message's days and scan time. The scan time only counts for a price from today
-- and when it lies within the last day; anything else is dropped. Pure.
function ns.WireFreshness(days, visit, now)
  if not days then return nil end
  local valid = days == 0 and visit and visit <= now + CLOCK_SLACK and now - visit < DAY
  return {days = days, visit = valid and visit or nil}
end

-- days, visit for a message. Pure.
function ns.ToWire(fresh)
  if not fresh then return nil end
  return fresh.days, fresh.visit
end

-- stored = {price, seen, visit, from} or nil, fresh = freshness of the received price. Returns the entry
-- to store, or nil when the price is invalid or not fresher than the stored one. Pure.
function ns.AcceptSharedPrice(stored, price, fresh, from, now)
  if not (price and price > 0 and fresh and fresh.days and fresh.days >= 0 and fresh.days <= ns.MAX_SHARED_AGE) then
    return nil
  end
  if stored and stored.seen and not ns.IsFresher(fresh, ns.SharedFreshness(stored, now)) then return nil end
  return {price = price, seen = fresh.visit or now - fresh.days * DAY, visit = fresh.visit, from = from}
end

-- Removes shared prices Auctionator would no longer report an age for. Pure.
function ns.PruneSharedPrices(db, now)
  for id, entry in pairs(db) do
    if type(entry) ~= "table" or not entry.seen or now - entry.seen >= (ns.MAX_SHARED_AGE + 1) * DAY then
      db[id] = nil
    end
  end
end

-- true when fresh beats at least one of the askers (nil = an asker without a price). Pure.
local function HelpsAnyone(fresh, askers)
  for _, asker in ipairs(askers) do
    if ns.IsFresher(fresh, asker) then return true end
  end
  return false
end

-- Answers for items = {{id, askers = {freshness, ...}}, ...} (NO_PRICE for an asker without a price):
-- our own price, at most 21 days old, fresher than at least one asker's and than what another member
-- already answered (answered[id] = freshest answer seen). lookup(id) returns price, freshness. Pure.
function ns.PickAnswers(items, lookup, answered)
  local entries, seen = {}, {}
  for _, item in ipairs(items) do
    local id = item.id
    if not seen[id] then
      seen[id] = true
      local price, mine = lookup(id)
      if price and price > 0 and mine and mine.days <= ns.MAX_SHARED_AGE
          and HelpsAnyone(mine, item.askers)
          and not (answered[id] and not ns.IsFresher(mine, answered[id])) then
        local days, visit = ns.ToWire(mine)
        table.insert(entries, {id = id, price = price, days = days, visit = visit})
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
local NOTICE_SECONDS = 60 -- one "new full scan" notice per sender and minute is enough
local BAGS = NUM_BAG_SLOTS or 4

local asked = {}     -- itemID -> GetTime() of our last query (session only)
local pending = {}   -- itemID -> {freshness of each asker}, answered after a random delay
local answered = {}  -- itemID -> freshest valid answer another member sent while we wait
local notices = {}   -- sender -> GetTime() of their last notice
local queue = {}
local sending, queryScheduled, answerScheduled, refreshScheduled = false, false, false, false
local registered = false
local members = 0
local ahOpenedAt -- server time the auction house was opened
local scanStarted -- server time of a full scan whose data hasn't arrived yet

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

-- This auction house's shared prices, created on first use
local function SharedStore()
  local key = ns.RealmKey()
  KeepOrSellDB.sharedPrices = KeepOrSellDB.sharedPrices or {}
  KeepOrSellDB.sharedPrices[key] = KeepOrSellDB.sharedPrices[key] or {}
  return KeepOrSellDB.sharedPrices[key]
end

-- Auctionator price and freshness of an item in our own database
local function OwnPrice(id, now)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not (api and api.GetAuctionPriceByItemID and api.GetAuctionAgeByItemID) then return nil end
  local price = api.GetAuctionPriceByItemID(addonName, id)
  if not price then return nil end
  return price, ns.OwnFreshness(api.GetAuctionAgeByItemID(addonName, id), ns.LastFullScan(), now)
end

-- The freshest price we know for an item: our own or one shared earlier
local function BestKnown(id, now)
  local _, best = OwnPrice(id, now)
  local prices = ns.SharedPrices()
  local shared = prices and prices[id]
  if shared and shared.seen then
    local fresh = ns.SharedFreshness(shared, now)
    if ns.IsFresher(fresh, best) then best = fresh end
  end
  return best
end

-- Tradeable bag items not asked for lately, with the freshness of what we know
local function ItemsToAsk(clock, now)
  local items, seen = {}, {}
  for bag = 0, BAGS do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      local id = info and info.itemID
      if id and not seen[id] and not info.isBound and (not asked[id] or clock - asked[id] >= REASK_SECONDS) then
        seen[id] = true
        local days, visit = ns.ToWire(BestKnown(id, now))
        table.insert(items, {id = id, days = days, visit = visit})
      end
    end
  end
  return items
end

local function Query()
  queryScheduled = false
  if not (Enabled() and Channel() and C_Container and C_Container.GetContainerItemInfo) then return end
  if InCombatLockdown and InCombatLockdown() then
    -- try again after the fight instead of losing the query
    ns.ScheduleShareQuery()
    return
  end
  local clock = GetTime()
  local items = ItemsToAsk(clock, GetServerTime())
  for _, item in ipairs(items) do asked[item.id] = clock end
  Send(ns.EncodeQuery(items))
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
  local now = GetServerTime()
  local items = {}
  for id, askers in pairs(pending) do table.insert(items, {id = id, askers = askers}) end
  table.sort(items, function(a, b) return a.id < b.id end)
  local entries = ns.PickAnswers(items, function(id) return OwnPrice(id, now) end, answered)
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

local function Asked(items, now)
  -- without Auctionator there is nothing to answer with
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not (api and api.GetAuctionPriceByItemID) then return end
  for _, item in ipairs(items) do
    pending[item.id] = pending[item.id] or {}
    table.insert(pending[item.id], ns.WireFreshness(item.days, item.visit, now) or NO_PRICE)
  end
  if not answerScheduled and next(pending) then
    answerScheduled = true
    -- random wait, so not every member answers the same item
    C_Timer.After(ANSWER_DELAY_MIN + math.random() * (ANSWER_DELAY_MAX - ANSWER_DELAY_MIN), Answer)
  end
end

local function Answered(entries, name, now)
  local db, changed = SharedStore(), false
  for _, e in ipairs(entries) do
    local fresh = ns.WireFreshness(e.days, e.visit, now)
    local entry = ns.AcceptSharedPrice(db[e.id], e.price, fresh, name, now)
    -- only a valid answer spares us from answering ourselves
    local valid = e.price > 0 and fresh and fresh.days <= ns.MAX_SHARED_AGE
    if valid and pending[e.id] and (not answered[e.id] or ns.IsFresher(fresh, answered[e.id])) then
      answered[e.id] = fresh
    end
    if entry then
      db[e.id] = entry
      changed = true
    end
  end
  if changed then ScheduleRefresh() end
end

local function Noticed(name)
  local clock = GetTime()
  if notices[name] and clock - notices[name] < NOTICE_SECONDS then return end
  notices[name] = clock
  -- someone finished a full scan: ask again right away
  asked = {}
  ns.ScheduleShareQuery()
end

function ns.HandleShareMessage(prefix, text, channel, sender)
  if prefix ~= PREFIX or not (KeepOrSellDB and KeepOrSellDB.share) then return end
  if channel ~= "PARTY" and channel ~= "RAID" then return end
  local name = ns.ParseSender(sender, GetNormalizedRealmName and GetNormalizedRealmName())
  if not name or name == UnitName("player") then return end
  local message = ns.DecodeMessage(text)
  if not message then return end
  if message.kind == "Q" then
    Asked(message.items, GetServerTime())
  elseif message.kind == "A" then
    Answered(message.entries, name, GetServerTime())
  else
    Noticed(name)
  end
end

function ns.ShareAuctionHouseShown()
  ahOpenedAt = GetServerTime()
end

-- Tells the group about a full scan that arrived during this auction house visit
function ns.ShareAuctionHouseClosed()
  local scan = ns.LastFullScan()
  if scan and ahOpenedAt and scan >= ahOpenedAt and Enabled() and Channel() then Send(ns.EncodeNotice()) end
  ahOpenedAt, scanStarted = nil, nil -- a scan cut short by closing doesn't count
end

-- REPLICATE_ITEM_LIST_UPDATE: the full scan's data arrived, now it counts
function ns.ShareFullScanArrived()
  if not scanStarted then return end
  if C_AuctionHouse.GetNumReplicateItems and C_AuctionHouse.GetNumReplicateItems() == 0 then return end
  KeepOrSellDB.fullScans = KeepOrSellDB.fullScans or {}
  KeepOrSellDB.fullScans[ns.RealmKey()] = scanStarted
  scanStarted = nil
end

-- Only a full scan counts, single searches don't. Hooks Blizzard's function, so this works with any
-- scanning addon; the time is kept once the data arrives (ns.ShareFullScanArrived).
local function HookFullScan()
  if not (hooksecurefunc and C_AuctionHouse and C_AuctionHouse.ReplicateItems) then return end
  hooksecurefunc(C_AuctionHouse, "ReplicateItems", function() scanStarted = GetServerTime() end)
end

function ns.RegisterShare()
  HookFullScan()
  if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix and C_ChatInfo.SendAddonMessage) then return end
  C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  registered = true
  members = GetNumGroupMembers and GetNumGroupMembers() or 0
end
