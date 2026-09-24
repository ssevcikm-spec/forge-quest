extends Node2D
## Mapa úrovně postavená z JSON, který vygeneroval `forge level`.
##
## PROČ JSON A NE .tscn: mapa musí být text, který se dá diffovat v gitu a který
## zvládne přečíst i AI agent (u binárních scén s UID se to nedaří). Uzel si
## z mřížky postaví dlaždice za běhu – a hlavně umí odpovědět na jednu otázku,
## na které stojí pohyb hráče: „je tohle políčko průchozí?"
##
## Mřížka je řádek na řádek, znak na buňku: 0 = zeď, 1 = podlaha místnosti,
## 2 = chodba. Konvence je stejná v Pythonu (pipeline/levels.py) i tady.

const TILE_DIR := "res://assets/tiles/"
const DEFAULT_TILES := {"0": "brick", "1": "stone", "2": "dirt"}

var source := ""
var level_name := ""
var cell := 16
var offset := Vector2.ZERO
var grid := PackedStringArray()
var width := 0
var height := 0
var tile_names := {}
var markers: Array = []
var spawn_cell := Vector2i.ZERO
var stats := {}

var _textures := {}


func load_file(path: String) -> bool:
	"""Načte úroveň ze souboru. Vrací false, když soubor chybí nebo je poškozený."""
	if not FileAccess.file_exists(path):
		return false
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if not (data is Dictionary):
		push_error("[level] %s není platné JSON" % path)
		return false

	source = path
	level_name = str(data.get("name", ""))
	cell = int(data.get("cell", 16))
	width = int(data.get("width", 0))
	height = int(data.get("height", 0))
	grid = PackedStringArray(data.get("grid", []))
	markers = data.get("markers", [])
	stats = data.get("stats", {})
	tile_names = data.get("tiles", DEFAULT_TILES)

	var off: Array = data.get("offset", [0, 0])
	if off.size() >= 2:
		offset = Vector2(float(off[0]), float(off[1]))

	# Hlavička a mřížka si musí odpovídat – poškozený soubor se nesmí tiše použít.
	if width <= 0 or height <= 0 or grid.size() != height:
		push_error("[level] %s: mřížka nesedí s hlavičkou (%d řádků, čekáno %d)"
			% [path, grid.size(), height])
		return false
	for row in grid:
		if row.length() != width:
			push_error("[level] %s: řádek má %d znaků, čekáno %d" % [path, row.length(), width])
			return false

	for m in markers:
		if str(m.get("type", "")) == "spawn":
			var c: Array = m.get("cell", [0, 0])
			spawn_cell = Vector2i(int(c[0]), int(c[1]))
	return true


func build() -> void:
	"""Postaví dlaždice jako Sprite2D. Bez vygenerovaných dlaždic zůstane jen
	mřížka (mapa se nevykreslí, ale logika průchodnosti funguje dál)."""
	for child in get_children():
		child.queue_free()

	for y in height:
		for x in width:
			var name := _tile_for(grid[y][x])
			var tex := _texture(name)
			if tex == null:
				continue
			var s := Sprite2D.new()
			s.name = "T%d_%d" % [x, y]
			s.texture = tex
			s.centered = false
			# Střed = pozice bez zaokrouhlení, aby dlaždice na sebe přesně sedly
			# (u neceločíselného měřítka vznikají jinak jednopixelové spáry).
			s.position = offset + Vector2(x * cell, y * cell)
			s.scale = Vector2(float(cell) / float(tex.get_width()),
							  float(cell) / float(tex.get_height()))
			s.z_index = 0 if grid[y][x] != "0" else 1
			add_child(s)
	print("[level] %s: %d×%d políček po %dpx, dlaždic: %d, značek: %d"
		% [level_name, width, height, cell, get_child_count(), markers.size()])


func _tile_for(znak: String) -> String:
	return str(tile_names.get(znak, DEFAULT_TILES.get(znak, "stone")))


func _texture(tile_name: String) -> Texture2D:
	if _textures.has(tile_name):
		return _textures[tile_name]
	var path := TILE_DIR + tile_name + ".png"
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_textures[tile_name] = tex
	return tex


# ------------------------------------------------------------- průchodnost ----
func is_walkable_cell(cx: int, cy: int) -> bool:
	"""Průchozí je jen políčko uvnitř mapy, které není zeď ("0")."""
	if cx < 0 or cy < 0 or cx >= width or cy >= height:
		return false
	return grid[cy][cx] != "0"


func cell_at(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor((pos.x - offset.x) / float(cell))),
					int(floor((pos.y - offset.y) / float(cell))))


func is_walkable_at(pos: Vector2) -> bool:
	var c := cell_at(pos)
	return is_walkable_cell(c.x, c.y)


func cell_center(cx: int, cy: int) -> Vector2:
	return offset + Vector2(cx * cell + cell / 2.0, cy * cell + cell / 2.0)


func markers_of(type: String) -> Array:
	var out: Array = []
	for m in markers:
		if str(m.get("type", "")) == type:
			out.append(m)
	return out


func marker_positions(type: String) -> Array:
	var out: Array = []
	for m in markers_of(type):
		var c: Array = m.get("cell", [0, 0])
		out.append(cell_center(int(c[0]), int(c[1])))
	return out


func walkable_count() -> int:
	var n := 0
	for y in height:
		for x in width:
			if grid[y][x] != "0":
				n += 1
	return n


func reachable_count(from_cell := Vector2i(-1, -1)) -> int:
	"""Spočítá dosažitelná políčka ze spawnu – stejné ověření jako v Pythonu,
	ale tady nad tím, co má hra skutečně načtené."""
	if from_cell.x < 0:
		from_cell = spawn_cell
	if not is_walkable_cell(from_cell.x, from_cell.y):
		return 0
	var seen := {from_cell: true}
	var front: Array[Vector2i] = [from_cell]
	while not front.is_empty():
		var c: Vector2i = front.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if is_walkable_cell(n.x, n.y) and not seen.has(n):
				seen[n] = true
				front.append(n)
	return seen.size()
