# AGENTS.md

Hinweise für KI-Agenten (Claude Code, Codex, Cursor …), die an KeepOrSell arbeiten.

## Was das Addon tut

WoW-Addon, das Taschen-Items in Gruppen einteilt: **Quest** (behalten), **Profession** (Zutaten, die noch
Skillpunkte geben), **AuctionHouse** (Auktionspreis ≥ Faktor × Händlerpreis) und **Junk** über Scrap
(billige Handwerkswaren, Ausrüstung, die die Klasse nie tragen kann). Eine Tooltip-Zeile erklärt die Einstufung.
Es setzt auf die öffentlichen APIs von **Baganator**, **Auctionator**, **Scrap** und **QuestieDB** (Datenbank-Addon
von Questie) – alle vier sind optional (`OptionalDeps`), jede Anbindung muss ohne das jeweilige Addon still nichts tun.

## Aufbau

Ladereihenfolge steht in `KeepOrSell.toc`. Alle Dateien teilen sich die Addon-Tabelle `ns`.

| Datei | Inhalt |
|---|---|
| `Locales.lua` | Texte in `ns.L`; Englisch Standard, `deDE` überschreibt |
| `Objectives.lua` | Questziele aus dem Questlog lesen (`ns.Refresh`, `ns.GetObjectiveState`, `ns.ParseObjectiveName`) – reine Logik |
| `Prices.lua` | Preis-Einstufung `ns.ClassifyPrice` / `ns.ClassifyPrices` (Mindestgewinn, Preisalter), Preise über Auctionator (`ns.GetPrices`) |
| `Gear.lua` | `ns.IsUnusableGear`: Waffen-/Rüstungsarten, die eine Klasse nie lernen kann – reine Logik |
| `Professions.lua` | Merkt sich Zutaten gelernter, nicht grauer Rezepte pro Charakter (`KeepOrSellDB.recipes`) beim Öffnen des Berufsfensters; erkennt Rezepte als ungelernt/bekannt/fremder Beruf (`ns.GetRecipeState`) |
| `Questie.lua` | Kommende Quests über QuestieDBs öffentliche API (`LibQuestieDB`, Contract 2): `ns.GetQuestieQuest`, reine Auswahl `ns.PickQuestieQuest` (±5 Stufen, Rasse/Klasse, nicht erledigt); für Items der Klasse Quest `ns.GetQuestItemQuest` (jede Stufe, sonst erledigte Quest) für die Tooltip-Zeile. Eigener Item→Quest-Index aus allen Quests, nach dem Login häppchenweise gebaut (`ns.BuildQuestieIndex`) – `Item.relatedQuests` ist auf Forever leer |
| `Classify.lua` | Eine Entscheidung pro Item (`ns.Decide` rein, `ns.Classify` mit API) – genutzt von Baganator, Scrap und Tooltip |
| `Scrap.lua` | Hängt sich in `Scrap:IsJunk`; Scraps eigene Liste und „kein Schrott“-Markierungen haben Vorrang |
| `Baganator.lua` | Eck-Widget und Item-Set-Quelle über `Baganator.API.*` |
| `Tooltip.lua` | Tooltip-Zeile über `TooltipDataProcessor` (Fallback `OnTooltipSetItem`) |
| `Hints.lua` | Hinweise (`ns.CollectHints` rein): Knopf im Baganator-Taschenfenster über `Baganator.API.RegisterRegion`, ohne Baganator einmal im Chat |
| `Bags.lua` | Ein Durchlauf über die Taschen (`ns.ScanBags`, einmal pro Frame): Schrott laut `Scrap:IsJunk` (ohne Scrap grau + `ns.ShouldScrap`), Händlerwert, AH-Wert der Gruppe Auktionshaus |
| `Destroy.lua` | Zerstören-Knopf im Baganator-Taschenfenster: billigster Schrott nach Händlerpreis × Stapel (`ns.PickCheapest` rein, nie gesperrt oder ab Selten), Kandidaten aus `ns.ScanBags` (`ns.FindDestroyTarget`); `ns.DestroyTarget` prüft Slot und Cursor vor `DeleteCursorItem`; bei „Inventar voll“ im Lootfenster leuchtet der Knopf, wenn die Beute mehr wert ist (`ns.LootWorthMore` rein) |
| `BagValue.lua` | Taschenwert-Zeile im Baganator-Taschenfenster (`ns.SumBagValue`, `ns.FormatBagValue` rein) |
| `Dependencies.lua` | Status der optionalen Addons (`ns.DependencyStatus` rein, `ns.GetDependencyStatus`), welche Option welches Addon braucht (`ns.OPTION_NEEDS`), Mixin für die Zeilen-Vorlage in `Options.xml` |
| `Options.lua` | Optionen unter Esc → Optionen → AddOns über die `Settings`-API; Optionen ohne ihr Addon ausgegraut (`AddModifyPredicate`), Abhängigkeitsliste am Ende |
| `Core.lua` | SavedVariables `KeepOrSellDB`, Events, Slash-Befehl `/kos` (öffnet nur die Optionen) |

Baganator-Eigenheiten: Items mit Item-Set landen fest in der Equipment-Sets-Kategorie, vor jeder Suche und
unabhängig von Prioritäten – eigene Suchkategorien auf Set-Namen greifen deshalb nie. Ein API für Quest-Addons
gibt es nicht. Das Scrap-Schrott-Plugin bringt Baganator selbst mit (`Baganator/API/Junk.lua`).

## Regeln

- **Nur öffentliche APIs** der Fremd-Addons nutzen, keine Interna. Vorhandensein immer prüfen
  (`if not (Baganator and Baganator.API ...) then return end`).
- **Mehrere Clients**: Die TOC listet Retail und Classic-Varianten; gespielt und getestet wird nur auf
  WoW: Forever (Interface 16001, Blizzard-UI-Quelle: Gethe/wow-ui-source, Branch `forever`). Forever nutzt die
  moderne Oberfläche (`Settings`, `C_TradeSkillUI`/`Blizzard_Professions`, `TooltipDataProcessor`).
  `C_SettingsUtil.OpenSettingsPanel` (hinter `Settings.OpenToCategory`) ist dort für Addons gesperrt. API-Unterschiede abfangen
  (z. B. `C_QuestLog.GetInfo` vs. Classic-Questlog, `C_Item.GetItemInfo` vs. `GetItemInfo`).
- **Im Zweifel behalten**: Ohne bekannten, aktuellen Auktionspreis oder Item-Namen wird nichts als Schrott
  markiert. Als Junk gelten nur Handwerkswaren (`classID 7`), graue/weiße Ausrüstung (ohne Hemd, Wappenrock,
  Angelrute) und Ausrüstung, die die Klasse **nie** tragen kann (auch nicht nach späterem Training), sowie Items mit
  unerfüllter Klassen-/Rassen-Anforderung (Tooltip-Zeile `UsageRequirement`/`RaceClass`, rot) sowie
  Rezepte, die schon bekannt sind oder zu einem Beruf gehören, den der Charakter nicht hat (Option `recipeJunk`), sowie
  Questgegenstände (`classID 12`), deren Quests laut QuestieDB alle erledigt oder für den Charakter nicht machbar sind
  (Option `questie`) – nie grüne oder bessere tragbare Ausrüstung, Verbrauchsgüter, andere Questitems. Tragbare Ausrüstung darf ins Auktionshaus
  (handelbar und lohnend). Einzige Ausnahme vom „Im Zweifel“: graue/weiße Ausrüstung ohne Auktionspreis gilt als
  nicht lohnend, sobald der Spieler mit Auctionator im AH war (`KeepOrSellDB.ahVisited`).
- **Neue Texte** immer in `Locales.lua`, englisch und deutsch.
- Reine Logik (ohne WoW-Frames) in eigenen Funktionen halten, damit sie testbar bleibt.
- Code-Kommentare (Lua und Tests) **auf Englisch**. Commit-Messages auf Deutsch, Conventional Commits (`feat:`, `fix:`, `chore:` …).
- `README.md` ist englisch mit deutschem Abschnitt; `CHANGELOG.md` englisch.
- Die README ist zugleich die **CurseForge-Projektbeschreibung** (Markdown). CurseForge kann sie nicht per API
  übernehmen – nach README-Änderungen den Maintainer erinnern, sie dort von Hand einzufügen.

## Tests

Unit-Tests in Python mit [lupa](https://pypi.org/project/lupa/) (Lua 5.1), WoW-APIs werden gestubbt:

```bash
pip install lupa
python -m unittest discover -s tests -v
```

Neue Logik bekommt einen Test; Ingame-Verhalten (Frames, Events, Baganator-Anzeige) lässt sich
nur im Client prüfen – das ehrlich so benennen.

**Abgleich mit der Forever-API:** `tests/data/forever_api.json` enthält Blizzards generierte API-Doku
(Funktionen, Events, Enums) aus Gethe/wow-ui-source, Branch `forever`. `tests/test_api.py` prüft den
Addon-Code dagegen (`C_*`-Aufrufe, `Enum`-Werte, Events, Globals aus `.luacheckrc`), und jeder Test-Stub
für `C_*`/`Enum` wird beim Laden gegen sie geprüft (`tests/wowapi.py`). Fehlt etwas in der Doku, das es
trotzdem gibt oder das nur abgesichert genutzt wird: mit Begründung in `UNDOCUMENTED_FUNCTIONS`
(`wowapi.py`) bzw. `NOT_IN_DOCS` (`test_api.py`) eintragen. Nach einem Client-Patch neu erzeugen:
`python tests/update_api.py`.

**luacheck:** `.luacheckrc` listet jedes Global, das das Addon nutzt – ein neues Global dort eintragen.
Lokal ohne Lua-Installation über Docker:
`docker run --rm -v "$PWD:/data" -w /data ghcr.io/lunarmodules/luacheck .`

Beides läuft in `.github/workflows/test.yml` bei Push und Pull Request; der Release-Workflow
startet erst nach grünen Tests.

## Release

Veröffentlicht wird automatisch über `.github/workflows/release.yml` (BigWigsMods/packager) zu
CurseForge (Projekt-ID in der TOC) und GitHub Releases.

1. `CHANGELOG.md` um die neue Version ergänzen, committen.
2. Annotiertes Tag `vX.Y.Z` setzen und pushen – das startet den Upload.

`## Version: @project-version@` nicht von Hand ersetzen, der Packager setzt sie aus dem Tag.
Neue Dateien oder Ordner, die nicht ins Addon-ZIP gehören, in `.pkgmeta` unter `ignore` eintragen.
Tags und Pushes nur nach Freigabe durch den Maintainer.
