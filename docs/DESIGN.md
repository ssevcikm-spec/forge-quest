# Překážkový Skok

> **Záměr:** Pokracuj ve vyvoji plosinovky: pridej obtiznost a cil hry - nepritel, ktereho jde porazit skokem na hlavu, ukazatel prubehu urovne, plynuly prechod mezi urovnemi a zaverecna obrazovka po dokonceni posledni urovne.

> **Vzhled:** varianta `autumn`

**Žánr:** platformer s obtížností a výzvami  
**Pilíř:** Jedinečná mechanika porážky nepřátel skokem na hlavu a dynamická obtížnost

## Vize

Hráč ovládá postavu, která běží a skáče po dlaždicové mapě, zabíjí nepřátele skokem na hlavu, postupuje skrze 7 úrovní, které se stávají stále obtížnějšími, a končí výherní obrazovkou s časem a výsledkem. Hra vypadá minimalisticky s jasnou paletou a velkými spritami pro snadné vnímání. Hudba vytváří napětí během levelu a uvolnění po vítězství.

## Mechaniky

- Skok na hlavu nepřátel (detekce kolize zhora)
- Postupné zvýšování rychlosti nepřátel podle levelu
- Ukazatel průběhu úrovně (1/7)
- Plynulý přechod mezi úrovněmi (animace zmizení a objevení mapy)
- Obrazovka po dokončení poslední úrovně s časem a skóre

## Jak to má vypadat

- **Grafika:** Minimalistické designy s jasnou paletou (modré, žluté, černé). Sprity mají rozměry 64x64px. Nepřátelé mají jasné kontury a animace pro 'poražení'. Ukazatel průběhu je obdélníkem s červenou barvou.
- **Zvuk:** Hudba má středně tempo s náhlými tóny při porážce nepřátel. Zvuky skoků a zásahů jsou krátce a akcentovaně. Přechod mezi úrovněmi zahrnuje zvuk 'překročení' a zvuky mapy.

## Rozsah

Do projektu se vejde 7 úrovní s nepřáteli, ukazatel průběhu, plynulý přechod mezi levely a obrazovka vítězství. Vynecháváme mnohoúrovňové výzvy, komplexní AI nepřátel a multiplayer.

## Plán prací

| # | Úkol | id |
|---|---|---|
| 1 | Nepřítel, který se dá porazit skokem | `pridat-neprijatel` |
| 2 | Ukazatel průběhu úrovně | `pridat-ukazatel` |
| 3 | Plynulý přechod mezi úrovněmi | `plynuly-prijit` |
| 4 | Obrazovka po dokončení poslední úrovně | `vyherni-obrazovka` |

---

*Tenhle dokument vygeneroval plánovač (`forge plan`) a je zadáním pro orchestr: jednotlivé úkoly jsou v `.forge/roadmap.json`. Slabší modely je plní po jednom; dokument je tu proto, aby se neztratila vize.*
