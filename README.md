# KeepOrSell

**Keep it, auction it or vendor it?** KeepOrSell answers that question for every item in your bags. It is made for new players who struggle to tell what is worth keeping.

It combines **Baganator**, **Auctionator** and **Scrap**:

| Group | What ends up there | What to do |
|---|---|---|
| **Quest** | Quest items *and* regular items an active quest asks for (e.g. "6/10 Lean Wolf Flank") | Keep |
| **Profession** | Reagents of your known recipes that still give skill points, and recipes for your professions you haven't learned yet | Keep |
| **AuctionHouse** | Items whose current auction price is at least 2× the vendor price | Sell on the auction house |
| **Junk** (Scrap) | Grey items, cheap trade goods no quest or recipe needs, grey and white gear not worth auctioning, and gear or items your class can never use | Scrap sells them at the vendor |

Items without a known or recent auction price are left alone – when in doubt, you keep them. Gear you could wear (green or better) is never junk – it only goes to the auction house when tradeable and worth it.

Hover over an item: a tooltip line tells you where it goes and why (e.g. "Auction house – AH 1g 20s, vendor 15s").

When KeepOrSell needs something from you – a fresh Auctionator scan, opening a profession window – a small hint button appears at the bottom left of Baganator's bag window. Hover it for details. Without Baganator the hints show in chat after login.

## Requirements

- [Baganator](https://www.curseforge.com/wow/addons/baganator) (category view)
- [Auctionator](https://www.curseforge.com/wow/addons/auctionator) – scan the auction house once, otherwise there are no prices
- [Scrap](https://www.curseforge.com/wow/addons/scrap) – optional, for automatic vendoring

Questie is **not** required; quest objectives are read from your quest log.

## Setup

Nothing to do. KeepOrSell reports its groups to Baganator as item sets, so **Quest**, **Profession** and **AuctionHouse** show up as their own groups inside Baganator's equipment sets category (category view). Regular quest items are put into the Quest group too. Baganator picks **Scrap** as junk plugin on its own.

To move the groups elsewhere in your bags, move the *equipment sets* category in Baganator (Bags → cog → Categories).

Open each of your profession windows once, so KeepOrSell learns your recipes. It updates them every time you open the window again.

## Options

Esc → Options → AddOns → **KeepOrSell**, or type `/kos`:

- **Auction house threshold** – auction price must be at least this many times the vendor price (default 2×)
- **Minimum AH profit** – per item, after the 5% AH cut; below that the item goes to the vendor (default off)
- **Maximum price age** – auction prices older than this are ignored and the item is kept (default 7 days)
- **Cheap trade goods as junk** – for Scrap, on/off
- **Items your class can't use** – e.g. mail or swords for a druid, or items marked "Classes: Mage": auction house when tradeable and worth it, otherwise junk; on/off
- **Grey and white gear as junk** – when not worth auctioning; without an auction price once you have visited the AH with Auctionator. Shirts, tabards and fishing poles are kept; on/off
- **Keep profession reagents** – on/off
- **Show in tooltip** – on/off
- **Show hints** – on/off
- **Show groups in Baganator** – on/off (needs `/reload`)

KeepOrSell only marks **trade goods**, **grey and white gear** and **gear your class can never wear** as junk – never green or better gear you could wear, consumables or quest items. Items you mark as "not junk" in Scrap always win.

Works on Retail and the Classic clients.

---

## Deutsch

**Behalten, ins Auktionshaus oder zum Händler?** KeepOrSell beantwortet das für jedes Item in der Tasche – gedacht für Einsteiger.

- **Quest**: Quest-Items und normale Items, die eine aktive Quest verlangt (z. B. „6/10 Magere Wolfflanke“). Behalten.
- **Beruf**: Zutaten deiner bekannten Rezepte, die noch Skillpunkte geben, und Rezepte für deine Berufe, die du noch nicht kannst. Behalten.
- **Auktionshaus**: Auktionspreis mindestens doppelt so hoch wie der Händlerpreis. Im AH verkaufen.
- **Schrott** (Scrap): graue Items, billige Handwerkswaren ohne Quest- oder Rezeptbezug, graue und weiße Ausrüstung, die sich im AH nicht lohnt, und Ausrüstung oder Items, die deine Klasse nie nutzen kann (z. B. „Klassen: Magier“). Scrap verkauft sie beim Händler.

Grüne und bessere Ausrüstung, die du tragen könntest, wird nie Schrott – höchstens Auktionshaus, wenn handelbar und lohnend. Der Tooltip zeigt, wohin ein Item gehört und warum. Braucht KeepOrSell etwas von dir (neuer Auctionator-Scan, Berufsfenster öffnen), erscheint unten links im Baganator-Taschenfenster ein Hinweis-Knopf.

Einrichtung ist nicht nötig: Quest, Beruf und Auktionshaus erscheinen als eigene Gruppen in Baganators Equipment-Sets-Kategorie, Scrap wählt Baganator selbst als Schrott-Plugin. Öffne jedes Berufsfenster einmal, damit KeepOrSell deine Rezepte kennt. Einstellungen unter Esc → Optionen → AddOns → **KeepOrSell** oder mit `/kos`: Auktionshaus-Schwelle, Mindestgewinn, Höchstalter der Preise, Schrott, Ausrüstung, graue/weiße Ausrüstung, Berufsmaterial, Tooltip, Hinweise, Gruppen in Baganator.

## License

GPL-3.0-or-later · Source & issues: https://github.com/svengabr/KeepOrSell
