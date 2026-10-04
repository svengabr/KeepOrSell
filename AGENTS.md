# AGENTS.md

Hinweise für KI-Agenten (Claude Code, Codex, Cursor …), die an KeepOrSell arbeiten.

## Was das Addon tut

WoW-Addon, das Taschen-Items in drei Gruppen einteilt: **Quest** (behalten), **AuctionHouse**
(Auktionspreis ≥ Faktor × Händlerpreis) und **Junk** über Scrap (billige Handwerkswaren).
Es setzt auf die öffentlichen APIs von **Baganator**, **Auctionator** und **Scrap** – alle drei
sind optional (`OptionalDeps`), jede Anbindung muss ohne das jeweilige Addon still nichts tun.

## Aufbau

Ladereihenfolge steht in `KeepOrSell.toc`. Alle Dateien teilen sich die Addon-Tabelle `ns`.

| Datei | Inhalt |
|---|---|
| `Locales.lua` | Texte in `ns.L`; Englisch Standard, `deDE` überschreibt |
| `Objectives.lua` | Questziele aus dem Questlog lesen (`ns.Refresh`, `ns.GetObjectiveState`, `ns.ParseObjectiveName`) – reine Logik |
| `Prices.lua` | Preis-Einstufung `ns.ClassifyPrice` / `ns.GetPriceClass` über Auctionator – reine Logik |
| `Scrap.lua` | Hängt sich in `Scrap:IsJunk`; Scraps eigene Liste und „kein Schrott“-Markierungen haben Vorrang |
| `Baganator.lua` | Eck-Widget und Item-Set-Quelle über `Baganator.API.*` |
| `Core.lua` | SavedVariables `KeepOrSellDB`, Events, Slash-Befehl `/kos` |

Baganator-Eigenheiten: Items mit Item-Set landen fest in der Equipment-Sets-Kategorie, vor jeder Suche und
unabhängig von Prioritäten – eigene Suchkategorien auf Set-Namen greifen deshalb nie. Ein API für Quest-Addons
gibt es nicht. Das Scrap-Schrott-Plugin bringt Baganator selbst mit (`Baganator/API/Junk.lua`).

## Regeln

- **Nur öffentliche APIs** der Fremd-Addons nutzen, keine Interna. Vorhandensein immer prüfen
  (`if not (Baganator and Baganator.API ...) then return end`).
- **Mehrere Clients**: Die TOC listet Retail und Classic-Varianten. API-Unterschiede abfangen
  (z. B. `C_QuestLog.GetInfo` vs. Classic-Questlog, `C_Item.GetItemInfo` vs. `GetItemInfo`).
- **Im Zweifel behalten**: Ohne bekannten Auktionspreis oder Item-Namen wird nichts als Schrott
  markiert. Als Junk gelten nur Handwerkswaren (`classID 7`), nie Ausrüstung, Verbrauchsgüter, Questitems.
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

## Release

Veröffentlicht wird automatisch über `.github/workflows/release.yml` (BigWigsMods/packager) zu
CurseForge (Projekt-ID in der TOC) und GitHub Releases.

1. `CHANGELOG.md` um die neue Version ergänzen, committen.
2. Annotiertes Tag `vX.Y.Z` setzen und pushen – das startet den Upload.

`## Version: @project-version@` nicht von Hand ersetzen, der Packager setzt sie aus dem Tag.
Neue Dateien oder Ordner, die nicht ins Addon-ZIP gehören, in `.pkgmeta` unter `ignore` eintragen.
Tags und Pushes nur nach Freigabe durch den Maintainer.
