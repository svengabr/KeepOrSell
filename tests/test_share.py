"""Tests for sharing auction prices within the group (Share.lua)."""
import unittest

from addon import load


class MessageTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(("Prices.lua", "Share.lua"), base=False)

    def rows(self, rows):
        return self.rt.table_from([self.rt.table_from(r) for r in rows])

    def test_query_roundtrip(self):
        # no price / 2 days old / today, last full scan at server time 8629200 (3 hours before NOW)
        items = self.rows([{"id": 3}, {"id": 4, "days": 2}, {"id": 2589, "days": 0, "visit": NOW - 10800}])
        messages = list(self.ns.EncodeQuery(items).values())
        self.assertEqual(messages, ["2|Q|3,4:2,2589:0:8629200"])
        decoded = self.ns.DecodeMessage(messages[0])
        self.assertEqual(decoded.kind, "Q")
        self.assertEqual([(i.id, i.days, i.visit) for i in decoded["items"].values()],
                         [(3, None, None), (4, 2, None), (2589, 0, NOW - 10800)])

    def test_answer_roundtrip(self):
        entries = self.rows([{"id": 3, "price": 1200, "days": 2}, {"id": 2589, "price": 40, "days": 0, "visit": NOW - 300}])
        messages = list(self.ns.EncodeAnswer(entries).values())
        self.assertEqual(messages, ["2|A|3:1200:2,2589:40:0:8639700"])
        decoded = self.ns.DecodeMessage(messages[0])
        self.assertEqual([(e.id, e.price, e.days, e.visit) for e in decoded.entries.values()],
                         [(3, 1200, 2, None), (2589, 40, 0, NOW - 300)])

    def test_notice(self):
        self.assertEqual(list(self.ns.EncodeNotice().values()), ["2|N|"])
        self.assertEqual(self.ns.DecodeMessage("2|N|").kind, "N")

    def test_split_at_255_bytes(self):
        ids = list(range(100000, 100100))  # 100 six-digit IDs with scan times, ~1900 bytes
        items = self.rows([{"id": i, "days": 0, "visit": 1790000000} for i in ids])
        messages = list(self.ns.EncodeQuery(items).values())
        self.assertGreater(len(messages), 1)
        self.assertTrue(all(len(m) <= 255 for m in messages))
        decoded = [i.id for m in messages for i in self.ns.DecodeMessage(m)["items"].values()]
        self.assertEqual(decoded, ids)

    def test_empty_list_sends_nothing(self):
        self.assertEqual(len(list(self.ns.EncodeQuery(self.rows([])).values())), 0)

    def test_unknown_version_or_kind(self):
        self.assertIsNone(self.ns.DecodeMessage("1|Q|3"))  # 0.8.0 counted ages in days only
        self.assertIsNone(self.ns.DecodeMessage("2|X|3"))
        self.assertIsNone(self.ns.DecodeMessage("garbage"))
        self.assertIsNone(self.ns.DecodeMessage(None))

    def test_bad_entries_dropped(self):
        decoded = self.ns.DecodeMessage("2|Q|0x10,-5,1.5,,7,0,8:1:2:3,9:x")
        self.assertEqual([i.id for i in decoded["items"].values()], [7])
        decoded = self.ns.DecodeMessage("2|A|3:12:1,4:-1:2,5:1e3:0,6:10,7:20:3,8:1:0:1:9")
        self.assertEqual([e.id for e in decoded.entries.values()], [3, 7])

    def test_wire_freshness(self):
        fresh = self.ns.WireFreshness(0, NOW - 300, NOW)
        self.assertEqual((fresh.days, fresh.visit), (0, NOW - 300))
        self.assertIsNone(self.ns.WireFreshness(2, NOW - 300, NOW).visit)  # scan time only counts for today
        self.assertIsNone(self.ns.WireFreshness(0, NOW + 3600, NOW).visit)  # in the future
        self.assertIsNone(self.ns.WireFreshness(0, NOW - DAY, NOW).visit)  # not from today
        self.assertIsNone(self.ns.WireFreshness(None, None, NOW))
        days, visit = self.ns.ToWire(self.rt.table_from({"days": 0, "visit": NOW - 300}))
        self.assertEqual((days, visit), (0, NOW - 300))


DAY = 86400
NOW = 100 * DAY


class AcceptTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(("Prices.lua", "Share.lua"), base=False)

    def accept(self, stored, price, days, visit=None):
        stored = self.rt.table_from(stored) if stored else None
        fresh = self.rt.table_from({"days": days, "visit": visit}) if days is not None else None
        return self.ns.AcceptSharedPrice(stored, price, fresh, "Sven", NOW)

    def test_new_price_stored_with_seen_day(self):
        entry = self.accept(None, 1200, 2)
        # "from" is a Python keyword, hence entry["from"]
        self.assertEqual((entry.price, entry.seen, entry.visit, entry["from"]), (1200, NOW - 2 * DAY, None, "Sven"))

    def test_todays_price_keeps_scan_time(self):
        entry = self.accept(None, 40, 0, NOW - 300)
        self.assertEqual((entry.seen, entry.visit), (NOW - 300, NOW - 300))

    def test_fresher_replaces_older(self):
        self.assertIsNotNone(self.accept({"price": 900, "seen": NOW - 5 * DAY}, 1200, 1))
        # same day, later full scan
        self.assertIsNotNone(self.accept({"price": 35, "seen": NOW - 3 * 3600, "visit": NOW - 3 * 3600}, 40, 0, NOW - 300))

    def test_same_age_or_older_ignored(self):
        self.assertIsNone(self.accept({"price": 900, "seen": NOW - 2 * DAY}, 1200, 2))
        self.assertIsNone(self.accept({"price": 900, "seen": NOW - 2 * DAY}, 1200, 4))
        self.assertIsNone(self.accept({"price": 35, "seen": NOW - 300, "visit": NOW - 300}, 40, 0, NOW - 3 * 3600))
        self.assertIsNone(self.accept({"price": 35, "seen": NOW - 300, "visit": NOW - 300}, 40, 0))

    def test_invalid_values(self):
        self.assertIsNone(self.accept(None, 0, 1))
        self.assertIsNone(self.accept(None, 100, 22))
        self.assertIsNone(self.accept(None, None, 1))
        self.assertIsNone(self.accept(None, 100, None))

    def test_prune_drops_entries_older_than_21_days(self):
        db = self.rt.eval("{[1] = {price = 1, seen = %d}, [2] = {price = 1, seen = %d}}" % (NOW - 22 * DAY, NOW - 3 * DAY))
        self.ns.PruneSharedPrices(db, NOW)
        self.assertEqual(list(db.keys()), [2])


class AnswerTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(("Prices.lua", "Share.lua"), base=False)
        # own prices: 3 one day old, 4 too old to share, 5 unknown, 6 today from a full scan 5 minutes ago
        self.lookup = self.rt.eval("""function(id)
          if id == 3 then return 1200, {days = 1} end
          if id == 4 then return 50, {days = 30} end
          if id == 6 then return 40, {days = 0, visit = %d} end
        end""" % (NOW - 300))

    def pick(self, items, answered=None):
        # items = [(id, [asker freshness or None for "no price"])]; a bare (id, None) means one asker without a price
        no_price = self.rt.eval("{days = math.huge}")
        def askers(fs):
            return self.rt.table_from([self.rt.table_from(f) if f else no_price for f in (fs if isinstance(fs, list) else [fs])])
        rows = [self.rt.table_from({"id": i, "askers": askers(f)}) for i, f in items]
        answered = self.rt.table_from({k: self.rt.table_from(v) for k, v in (answered or {}).items()})
        return [(e.id, e.price, e.days, e.visit)
                for e in self.ns.PickAnswers(self.rt.table_from(rows), self.lookup, answered).values()]

    def test_only_known_prices_up_to_21_days(self):
        self.assertEqual(self.pick([(3, None), (4, None), (5, None)]), [(3, 1200, 1, None)])

    def test_only_when_fresher_than_the_asker(self):
        self.assertEqual(self.pick([(3, {"days": 4})]), [(3, 1200, 1, None)])
        self.assertEqual(self.pick([(3, {"days": 1})]), [])
        self.assertEqual(self.pick([(3, {"days": 0})]), [])
        # the asker scanned 3 hours ago, we 5 minutes ago
        self.assertEqual(self.pick([(6, {"days": 0, "visit": NOW - 3 * 3600})]), [(6, 40, 0, NOW - 300)])
        self.assertEqual(self.pick([(6, {"days": 0})]), [])  # asker without a full scan: tie

    def test_answers_if_any_asker_is_helped(self):
        # one asker without a full scan (tie), another with an older one: answer for the second
        self.assertEqual(self.pick([(6, [{"days": 0}, {"days": 0, "visit": NOW - 3 * 3600}])]), [(6, 40, 0, NOW - 300)])

    def test_skip_when_someone_answered_as_fresh(self):
        self.assertEqual(self.pick([(3, None)], {3: {"days": 1}}), [])
        self.assertEqual(self.pick([(3, None)], {3: {"days": 0}}), [])
        self.assertEqual(self.pick([(3, None)], {3: {"days": 2}}), [(3, 1200, 1, None)])

    def test_duplicate_ids_once(self):
        self.assertEqual(self.pick([(3, None), (3, None)]), [(3, 1200, 1, None)])


class SenderTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(("Share.lua",), base=False)

    def test_same_realm(self):
        self.assertEqual(self.ns.ParseSender("Sven", "Thunderstrike"), "Sven")
        # modern clients add the realm even for the own one
        self.assertEqual(self.ns.ParseSender("Sven-Thunderstrike", "Thunderstrike"), "Sven")

    def test_other_realm_rejected(self):
        self.assertIsNone(self.ns.ParseSender("Sven-Spineshatter", "Thunderstrike"))
        self.assertIsNone(self.ns.ParseSender(None, "Thunderstrike"))

    def test_send_outcome(self):
        codes = self.rt.eval("{Success = 0, AddonMessageThrottle = 3, ChannelThrottle = 8}")
        self.assertEqual(self.ns.SendOutcome(0, codes), "ok")
        self.assertEqual(self.ns.SendOutcome(True, codes), "ok")   # older clients return a boolean
        self.assertEqual(self.ns.SendOutcome(None, codes), "ok")   # or nothing
        self.assertEqual(self.ns.SendOutcome(3, codes), "retry")
        self.assertEqual(self.ns.SendOutcome(8, codes), "retry")
        self.assertEqual(self.ns.SendOutcome(5, codes), "drop")
        self.assertEqual(self.ns.SendOutcome(False, codes), "drop")


RUNTIME_STUBS = """
NUM_BAG_SLOTS = 0
SENT, TIMERS = {}, {}
GROUP, RAID, MEMBERS, COMBAT, LOCKDOWN = true, false, 2, false, false
SEND_RESULT = 0
SERVER_TIME = %d
function GetServerTime() return SERVER_TIME end
function GetTime() return CLOCK or 0 end
function GetNormalizedRealmName() return "Thunderstrike" end
function UnitName() return "Me" end
function UnitFactionGroup() return "Alliance" end
KEY = "Thunderstrike-Alliance"
function IsInGroup() return GROUP end
function IsInRaid() return RAID end
function GetNumGroupMembers() return GROUP and MEMBERS or 0 end
function InCombatLockdown() return COMBAT end
function hooksecurefunc(tbl, name, fn)
  if type(tbl) == "string" then tbl, name, fn = _G, tbl, name end
  local original = tbl[name]
  tbl[name] = function(...) original(...) fn(...) end
end
Enum = {SendAddonMessageResult = {Success = 0, AddonMessageThrottle = 3, ChannelThrottle = 8}}
C_ChatInfo = {
  RegisterAddonMessagePrefix = function(prefix) PREFIX = prefix return 0 end,
  InChatMessagingLockdown = function() return LOCKDOWN end,
  SendAddonMessage = function(prefix, text, channel)
    if SEND_RESULT == 0 then table.insert(SENT, channel .. " " .. text) end
    return SEND_RESULT
  end,
}
C_AuctionHouse = {ReplicateItems = function() end, GetNumReplicateItems = function() return REPLICATED or 0 end}
C_Timer = {After = function(delay, fn) table.insert(TIMERS, fn) end}
function RunTimers()
  for _ = 1, 20 do
    local pending = TIMERS
    TIMERS = {}
    if #pending == 0 then return end
    for _, fn in ipairs(pending) do fn() end
  end
end
BAG = {3, 4, 9}  -- itemIDs in bag 0
BOUND_IDS = {[9] = true}  -- soulbound, never on the auction house
C_Container = {
  GetContainerNumSlots = function() return #BAG end,
  GetContainerItemInfo = function(bag, slot)
    local id = BAG[slot]
    return id and {itemID = id, hyperlink = "link" .. id, isBound = BOUND_IDS[id] == true}
  end,
}
OWN = {}  -- itemID -> {price, age in days} in our own Auctionator
Auctionator = {API = {v1 = {
  GetAuctionPriceByItemID = function(_, id) return OWN[id] and OWN[id][1] end,
  GetAuctionAgeByItemID = function(_, id) return OWN[id] and OWN[id][2] end,
}}}
KeepOrSellDB = {share = true, sharedPrices = {}, fullScans = {}}
function SHARED(id) return (KeepOrSellDB.sharedPrices[KEY] or {})[id] end
""" % NOW


class ExchangeTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(("Prices.lua", "Share.lua"), stubs=RUNTIME_STUBS, base=False)
        self.rt.eval("""function(ns)
          ns.SettingsChanged = function() ns.refreshed = (ns.refreshed or 0) + 1 end
        end""")(self.ns)
        self.ns.RegisterShare()

    def sent(self):
        return list(self.rt.eval("SENT").values())

    def receive(self, text, sender="Sven-Thunderstrike", channel="PARTY"):
        self.ns.HandleShareMessage("KeepOrSell", text, channel, sender)

    def query(self):
        self.ns.ScheduleShareQuery()
        self.rt.execute("RunTimers()")

    def test_registers_prefix(self):
        self.assertEqual(self.rt.eval("PREFIX"), "KeepOrSell")

    def test_asks_for_tradeable_bag_items_with_own_age(self):
        # 3 without a price, 4 with a price from today's full scan an hour ago, 9 soulbound
        self.rt.execute("OWN[4] = {35, 0}; KeepOrSellDB.fullScans[KEY] = SERVER_TIME - 3600")
        self.ns.ScheduleShareQuery()  # bundled with the next one
        self.query()
        self.assertEqual(self.sent(), ["PARTY 2|Q|3,4:0:%d" % (NOW - 3600)])

    def test_full_scan_of_another_realm_does_not_count(self):
        self.rt.execute("OWN[4] = {35, 0}; KeepOrSellDB.fullScans['Other-Horde'] = SERVER_TIME - 3600")
        self.query()
        self.assertEqual(self.sent(), ["PARTY 2|Q|3,4:0"])

    def test_asks_with_best_known_age(self):
        # a price shared earlier is fresher than our own
        self.rt.execute("OWN[3] = {30, 5}; KeepOrSellDB.sharedPrices[KEY] = {[3] = {price = 40, seen = SERVER_TIME - 86400}}")
        self.query()
        self.assertEqual(self.sent(), ["PARTY 2|Q|3:1,4"])

    def test_raid_channel(self):
        self.rt.execute("RAID = true")
        self.query()
        self.assertEqual(self.sent(), ["RAID 2|Q|3,4"])

    def test_no_query_alone_disabled_or_locked(self):
        for setup in ("GROUP = false", "KeepOrSellDB.share = false", "LOCKDOWN = true"):
            self.rt.execute("SENT = {}; GROUP = true; KeepOrSellDB.share = true; LOCKDOWN = false; " + setup)
            self.query()
            self.assertEqual(self.sent(), [], setup)

    def test_query_waits_for_combat_end(self):
        self.rt.execute("COMBAT = true")
        self.ns.ScheduleShareQuery()
        self.rt.execute("local t = TIMERS; TIMERS = {}; t[1]()")  # first attempt during combat
        self.assertEqual(self.sent(), [])
        self.rt.execute("COMBAT = false; RunTimers()")
        self.assertEqual(self.sent(), ["PARTY 2|Q|3,4"])

    def test_asks_again_only_after_ten_minutes_new_member_or_notice(self):
        self.query()
        self.rt.execute("SENT = {}; CLOCK = 60")
        self.query()
        self.assertEqual(self.sent(), [])
        self.rt.execute("MEMBERS = 3")
        self.ns.ShareRosterChanged()
        self.rt.execute("RunTimers()")
        self.assertEqual(self.sent(), ["PARTY 2|Q|3,4"])
        # another member finished a full scan
        self.rt.execute("SENT = {}")
        self.receive("2|N|")
        self.rt.execute("RunTimers()")
        self.assertEqual(self.sent(), ["PARTY 2|Q|3,4"])

    def test_answers_only_with_fresher_prices(self):
        # our full scan 5 minutes ago; the asker has 3 from 3 hours ago and 4 from an hour ago,
        # we only have 4 from yesterday
        self.rt.execute("OWN[3] = {40, 0}; OWN[4] = {50, 1}; KeepOrSellDB.fullScans[KEY] = SERVER_TIME - 300")
        self.receive("2|Q|3:0:%d,4:0:%d" % (NOW - 10800, NOW - 3600))
        self.rt.execute("RunTimers()")
        self.assertEqual(self.sent(), ["PARTY 2|A|3:40:0:%d" % (NOW - 300)])

    def test_answer_for_several_askers_helps_the_oldest(self):
        self.rt.execute("OWN[3] = {40, 1}")
        self.receive("2|Q|3:0", sender="A")
        self.receive("2|Q|3:4", sender="B")
        self.rt.execute("RunTimers()")
        self.assertEqual(self.sent(), ["PARTY 2|A|3:40:1"])

    def test_no_answer_when_someone_was_faster(self):
        self.rt.execute("OWN[3] = {1200, 1}")
        self.receive("2|Q|3")
        self.receive("2|A|3:1100:1", sender="Other")
        self.rt.execute("RunTimers()")
        self.assertEqual(self.sent(), [])

    def test_invalid_answer_does_not_silence_us(self):
        self.rt.execute("OWN[3] = {1200, 1}")
        self.receive("2|Q|3")
        self.receive("2|A|3:0:0", sender="Other")  # price 0: nobody stores it
        self.rt.execute("RunTimers()")
        self.assertEqual(self.sent(), ["PARTY 2|A|3:1200:1"])

    def test_stores_answer_and_refreshes_once(self):
        self.receive("2|A|3:1200:1,4:40:0:%d" % (NOW - 300))
        self.rt.execute("RunTimers()")
        entry = self.rt.eval("SHARED(3)")
        self.assertEqual((entry.price, entry.seen, entry["from"]), (1200, NOW - DAY, "Sven"))
        entry = self.rt.eval("SHARED(4)")
        self.assertEqual((entry.price, entry.visit), (40, NOW - 300))
        self.assertEqual(self.ns.refreshed, 1)

    def test_ignores_own_other_realm_whisper_and_disabled(self):
        self.receive("2|A|3:1200:1", sender="Me-Thunderstrike")
        self.receive("2|A|3:1200:1", sender="Sven-Spineshatter")
        self.receive("2|A|3:1200:1", channel="WHISPER")
        self.rt.execute("KeepOrSellDB.share = false")
        self.receive("2|A|3:1200:1")
        self.assertIsNone(self.rt.eval("SHARED(3)"))

    def test_full_scan_counts_once_its_data_arrived(self):
        self.ns.ShareAuctionHouseShown()
        self.rt.execute("SERVER_TIME = SERVER_TIME + 30; C_AuctionHouse.ReplicateItems()")
        self.assertIsNone(self.rt.eval("KeepOrSellDB.fullScans[KEY]"))  # requested, nothing arrived yet
        self.rt.execute("SERVER_TIME = SERVER_TIME + 20; REPLICATED = 5000")
        self.ns.ShareFullScanArrived()
        self.assertEqual(self.rt.eval("KeepOrSellDB.fullScans[KEY]"), NOW + 30)  # the time it started
        self.ns.ShareAuctionHouseClosed()
        self.rt.execute("RunTimers()")
        self.assertEqual(self.sent(), ["PARTY 2|N|"])

    def test_aborted_full_scan_does_not_count(self):
        self.ns.ShareAuctionHouseShown()
        self.rt.execute("C_AuctionHouse.ReplicateItems()")
        self.ns.ShareFullScanArrived()  # an update without items
        self.ns.ShareAuctionHouseClosed()  # closed before the data came
        self.rt.execute("REPLICATED = 5000")
        self.ns.ShareFullScanArrived()
        self.rt.execute("RunTimers()")
        self.assertIsNone(self.rt.eval("KeepOrSellDB.fullScans[KEY]"))
        self.assertEqual(self.sent(), [])

    def test_no_notice_without_full_scan(self):
        self.rt.execute("KeepOrSellDB.fullScans[KEY] = SERVER_TIME - 3600")  # earlier visit
        self.ns.ShareAuctionHouseShown()
        self.ns.ShareAuctionHouseClosed()
        self.rt.execute("RunTimers()")
        self.assertEqual(self.sent(), [])

    def test_notice_once_per_minute_and_sender(self):
        self.query()
        self.rt.execute("SENT = {}")
        self.receive("2|N|")
        self.rt.execute("RunTimers()")
        self.assertEqual(len(self.sent()), 1)
        self.rt.execute("SENT = {}; CLOCK = 30")
        self.receive("2|N|")
        self.rt.execute("RunTimers()")
        self.assertEqual(self.sent(), [])
        self.receive("2|N|", sender="Other")
        self.rt.execute("RunTimers()")
        self.assertEqual(len(self.sent()), 1)

    def test_throttled_message_sent_later(self):
        self.rt.execute("SEND_RESULT = 3")
        self.ns.ScheduleShareQuery()
        self.rt.execute("local t = TIMERS; TIMERS = {}; t[1]()")  # query timer: first send throttled
        self.rt.execute("local t = TIMERS; TIMERS = {}; t[1]()")  # retry: still throttled
        self.assertEqual(self.sent(), [])
        self.rt.execute("SEND_RESULT = 0; RunTimers()")
        self.assertEqual(self.sent(), ["PARTY 2|Q|3,4"])

    def test_leaving_group_drops_queue(self):
        self.rt.execute("SEND_RESULT = 3")
        self.ns.ScheduleShareQuery()
        self.rt.execute("local t = TIMERS; TIMERS = {}; t[1]()")
        self.rt.execute("GROUP = false; SEND_RESULT = 0")
        self.ns.ShareRosterChanged()  # the client fires GROUP_ROSTER_UPDATE on leaving too
        self.rt.execute("RunTimers()")
        self.assertEqual(self.sent(), [])
        self.rt.execute("GROUP = true")
        self.ns.ShareRosterChanged()
        self.rt.execute("RunTimers()")
        self.assertEqual(self.sent(), ["PARTY 2|Q|3,4"])  # no leftover from before

    def test_option_off_drops_queue(self):
        self.rt.execute("SEND_RESULT = 3")
        self.ns.ScheduleShareQuery()
        self.rt.execute("local t = TIMERS; TIMERS = {}; t[1]()")  # first send throttled
        self.rt.execute("KeepOrSellDB.share = false; SEND_RESULT = 0; RunTimers()")
        self.assertEqual(self.sent(), [])
        self.assertEqual(self.rt.eval("#TIMERS"), 0)  # no retry timer left
        self.rt.execute("KeepOrSellDB.share = true; MEMBERS = 3")
        self.ns.ShareRosterChanged()
        self.rt.execute("RunTimers()")
        self.assertEqual(self.sent(), ["PARTY 2|Q|3,4"])  # fresh query, no leftover


if __name__ == "__main__":
    unittest.main()
