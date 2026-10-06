# Changelog

## 0.12.0

- Questie: newer races such as the High Order Skyborn now get the upcoming quests of their faction. QuestieDB marks these races with a bit that can't be derived from the race ID, so before, every race-restricted quest was ignored for them and its items (e.g. Murloc Eyes for "Westfall Stew") could end up as junk.

## 0.11.1

- KeepOrSell is now published for WoW: Forever only, the only client it is played and tested on. Retail and the other Classic flavors are no longer listed.

## 0.11.0

- Optional TradeSkillMaster support for advanced users: when Auctionator has no price for an item (and no group member shared one), KeepOrSell uses TSM's lowest buyout, otherwise its market value. The tooltip marks these prices with "(TSM)". TSM prices have no age, so "Maximum price age" doesn't apply to them, and they are not shared with the group. Grey/white gear without a price still needs an auction house visit with Auctionator before it counts as junk.
- With Questie, items that start a quest or that a quest hands you now count as quest items, whatever their item class: they stay in the Quest group (the tooltip names the quest) while the quest is open, and become junk once it is done – e.g. a second library book after turning in the first one, or a leftover quest tool. Items with no known quest still stay.

## 0.10.0

- Bag value in Baganator's bag window (bottom left), e.g. "Junk 1g 20s · AH 15g": your junk at the vendor and the AuctionHouse group at auction (before fees). Hover it for item counts and the three most valuable auction items. New option "Show bag value" (default on, needs Baganator).
- Bags full while looting: when the loot is worth more than your cheapest junk (better of auction and vendor price; quest and profession items always count), the destroy button glows until the loot window closes and one chat line names both items. One click makes room, then loot as usual.

## 0.9.0

- Destroy button in Baganator's bag window (bottom left): each click destroys the cheapest junk item in your bags (vendor price × stack) – for small bags far from a vendor. Hover it to see which item goes next. Only items Scrap would sell (without Scrap: grey items and KeepOrSell's junk), never rare or better items. New option "Destroy button" (default on, needs Baganator).

## 0.8.2

- Shared prices now keep everyone up to date, not only fill gaps: KeepOrSell asks the group about every tradeable item in your bags, and members answer when their price is fresher. Fresher means fewer days old; for two prices from the same day, the later **full scan** wins. KeepOrSell notes the time of your last full auction house scan once its data has arrived (single searches don't count) and tells the group right after, so the others pick up the new prices at once.
- Full scan times and shared prices are kept per realm and faction, since each has its own auction house. Prices shared with 0.8.0 or 0.8.1 are dropped once, they don't say which auction house they came from.
- The group protocol changed: 0.8.1 and earlier don't exchange prices with 0.8.2, everyone in the group needs 0.8.2.

## 0.8.1

- Quest items (item class Quest) now name their quest in the tooltip, e.g. "Quest – quest item for \"Westfall Stew\" (level 14)", looked up with Questie at any level.
- With Questie, a quest item whose quests you have all done is no longer kept: it goes to the auction house when worth it, otherwise it becomes junk (soulbound ones too). Without an auction price it stays.

## 0.8.0

- Share auction prices in your group: KeepOrSell asks your party or raid for prices you are missing or that are too old, and members of your realm with KeepOrSell and Auctionator answer with theirs. Shared prices are saved with their age, expire like your own (Maximum price age) and the tooltip names who shared them, e.g. "(price from Sven, 2 days old)". New option "Share prices in the group" (default on); switching it off also ignores prices shared earlier. Auctionator's own database is not changed.

## 0.7.2

- The auction house threshold is now at least 1.1× the vendor price (slider 1.1–10 in steps of 0.1). Below that, the 5% auction house cut could leave you with less than the vendor pays, and Auctionator warned when posting. Lower saved values are raised to 1.1.

## 0.7.1

- Profession tools (Mining Pick, Blacksmith Hammer, Skinning Knife, runed enchanting rods, Arclight Spanner and others) are never sold or sent to the auction house anymore. The tooltip says "Keep – profession tool".

## 0.7.0

- Questie support: items a quest you haven't done yet needs (within 5 levels of yours, open to your race and class) go to the Quest group instead of being sold. The tooltip names the quest. Needs Questie (QuestieDB); new option "Upcoming quests (Questie)".
- Options are grouped into Auction house, Junk, Keep and Display. The panel lists Auctionator, Baganator, Scrap and Questie with their status (active, disabled, not installed). Options that need a missing addon are greyed out and say which addon they need.
- Faster: item decisions are cached, so Baganator refreshes no longer recalculate every item (fixes stutter with the bag window open).
- The hint button only asks Baganator for a new layout when it actually changes.
- Author name in the TOC is now Conoar.
- Recipes you already know and recipes for professions you don't have now go to AuctionHouse when worth it, otherwise to junk (new option "Useless recipes").
- Fixed a Lua error (`DoesItemExist`) when hovering items in the merchant's buyback tab.

## 0.6.2

- Hints in Baganator's bag window (bottom left) when KeepOrSell needs something from you: Auctionator missing, no auction house visit yet, outdated prices in your bags, profession windows never opened. Hover for details, click for options. Without Baganator the hints show in chat after login. Can be switched off.

## 0.6.1

- Recipes for your own professions that you haven't learned yet go to the Profession group instead of the auction house. Already known recipes are classified as before.

## 0.6.0

- Options panel under Esc → Options → AddOns → KeepOrSell (auction house threshold, Scrap junk, Baganator groups).
- `/kos` now only opens the options panel; the `factor`, `scrap` and `sets` subcommands are gone.
- Tooltip line explaining where an item goes and why (can be switched off).
- Minimum auction house profit per item, after the 5% AH cut.
- Maximum auction price age: older Auctionator prices are ignored and the item is kept.
- New Profession group: reagents of known recipes that still give skill points are kept and never junk.
- Gear your class can never wear (e.g. mail or swords for a druid) goes to the auction house when tradeable and worth it, otherwise to junk. Gear you could wear is never junk.
- Grey and white gear that no quest needs and that isn't worth auctioning is junk; without an auction price once you have visited the auction house with Auctionator. Shirts, tabards and fishing poles are kept.
- Worn items get no tooltip line.
- Items for other classes ("Classes: Mage") are treated like gear your class can't use.
- The tooltip also says when an outdated auction price is the reason an item stays.
- Soulbound items are no longer put into the AuctionHouse group.

## 0.5.0

- No Baganator setup needed anymore: Quest and AuctionHouse appear as groups in the equipment sets category.
- Regular quest items are part of the Quest group.
- Quest group renamed from "Quest Objective" to "Quest".

## 0.4.1

- First release on CurseForge.
- Automated packaging via GitHub Actions.

## 0.4.0

- Renamed from BagQuestMarks to **KeepOrSell**, slash command `/kos`.
- English and German texts.

## 0.3.0

- Cheap trade goods are marked as junk via Scrap.

## 0.2.0

- "AuctionHouse" group based on Auctionator prices.

## 0.1.0

- Quest objective items reported to Baganator.
