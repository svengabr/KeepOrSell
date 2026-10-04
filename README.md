# KeepOrSell

**Keep it, auction it or vendor it?** KeepOrSell answers that question for every item in your bags. It is made for new players who struggle to tell what is worth keeping.

It combines **Baganator**, **Auctionator** and **Scrap**:

| Group | What ends up there | What to do |
|---|---|---|
| **Quest** | Quest items *and* regular items an active quest asks for (e.g. "6/10 Lean Wolf Flank") | Keep |
| **AuctionHouse** | Items whose current auction price is at least 2× the vendor price | Sell on the auction house |
| **Junk** (Scrap) | Grey items plus cheap trade goods that no quest needs and that are worth little on the AH | Scrap sells them at the vendor |

Items without a known auction price are left alone – when in doubt, you keep them.

## Requirements

- [Baganator](https://www.curseforge.com/wow/addons/baganator) (category view)
- [Auctionator](https://www.curseforge.com/wow/addons/auctionator) – scan the auction house once, otherwise there are no prices
- [Scrap](https://www.curseforge.com/wow/addons/scrap) – optional, for automatic vendoring

Questie is **not** required; quest objectives are read from your quest log.

## Setup

Nothing to do. KeepOrSell reports its groups to Baganator as item sets, so **Quest** and **AuctionHouse** show up as their own groups inside Baganator's equipment sets category (category view). Regular quest items are put into the Quest group too. Baganator picks **Scrap** as junk plugin on its own.

To move the groups elsewhere in your bags, move the *equipment sets* category in Baganator (Bags → cog → Categories).

## Commands

- `/kos` – list detected quest objective items and current settings
- `/kos factor 3` – auction house threshold (default 2× vendor price)
- `/kos scrap` – cheap trade goods as Scrap junk on/off
- `/kos sets` – report groups to Baganator on/off (needs `/reload`)

Only **trade goods** are ever marked as junk by KeepOrSell – never gear, consumables or quest items. Items you mark as "not junk" in Scrap always win.

Works on Retail and the Classic clients.

---

## Deutsch

**Behalten, ins Auktionshaus oder zum Händler?** KeepOrSell beantwortet das für jedes Item in der Tasche – gedacht für Einsteiger.

- **Quest**: Quest-Items und normale Items, die eine aktive Quest verlangt (z. B. „6/10 Magere Wolfflanke“). Behalten.
- **Auktionshaus**: Auktionspreis mindestens doppelt so hoch wie der Händlerpreis. Im AH verkaufen.
- **Schrott** (Scrap): graue Items plus billige Handwerkswaren ohne Questbezug. Scrap verkauft sie beim Händler.

Einrichtung ist nicht nötig: Quest und Auktionshaus erscheinen als eigene Gruppen in Baganators Equipment-Sets-Kategorie, Scrap wählt Baganator selbst als Schrott-Plugin. Befehle: `/kos`, `/kos faktor 3`, `/kos scrap`, `/kos sets`.

## License

GPL-3.0-or-later · Source & issues: https://github.com/svengabr/KeepOrSell
