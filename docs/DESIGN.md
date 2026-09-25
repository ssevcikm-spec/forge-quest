# Pokladnice Stínů

> **Záměr:** Hra je hratelna, ale chybi ji cil a smycka: hrac nema duvod ji hrat znovu. Pridej postup (vice urovni / cil) a restart nebo menu. Co uz ve hre je: mapa, mince, neprately, truhla, zivoty, skore, shield, hybnost, tres obrazovky.

**Žánr:** Akční dungeon crawler  
**Pilíř:** Postupný průchod labyrinty se sběrem mincí pro odemčení cesty dál.

## Vize

Hráč se ocitá v temných kobkách, kde musí v každém patře sesbírat dostatek mincí, aby se aktivovala truhla (brána) do další úrovně. Atmosféra je napínavá, nepřátelé jsou s každým patrem rychlejší a nebezpečnější. Hráč musí balancovat mezi rizikem sběru a bezpečným ústupem k východu. Cílem je projít všechny tři úrovně s co nejvyšším skóre. Po dokončení nebo smrti má hráč možnost okamžitého restartu, což podporuje opakované hraní pro překonání rekordu.

## Mechaniky

- Odemknutí východu (truhly) po nasbírání určitého počtu mincí
- Lineární postup skrze 3 úrovně se zvyšující se obtížností
- Restartovací smyčka pomocí klávesy R po prohře či výhře
- HUD zobrazující aktuální úroveň a zbývající mince

## Jak to má vypadat

- **Grafika:** Temné 2D prostředí, barevné odlišení entit (mince zlatá, hráč modrý, nepřátelé červení), velikost spritů 32x32 pixelů.
- **Zvuk:** Tajemná hudba na pozadí, cinkavý zvuk při sběru a výrazný fanfárový zvuk při průchodu úrovní.

## Rozsah

3 úrovně definované v JSON souborech, základní nepřátelé, systém životů a skóre. Vynecháváme nákupy vylepšení a komplexní inventář.

## Plán prací

| # | Úkol | id |
|---|---|---|
| 1 | Správa indexu úrovní | `level-progression-state` |
| 2 | Odemčení východu mincemi | `chest-unlock-logic` |
| 3 | Systém restartu hry | `game-restart-logic` |
| 4 | Zobrazení čísla úrovně | `hud-level-display` |
| 5 | Zvyšování obtížnosti | `enemy-scaling-difficulty` |
| 6 | Čištění scény při přechodu | `level-transition-cleanup` |

---

*Tenhle dokument vygeneroval plánovač (`forge plan`) a je zadáním pro orchestr: jednotlivé úkoly jsou v `.forge/roadmap.json`. Slabší modely je plní po jednom; dokument je tu proto, aby se neztratila vize.*
