# Auktionspreise in der Gruppe teilen – Design

Stand: 2026-10-04 · Status: zur Durchsicht

## Ziel

Ein Gruppenmitglied hat KeepOrSell und Auctionator installiert, aber keine (frischen) Auktionsdaten,
weil es nicht oder lange nicht im Auktionshaus war. Ein anderes Mitglied hat frische Daten. KeepOrSell
soll fehlende Preise automatisch innerhalb der Gruppe austauschen, damit die Einstufung (Auktionshaus,
Schrott über Scrap, Tooltip) beim Empfänger sofort funktioniert.

**Erfolg:** Der Empfänger tritt einer Gruppe bei. Ohne eigenes Zutun bekommen die Items in seiner Tasche,
die bisher „kein Preis“ oder „Preis zu alt“ hatten, die Preise des Mitglieds mit Daten, mit korrektem
Alter. Die Tooltip-Zeile zeigt, von wem der Preis stammt.

## Entscheidungen

| Frage | Entscheidung |
|---|---|
| Setup des Empfängers | KeepOrSell + Auctionator, nur ohne Scan. Empfangen funktioniert trotzdem auch ohne Auctionator. |
| Auslöser | Automatisch: Der Empfänger fragt bei Gruppenbeitritt und neuen Taschen-Items |
| Speicherung | Dauerhaft in `KeepOrSellDB.sharedPrices`, mit dem Tag, an dem der Absender den Preis gesehen hat; Verfall über die vorhandene Option „Höchstes Preisalter“ |
| In Auctionators Datenbank schreiben? | **Nein.** `Auctionator.API.v1` kann nur lesen. `Auctionator.DatabaseMixin:SetPrice` ist intern und schreibt immer auf den heutigen Scan-Tag; alte Preise würden als frisch gelten und die Preis-Historie des Empfängers verfälschen. |
| Antwortkanal | An die ganze Gruppe (`PARTY`/`RAID`): Alle profitieren, und andere Antwortende sehen, was schon beantwortet ist |
| Ansatz | A: Frage und Antwort pro Item (statt ungefragt Preise zu senden). Keine Bibliothek (AceComm/ChatThrottleLib), eigene kleine Warteschlange. |

## Protokoll

Präfix `KeepOrSell`, Kanal `RAID` wenn in einem Schlachtzug, sonst `PARTY`. Jede Nachricht ≤ 255 Bytes
und beginnt mit der Protokollversion; Nachrichten mit unbekannter Version werden verworfen.

- **Frage:** `1|Q|<id>,<id>,…` – Item-IDs ohne Preis oder mit zu altem Preis. Längere Listen werden auf
  mehrere Nachrichten verteilt.
- **Antwort:** `1|A|<id>:<preis>:<alter>,…` – Preis in Kupfer, Alter in ganzen Tagen (wie Auctionator es
  meldet). Längere Listen werden auf mehrere Nachrichten verteilt.

Geteilt wird pro Item-ID (`GetAuctionPriceByItemID` / `GetAuctionAgeByItemID` beim Absender). Für Items
mit Zufallssuffix gilt also, was Auctionator für die Item-ID kennt.

## Ablauf

**Fragen (Empfänger):**
1. Auslöser: `GROUP_ROSTER_UPDATE` (Beitritt) und `BAG_UPDATE_DELAYED`, gebündelt und um einige
   Sekunden verzögert.
2. Nicht senden, wenn: Option `share` aus, nicht in einer Gruppe, `InCombatLockdown()`,
   `C_ChatInfo.InChatMessagingLockdown()`.
3. Gesammelt werden die Item-IDs der Taschen, bei denen `ns.Classify(...).needsPrice` gilt.
4. Jedes Item höchstens alle 10 Minuten erneut erfragen (Merker nur für die Sitzung).

**Antworten (alle anderen):**
1. Bei einer Frage aus derselben Gruppe: Für jede ID den eigenen Auctionator-Preis samt Alter
   nachschlagen. Nur Items mit Preis und mit Alter ≤ 21 Tage kommen in Frage.
2. Zufällig 0,5–2 s warten. Ist inzwischen für ein Item eine gleich frische oder frischere Antwort eines
   anderen Mitglieds eingegangen, wird es weggelassen.
3. Die verbleibenden Items als Antwort senden.

**Empfangen (alle):**
1. Absender prüfen: nicht ich selbst, kein Realm-Anhang am Namen (Auktionshäuser sind realmgebunden).
2. Jeden Eintrag prüfen: Preis > 0, 0 ≤ Alter ≤ 21, ganze Zahlen.
3. Speichern, wenn frischer als der vorhandene Eintrag:
   `KeepOrSellDB.sharedPrices[itemID] = {price = …, seen = time() - alter * 86400, from = name}`.
4. Danach einmal (gebündelt) Entscheidungscache leeren und `ns.RefreshBaganator()`.

**Senden:** Warteschlange mit höchstens einer Nachricht pro Sekunde. Liefert `SendAddonMessage` eine
Drosselung (`AddonMessageThrottle`, `ChannelThrottle`), bleibt die Nachricht vorne und wird später erneut
versucht. Andere Fehler verwerfen die Nachricht. Ältere Clients, die `true`/`false` liefern, werden
ebenso behandelt (`true` = Erfolg).

## Preiswahl

`ns.GetPrices` bleibt die einzige Preisquelle für die Einstufung. Neu ist die reine Funktion
`ns.PickPrice(own, shared, now)`: Der geteilte Preis wird genommen, wenn der eigene fehlt oder älter ist
(eigenes Alter `nil` bei vorhandenem Preis zählt als älter als 21 Tage). Das Ergebnis enthält dann
`ah`, `age` (aus `seen` in ganzen Tagen), `hasAge = true` und `from`. Damit greifen Mindestgewinn,
Faktor und Höchstes Preisalter unverändert.

Die Ausnahme „graue/weiße Ausrüstung ohne Preis gilt nach AH-Besuch als nicht lohnend“
(`KeepOrSellDB.ahVisited`) bleibt an den eigenen AH-Besuch gebunden; geteilte Preise ändern daran nichts.

## Bausteine

| Datei | Änderung |
|---|---|
| `Share.lua` (neu, in der TOC vor `Classify.lua`) | Reine Logik: `ns.EncodeQuery`, `ns.EncodeAnswer`, `ns.DecodeMessage`, `ns.AcceptSharedPrice`, `ns.PickAnswers`. Mit WoW-API: Präfix registrieren, `CHAT_MSG_ADDON`, Absenderprüfung, Warteschlange, Fragezeitpunkt, `ns.PruneSharedPrices` |
| `Prices.lua` | `ns.PickPrice` (rein), `ns.GetPrices` nutzt sie |
| `Tooltip.lua` | Zusatz „(Preis von Name, X Tage)“, wenn `from` gesetzt ist |
| `Core.lua` | Standard `share = true`, `sharedPrices = {}`; beim Login Einträge älter als 21 Tage löschen; Events an `Share.lua` weiterreichen |
| `Options.lua` | Option „Preise in der Gruppe teilen“ – **nicht** in `ns.OPTION_NEEDS`, weil Empfangen ohne Auctionator funktioniert |
| `Locales.lua` | Optionstext, Tooltip-Text der Option, Herkunftszusatz – englisch und deutsch |
| `.luacheckrc` | `C_ChatInfo`, `IsInGroup`, `IsInRaid`, `InCombatLockdown` u. a. |
| `tests/test_api.py` | `IsInGroup`, `IsInRaid` in `NOT_IN_DOCS` (stehen nicht in Blizzards generierter Doku, sind FrameXML-sichtbare Globals) |
| `.pkgmeta` | `docs` unter `ignore` |
| `README.md`, `CHANGELOG.md` | Funktion beschreiben (README danach auf CurseForge von Hand nachtragen) |

## Fehlerfälle

- Gegenseite ohne KeepOrSell oder mit älterer Version: Das Präfix wird dort ignoriert bzw. die Version
  verworfen; es passiert nichts.
- Kaputte oder manipulierte Nachrichten: `ns.DecodeMessage` liefert `nil` oder lässt ungültige Einträge
  weg; nichts wird gespeichert.
- Niemand in der Gruppe hat Daten: Es kommt keine Antwort, die Items bleiben wie heute (Im Zweifel behalten).
- Ohne Auctionator: Empfangen und Nutzen funktioniert, Antworten nicht.

## Tests

Unit-Tests (lupa) für die reine Logik:
- Kodieren/Dekodieren, Aufteilung an der 255-Byte-Grenze, unbekannte Version, kaputte Einträge
- `ns.AcceptSharedPrice`: frischer ersetzt älter, älter ersetzt nicht, ungültige Werte
- `ns.PickPrice`: eigener fehlt / eigener älter / eigener frischer / beide fehlen
- `ns.PickAnswers`: nur eigene Preise, Alter ≤ 21, bereits frischer beantwortete IDs weglassen
- Stub für `C_ChatInfo` wird gegen die Forever-Doku geprüft (`tests/wowapi.py`)

**Nur ingame prüfbar:** echter Austausch zwischen zwei Clients in einer Gruppe, Drosselung, Aktualisierung
der Baganator-Anzeige und der Tooltip-Zusatz.

## Nicht enthalten

- Schreiben in Auctionators Datenbank
- Antwort „nicht im AH“ für Items ohne Preis
- Preise je Zufallssuffix
- Teilen über Gilde oder Flüstern
