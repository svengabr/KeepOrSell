# KeepOrSell

**Keep it, auction it or vendor it?** KeepOrSell answers that question for every item in your bags. It is made for new players who struggle to tell what is worth keeping.

It combines **Baganator**, **Auctionator** and **Scrap**:

| Group | What ends up there | What to do |
|---|---|---|
| **Quest** | Quest items, regular items an active quest asks for (e.g. "6/10 Lean Wolf Flank") and, with Questie, items a quest you haven't done yet needs (within 5 levels of yours) | Keep |
| **Profession** | Reagents of your known recipes that still give skill points, and recipes for your professions you haven't learned yet | Keep |
| **AuctionHouse** | Items whose current auction price is at least 2× the vendor price | Sell on the auction house |
| **Junk** (Scrap) | Grey items, cheap trade goods no quest or recipe needs, grey and white gear not worth auctioning, gear or items your class can never use, recipes you already know or for professions you don't have, and, with Questie, quest items of quests you have done (unless worth auctioning) | Scrap sells them at the vendor |

Items without a known or recent auction price are left alone – when in doubt, you keep them. Gear you could wear (green or better) is never junk – it only goes to the auction house when tradeable and worth it.

Hover over an item: a tooltip line tells you where it goes and why (e.g. "Auction house – AH 1g 20s, vendor 15s").

When KeepOrSell needs something from you – a fresh Auctionator scan, opening a profession window – a small hint button appears at the bottom left of Baganator's bag window. Hover it for details. Without Baganator the hints show in chat after login.

Bags full and no vendor nearby? A destroy button next to it (the item's icon with a red cross) destroys the cheapest junk item in your bags on each click – vendor price × stack, so a stack of grey vendor trash worth a few copper goes first. Hover it to see which item is next. It only takes what Scrap would sell (without Scrap: grey items and KeepOrSell's junk), never rare or better items. If your bags are full while looting and the loot is worth more than that junk, the button glows and a chat line tells you.

## Installation

Get it on [CurseForge](https://www.curseforge.com/wow/addons/keeporsell) – via the CurseForge app or as a manual download into `Interface/AddOns`.

## Requirements

- [Baganator](https://www.curseforge.com/wow/addons/baganator) (category view)
- [Auctionator](https://www.curseforge.com/wow/addons/auctionator) – scan the auction house once, otherwise there are no prices
- [Scrap](https://www.curseforge.com/wow/addons/scrap) – optional, for automatic vendoring
- [Questie](https://www.curseforge.com/wow/addons/questie) – optional; without it only quests in your quest log count. With it, items for quests you haven't picked up or finished yet are kept too, if the quest is within 5 levels of yours and open to your race and class. The tooltip names the quest, also for quest items. Quest items whose quests you have all done become junk.

## Setup

Nothing to do. KeepOrSell reports its groups to Baganator as item sets, so **Quest**, **Profession** and **AuctionHouse** show up as their own groups inside Baganator's equipment sets category (category view). Regular quest items are put into the Quest group too. Baganator picks **Scrap** as junk plugin on its own.

To move the groups elsewhere in your bags, move the *equipment sets* category in Baganator (Bags → cog → Categories).

Open each of your profession windows once, so KeepOrSell learns your recipes. It updates them every time you open the window again.

## Options

Esc → Options → AddOns → **KeepOrSell**, or type `/kos`:

- **Auction house threshold** – auction price must be at least this many times the vendor price (default 2×)
- **Minimum AH profit** – per item, after the 5% AH cut; below that the item goes to the vendor (default off)
- **Maximum price age** – auction prices older than this are ignored and the item is kept (default 7 days)
- **Share prices in the group** – your party or raid keeps each other's auction prices up to date: KeepOrSell asks for the items in your bags, and whoever has a fresher Auctionator price answers. Fresher means fewer days old; for two prices from the same day, the later full scan wins (single searches don't count). After a full scan KeepOrSell tells the group right away. Only realm mates with KeepOrSell take part, shared prices keep their age and the tooltip names who shared them; switching it off also ignores prices shared earlier (default on)
- **Cheap trade goods as junk** – for Scrap, on/off
- **Items your class can't use** – e.g. mail or swords for a druid, or items marked "Classes: Mage": auction house when tradeable and worth it, otherwise junk; on/off
- **Grey and white gear as junk** – when not worth auctioning; without an auction price once you have visited the AH with Auctionator. Shirts, tabards and fishing poles are kept; on/off
- **Useless recipes** – recipes you already know or for professions you don't have: auction house when tradeable and worth it, otherwise junk; on/off
- **Keep profession reagents** – on/off
- **Upcoming quests (Questie)** – on/off

Options that need an addon you don't have (Auctionator for prices, Baganator for the groups, Questie for upcoming quests) are greyed out. At the bottom of the panel, a list shows whether Auctionator, Baganator, Scrap and Questie are active, disabled or not installed.
- **Show in tooltip** – on/off
- **Show hints** – on/off
- **Destroy button** – destroys the cheapest junk on each click, needs Baganator; on/off
- **Show groups in Baganator** – on/off (needs `/reload`)

KeepOrSell only marks **trade goods**, **grey and white gear** and **gear your class can never wear** as junk – never green or better gear you could wear, consumables or quest items you may still need. Items you mark as "not junk" in Scrap always win.

Works on Retail and the Classic clients.

---

## Deutsch

**Behalten, ins Auktionshaus oder zum Händler?** KeepOrSell beantwortet das für jedes Item in der Tasche – gedacht für Einsteiger.

- **Quest**: Quest-Items und normale Items, die eine aktive Quest verlangt (z. B. „6/10 Magere Wolfflanke“), mit Questie auch Items, die eine noch nicht erledigte Quest höchstens 5 Stufen über oder unter deiner braucht – der Tooltip nennt die Quest. Behalten.
- **Beruf**: Zutaten deiner bekannten Rezepte, die noch Skillpunkte geben, und Rezepte für deine Berufe, die du noch nicht kannst. Behalten.
- **Auktionshaus**: Auktionspreis mindestens doppelt so hoch wie der Händlerpreis. Im AH verkaufen.
- **Schrott** (Scrap): graue Items, billige Handwerkswaren ohne Quest- oder Rezeptbezug, graue und weiße Ausrüstung, die sich im AH nicht lohnt, und Ausrüstung oder Items, die deine Klasse nie nutzen kann (z. B. „Klassen: Magier“), sowie Rezepte, die du schon kannst oder für Berufe, die du nicht hast, und mit Questie Questgegenstände erledigter Quests (wenn sie sich im AH nicht lohnen). Scrap verkauft sie beim Händler.

Grüne und bessere Ausrüstung, die du tragen könntest, wird nie Schrott – höchstens Auktionshaus, wenn handelbar und lohnend. Der Tooltip zeigt, wohin ein Item gehört und warum. Braucht KeepOrSell etwas von dir (neuer Auctionator-Scan, Berufsfenster öffnen), erscheint unten links im Baganator-Taschenfenster ein Hinweis-Knopf. Daneben zerstört ein Knopf bei jedem Klick den billigsten Schrott in deinen Taschen (Händlerpreis × Stapel) – für volle Taschen fern vom Händler; der Tooltip zeigt, welches Item als Nächstes dran ist. Sind die Taschen beim Looten voll und die Beute mehr wert, leuchtet der Knopf. Nur Schrott, den Scrap verkaufen würde, nie seltene oder bessere Items.

In der Gruppe halten sich alle gegenseitig die Auktionspreise aktuell: KeepOrSell fragt nach den Items in deiner Tasche, und wer einen frischeren Auctionator-Preis hat, antwortet. Frischer heißt weniger Tage alt; bei zwei Preisen vom selben Tag gewinnt der spätere Komplett-Scan (einzelne Suchen zählen nicht). Nach einem Komplett-Scan sagt KeepOrSell der Gruppe sofort Bescheid. Mit dabei sind Mitglieder deines Realms mit KeepOrSell; der Tooltip zeigt, von wem der Preis stammt und wie alt er ist.

Installation über [CurseForge](https://www.curseforge.com/wow/addons/keeporsell) (App oder manueller Download nach `Interface/AddOns`). Einrichtung ist nicht nötig: Quest, Beruf und Auktionshaus erscheinen als eigene Gruppen in Baganators Equipment-Sets-Kategorie, Scrap wählt Baganator selbst als Schrott-Plugin. Öffne jedes Berufsfenster einmal, damit KeepOrSell deine Rezepte kennt. Einstellungen unter Esc → Optionen → AddOns → **KeepOrSell** oder mit `/kos`: Auktionshaus-Schwelle, Mindestgewinn, Höchstalter der Preise, Preise in der Gruppe teilen, Schrott, Ausrüstung, graue/weiße Ausrüstung, nutzlose Rezepte, Berufsmaterial, kommende Quests (Questie), Tooltip, Hinweise, Zerstören-Knopf, Gruppen in Baganator. Optionen, deren Addon fehlt, sind ausgegraut; unten im Fenster steht, welche der Addons Auctionator, Baganator, Scrap und Questie aktiv, deaktiviert oder nicht installiert sind.

## License

GPL-3.0-or-later · Download: https://www.curseforge.com/wow/addons/keeporsell · Source & issues: https://github.com/svengabr/KeepOrSell
