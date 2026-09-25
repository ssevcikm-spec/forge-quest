#!/usr/bin/env python
r"""Ověří, že hra opravdu vykreslila mapu z JSON – buňku po buňce, měřením.

PROČ: screenshot se dá „zkontrolovat očima", jenže to je dojem a nedá se to
pustit v CI. Tenhle skript porovná snímek hry s mřížkou v .json: u každého
políčka zjistí barvu pixelu v jeho středu a přiřadí ji k nejbližší dlaždicové
paletě (kámen = podlaha, cihla = zeď, hlína = chodba). Když mapa sedí, souhlasí
skoro všechno; když se vykreslí špatně (posun, přehozené vrstvy, chybějící
dlaždice), je to hned vidět v číslech.

Použití:
    python tools/verify-level-render.py <snimek.png> <uroven.json> [--tolerance N]
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image

# Palety jsou stejné jako v pipeline/tiles.py (drží hru pohromadě).
PALETTES = {
    "stone": [(64, 66, 74), (84, 86, 94), (104, 106, 114), (126, 128, 136)],
    "brick": [(96, 46, 40), (120, 58, 48), (142, 74, 58), (70, 70, 76)],
    "dirt": [(72, 52, 38), (92, 68, 48), (112, 84, 58), (132, 102, 70)],
    "grass": [(34, 78, 42), (48, 104, 54), (64, 130, 66), (86, 154, 78), (110, 176, 92)],
    "sand": [(168, 142, 96), (190, 164, 116), (210, 186, 138), (228, 206, 162)],
    "water": [(24, 60, 108), (32, 82, 140), (44, 108, 170), (62, 136, 198)],
}

# Entity stojí NA dlaždicích, takže jejich pixely k terénu nepatří. Když se
# buňka netrefí do dlaždice, ale do některé z těchto barev, není to chyba mapy.
ENTITY_COLORS = {
    "mince": (255, 217, 51),
    "hráč (fallback)": (89, 217, 255),
    "nepřítel (fallback)": (255, 0, 0),
    "truhla (fallback)": (204, 128, 51),
}


def nearest_palette(rgb: tuple[int, int, int]) -> tuple[str, float]:
    best, best_d = "?", 1e9
    for name, colors in PALETTES.items():
        for c in colors:
            d = sum((a - b) ** 2 for a, b in zip(rgb, c)) ** 0.5
            if d < best_d:
                best, best_d = name, d
    return best, best_d


def auto_ignore(level_path: Path, level: dict) -> list[tuple[int, int, int, int]]:
    """Sám najde oblasti, které dlaždice legitimně překrývají.

    Konkrétně miniaturu mapy: když vedle úrovně leží `../scripts/game.gd`
    a mluví o uzlu Minimap, vyjme se její obdélník (120×64 v pravém dolním
    rohu). Díky tomu se nemusí rozměry opisovat do CI workflow – a když hru
    miniaturu nemá, nic se nevyjímá.
    """
    # Hru hledáme směrem nahoru od úrovně: v repu je to <repo>/scripts/game.gd,
    # v projektu <projekt>/scripts/game.gd, ale úroveň může být i hlouběji.
    hra = None
    for predchudce in (level_path.parent, *level_path.parents):
        kandidat = predchudce / "scripts" / "game.gd"
        if kandidat.is_file():
            hra = kandidat
            break
    if hra is None:
        return []
    try:
        kod = hra.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    if "Minimap" not in kod:
        return []
    vp = level.get("viewport") or [480, 270]
    return [(int(vp[0]) - 124, int(vp[1]) - 68, 124, 68)]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("shot")
    ap.add_argument("level")
    ap.add_argument("--tolerance", type=float, default=40.0,
                    help="jak daleko může být barva od palety, aby se ještě uznala")
    ap.add_argument("--min-agreement", type=float, default=0.75,
                    help="minimální podíl políček, která musí sedět")
    ap.add_argument("--ignore-rect", action="append", default=[],
                    metavar="X,Y,W,H",
                    help="oblast, která se nepočítá (např. miniatura mapy v rohu); "
                         "lze zadat vícekrát")
    args = ap.parse_args()

    ignorovat: list[tuple[int, int, int, int]] = []
    for spec in args.ignore_rect:
        try:
            x, y, w, h = (int(v) for v in spec.split(","))
        except ValueError:
            print(f"CHYBA: --ignore-rect má být 'X,Y,W,H', ne '{spec}'")
            return 2
        ignorovat.append((x, y, w, h))

    img = Image.open(args.shot).convert("RGB")
    level_path = Path(args.level)
    level = json.loads(level_path.read_text(encoding="utf-8"))
    # Co si nástroj najde sám (miniatura mapy) – k ručním oblastem se přidá.
    auto = auto_ignore(level_path, level)
    if auto:
        print(f"Automaticky vyjímám oblasti: {auto} (miniatura mapy)")
    ignorovat += auto
    grid = level["grid"]
    cell = int(level["cell"])
    off_x, off_y = level.get("offset", [0, 0])
    want = {k: v for k, v in level["tiles"].items()}  # "0" -> brick, "1" -> stone, "2" -> dirt

    ok = 0
    total = 0
    entities = 0
    overlays = 0
    wrong: list[str] = []
    outside = 0
    # Entity mívají sprite větší než jedno políčko, takže povolíme i sousedy
    # značky. (HUD text nahoře zůstává jako zbytková odchylka – proto se
    # porovnává s tolerancí, ne na 100 %.)
    marker_cells = set()
    for m in level.get("markers", []):
        mx, my = int(m["cell"][0]), int(m["cell"][1])
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                marker_cells.add((mx + dx, my + dy))
    for y, row in enumerate(grid):
        for x, znak in enumerate(row):
            px = int(off_x + x * cell + cell / 2)
            py = int(off_y + y * cell + cell / 2)
            if px < 0 or py < 0 or px >= img.width or py >= img.height:
                outside += 1
                continue
            # Oblasti, které dlaždice legitimně překrývají (miniatura mapy, HUD)
            if any(rx <= px < rx + rw and ry <= py < ry + rh
                   for rx, ry, rw, rh in ignorovat):
                overlays += 1
                continue
            total += 1
            rgb = img.getpixel((px, py))
            seen, dist = nearest_palette(rgb)
            expected = want.get(znak, "?")
            if seen == expected:
                ok += 1
                continue
            # Je to entita? (kreslí se nad dlaždicí, takže ji překryje)
            entity = min(ENTITY_COLORS.items(),
                         key=lambda kv: sum((a - b) ** 2 for a, b in zip(rgb, kv[1])))
            entity_d = sum((a - b) ** 2 for a, b in zip(rgb, entity[1])) ** 0.5
            if entity_d <= 60.0:
                entities += 1
                if (x, y) not in marker_cells:
                    wrong.append(f"({x},{y}) {entity[0]} mimo značku mapy")
                continue
            if len(wrong) < 8:
                wrong.append(f"({x},{y}) čekáno {expected}, vidím {seen} "
                             f"vzdálenost {dist:.0f}px")

    terrain = total - entities
    ratio = ok / terrain if terrain else 0.0
    print(f"Snímek {img.width}×{img.height}, úroveň {len(grid[0])}×{len(grid)} "
          f"po {cell}px, offset {[off_x, off_y]}")
    print(f"Terén sedí {ok}/{terrain} políček = {ratio * 100:.1f}% "
          f"(překrytých entitami: {entities}, ignorovaných oblastí: {overlays}, "
          f"mimo snímek: {outside})")
    for w in wrong:
        print(f"  chyba: {w}")
    if ratio < args.min_agreement:
        print(f"SELHÁNÍ: pod {args.min_agreement * 100:.0f}% – mapa se nevykreslila podle JSON")
        return 1
    print("OK: vykreslená mapa odpovídá mřížce v JSON")
    return 0


if __name__ == "__main__":
    sys.exit(main())
