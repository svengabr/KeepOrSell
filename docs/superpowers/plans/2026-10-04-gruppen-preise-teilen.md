# Auktionspreise in der Gruppe teilen – Umsetzungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gruppenmitglieder ohne frische Auctionator-Daten bekommen fehlende Auktionspreise automatisch von Mitgliedern mit Daten, gespeichert mit Alter in `KeepOrSellDB.sharedPrices`.

**Architecture:** Neue Datei `Share.lua` mit reiner Logik (Nachrichten kodieren/dekodieren, Annahme, Antwortauswahl, Absenderprüfung) und einem dünnen WoW-Teil (Addon-Nachrichten über `C_ChatInfo`, Warteschlange, Zeitsteuerung). `ns.GetPrices` wählt über die reine `ns.PickPrice` zwischen eigenem und geteiltem Preis; alle anderen Einstufungen bleiben unverändert.

**Tech Stack:** Lua 5.1 (WoW: Forever, Interface 16001), Tests in Python mit lupa, luacheck.

**Spec:** `docs/superpowers/specs/2026-10-04-gruppen-preise-teilen-design.md`

## Global Constraints

- Code-Kommentare (Lua und Tests) englisch; Commit-Messages deutsch, Conventional Commits.
- Neue Texte in `Locales.lua`, englisch und deutsch.
- Jedes neue Global in `.luacheckrc`; Globals ohne Eintrag in Blizzards Doku zusätzlich mit Begründung in `NOT_IN_DOCS` (`tests/test_api.py`).
- Test-Stubs für `C_*`/`Enum` müssen zur Forever-Doku passen (wird beim Laden geprüft): `Enum.SendAddonMessageResult` = `Success 0`, `AddonMessageThrottle 3`, `ChannelThrottle 8`.
- Nur öffentliche Auctionator-API (`Auctionator.API.v1.GetAuctionPriceByItemID`, `GetAuctionAgeByItemID`), nie in Auctionators Datenbank schreiben.
- Im Zweifel behalten: fehlerhafte, fremde oder fehlende Daten ändern nichts an der heutigen Einstufung.
- Präfix `KeepOrSell`, Nachrichten ≤ 255 Bytes, Protokollversion `1`, Höchstalter geteilter Preise 21 Tage.
- Zeit für gespeicherte Preise: `GetServerTime()` (dokumentiert), nicht `time()`.
- Alle Tests: `python -m unittest discover -s tests -v`. Einzelne Datei: `python -m unittest discover -s tests -p test_share.py -v`.
- Tags und Pushes nur nach Freigabe durch den Maintainer.

## Review Focus

1. **Absender mit Realm-Anhang auf demselben Realm:** Moderne Clients liefern bei `CHAT_MSG_ADDON` oft `Name-Realm` auch für den eigenen Realm. Erwartet: wird angenommen, wenn der Realm gleich `GetNormalizedRealmName()` ist (Test in Task 2).
2. **Zahlen in fremdem Format** (`0x10`, `-5`, `1.5`, leere Einträge): Erwartet: Eintrag verworfen, Rest der Nachricht bleibt nutzbar (Test in Task 1).
3. **Eigener Preis frischer als der geteilte:** Erwartet: eigener Preis gewinnt, kein Herkunftszusatz (Test in Task 3).
4. **Drosselung beim Senden:** Erwartet: Nachricht bleibt in der Warteschlange und wird später gesendet, nicht verworfen (Test in Task 5).
5. **Gruppe verlassen mit vollen Warteschlangen:** Erwartet: Warteschlange wird geleert, kein Lua-Fehler (Test in Task 5).

---

### Task 1: Nachrichtenformat

**Files:**
- Create: `Share.lua`
- Modify: `KeepOrSell.toc` (nach `Prices.lua`), `.pkgmeta` (`docs` ignorieren)
- Test: `tests/test_share.py` (neu)

**Interfaces:**
- Produces:
  - `ns.EncodeQuery(ids)` → Liste von Strings `1|Q|<id>,<id>,…`, jede ≤ 255 Bytes
  - `ns.EncodeAnswer(entries)` mit `entries = {{id=, price=, age=}, …}` → Liste von Strings `1|A|<id>:<price>:<age>,…`
  - `ns.DecodeMessage(text)` → `{kind = "Q", ids = {…}}` | `{kind = "A", entries = {{id, price, age}, …}}` | `nil`
  - `ns.MAX_SHARED_AGE = 21`

- [ ] **Step 1: Write the failing test**

`tests/test_share.py`:

```python
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


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m unittest discover -s tests -p test_share.py -v`
Expected: FAIL/ERROR – `Share.lua` existiert nicht (`cannot open`).

- [ ] **Step 3: Write minimal implementation**

`Share.lua`:

```lua
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
```

`KeepOrSell.toc`: Zeile `Share.lua` direkt nach `Prices.lua` einfügen.

`.pkgmeta`: unter `ignore:` die Zeile `  - docs` ergänzen.

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m unittest discover -s tests -p test_share.py -v`
Expected: PASS (6 Tests). Dann alle Tests: `python -m unittest discover -s tests -v` – PASS (`test_api` scannt `Share.lua` mit, es gibt noch keine neuen Globals).

- [ ] **Step 5: Commit**

```bash
git add Share.lua KeepOrSell.toc .pkgmeta tests/test_share.py
git commit -m "feat: Nachrichtenformat für geteilte Auktionspreise"
```

---

### Task 2: Annahme, Antwortauswahl, Absender, Sendeergebnis

**Files:**
- Modify: `Share.lua`
- Test: `tests/test_share.py`

**Interfaces:**
- Consumes: `ns.MAX_SHARED_AGE` (Task 1)
- Produces:
  - `ns.AcceptSharedPrice(stored, price, age, from, now)` → `{price, seen, from}` oder `nil`. `seen = now - age * 86400`. Nur wenn `price > 0`, `0 ≤ age ≤ 21` und strikt weniger Tage alt als `stored`.
  - `ns.PickAnswers(ids, lookup, answered)` → `{{id, price, age}, …}`; `lookup(id)` → `price, age`; `answered[id]` = kleinstes Alter, mit dem schon ein anderer geantwortet hat. Doppelte IDs nur einmal.
  - `ns.ParseSender(sender, realm)` → Kurzname oder `nil` (fremder Realm)
  - `ns.SendOutcome(result, codes)` → `"ok"` | `"retry"` | `"drop"`
  - `ns.PruneSharedPrices(db, now)` – löscht Einträge älter als 21 Tage

- [ ] **Step 1: Write the failing test**

An `tests/test_share.py` anhängen (vor `if __name__`):

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m unittest discover -s tests -p test_share.py -v`
Expected: FAIL – `attempt to call a nil value (field 'AcceptSharedPrice')` usw.

- [ ] **Step 3: Write minimal implementation**

In `Share.lua` nach `ns.DecodeMessage` anhängen:

```lua
local DAY = 86400

local function AgeInDays(seen, now)
  return math.max(0, math.floor((now - seen) / DAY))
end
ns.SharedAgeInDays = AgeInDays

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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m unittest discover -s tests -p test_share.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Share.lua tests/test_share.py
git commit -m "feat: Annahme und Auswahl geteilter Auktionspreise"
```

---

### Task 3: Geteilte Preise in der Einstufung

**Files:**
- Modify: `Prices.lua` (`ns.GetPrices`, neue `ns.PickPrice`)
- Test: `tests/test_prices.py`

**Interfaces:**
- Consumes: Einträge `KeepOrSellDB.sharedPrices[itemID] = {price, seen, from}` (Task 2)
- Produces:
  - `ns.PickPrice(own, shared, now)` → `own` unverändert, oder Kopie mit `ah = shared.price`, `age` (Tage), `hasAge = true`, `from = shared.from`, `vendor = own.vendor`
  - `ns.GetPrices(itemLink)` liefert zusätzlich `from`, wenn der geteilte Preis gewählt wurde

- [ ] **Step 1: Write the failing test**

In `tests/test_prices.py` neue Klasse vor `if __name__` einfügen:

```python
DAY = 86400
NOW = 100 * DAY


class SharedPriceTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(("Prices.lua",), base=False)

    def pick(self, own, shared):
        shared = self.rt.table_from(shared) if shared else None
        return self.ns.PickPrice(self.rt.table_from(own), shared, NOW)

    def test_no_shared_price_keeps_own(self):
        prices = self.pick({"ah": 300, "vendor": 100, "age": 1, "hasAge": True}, None)
        self.assertEqual((prices.ah, prices.age), (300, 1))

    def test_shared_fills_missing_price(self):
        prices = self.pick({"vendor": 100}, {"price": 500, "seen": NOW - 2 * DAY, "from": "Sven"})
        self.assertEqual((prices.ah, prices.vendor, prices.age, prices.hasAge, prices["from"]),
                         (500, 100, 2, True, "Sven"))

    def test_shared_replaces_older_own(self):
        prices = self.pick({"ah": 300, "vendor": 100, "age": 9, "hasAge": True},
                           {"price": 500, "seen": NOW - 1 * DAY, "from": "Sven"})
        self.assertEqual((prices.ah, prices["from"]), (500, "Sven"))
        # own price older than Auctionator reports (age nil) counts as old too
        prices = self.pick({"ah": 300, "hasAge": True}, {"price": 500, "seen": NOW - 1 * DAY, "from": "Sven"})
        self.assertEqual(prices.ah, 500)

    def test_fresher_own_wins(self):
        prices = self.pick({"ah": 300, "vendor": 100, "age": 1, "hasAge": True},
                           {"price": 500, "seen": NOW - 3 * DAY, "from": "Sven"})
        self.assertEqual((prices.ah, prices["from"]), (300, None))

    def test_own_without_age_api_wins(self):
        # older Auctionator without an age: its price is trusted as before
        prices = self.pick({"ah": 300}, {"price": 500, "seen": NOW, "from": "Sven"})
        self.assertEqual(prices.ah, 300)

    def test_lookup_uses_shared_price(self):
        rt, ns = load(("Prices.lua",), stubs="""
          function GetServerTime() return %d end
          KeepOrSellDB.sharedPrices = {[3] = {price = 700, seen = %d, from = "Sven"}}
        """ % (NOW, NOW - DAY))
        prices = ns.GetPrices("link3")
        self.assertEqual((prices.ah, prices.vendor, prices.age, prices["from"]), (700, 38, 1, "Sven"))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m unittest discover -s tests -p test_prices.py -v`
Expected: FAIL – `PickPrice` ist nil, `GetPrices("link3").ah` ist nil.

- [ ] **Step 3: Write minimal implementation**

In `Prices.lua` vor `function ns.GetPrices` einfügen:

```lua
local DAY = 86400

-- own = {ah, vendor, age, hasAge} from Auctionator; shared = {price, seen, from} from a group member.
-- The shared price wins when the own one is missing or older. Pure.
function ns.PickPrice(own, shared, now)
  if not (shared and shared.price and shared.seen) then return own end
  local sharedAge = math.max(0, math.floor((now - shared.seen) / DAY))
  if own.ah and own.ah > 0 then
    -- without an age API the own price is trusted as before
    if not own.hasAge then return own end
    if own.age and own.age <= sharedAge then return own end
  end
  return {ah = shared.price, vendor = own.vendor, age = sharedAge, hasAge = true, from = shared.from}
end
```

`ns.GetPrices` ersetzen durch:

```lua
-- {ah, vendor, age, hasAge, from}; age = days since last seen on the AH (nil = never or older than 21 days),
-- from = the group member who shared the price (nil for the own Auctionator price)
function ns.GetPrices(itemLink)
  local api = Api()
  local prices = {}
  if not itemLink then return prices end
  if api and api.GetAuctionPriceByItemLink then
    prices.ah = api.GetAuctionPriceByItemLink(addonName, itemLink)
  end
  if prices.ah and api.GetAuctionAgeByItemLink then
    prices.hasAge = true
    prices.age = api.GetAuctionAgeByItemLink(addonName, itemLink)
  end
  prices.vendor = VendorPrice(itemLink)
  local shared = KeepOrSellDB and KeepOrSellDB.sharedPrices
  local id = shared and C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(itemLink)
  if id and shared[id] and GetServerTime then
    return ns.PickPrice(prices, shared[id], GetServerTime())
  end
  return prices
end
```

`.luacheckrc` → `read_globals` alphabetisch `"GetServerTime",` ergänzen (steht in der Forever-Doku, kein `NOT_IN_DOCS` nötig).

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m unittest discover -s tests -v`
Expected: PASS (alle, inkl. `test_api`).

- [ ] **Step 5: Commit**

```bash
git add Prices.lua .luacheckrc tests/test_prices.py
git commit -m "feat: geteilte Auktionspreise in der Einstufung nutzen"
```

---

### Task 4: Herkunft im Tooltip

**Files:**
- Modify: `Tooltip.lua` (`PriceText`), `Locales.lua`
- Test: `tests/test_tooltip.py`

**Interfaces:**
- Consumes: `prices.from`, `prices.age` aus `ns.GetPrices` (Task 3)
- Produces: `L.TIP_SHARED` (`"(price from %s, %d days old)"`), `L.TIP_SHARED_TODAY` (`"(price from %s, today)"`)

- [ ] **Step 1: Write the failing test**

In `TooltipTests` (`tests/test_tooltip.py`) ergänzen:

```python
    def test_shared_price_names_sender(self):
        db = self.rt.eval("KeepOrSellDB")
        text = self.ns.TooltipText(self.rt.eval("{kind = 'ah'}"),
                                   self.rt.eval("{ah = 1000, vendor = 38, age = 2, from = 'Sven'}"), db)
        self.assertIn("AH 1000c, vendor 38c (price from Sven, 2 days old)", text)
        text = self.ns.TooltipText(self.rt.eval("{kind = 'ah'}"),
                                   self.rt.eval("{ah = 1000, vendor = 38, age = 0, from = 'Sven'}"), db)
        self.assertIn("(price from Sven, today)", text)

    def test_own_price_has_no_sender(self):
        self.assertNotIn("price from", self.show(3))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m unittest discover -s tests -p test_tooltip.py -v`
Expected: FAIL – Zusatz fehlt.

- [ ] **Step 3: Write minimal implementation**

`Locales.lua`, englische Tabelle nach `TIP_STALE`:

```lua
  TIP_SHARED = "(price from %s, %d days old)",
  TIP_SHARED_TODAY = "(price from %s, today)",
```

deutscher Block nach `L.TIP_STALE`:

```lua
  L.TIP_SHARED = "(Preis von %s, %d Tage alt)"
  L.TIP_SHARED_TODAY = "(Preis von %s, von heute)"
```

`Tooltip.lua`, in `PriceText` direkt nach der ersten Zeile (`local text = L.TIP_PRICES:format(...)`):

```lua
  -- a price shared by a group member names who saw it and when
  if prices.from then
    local shared = (prices.age or 0) > 0 and L.TIP_SHARED:format(prices.from, prices.age)
      or L.TIP_SHARED_TODAY:format(prices.from)
    text = text .. " " .. shared
  end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m unittest discover -s tests -p test_tooltip.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Tooltip.lua Locales.lua tests/test_tooltip.py
git commit -m "feat: Tooltip nennt, wer einen Auktionspreis geteilt hat"
```

---

### Task 5: Austausch zur Laufzeit

**Files:**
- Modify: `Share.lua` (WoW-Teil), `Core.lua`, `.luacheckrc`, `tests/test_api.py` (`NOT_IN_DOCS`)
- Test: `tests/test_share.py`

**Interfaces:**
- Consumes: alle Funktionen aus Task 1–2; `ns.Classify(itemID, link, location).needsPrice` (`Classify.lua`); `ns.RefreshBaganator()` (`Baganator.lua`, leert den Cache)
- Produces:
  - `ns.RegisterShare()` – Präfix registrieren (beim Login)
  - `ns.ScheduleShareQuery()` – Frage gebündelt nach 5 s
  - `ns.ShareRosterChanged()` – bei `GROUP_ROSTER_UPDATE`: neue Mitglieder → Merker „schon gefragt“ leeren, dann Frage planen
  - `ns.HandleShareMessage(prefix, text, channel, sender)` – für `CHAT_MSG_ADDON`

- [ ] **Step 1: Write the failing test**

An `tests/test_share.py` anhängen:

```python
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
          ns.RefreshBaganator = function() ns.refreshed = (ns.refreshed or 0) + 1 end
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m unittest discover -s tests -p test_share.py -v`
Expected: FAIL – `RegisterShare` ist nil.

- [ ] **Step 3: Write minimal implementation**

An `Share.lua` anhängen:

```lua
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
  if not channel then queue = {} end -- left the group: nobody to send to
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
    ns.RefreshBaganator()
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
```

`Core.lua`:

1. `DEFAULTS` um `share = true,` ergänzen.
2. In `ADDON_LOADED` nach der Defaults-Schleife:
   ```lua
       -- not in DEFAULTS: a table there would be shared by reference
       KeepOrSellDB.sharedPrices = KeepOrSellDB.sharedPrices or {}
   ```
3. Signatur des Handlers auf `frame:SetScript("OnEvent", function(_, event, arg1, ...)` ändern.
4. In `PLAYER_LOGIN` nach `ns.HookTooltip()`:
   ```lua
       ns.PruneSharedPrices(KeepOrSellDB.sharedPrices, GetServerTime())
       ns.RegisterShare()
       ns.ScheduleShareQuery()
   ```
   und bei den Registrierungen `frame:RegisterEvent("GROUP_ROSTER_UPDATE")` und `frame:RegisterEvent("CHAT_MSG_ADDON")`.
5. Zweig `BAG_UPDATE_DELAYED or SKILL_LINES_CHANGED` aufteilen:
   ```lua
     elseif event == "BAG_UPDATE_DELAYED" then
       ScheduleHints()
       ns.ScheduleShareQuery()
     elseif event == "SKILL_LINES_CHANGED" then
       ScheduleHints()
   ```
6. Neue Zweige:
   ```lua
     elseif event == "GROUP_ROSTER_UPDATE" then
       ns.ShareRosterChanged()
     elseif event == "CHAT_MSG_ADDON" then
       ns.HandleShareMessage(arg1, ...)
   ```

`tests/test_options.py`, Funktion `load()`: `"Share.lua"` nach `"Prices.lua"` in die Dateiliste aufnehmen.

`.luacheckrc` → `read_globals` alphabetisch ergänzen: `"C_ChatInfo"`, `"GetNormalizedRealmName"`, `"GetNumGroupMembers"`, `"InCombatLockdown"`, `"IsInGroup"`, `"IsInRaid"`.

`tests/test_api.py` → `NOT_IN_DOCS`, im Block „Legacy global C functions without generated docs“:

```python
    "IsInGroup": "legacy global, used by Blizzard_FrameXMLUtil/PartyUtil and the unit frames on Forever",
    "IsInRaid": "legacy global, used by the raid frames on Forever",
    "GetNumGroupMembers": "legacy global, used by the party and raid frames on Forever",
    "InCombatLockdown": "legacy global, used throughout FrameXML for secure frames",
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m unittest discover -s tests -v`
Expected: PASS (alle). Danach luacheck:
`docker run --rm -v "$PWD:/data" -w /data ghcr.io/lunarmodules/luacheck .` – Expected: `0 warnings / 0 errors`.

- [ ] **Step 5: Commit**

```bash
git add Share.lua Core.lua .luacheckrc tests/test_api.py tests/test_options.py tests/test_share.py
git commit -m "feat: Auktionspreise automatisch in der Gruppe austauschen"
```

---

### Task 6: Option „Preise in der Gruppe teilen“

**Files:**
- Modify: `Options.lua`, `Locales.lua`
- Test: `tests/test_options.py`

**Interfaces:**
- Consumes: `KeepOrSellDB.share` (Default aus Task 5)
- Produces: `L.OPT_SHARE`, `L.OPT_SHARE_TIP`; Checkbox `share` im Abschnitt Auktionshaus nach `maxAge`, ohne Eintrag in `ns.OPTION_NEEDS`

- [ ] **Step 1: Write the failing test**

In `tests/test_options.py`:

`test_panel_registered` – erwartete Liste anpassen:

```python
        self.assertEqual(list(self.calls.controls.values()), [
            "slider:factor", "slider:minProfit", "slider:maxAge", "checkbox:share", "checkbox:scrap", "checkbox:gear",
            "checkbox:plainGear", "checkbox:recipeJunk", "checkbox:profession", "checkbox:questie", "checkbox:tooltip", "checkbox:hints", "checkbox:setSource"])
```

Neuer Test:

```python
    def test_share_option(self):
        self.assertTrue(self.rt.eval("KeepOrSellDB.share"))
        self.assertEqual(self.calls.settings["share"].varType, "boolean")
        # receiving works without Auctionator, so the option is never greyed out
        self.assertNotIn("Needs", self.calls.tooltips["share"])
        self.assertTrue(self.rt.eval("ENABLED('share')"))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m unittest discover -s tests -p test_options.py -v`
Expected: FAIL – `checkbox:share` fehlt.

- [ ] **Step 3: Write minimal implementation**

`Locales.lua`, englisch nach `OPT_MAX_AGE_TIP`:

```lua
  OPT_SHARE = "Share prices in the group",
  OPT_SHARE_TIP = "Asks your party or raid for auction prices you are missing and answers with your Auctionator prices. Only members of your realm with KeepOrSell take part. Shared prices keep their age and show who shared them.",
```

deutsch nach `L.OPT_MAX_AGE_TIP`:

```lua
  L.OPT_SHARE = "Preise in der Gruppe teilen"
  L.OPT_SHARE_TIP = "Fragt deine Gruppe oder deinen Schlachtzug nach Auktionspreisen, die dir fehlen, und antwortet mit deinen Auctionator-Preisen. Mit dabei sind nur Mitglieder deines Realms mit KeepOrSell. Geteilte Preise behalten ihr Alter und zeigen, wer sie geteilt hat."
```

`Options.lua`, nach der `maxAge`-Slider-Zeile:

```lua
  Checkbox("share", L.OPT_SHARE, L.OPT_SHARE_TIP)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m unittest discover -s tests -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Options.lua Locales.lua tests/test_options.py
git commit -m "feat: Option zum Teilen der Auktionspreise in der Gruppe"
```

---

### Task 7: README und Changelog

**Files:**
- Modify: `README.md`, `CHANGELOG.md`

- [ ] **Step 1: README ergänzen**

Unter `## Options` nach der Zeile zu **Maximum price age**:

```markdown
- **Share prices in the group** – asks your party or raid for missing auction prices and answers with yours; only realm mates with KeepOrSell take part, shared prices keep their age and the tooltip names who shared them (default on)
```

Im deutschen Abschnitt, in der Aufzählung der Einstellungen nach „Höchstalter der Preise,“: `Preise in der Gruppe teilen,` einfügen. Nach dem Absatz zu Grüner Ausrüstung/Hinweis-Knopf einen Satz anhängen:

```markdown
Fehlen dir Auktionspreise, fragt KeepOrSell automatisch deine Gruppe: Mitglieder deines Realms mit KeepOrSell und Auctionator antworten mit ihren Preisen. Der Tooltip zeigt dann, von wem der Preis stammt und wie alt er ist.
```

- [ ] **Step 2: Changelog ergänzen**

Ganz oben unter `# Changelog`:

```markdown
## Unreleased

- Share auction prices in your group: KeepOrSell asks your party or raid for prices you are missing or that are too old, and members of your realm with KeepOrSell and Auctionator answer with theirs. Shared prices are saved with their age, expire like your own (Maximum price age) and the tooltip names who shared them, e.g. "(price from Sven, 2 days old)". New option "Share prices in the group" (default on). Auctionator's own database is not changed.
```

- [ ] **Step 3: Alle Prüfungen**

Run: `python -m unittest discover -s tests -v` – Expected: PASS.
Run: `docker run --rm -v "$PWD:/data" -w /data ghcr.io/lunarmodules/luacheck .` – Expected: 0 warnings / 0 errors.

- [ ] **Step 4: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: Preise in der Gruppe teilen in README und Changelog"
```

Danach den Maintainer erinnern: README von Hand auf CurseForge einfügen; ingame mit zwei Accounts in einer Gruppe prüfen (Austausch, Tooltip-Zusatz, Baganator-Aktualisierung). Kein Tag, kein Push ohne Freigabe.
