# Konvence pro agenty (čti před každou změnou)

Tenhle soubor je **jen ke čtení** – agent ho dostává do kontextu a nemá ho měnit.
Vznikl z konkrétních chyb, které už jednou prošly a shodily testy. Každé
pravidlo má dole důvod, proč tam je.

## 1. GDScript: typy piš výslovně, `:=` jen když je typ známý

Nejčastější chyba free modelů: `var cil := uzel.position + uzel.smer * 40 * delta`.
Uzel z `get_nodes_in_group()` **nemá typ**, takže Godot ohlásí
`Cannot infer the type of "cil" variable because the value doesn't have a set type`,
skript hry se vůbec nenačte a **celá hra přestane existovat** (testy pak hlásí
„skript hry jde načíst" jako FAIL).

```gdscript
# ŠPATNĚ – spadne na parsování
for uzel in get_tree().get_nodes_in_group("enemy"):
    var cil := uzel.position + uzel.smer * 40.0 * delta

# SPRÁVNĚ – výslovný typ, uzel zůstává bez typu
for uzel in get_tree().get_nodes_in_group("enemy"):
    var cil: Vector2 = uzel.position + uzel.smer * 40.0 * delta
    uzel.position = cil
```

Platí to i pro `get_tree().get_first_node_in_group(...)`, `get_node_or_null(...)`
a cokoli dalšího, co vrací `Node`/`Variant` bez konkrétního typu.

## 2. Když se skript hry nenačte, poznáš to hned

Testy to řeknou („skript hry jde načíst"), ale **spustit si je musí CI** – ty
sám Godot nemáš. Proto: změnu dělej malou, v jednom souboru, a nikdy
nepřepisuj celý soubor, když měníš pár řádků.

## 3. Hra je postavená programově

Celá scéna se staví v `scripts/game.gd` (uzly se vytvářejí v kódu, žádné
ukládané `.tscn` kromě `main.tscn`). Když přidáváš uzel:

- dej mu `name` (testy a hledání podle skupin se o to opírají),
- přidej ho do skupiny (`coin`, `enemy`, `chest`, `player`), když se s ním má
  něco dít,
- nepřidávej nové soubory, když to jde udělat v `scripts/game.gd`.

## 4. Mapa (úroveň) – jak se ptát, kudy se dá chodit

Mapu spravuje uzel `Level` ve skupině `level` (`scripts/level.gd`):

| Metoda | Co vrací |
|---|---|
| `is_walkable_at(pozice: Vector2) -> bool` | je na té pozici průchozí políčko? |
| `is_walkable_cell(cx: int, cy: int) -> bool` | totéž pro políčko v mřížce |
| `cell_center(cx: int, cy: int) -> Vector2` | střed políčka ve světových souřadnicích |
| `marker_positions("coin"\|"spawn"\|"exit") -> Array` | pozice značek z mapy |
| `spawn_cell -> Vector2i`, `width`, `height`, `cell` | rozměry mřížky |

Nový předmět **nikdy neumisťuj na náhodnou pozici** – s mapou by mohl skončit ve
zdi. Použij `_safe_spot(vp)` (už v `game.gd` je) nebo `marker_positions()`.

## 5. Co agent nesmí měnit

`tests/`, `.github/`, `.forge/`, `project.godot` – to jsou pravidla hry
a automatického sloučení. Když agent sáhne na testy, ztratí tím páku, která
hlídá jeho vlastní práci. Automatické sloučení navíc pustí jen změny
v `scripts/` a `assets/` do 60 řádků.

## 6. Styl

- Komentáře a texty v UI **česky** (HUD, hlášky), kód anglicky podle okolí.
- Změna musí být **aditivní**: nic nemaž a nepřejmenovávej, co funguje.
- Když si nejsi jistý, udělej méně – malý správný krok je lepší než velký
  rozbitý.

## 7. Ověření

Testy běží v CI na každý PR (`Godot --headless`): 31 kontrol. Když něco
nevyjde, je to vidět v logu jako `[test] FAIL …` – čti ten řádek, ne celý log.
