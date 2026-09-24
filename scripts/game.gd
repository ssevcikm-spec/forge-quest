extends Node2D
## Hlavní scéna startovní šablony: hráč sbírá mince.
##
## Celá scéna se staví programově (žádné ukládané .tscn kromě main.tscn), protože
## tak ji umí agent vygenerovat a upravit jako text. Assety se načítají z
## res://assets – když v projektu ještě nejsou, použije se barevný obdélník,
## takže hra je hratelná i před vygenerováním grafiky.

const COIN_COUNT := 5
const SPRITE_DIR := "res://assets/sprites/"
const SFX_DIR := "res://assets/audio/sfx/"
const LEVEL_DIR := "res://assets/levels/"
const LEVEL_NAME := "main"

var score := 0
var coin_total := COIN_COUNT
var best: int = 0
var lives: int = 3
var player: Area2D
var level: Node2D
var hud: Label
var sfx := {}
var cas_hry: float = 0.0
var paused := false
var pause_label: Label
var fps_label: Label

func _ready() -> void:
	_load_best()
	randomize()
	_load_sfx()
	_add_background()
	_add_music()
	_add_level()
	player = _make_player()
	add_child(player)

	var vp := get_viewport_rect().size
	var spots := _coin_spots(vp)
	coin_total = spots.size()
	for i in coin_total:
		add_child(_make_coin(i, spots[i]))

	_add_ui()
	print("[game] připraveno: hráč + %d mincí, zvuků načteno: %d, dlaždice: %s, úroveň: %s" % [
		coin_total, sfx.size(), "ano" if _texture("tiles/grass") else "ne",
		"%s %d×%d" % [level.level_name, level.width, level.height] if level else "ne"])

	# Přidání nepřátel
	var enemy1 := _make_enemy("Enemy1", vp)
	add_child(enemy1)
	var enemy2 := _make_enemy("Enemy2", vp)
	add_child(enemy2)

	# Přidání truhly
	var chest := _make_chest(vp)
	add_child(chest)

	# Přidání miniaturu mapy
	if ResourceLoader.exists("res://assets/levels/main.preview.png"):
		var minimap := TextureRect.new()
		minimap.name = "Minimap"
		minimap.texture = load("res://assets/levels/main.preview.png")
		minimap.position = Vector2(get_viewport_rect().size.x - 120 - 4, get_viewport_rect().size.y - 64 - 4)
		# POZOR na pořadí: expand_mode musí být nastavený před size a size až
		# POTÉ, co je uzel ve stromu. TextureRect má výchozí EXPAND_KEEP_SIZE
		# („minimální velikost = velikost textury"), náhled mapy je 480×256,
		# takže se nastavených 120×64 tiše zahodilo a miniatura zakryla celou
		# obrazovku. Uvnitř _ready() se rozvržení dopočítá až po přidání do
		# stromu – proto se velikost nastavuje až za add_child.
		minimap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		minimap.custom_minimum_size = Vector2(120, 64)
		minimap.stretch_mode = TextureRect.STRETCH_SCALE
		minimap.z_index = 8
		add_child(minimap)
		minimap.size = Vector2(120, 64)

		var dot := ColorRect.new()
		dot.name = "MinimapDot"
		dot.color = Color(0.35, 0.85, 1.0)
		dot.size = Vector2(3, 3)
		dot.z_index = 9
		minimap.add_child(dot)


func _update_hud() -> void:
	if hud:
		hud.text = "Skóre: %d / %d (nejlepší: %d)   Životy: %d" % [score, coin_total, best, lives]


# ----------------------------------------------------------------- assety ----
func _texture(rel: String) -> Texture2D:
	"""Načte texturu z res://assets/<rel>.png (např. "sprites/player", "tiles/grass")."""
	var path := "res://assets/%s.png" % rel
	if ResourceLoader.exists(path):
		return load(path)
	return null


func _add_background() -> void:
	"""Dlaždicová podloha z assets/tiles. Bez ní zůstane jen jednolitá barva."""
	var tex := _texture("tiles/grass")
	if tex == null:
		return
	var vp := get_viewport_rect().size
	var bg := TextureRect.new()
	bg.name = "Background"
	bg.texture = tex
	# Pozadi je cela obrazovka, takze musi byt vespod (viz test vrstev).
	bg.z_index = -3
	# Dlaždice se opakuje přes celou obrazovku – proto se vyplatilo, že beze švu.
	bg.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	bg.stretch_mode = TextureRect.STRETCH_TILE
	# POZOR: rodič je Node2D, ne Control – anchory se proti němu nepočítají
	# a velikost zůstane nulová (ověřeno: pozadí se pak vůbec nevykreslilo).
	# Velikost se proto nastavuje natvrdo podle viewportu.
	bg.position = Vector2.ZERO
	bg.size = vp
	bg.show_behind_parent = true
	add_child(bg)
	move_child(bg, 0)


func _add_music() -> void:
	"""Hudba na pozadí. Smyčku nastavujeme v kódu, protože import .wav ji sám
	nezapne – a skladby z `forge music` jsou dělané přesně pro smyčku."""
	for track in ["theme", "chiptune", "calm"]:
		var path := "res://assets/audio/music/%s.wav" % track
		if not ResourceLoader.exists(path):
			continue
		var stream = load(path)
		if stream is AudioStreamWAV:
			# Konec smyčky se bere z DÉLKY, ne z velikosti dat: Godot umí .wav
			# importovat komprimovaně (IMA ADPCM), takže přepočet z bajtů vyjde
			# špatně – naměřeno 519 200 místo 1 283 050 vzorků, což by skladbu
			# uřízlo ve dvou pětinách.
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = int(stream.get_length() * stream.mix_rate)
		var player := AudioStreamPlayer.new()
		player.name = "Music"
		player.stream = stream
		player.volume_db = -9.0
		add_child(player)
		player.play()
		print("[game] hudba: %s" % track)
		return


func _add_level() -> void:
	"""Postaví mapu z assets/levels/<nazev>.json (generuje `forge level`).
	Když úroveň v projektu není, hra se hraje na holé ploše – pořád hratelná."""
	var path := LEVEL_DIR + LEVEL_NAME + ".json"
	if not FileAccess.file_exists(path):
		print("[game] úroveň %s není – hraju bez mapy" % path)
		return
	var script = load("res://scripts/level.gd")
	if script == null:
		return
	var node := Node2D.new()
	node.name = "Level"
	node.set_script(script)
	node.add_to_group("level")
	if not node.load_file(path):
		node.queue_free()
		return
	# Dlaždice kreslíme pod vším ostatním: zdi mají z_index 1 (aby zakryly spáry
	# mezi podlahou), takže bez posunu by přelezly hráče. Odsazení celé mapy
	# o -2 posune i její potomky (z_as_relative je výchozí), hráč zůstane nahoře.
	node.z_index = -1
	level = node
	add_child(level)
	level.build()


func _coin_spots(vp: Vector2) -> Array:
	"""Mince stojí tam, kde je vyznačila mapa (středy místností – ověřeně
	průchozí). Bez mapy se rozhodí náhodně jako dřív."""
	var spots: Array = []
	if level:
		spots = level.marker_positions("coin")
	if spots.is_empty():
		for i in COIN_COUNT:
			spots.append(Vector2(randf_range(24.0, vp.x - 24.0), randf_range(24.0, vp.y - 24.0)))
	return spots


func _add_ui() -> void:
	"""HUD s panelem z assets/ui (devět řezů). Bez assetu zůstane holý text."""
	var panel_tex := _texture("ui/panel")
	if panel_tex:
		var panel := NinePatchRect.new()
		panel.name = "HudPanel"
		panel.texture = panel_tex
		panel.patch_margin_left = 4
		panel.patch_margin_top = 4
		panel.patch_margin_right = 4
		panel.patch_margin_bottom = 4
		panel.position = Vector2(4, 4)
		panel.size = Vector2(150, 26)
		panel.show_behind_parent = true
		add_child(panel)

	hud = Label.new()
	hud.name = "Hud"
	hud.position = Vector2(10, 8)
	add_child(hud)
	_update_hud()

	pause_label = Label.new()
	pause_label.name = "PauseLabel"
	pause_label.text = "PAUZA"
	pause_label.position = get_viewport_rect().size / 2.0
	pause_label.visible = false
	add_child(pause_label)

	fps_label = Label.new()
	fps_label.name = "Fps"
	fps_label.position = Vector2(get_viewport_rect().size.x - 100, 8)
	add_child(fps_label)


func _visual(asset_name: String, fallback: Color, size: Vector2) -> Node2D:
	var holder := Node2D.new()
	var tex := _texture("sprites/%s" % asset_name)
	if tex:
		var s := Sprite2D.new()
		s.texture = tex
		holder.add_child(s)
	else:
		var rect := ColorRect.new()
		rect.color = fallback
		rect.size = size
		rect.position = -size / 2.0
		holder.add_child(rect)
	return holder


func _load_sfx() -> void:
	var dir := DirAccess.open(SFX_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		if not f.ends_with(".wav"):
			continue
		var res_path := SFX_DIR + f
		if ResourceLoader.exists(res_path):
			sfx[f.get_basename()] = load(res_path)


func play_sfx(sfx_name: String) -> void:
	if not sfx.has(sfx_name):
		return
	var p := AudioStreamPlayer.new()
	p.stream = sfx[sfx_name]
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# ------------------------------------------------------------------ entity ----
func _make_player() -> Area2D:
	var p := Area2D.new()
	p.name = "Player"
	p.set_script(load("res://scripts/player.gd"))
	# Start z mapy (spawn), jinak střed obrazovky.
	if level:
		p.position = level.cell_center(level.spawn_cell.x, level.spawn_cell.y)
	else:
		p.position = get_viewport_rect().size / 2.0
	p.z_index = 5
	# Když existuje animace (vygenerovaná přes `forge anim`), hráč se hýbe.
	# Jinak se použije statický sprite, případně barevný obdélník.
	var anim := _animation_visual("walk")
	if anim:
		p.add_child(anim)
	else:
		p.add_child(_visual("player", Color(0.35, 0.85, 1.0), Vector2(10, 10)))
	return p


func _animation_visual(anim_name: String) -> Node2D:
	"""Načte SpriteFrames vygenerované pipeline (assets/<nazev>.tres)."""
	var res_path := "res://assets/%s.tres" % anim_name
	if not ResourceLoader.exists(res_path):
		return null
	var frames = load(res_path)
	if not (frames is SpriteFrames) or not frames.has_animation(anim_name):
		return null
	var s := AnimatedSprite2D.new()
	s.name = "Animation"
	s.sprite_frames = frames
	s.animation = anim_name
	s.play()
	return s


func _make_coin(index: int, pos: Vector2) -> Area2D:
	var c := Area2D.new()
	c.name = "Coin%d" % (index + 1)
	c.add_to_group("coin")
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 5.0
	shape.shape = circle
	c.add_child(shape)
	c.add_child(_visual("coin", Color(1.0, 0.85, 0.2), Vector2(8, 8)))
	c.position = pos
	c.z_index = 3
	c.area_entered.connect(_on_coin_touched.bind(c))
	return c


func _on_coin_touched(other: Area2D, coin: Area2D) -> void:
	if other != player or not is_instance_valid(coin) or not coin.is_in_group("coin"):
		return
	score += 1
	if score > best:
		best = score
		_save_best()
	play_sfx("coin")
	coin.remove_from_group("coin")
	coin.queue_free()
	_update_hud()
	if score >= coin_total:
		play_sfx("win")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_SPACE and event.pressed:
		paused = not paused
		get_tree().paused = paused
		pause_label.visible = paused
	elif event is InputEventKey and event.keycode == KEY_M and event.pressed:
		var music := get_node_or_null('Music')
		if music:
			music.stream_paused = not music.stream_paused


func _update_minimap_dot() -> void:
	var minimap := get_node_or_null('Minimap')
	if minimap == null:
		return
	var dot := minimap.get_node_or_null('MinimapDot')
	if dot == null:
		return
	var vp: Vector2 = get_viewport_rect().size
	dot.position = Vector2(player.position.x / vp.x * 120.0, player.position.y / vp.y * 64.0)

func _process(delta: float) -> void:
	cas_hry += delta
	_spin_coins(cas_hry)
	if fps_label:
		fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	_move_enemies(delta)
	_update_minimap_dot()


func _safe_spot(vp: Vector2) -> Vector2:
	"""Náhodné místo, které je průchozí. Bez mapy je to cokoliv v obraze –
	s mapou by náhodná pozice mohla skončit ve zdi (to se stávalo).

	Navíc se vyhýbá místu, kde stojí hráč: nepřítel, který se objeví přímo na
	hráči, ho zraní dřív, než se hra rozeběhne."""
	if level == null:
		return Vector2(randf_range(24.0, vp.x - 24.0), randf_range(24.0, vp.y - 24.0))
	var odstup := 28.0
	for i in 40:
		var p := Vector2(randf_range(8.0, vp.x - 8.0), randf_range(8.0, vp.y - 8.0))
		if level.is_walkable_at(p) and (player == null or p.distance_to(player.position) >= odstup):
			return p
	return level.cell_center(level.spawn_cell.x, level.spawn_cell.y) + Vector2(odstup, odstup)


func _make_enemy(name: String, vp: Vector2) -> Area2D:
	var e := Area2D.new()
	e.name = name
	# Skript musí být na uzlu DŘÍV, než se nastaví 'smer': do Area2D.new() se
	# vlastní vlastnost přidat nedá (chyba „Invalid assignment of property or
	# key 'smer' ... on a base object of type 'Area2D'") a nepřítel by se
	# vůbec nepřidal do scény. Vlastnost deklaruje scripts/enemy.gd.
	e.set_script(load("res://scripts/enemy.gd"))
	e.add_to_group("enemy")
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 5.0
	shape.shape = circle
	e.add_child(shape)
	e.add_child(_visual("enemy", Color(1.0, 0.0, 0.0), Vector2(8, 8)))
	e.position = _safe_spot(vp)
	e.smer = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	e.area_entered.connect(_on_enemy_touched.bind(e))
	return e


func _on_enemy_touched(other: Area2D, enemy: Area2D) -> void:
	if other != player or not is_instance_valid(enemy) or not enemy.is_in_group("enemy"):
		return
	play_sfx("hurt")
	lives -= 1
	_update_hud()
	enemy.visible = false
	enemy.remove_from_group("enemy")
	enemy.queue_free()
	if lives <= 0:
		get_tree().paused = true


func _make_chest(vp: Vector2) -> Area2D:
	var c := Area2D.new()
	c.name = "Chest"
	c.add_to_group("chest")
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 5.0
	shape.shape = circle
	c.add_child(shape)
	c.add_child(_visual("chest", Color(0.8, 0.5, 0.2), Vector2(8, 8)))
	# Truhla patří k východu z úrovně – když mapa existuje, stojí přesně tam.
	var exits: Array = level.marker_positions("exit") if level else []
	c.position = exits[0] if not exits.is_empty() else _safe_spot(vp)
	c.area_entered.connect(_on_chest_touched.bind(c))
	return c


func _on_chest_touched(other: Area2D, chest: Area2D) -> void:
	if other != player or not is_instance_valid(chest) or not chest.is_in_group("chest"):
		return
	play_sfx("powerup")
	chest.remove_from_group("chest")
	chest.queue_free()


func _move_enemies(delta: float) -> void:
	var level_node := get_tree().get_first_node_in_group("level")
	for nepritel in get_tree().get_nodes_in_group("enemy"):
		var cil: Vector2 = nepritel.position + nepritel.smer * 40.0 * delta
		var vp := get_viewport_rect().size
		if level_node != null and level_node.has_method("is_walkable_at"):
			if not level_node.is_walkable_at(cil):
				nepritel.smer = -nepritel.smer
			else:
				nepritel.position = cil
		elif cil.x < 0 or cil.x > vp.x or cil.y < 0 or cil.y > vp.y:
			nepritel.smer = -nepritel.smer
		else:
			nepritel.position = cil
func _spin_coins(cas: float) -> void:
	for mince in get_tree().get_nodes_in_group("coin"):
		var faze: float = cas * 3.0 + float(mince.get_index())
		mince.scale = Vector2(abs(cos(faze)), 1.0)
func _load_best() -> void:
	var cfg := ConfigFile.new()
	var chyba: int = cfg.load('user://best.cfg')
	if chyba == OK:
		best = int(cfg.get_value('hra', 'skore', 0))

func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value('hra', 'skore', best)
	cfg.save('user://best.cfg')
