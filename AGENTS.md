# AGENTS.md

Notes for AI agents (Claude Code, Codex, Cursor …) working on KeepOrSell.

## What the addon does

WoW addon that sorts bag items into groups: **Quest** (keep), **Open** (clams, boxes: each takes a bag slot), **Profession** (reagents that still give
skill points), **AuctionHouse** (auction price ≥ factor × vendor price), **Disenchant** (enchanters only) and **Junk** via Scrap
(cheap trade goods, gear the class can never wear). A tooltip line explains the decision.
It relies on the public APIs of **Baganator**, **Auctionator**, **TradeSkillMaster**, **Scrap** and **QuestieDB**
(Questie's database addon). All five are optional (`OptionalDeps`); every integration must silently do nothing without its addon.

## Layout

Folders: `Locales/` texts, `Rules/` classification logic (testable without frames), `Integrations/` hooks into
other addons, `UI/` buttons and options, `Core/` startup, bag scan, dependencies. New files go into the matching
folder and into the TOC; the tests find them by name (`tests/addon.py`, `SOURCE_DIRS`). Load order is set in
`KeepOrSell.toc`. All files share the addon table `ns`.

| File | Content |
|---|---|
| `Locales/Locales.lua` | Texts in `ns.L`; English by default, `deDE` overrides |
| `Rules/Objectives.lua` | Reads quest objectives from the quest log (`ns.Refresh`, `ns.GetObjectiveState`, `ns.ParseObjectiveName`), pure logic |
| `Rules/Prices.lua` | Price classification `ns.ClassifyPrice` / `ns.ClassifyPrices` (minimum profit, price age), prices via Auctionator (`ns.GetPrices`), TSM only fills gaps (`ns.MergeFallback` pure) |
| `Integrations/TSM.lua` | `ns.GetTSMPrice`: TSM price `first(DBMinBuyout, DBMarket)` via `TSM_API`; used only when neither Auctionator nor a shared price exists, no age (`maxAge` doesn't apply), never shared, doesn't count as `ahVisited` |
| `Rules/Share.lua` | Shares auction prices within the group (addon messages): asks for the bag items, whoever has a fresher price answers (`ns.IsFresher` in `Prices.lua`) |
| `Rules/Gear.lua` | `ns.IsUnusableGear`: weapon/armor types a class can never learn; `ns.IsClassItem`: spell reagents and class tools by class (Thieves' Tools, totems, Light Feather …), kept no matter what (vendor reagents except Rebirth seeds and Light Feather are freed once the legacy talent "Reagent Economy" is known, `ns.HasReagentEconomy` via `C_SpellBook.IsSpellKnown(1225503)`); pure logic |
| `Rules/Professions.lua` | Remembers reagents of learned, non-grey recipes per character (`KeepOrSellDB.recipes`) when the profession window opens; follows learned recipes that craft one reagent into another (`KeepOrSellDB.crafts`, `ns.ReagentIndex` pure: dust → particles → skill-up recipe); also reagents of not-yet-learned, non-grey recipes (`KeepOrSellDB.upcoming`, `ns.IsUpcomingReagent`: Profession group even when worth auctioning, never junk); tells recipes apart as unlearned/known/other profession (`ns.GetRecipeState`) |
| `Rules/Questie.lua` | Upcoming quests via QuestieDB's public API (`LibQuestieDB`, contract 2): `ns.GetQuestieQuest`, pure selection `ns.PickQuestieQuest` (±5 levels, race/class, not completed); for items of class Quest and quest-only items `ns.GetQuestItemQuest` (any level, otherwise a completed quest) for the tooltip line. Own item→quest index over all quests (objectives, required source items, `startedBy` items, `sourceItemId`), built in chunks after login (`ns.BuildQuestieIndex`), because `Item.relatedQuests` is empty on Forever; `ns.IsQuestOnlyItem` = the item starts a quest or a quest hands it out (objectives like Linen Cloth don't count) |
| `Rules/Disenchant.lua` | Classic disenchant tables by item level (`ns.DisenchantOutcomes` pure), average value from Auctionator material prices (`ns.DisenchantValue`, `ns.GetPricesByID`; a missing price below 10% chance counts as 0, otherwise the value is unknown), `ns.DisenchantWins` pure: for enchanters (`ns.IsEnchanter`, option `disenchant`) junk/AH items go to the Disenchant group when worth more; bound items unless the vendor pays more; always when a material is a skill-up reagent |
| `Rules/Classify.lua` | One decision per item (`ns.Decide` pure, `ns.Classify` with API), used by Baganator, Scrap and the tooltip; one tooltip read per itemID for a class restriction; items to open via `hasLoot` of the bag slot or the tooltip line "<Right Click to Open>", never with a "Locked" line (`ns.IsOpenable` pure): openable items go to the Open group (option `openable`) right after the quest checks |
| `Integrations/Scrap.lua` | Hooks into `Scrap:IsJunk`; Scrap's own list and "not junk" marks take precedence |
| `Integrations/Baganator.lua` | Corner widget and item set source via `Baganator.API.*`; set items are never merged by Baganator, so copies that don't stack, sit in 2+ slots and have no other group (not gear, not junk) go to the Unstacked set (`ns.IsUnstackedSet` pure) |
| `Integrations/Tooltip.lua` | Tooltip line via `TooltipDataProcessor` (fallback `OnTooltipSetItem`); after an empty line the verdict, then two-column rows comparing disenchant / AH / vendor (`ns.TooltipRows` pure): the group's own way first in its color, for kept items the best one (AH after cut) as "Otherwise: …", the rest grey |
| `UI/Hints.lua` | Hints (`ns.CollectHints` pure; prices, professions, bag slots taken by items to open, items that don't stack in several slots via `ns.UnstackedList` pure): button in Baganator's bag window via `Baganator.API.RegisterRegion`, without Baganator once in chat |
| `UI/Setup.lua` | Setup window for new players, tiles with a sample bag and a progress bar, drawn only with Blizzard's own art (atlases checked with `C_Texture.GetAtlasExists`, item icons, Morpheus font), nothing shipped (`ns.SetupSteps`, `ns.SetupProgress`, `ns.SetupComplete`, `ns.ShouldShowSetup` pure): Baganator installed, category groups via a Baganator profile "KeepOrSell" imported with `Baganator.API.ImportString` (remembered per character in `KeepOrSellDB.baganatorSetup`, Baganator keeps the active profile per character), Auctionator installed, first scan (`ahVisited`); Scrap and Questie optional. Opens 5 s after login until done or `KeepOrSellDB.setupHidden`, waits for Baganator's own welcome window; `/kos setup`, options button, hints button while incomplete |
| `Core/Bags.lua` | `ns.CountSlots` (bag slots of one item), `ns.IsUnstackable` (max stack 1: Baganator may show copies as one stack, the tooltip and hints name the real slot count); one pass over the bags (`ns.ScanBags`, once per frame): junk per `Scrap:IsJunk` (without Scrap grey + `ns.ShouldScrap`), vendor value, AH value of the AuctionHouse group |
| `UI/Destroy.lua` | Destroy button in Baganator's bag window: cheapest junk by vendor price × stack (`ns.PickCheapest` pure, never locked or rare and above), candidates from `ns.ScanBags` (`ns.FindDestroyTarget`); `ns.DestroyTarget` checks slot and cursor before `DeleteCursorItem`; on "inventory full" in the loot window the button glows if the loot is worth more (`ns.LootWorthMore` pure) |
| `UI/BagValue.lua` | Bag value line in Baganator's bag window (`ns.SumBagValue`, `ns.FormatBagValue` pure) |
| `Core/Dependencies.lua` | Status of the optional addons (`ns.DependencyStatus` pure, `ns.GetDependencyStatus`), which option needs which addon (`ns.OPTION_NEEDS`, a list means any of them, `ns.IsAnyDependencyReady`), mixin for the row template in `UI/Options.xml` |
| `UI/Options.lua` | Options under Esc → Options → AddOns via the `Settings` API; options without their addon are greyed out (`AddModifyPredicate`), dependency list at the bottom |
| `Core/Core.lua` | SavedVariables `KeepOrSellDB`, events, slash command `/kos` (only opens the options) |

Baganator quirks: items with an item set always land in the Equipment Sets category, before any search and
regardless of priorities, so custom search categories on set names never match. There is no API for quest
addons. Baganator ships the Scrap junk plugin itself (`Baganator/API/Junk.lua`).

## Rules

- **English only in the repo**: the code is open source. Code comments (Lua and tests), commit messages,
  `AGENTS.md`, `CHANGELOG.md`, workflow files and all other docs are written in English. The only exceptions are
  player-facing translations: German strings in `Locales.lua`, `## Notes-deDE` in the TOC and the German section
  of `README.md`.
- **Public APIs only** of the other addons, no internals. Always check they exist
  (`if not (Baganator and Baganator.API ...) then return end`).
- **WoW: Forever only**: the TOC lists only Interface 16001, so CurseForge offers the addon for Forever only
  (Blizzard UI source: Gethe/wow-ui-source, branch `forever`). Don't add other flavors back. Forever uses the
  modern UI (`Settings`, `C_TradeSkillUI`/`Blizzard_Professions`, `TooltipDataProcessor`).
  `C_SettingsUtil.OpenSettingsPanel` (behind `Settings.OpenToCategory`) is blocked for addons there. Existing guards for API
  differences stay (e.g. `C_QuestLog.GetInfo` vs. the Classic quest log, `C_Item.GetItemInfo` vs. `GetItemInfo`).
- **When in doubt, keep**: without a known, recent auction price or item name nothing is marked as junk.
  TSM prices count as recent: TSM has no age API, and it is only asked when Auctionator and the group have no price.
  Junk is only trade goods (`classID 7`), grey/white gear (except shirts, tabards, fishing poles), gear the class
  can **never** wear (not even after later training), items with an unmet class/race requirement (tooltip line
  `UsageRequirement`/`RaceClass`, red), recipes that are already known or belong to a profession the character
  doesn't have (option `recipeJunk`), and quest items (`classID 12`, or of any class when QuestieDB lists them as
  quest starter or handed-out item) whose quests are all completed or not doable for the character according to
  QuestieDB (option `questie`). Never class items of the player's class (`ns.IsClassItem`), green or better wearable gear, consumables or
  other quest items. Wearable gear may go to the auction house (tradeable and worth it). For enchanters, green or better gear that would be junk or AuctionHouse goes to
  the Disenchant group instead when disenchanting is worth more (never junk). The only exception to
  "when in doubt": grey/white gear without an auction price counts as not worth it once the player has visited
  the AH with Auctionator (`KeepOrSellDB.ahVisited`).
- **New texts** always go into `Locales.lua`, in English and German.
- Keep pure logic (without WoW frames) in its own functions so it stays testable.
- Commit messages follow Conventional Commits (`feat:`, `fix:`, `chore:` …).
- `README.md` is English with a German section; `CHANGELOG.md` is English.
- The README is also the **CurseForge project description** (Markdown). CurseForge can't take it over via API;
  after README changes, remind the maintainer to paste it there by hand.

## Tests

Unit tests in Python with [lupa](https://pypi.org/project/lupa/) (Lua 5.1), WoW APIs are stubbed:

```bash
pip install lupa
python -m unittest discover -s tests -v
```

New logic gets a test. In-game behavior (frames, events, Baganator display) can only be checked in the client;
say so honestly.

**Checking against the Forever API:** `tests/data/forever_api.json` holds Blizzard's generated API docs
(functions, events, enums) from Gethe/wow-ui-source, branch `forever`. `tests/test_api.py` checks the addon
code against it (`C_*` calls, `Enum` values, events, globals from `.luacheckrc`), and every test stub for
`C_*`/`Enum` is checked against it on load (`tests/wowapi.py`). If something is missing from the docs but exists
anyway or is only used behind a guard, add it with a reason to `UNDOCUMENTED_FUNCTIONS` (`wowapi.py`) or
`NOT_IN_DOCS` (`test_api.py`). Regenerate after a client patch: `python tests/update_api.py`.

**luacheck:** `.luacheckrc` lists every global the addon uses; add new globals there.
Locally without a Lua install via Docker:
`docker run --rm -v "$PWD:/data" -w /data ghcr.io/lunarmodules/luacheck .`

Both run in `.github/workflows/test.yml` on push and pull request; the release workflow only starts after green
tests.

## Release

Publishing is automatic via `.github/workflows/release.yml` (BigWigsMods/packager) to CurseForge (project ID in
the TOC) and GitHub Releases.

1. Add the new version to `CHANGELOG.md` and commit.
2. Create an annotated tag `vX.Y.Z` and push it; that starts the upload.

Don't replace `## Version: @project-version@` by hand, the packager sets it from the tag. It sits in a `#@non-debug@`
block so a source checkout shows `dev` instead of the raw placeholder; the packager drops the `#@debug@` line and
uncomments the real one. The addon list icon is `Icon.tga` (64×64, scaled down from `media/logo.png`, whose source
is `media/logo.svg`).
New files or folders that don't belong in the addon ZIP go into `.pkgmeta` under `ignore`.
Tags and pushes only after the maintainer approves.
