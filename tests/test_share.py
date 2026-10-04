"""Tests for sharing auction prices within the group (Share.lua)."""
import unittest

from addon import load


class MessageTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(("Share.lua",), base=False)

    def lua_list(self, values):
        return self.rt.table_from(values)

    def entries(self, rows):
        return self.rt.table_from([self.rt.table_from(r) for r in rows])

    def test_query_roundtrip(self):
        messages = list(self.ns.EncodeQuery(self.lua_list([3, 4, 2589])).values())
        self.assertEqual(messages, ["1|Q|3,4,2589"])
        decoded = self.ns.DecodeMessage(messages[0])
        self.assertEqual(decoded.kind, "Q")
        self.assertEqual(list(decoded.ids.values()), [3, 4, 2589])

    def test_answer_roundtrip(self):
        messages = list(self.ns.EncodeAnswer(self.entries([{"id": 3, "price": 1200, "age": 2}])).values())
        self.assertEqual(messages, ["1|A|3:1200:2"])
        entry = self.ns.DecodeMessage(messages[0]).entries[1]
        self.assertEqual((entry.id, entry.price, entry.age), (3, 1200, 2))

    def test_split_at_255_bytes(self):
        ids = list(range(100000, 100100))  # 100 six-digit IDs, ~700 bytes
        messages = list(self.ns.EncodeQuery(self.lua_list(ids)).values())
        self.assertGreater(len(messages), 1)
        self.assertTrue(all(len(m) <= 255 for m in messages))
        decoded = [i for m in messages for i in self.ns.DecodeMessage(m).ids.values()]
        self.assertEqual(decoded, ids)

    def test_empty_list_sends_nothing(self):
        self.assertEqual(len(list(self.ns.EncodeQuery(self.lua_list([])).values())), 0)

    def test_unknown_version_or_kind(self):
        self.assertIsNone(self.ns.DecodeMessage("2|Q|3"))
        self.assertIsNone(self.ns.DecodeMessage("1|X|3"))
        self.assertIsNone(self.ns.DecodeMessage("garbage"))
        self.assertIsNone(self.ns.DecodeMessage(None))

    def test_bad_entries_dropped(self):
        decoded = self.ns.DecodeMessage("1|Q|0x10,-5,1.5,,7,0")
        self.assertEqual(list(decoded.ids.values()), [7])
        decoded = self.ns.DecodeMessage("1|A|3:12:1,4:-1:2,5:1e3:0,6:10,7:20:3")
        self.assertEqual([e.id for e in decoded.entries.values()], [3, 7])


DAY = 86400
NOW = 100 * DAY


class AcceptTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(("Share.lua",), base=False)

    def accept(self, stored, price, age):
        stored = self.rt.table_from(stored) if stored else None
        return self.ns.AcceptSharedPrice(stored, price, age, "Sven", NOW)

    def test_new_price_stored_with_seen_day(self):
        entry = self.accept(None, 1200, 2)
        # "from" is a Python keyword, hence entry["from"]
        self.assertEqual((entry.price, entry.seen, entry["from"]), (1200, NOW - 2 * DAY, "Sven"))

    def test_fresher_replaces_older(self):
        self.assertIsNotNone(self.accept({"price": 900, "seen": NOW - 5 * DAY}, 1200, 1))

    def test_same_age_or_older_ignored(self):
        self.assertIsNone(self.accept({"price": 900, "seen": NOW - 2 * DAY}, 1200, 2))
        self.assertIsNone(self.accept({"price": 900, "seen": NOW - 2 * DAY}, 1200, 4))

    def test_invalid_values(self):
        self.assertIsNone(self.accept(None, 0, 1))
        self.assertIsNone(self.accept(None, 100, 22))
        self.assertIsNone(self.accept(None, None, 1))

    def test_prune_drops_entries_older_than_21_days(self):
        db = self.rt.eval("{[1] = {price = 1, seen = %d}, [2] = {price = 1, seen = %d}}" % (NOW - 22 * DAY, NOW - 3 * DAY))
        self.ns.PruneSharedPrices(db, NOW)
        self.assertEqual(list(db.keys()), [2])


class AnswerTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(("Share.lua",), base=False)
        # own Auctionator prices: 3 fresh, 4 too old to share, 5 unknown
        self.lookup = self.rt.eval("""function(id)
          if id == 3 then return 1200, 1 end
          if id == 4 then return 50, 30 end
        end""")

    def pick(self, ids, answered=None):
        answered = self.rt.table_from(answered or {})
        return [(e.id, e.price, e.age) for e in self.ns.PickAnswers(self.rt.table_from(ids), self.lookup, answered).values()]

    def test_only_known_prices_up_to_21_days(self):
        self.assertEqual(self.pick([3, 4, 5]), [(3, 1200, 1)])

    def test_skip_when_someone_answered_as_fresh(self):
        self.assertEqual(self.pick([3], {3: 1}), [])
        self.assertEqual(self.pick([3], {3: 0}), [])
        self.assertEqual(self.pick([3], {3: 2}), [(3, 1200, 1)])

    def test_duplicate_ids_once(self):
        self.assertEqual(self.pick([3, 3]), [(3, 1200, 1)])


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
function GetServerTime() return %d end
function GetTime() return CLOCK or 0 end
function GetNormalizedRealmName() return "Thunderstrike" end
function UnitName() return "Me" end
function IsInGroup() return GROUP end
function IsInRaid() return RAID end
function GetNumGroupMembers() return GROUP and MEMBERS or 0 end
function InCombatLockdown() return COMBAT end
Enum = {SendAddonMessageResult = {Success = 0, AddonMessageThrottle = 3, ChannelThrottle = 8}}
C_ChatInfo = {
  RegisterAddonMessagePrefix = function(prefix) PREFIX = prefix return 0 end,
  InChatMessagingLockdown = function() return LOCKDOWN end,
  SendAddonMessage = function(prefix, text, channel)
    if SEND_RESULT == 0 then table.insert(SENT, channel .. " " .. text) end
    return SEND_RESULT
  end,
}
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
C_Container = {
  GetContainerNumSlots = function() return #BAG end,
  GetContainerItemInfo = function(bag, slot) return BAG[slot] and {itemID = BAG[slot], hyperlink = "link" .. BAG[slot]} end,
}
NEEDS = {[3] = true, [4] = true}  -- items without a usable price
OWN = {}  -- itemID -> {price, age} in our own Auctionator
Auctionator = {API = {v1 = {
  GetAuctionPriceByItemID = function(_, id) return OWN[id] and OWN[id][1] end,
  GetAuctionAgeByItemID = function(_, id) return OWN[id] and OWN[id][2] end,
}}}
KeepOrSellDB = {share = true, sharedPrices = {}}
""" % NOW


class ExchangeTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(("Share.lua",), stubs=RUNTIME_STUBS, base=False)
        self.rt.eval("""function(ns)
          ns.Classify = function(id) return {needsPrice = NEEDS[id]} end
          ns.SettingsChanged = function() ns.refreshed = (ns.refreshed or 0) + 1 end
        end""")(self.ns)
        self.ns.RegisterShare()

    def sent(self):
        return list(self.rt.eval("SENT").values())

    def receive(self, text, sender="Sven-Thunderstrike", channel="PARTY"):
        self.ns.HandleShareMessage("KeepOrSell", text, channel, sender)

    def test_registers_prefix(self):
        self.assertEqual(self.rt.eval("PREFIX"), "KeepOrSell")

    def test_asks_for_items_without_price(self):
        self.ns.ScheduleShareQuery()
        self.ns.ScheduleShareQuery()  # bundled
        self.rt.execute("RunTimers()")
        self.assertEqual(self.sent(), ["PARTY 1|Q|3,4"])

    def test_raid_channel(self):
        self.rt.execute("RAID = true")
        self.ns.ScheduleShareQuery()
        self.rt.execute("RunTimers()")
        self.assertEqual(self.sent(), ["RAID 1|Q|3,4"])

    def test_no_query_alone_disabled_or_locked(self):
        for setup in ("GROUP = false", "KeepOrSellDB.share = false", "LOCKDOWN = true"):
            self.rt.execute("SENT = {}; GROUP = true; KeepOrSellDB.share = true; LOCKDOWN = false; " + setup)
            self.ns.ScheduleShareQuery()
            self.rt.execute("RunTimers()")
            self.assertEqual(self.sent(), [], setup)

    def test_query_waits_for_combat_end(self):
        self.rt.execute("COMBAT = true")
        self.ns.ScheduleShareQuery()
        self.rt.execute("local t = TIMERS; TIMERS = {}; t[1]()")  # first attempt during combat
        self.assertEqual(self.sent(), [])
        self.rt.execute("COMBAT = false; RunTimers()")
        self.assertEqual(self.sent(), ["PARTY 1|Q|3,4"])

    def test_asks_again_only_after_ten_minutes_or_new_member(self):
        self.ns.ScheduleShareQuery()
        self.rt.execute("RunTimers(); SENT = {}; CLOCK = 60")
        self.ns.ScheduleShareQuery()
        self.rt.execute("RunTimers()")
        self.assertEqual(self.sent(), [])
        self.rt.execute("MEMBERS = 3")
        self.ns.ShareRosterChanged()
        self.rt.execute("RunTimers()")
        self.assertEqual(self.sent(), ["PARTY 1|Q|3,4"])

    def test_answers_with_own_prices(self):
        self.rt.execute("OWN[3] = {1200, 1}")
        self.receive("1|Q|3,4")
        self.rt.execute("RunTimers()")
        self.assertEqual(self.sent(), ["PARTY 1|A|3:1200:1"])

    def test_no_answer_when_someone_was_faster(self):
        self.rt.execute("OWN[3] = {1200, 1}")
        self.receive("1|Q|3")
        self.receive("1|A|3:1100:1", sender="Other")
        self.rt.execute("RunTimers()")
        self.assertEqual(self.sent(), [])

    def test_stores_answer_and_refreshes_once(self):
        self.receive("1|A|3:1200:1,4:50:2")
        self.rt.execute("RunTimers()")
        entry = self.rt.eval("KeepOrSellDB.sharedPrices[3]")
        self.assertEqual((entry.price, entry.seen, entry["from"]), (1200, NOW - DAY, "Sven"))
        self.assertEqual(self.ns.refreshed, 1)

    def test_ignores_own_other_realm_whisper_and_disabled(self):
        self.receive("1|A|3:1200:1", sender="Me-Thunderstrike")
        self.receive("1|A|3:1200:1", sender="Sven-Spineshatter")
        self.receive("1|A|3:1200:1", channel="WHISPER")
        self.rt.execute("KeepOrSellDB.share = false")
        self.receive("1|A|3:1200:1")
        self.assertIsNone(self.rt.eval("KeepOrSellDB.sharedPrices[3]"))

    def test_throttled_message_sent_later(self):
        self.rt.execute("SEND_RESULT = 3")
        self.ns.ScheduleShareQuery()
        self.rt.execute("local t = TIMERS; TIMERS = {}; t[1]()")  # query timer: first send throttled
        self.rt.execute("local t = TIMERS; TIMERS = {}; t[1]()")  # retry: still throttled
        self.assertEqual(self.sent(), [])
        self.rt.execute("SEND_RESULT = 0; RunTimers()")
        self.assertEqual(self.sent(), ["PARTY 1|Q|3,4"])

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
        self.assertEqual(self.sent(), ["PARTY 1|Q|3,4"])  # no leftover from before

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
        self.assertEqual(self.sent(), ["PARTY 1|Q|3,4"])  # fresh query, no leftover


if __name__ == "__main__":
    unittest.main()
