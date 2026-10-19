# KeepOrSell

<img src="https://raw.githubusercontent.com/svengabr/KeepOrSell/main/media/logo.png" alt="KeepOrSell logo" width="128">

Ever stood at a vendor wondering if that weird item in your bag is worth something? KeepOrSell sorts your bags for you. It tells you what to keep, what to put on the auction house and what's just junk.

Good for new players, and for everyone who's tired of hovering over every single item.

![KeepOrSell](https://raw.githubusercontent.com/svengabr/KeepOrSell/main/media/gallery/01-overview.jpg)

## What it does

Your bag items end up in these groups:

- **Quest**: stuff a quest still needs. Keep it.
- **Open**: clams, boxes and everything else with "Right Click to Open". Each one takes its own bag slot, even when Baganator shows ten of them as one stack. Open them to free the space.
- **Unstacked**: several copies of something that doesn't stack (scrolls, for example). Baganator would show them as one stack; here you see every slot they take.
- **Profession**: materials for recipes that still give skill points, whether you know them already or can still learn them, plus those recipes themselves. Keep it, even if the AH pays well.
- **AuctionHouse**: sells for at least twice the vendor price on the AH. Put it up for sale.
- **Junk**: grey items, cheap trade goods nobody needs, gear your class can't ever wear, recipes you already know. Scrap sells it at the next vendor.
- **For alts**: profession materials and class items another of your characters needs (same ruleset and faction). Mail them over. Your own needs come first.
- **Disenchant** (enchanters only): green, blue and purple gear you'd otherwise sell, when its materials are worth more than the vendor or the AH pays. Soulbound gear you can't auction lands here too. The tooltip shows the average value and what you'll likely get, e.g. "80% Lesser Magic Essence ×1–2".

Hover over any item and the tooltip tells you which group it's in and why, for example "Auction house: AH 1g 20s, vendor 15s". For gear you can wear it also says what it would bring once you no longer need it: disenchanting, the auction house or the vendor, whichever pays most.

Not sure about an item? Then it stays. No auction price means no junk. And green or better gear you could wear never counts as junk, nor does anything saved in an equipment set.

Want to keep something KeepOrSell would sell? **Alt+Right-click** it in your bags. It stays from now on, also without Scrap; click again to undo. `/kos kept` lists what you marked. Forgot the shortcut? Hover the gold **?** in Baganator's bag window.

![Auction house](https://raw.githubusercontent.com/svengabr/KeepOrSell/main/media/gallery/02-auction-house.jpg)

![Profession materials](https://raw.githubusercontent.com/svengabr/KeepOrSell/main/media/gallery/03-profession.jpg)

![Quest items](https://raw.githubusercontent.com/svengabr/KeepOrSell/main/media/gallery/04-quest.jpg)

![Junk](https://raw.githubusercontent.com/svengabr/KeepOrSell/main/media/gallery/05-junk.jpg)

![Disenchant](https://raw.githubusercontent.com/svengabr/KeepOrSell/main/media/gallery/06-disenchant.jpg)

## A few extras

- **Destroy button**: bags full and no vendor around? Click it and the cheapest junk in your bags is gone. Hover it to see what's next. It never touches rare or better items, and skips junk in profession bags (that wouldn't free a slot for anything else).
- **Loot coins**: loot with full bags, and a gold coin marks the loot that's worth more than the junk it would replace. Hover the loot to see which item to destroy for it, and the destroy button lights up. Loot that still fits onto a stack or into a profession bag needs no room and gets no coin.
- **Bag value**: a small line shows what your junk and your auction items are worth, e.g. "Junk 1g 20s · AH 15g".
- **Hints**: if KeepOrSell needs something from you (like a fresh AH scan), a little button shows up in your bag window.
- **Warnings**: destroy or sell something KeepOrSell would keep (a quest item, a reagent, an item you marked) and a warning in chat says why.
- **Account mode**: KeepOrSell thinks of your other characters too. Reagents that still give one of them skill points and the class items of their class (candles, poisons, totems …) go to "For alts", with their name in the tooltip. Each character logs in once with KeepOrSell; in the options you can leave single characters out.
- **Price sharing**: in a group, everyone with KeepOrSell keeps each other's auction prices fresh. Whoever has the newer price shares it.

![Bag tools](https://raw.githubusercontent.com/svengabr/KeepOrSell/main/media/gallery/07-bag-tools.jpg)

## Sharing filters

A filter is your setup as plain text: the decision options (e.g. factor, minimum profit, price age and the junk, profession and disenchant switches), your keep marks and your own rules. Post it in a forum or Discord, or paste someone else's.

- `/kos export` shows your filter. Select all, copy, share.
- `/kos import` opens an empty box. Paste a filter and press **Check**: it lists what would change (options, new keep marks, number of rules, ignored lines). **Apply** only works on a checked text. "Undo last import" in the options restores your options and rules and removes the keep marks the import added.
- `/kos rule <item> <group>` sets a rule for one item (groups: `keep`, `profession`, `ah`, `disenchant`, `junk`; `clear` removes it), `/kos rules` lists all rules.

```
KeepOrSell filter 1
name = Leveling
factor = 3
keep = 2589, 4306
item 2592 = junk                       # Wool Cloth
class 7 subclass 5 quality 0-1 = junk  # Trade Goods: Cloth, only grey or with a cheap, recent price
```

An item rule names one item and is as strong as Scrap's own junk list. A category rule is careful: it never junks green or better gear you can wear or items Forever added, and it junks other items only when they are grey, white bound items with a vendor price, or items with a known, recent price below the auction threshold. Quest items, keep marks, equipment sets, tools and class items always win over a filter. The text is only data, nothing in it is ever run, and lines KeepOrSell doesn't understand are dropped and counted.

## What you need

- [Baganator](https://www.curseforge.com/wow/addons/baganator): shows the groups in your bags (category view)
- [Auctionator](https://www.curseforge.com/wow/addons/auctionator): for prices. Scan the auction house once, otherwise there's nothing to compare.
- [TradeSkillMaster](https://www.curseforge.com/wow/addons/tradeskill-master) (optional, for advanced users): fills in prices Auctionator doesn't have. Auctionator's price always wins.
- [Scrap](https://www.curseforge.com/wow/addons/scrap) (optional): sells your junk automatically
- [Questie](https://www.curseforge.com/wow/addons/questie) (optional): without it, only quests in your log count. With it, KeepOrSell also keeps items for quests you haven't picked up yet (within 5 levels of you), and quest items from quests you're done with become junk. That includes items that start a quest (like the library books in Season of Discovery content) or that a quest hands you, whatever their item class; as long as the quest is open, they stay in the Quest group.

## Getting started

1. Install it via the [CurseForge](https://www.curseforge.com/wow/addons/keeporsell) app or drop it into `Interface/AddOns`.
2. Log in: a setup window shows what's still missing. One click there switches Baganator to category groups (as its own Baganator profile "KeepOrSell", your old one stays), and it explains how to scan with Auctionator. Open it again any time with `/kos setup`.
3. Scan the auction house once with Auctionator.
4. Open each of your profession windows once, so KeepOrSell knows your recipes.

That's it. The groups show up in Baganator inside the equipment sets category. Want them somewhere else? Move that category in Baganator (Bags → cog → Categories).

## Options

Esc → Options → AddOns → **KeepOrSell**, or just type `/kos`.

You can change how much more the AH price has to be (default 2×), set a minimum profit, ignore old prices (default: older than 7 days) and turn each part on or off: junk rules, profession materials (also those for recipes you haven't learned yet), account mode (what your other characters need, each character can be left out), disenchanting, Questie, Alt+Right-click to keep, tooltip, hints, destroy button, loot coins, bag value, price sharing. One button forgets every item you marked to keep. Options that need an addon you don't have are greyed out, and at the bottom you can see which of the addons are installed.

If you mark something as "not junk" in Scrap, KeepOrSell won't argue.

---

![Options](https://raw.githubusercontent.com/svengabr/KeepOrSell/main/media/gallery/08-options.jpg)

## Deutsch

Schon mal beim Händler gestanden und dich gefragt, ob das komische Item in der Tasche was wert ist? KeepOrSell sortiert deine Taschen für dich: was du behältst, was ins Auktionshaus kann und was einfach Schrott ist.

**Die Gruppen:**

- **Quest**: brauchst du noch für eine Quest. Behalten.
- **Öffnen**: Muscheln, Kisten und alles mit „Zum Öffnen rechtsklicken“. Jedes Stück belegt einen eigenen Taschenplatz, auch wenn Baganator zehn davon als einen Stapel zeigt. Aufmachen, dann ist wieder Platz.
- **Stapelt nicht**: mehrere Exemplare von etwas, das nicht stapelt (zum Beispiel Schriftrollen). Baganator würde sie als einen Stapel zeigen, hier siehst du jeden Platz, den sie belegen.
- **Beruf**: Material für Rezepte, die noch Skillpunkte geben, egal ob du sie schon kannst oder noch lernen kannst, und diese Rezepte selbst. Behalten, auch wenn das AH gut zahlt.
- **Auktionshaus**: bringt im AH mindestens das Doppelte vom Händlerpreis. Reinstellen.
- **Schrott**: graues Zeug, billige Handwerkswaren, Ausrüstung, die deine Klasse nie tragen kann, Rezepte, die du schon kennst. Scrap verkauft das beim nächsten Händler.
- **Für Twinks**: Berufsmaterial und Klassenitems, die ein anderer deiner Charaktere braucht (gleiches Ruleset, gleiche Fraktion). Per Post schicken. Was du selbst brauchst, geht vor.
- **Entzaubern** (nur für Verzauberer): grüne, blaue und lila Ausrüstung, die du sonst verkaufen würdest, wenn ihre Materialien mehr bringen als Händler oder AH. Auch seelengebundene Ausrüstung, die nicht ins AH darf. Der Tooltip zeigt den Durchschnittswert und was wahrscheinlich rauskommt.

Fahr mit der Maus über ein Item, und der Tooltip sagt dir, wo es hingehört und warum. Bei Ausrüstung, die du tragen kannst, steht dazu, was sie dir bringt, falls du sie nicht mehr brauchst: Entzaubern, Auktionshaus oder Händler, je nachdem, was am meisten bringt. Im Zweifel bleibt ein Item in der Tasche: Ohne Auktionspreis wird nichts zu Schrott, und grüne oder bessere Ausrüstung, die du tragen kannst, sowieso nie, genauso wenig wie alles aus einem Ausrüstungsset. Willst du etwas behalten, das KeepOrSell verkaufen würde? **Alt+Rechtsklick** darauf in der Tasche, dann bleibt es, auch ohne Scrap. Kürzel vergessen? Der **? KoS**-Knopf im Baganator-Taschenfenster zeigt sie beim Drüberfahren. Nochmal klicken hebt es auf, `/kos kept` listet alles Markierte.

**Extras:** Ein Knopf im Taschenfenster zerstört mit jedem Klick den billigsten Schrott, falls die Taschen voll sind und kein Händler in der Nähe ist (nie seltene oder bessere Items, nie aus Berufstaschen). Sind die Taschen beim Looten voll, markiert eine Goldmünze die Beute, die mehr wert ist als der Schrott, den sie ersetzen würde; der Tooltip der Beute sagt, was du dafür zerstören solltest, und der Knopf leuchtet. Beute, die noch auf einen Stapel passt, bekommt keine Münze. Daneben siehst du, was dein Schrott und deine AH-Items wert sind. In der Gruppe teilen sich alle mit KeepOrSell gegenseitig die frischeren Auktionspreise. Zerstörst oder verkaufst du etwas, das KeepOrSell behalten würde, sagt eine Warnung im Chat, warum. Im Account-Modus denkt KeepOrSell auch an deine Twinks: Zutaten, die einem von ihnen noch Skillpunkte geben, und Klassenitems seiner Klasse (Kerzen, Gifte, Totems …) landen in „Für Twinks“, mit seinem Namen im Tooltip. Jeder Charakter loggt sich dafür einmal mit KeepOrSell ein; in den Optionen kannst du einzelne auslassen.

**Du brauchst:** Baganator und Auctionator (einmal das AH scannen). Scrap und Questie sind optional. Mit Questie werden Quest-Items zu Schrott, sobald alle ihre Quests erledigt sind – auch Items, die eine Quest starten (etwa die Bibliotheksbücher) oder die dir eine Quest gibt. Solange die Quest offen ist, bleiben sie in der Gruppe Quest.

**Optional für Fortgeschrittene:** TradeSkillMaster. Hat Auctionator keinen Preis, nimmt KeepOrSell den von TSM.

**Loslegen:** installieren und einloggen. Ein Einrichtungsfenster zeigt, was noch fehlt, schaltet Baganator mit einem Klick auf Kategorie-Gruppen um (als eigenes Baganator-Profil „KeepOrSell“, dein altes bleibt) und erklärt den Scan mit Auctionator. Wieder öffnen mit `/kos setup`. Dann einmal das AH mit Auctionator scannen und jedes Berufsfenster einmal öffnen. Fertig. Einstellungen gibt's unter Esc → Optionen → AddOns → **KeepOrSell** oder mit `/kos`.

**Filter teilen:** Ein Filter ist dein Setup als Text: die Entscheidungs-Optionen (z. B. Faktor, Mindestgewinn, Preisalter, Schalter für Schrott, Beruf und Entzaubern), deine Behalten-Markierungen und eigene Regeln. `/kos export` zeigt ihn zum Kopieren, `/kos import` nimmt einen fremden. „Prüfen“ zeigt vorher, was sich ändern würde, erst dann geht „Übernehmen“. „Import rückgängig machen“ in den Optionen (Knopf „Rückgängig“) stellt Optionen und Regeln wieder her und entfernt die Markierungen, die der Import dazugebracht hat. `/kos rule <Item> <Gruppe>` setzt eine Regel für ein Item (`keep`, `profession`, `ah`, `disenchant`, `junk`, `clear` löscht sie), `/kos rules` listet alle Regeln. Eine Item-Regel ist so stark wie Scraps eigene Liste. Eine Kategorie-Regel macht nie grüne oder bessere tragbare Ausrüstung oder von Forever neu hinzugefügte Items zu Schrott, andere Items nur, wenn sie grau sind, weiße gebundene Items mit Händlerpreis oder Items mit einem bekannten, frischen Preis unter der Auktionsschwelle. Quest-Items, Markierungen, Ausrüstungssets, Werkzeuge und Klassen-Items gehen immer vor. Der Text besteht nur aus Daten und wird nie ausgeführt; Zeilen, die KeepOrSell nicht versteht, werden verworfen und gezählt.

**Unterstützen:** KeepOrSell ist kostenlos und bleibt es auch. Wenn es dir das Spiel ein bisschen leichter macht, kannst du mir [einen Kaffee ausgeben](https://buymeacoffee.com/conoar).

## Support

KeepOrSell is free and always will be. If it made your game a bit nicer, you can [buy me a coffee](https://buymeacoffee.com/conoar).

## License

GPL-3.0-or-later · Download: https://www.curseforge.com/wow/addons/keeporsell · Source & issues: https://github.com/svengabr/KeepOrSell
