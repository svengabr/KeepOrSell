# Bag Quest Marks

Markiert in Baganator alle Items, die eine Quest im Questlog als Ziel verlangt
(z. B. „6/10 Magere Wolfflanke“) – auch normales Handwerksmaterial, das Baganator
selbst nicht als Quest-Gegenstand erkennt.

- Eckmarkierung oben links: gelb = Ziel offen, grün = erfüllt, Quest noch nicht abgegeben.
- Set-Modus (Standard an): meldet die Items zusätzlich als Set „Questziel“ an Baganator.
- Mit Auctionator: Sets „Auktionshaus“ (Auktionspreis ≥ Faktor × Händlerpreis, Standard 2) und „Händler“ (darunter). Ohne bekannten Auktionspreis kein Set. Faktor: `/bqm faktor 3`.
- Mit Scrap: Handwerkswaren der Stufe „Händler“ (nicht Questziel) gelten als Schrott und werden von Scrap verkauft. Scraps eigene Liste und „kein Schrott“-Markierungen haben Vorrang. Aus: `/bqm scrap`.
- `/bqm` listet die erkannten Items, `/bqm set` schaltet den Set-Modus um (danach `/reload`).

Nutzt ausschließlich die öffentliche `Baganator.API`, kein Questie nötig.

Tests: `python -m unittest discover -s tests -v` (lupa)
