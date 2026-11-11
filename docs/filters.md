# Sharing filters

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
