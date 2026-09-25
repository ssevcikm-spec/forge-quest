# Stínový Sběratel

**Žánr:** Akční arkáda v bludišti  
**Pilíř:** Zvyšování rychlosti po sběru mincí a ochrana štítem z truhly.

## Vize

Hráč se ocitá v temném bludišti, kde musí posbírat všechny mince, aby vyhrál. S každou mincí se hráč na moment zrychlí, což vyžaduje postřeh. Nepřátelé se pohybují rychleji, čím méně mincí na mapě zbývá. Jedinou záchranou jsou truhly, které poskytují dočasnou nezranitelnost. Hra působí dynamicky a odměňuje riskantní průlety kolem nepřátel.

## Mechaniky

- Bonus k rychlosti hráče po sebrání mince
- Energetický štít z truhly blokující poškození
- Škálování rychlosti nepřátel podle zbývajících mincí
- Vizuální zpětná vazba (třes HUDu a změna barvy hráče)
- Postupné snižování bonusové rychlosti v čase

## Jak to má vypadat

- **Grafika:** Temné pozadí, neonově modrý hráč, fialoví nepřátelé, zářící zlaté mince. Sprity 32x32 pixelů.
- **Zvuk:** Rychlý syntezátorový soundtrack, vysoké cinknutí mince, tupý náraz při zásahu.

## Rozsah

3 úrovně v bludišti, zaměřeno na pohyb a interakci entit bez inventáře.

## Plán prací

| # | Úkol | id |
|---|---|---|
| 1 | Základ hybnosti hráče | `player-momentum-base` |
| 2 | Impuls ze sebrané mince | `coin-speed-trigger` |
| 3 | Mechanika štítu z truhly | `shield-logic-chest` |
| 4 | Dynamické zrychlení nepřátel | `enemy-dynamic-speed` |
| 5 | Třes obrazovky při zásahu | `hit-shake-effect` |
| 6 | Vizuální indikace štítu | `visual-shield-feedback` |

---

*Tenhle dokument vygeneroval plánovač (`forge plan`) a je zadáním pro orchestr: jednotlivé úkoly jsou v `.forge/roadmap.json`. Slabší modely je plní po jednom; dokument je tu proto, aby se neztratila vize.*
