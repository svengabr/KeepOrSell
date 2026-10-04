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

## Setup in Baganator

Nothing to do: on first login KeepOrSell creates the Baganator categories **Quest** (search `quest`) and **AuctionHouse** (search `auctionhouse & ~quest`) for you, with a priority that beats Baganator's built-in quest and equipment set categories. Baganator selects **Scrap** as junk plugin on its own.

If you deleted the categories or something went wrong, `/kos setup` creates them again. Manual setup (Bags → cog → Categories): create the two categories above with a priority above normal and choose **Scrap** under junk.

## Commands

- `/kos` – list detected quest objective items and current settings
- `/kos factor 3` – auction house threshold (default 2× vendor price)
- `/kos scrap` – cheap trade goods as Scrap junk on/off
- `/kos sets` – report groups to Baganator on/off (needs `/reload`)
- `/kos setup` – create the Baganator categories again

Only **trade goods** are ever marked as junk by KeepOrSell – never gear, consumables or quest items. Items you mark as "not junk" in Scrap always win.

---

## Deutsch

**Behalten, ins Auktionshaus oder zum Händler?** KeepOrSell beantwortet das für jedes Item in der Tasche – gedacht für Einsteiger.

- **Quest**: Quest-Items und normale Items, die eine aktive Quest verlangt (z. B. „6/10 Magere Wolfflanke“). Behalten.
- **Auktionshaus**: Auktionspreis mindestens doppelt so hoch wie der Händlerpreis. Im AH verkaufen.
- **Schrott** (Scrap): graue Items plus billige Handwerkswaren ohne Questbezug. Scrap verkauft sie beim Händler.

Die Baganator-Kategorien **Quest** (`quest`) und **Auktionshaus** (`auktionshaus & ~quest`) legt KeepOrSell beim ersten Login selbst an; `/kos setup` legt sie bei Bedarf neu an. Befehle: `/kos`, `/kos faktor 3`, `/kos scrap`, `/kos sets`, `/kos setup`.

## License

GPL-3.0-or-later
