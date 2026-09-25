extends Area2D
## Nepřítel: drží si směr, kterým se pohybuje.
##
## PROČ VLASTNÍ SKRIPT: do uzlu vytvořeného přes `Area2D.new()` se NEDÁ přidat
## vlastní vlastnost. `e.smer = Vector2(...)` skončí chybou
## „Invalid assignment of property or key 'smer' with value of type 'Vector2'
## on a base object of type 'Area2D'" – a protože chyba přeruší funkci, nepřítel
## se ani nepřidá do scény a ve hře prostě chybí. Přesně to se stalo v PR #9
## (testy to nepoznaly, protože se nic nepřidalo a testy se ptaly jen na mince).
##
## Vlastní skript vlastnost deklaruje, takže přiřazení funguje a uzly zůstávají
## Area2D – nic se nemusí předělávat na jiný typ uzlu.
##
## Pohyb nepřítele řídí scéna (`game.gd` → `_move_enemies`) podle skupiny
## "enemy", proto tu žádný `_physics_process` není. Prázdný `_physics_process`
## s `if is_dead: return` tu chvíli byl (PR #32) a nic nedělal – hlídač
## `tools/check-wiring.py` na takové zbytky upozorňuje.

var smer: Vector2 = Vector2.ZERO
var rychlost_nasobic: float = 1.0
