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

var score := 0
var player: Area2D
var hud: Label
var sfx := {}
var paused := false
var pause_label: Label
var fps_label: Label

func _ready() -> void:
	randomize()
	_load_sfx()
	_add_background()
	_add_music()
	player = _make_player()
	add_child(player)

	var vp := get_viewport_rect().size
	for i in COIN_COUNT:
		var c := _make_coin(i, vp)
		add_child(c)

	_add_ui()
	print("[game] připraveno: hráč + %d mincí, zvuků načteno: %d, dlaždice: %s" % [
		COIN_COUNT, sfx.size(), "ano" if _texture("tiles/grass") else "ne"])

	# Přidání nepřátel
	var enemy1 := _make_enemy("Enemy1", vp)
	add_child(enemy1)
	var enemy2 := _make_enemy("Enemy2", vp)
	add_child(enemy2)

	# Přidání truhly
	var chest := _make_chest(vp)
	add_child(chest)


func _update_hud() -> void:
	if hud:
		hud.text = "Score: %d / %d (sipky = pohyb)" % [score, COIN_COUNT]


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
	p.position = get_viewport_rect().size / 2.0
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


func _make_coin(index: int, vp: Vector2) -> Area2D:
	var c := Area2D.new()
	c.name = "Coin%d" % (index + 1)
	c.add_to_group("coin")
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 5.0
	shape.shape = circle
	c.add_child(shape)
	c.add_child(_visual("coin", Color(1.0, 0.85, 0.2), Vector2(8, 8)))
	c.position = Vector2(randf_range(24.0, vp.x - 24.0), randf_range(24.0, vp.y - 24.0))
	c.area_entered.connect(_on_coin_touched.bind(c))
	return c


func _on_coin_touched(other: Area2D, coin: Area2D) -> void:
	if other != player or not is_instance_valid(coin) or not coin.is_in_group("coin"):
		return
	score += 1
	play_sfx("coin")
	coin.remove_from_group("coin")
	coin.queue_free()
	_update_hud()
	if score >= COIN_COUNT:
		play_sfx("win")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_SPACE and event.pressed:
		paused = not paused
		get_tree().paused = paused
		pause_label.visible = paused


func _process(delta: float) -> void:
	if fps_label:
		fps_label.text = "FPS: %d" % Engine.get_frames_per_second()


func _make_enemy(name: String, vp: Vector2) -> Area2D:
	var e := Area2D.new()
	e.name = name
	e.add_to_group("enemy")
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 5.0
	shape.shape = circle
	e.add_child(shape)
	e.add_child(_visual("enemy", Color(1.0, 0.0, 0.0), Vector2(8, 8)))
	e.position = Vector2(randf_range(24.0, vp.x - 24.0), randf_range(24.0, vp.y - 24.0))
	e.area_entered.connect(_on_enemy_touched.bind(e))
	return e


func _on_enemy_touched(other: Area2D, enemy: Area2D) -> void:
	if other != player or not is_instance_valid(enemy) or not enemy.is_in_group("enemy"):
		return
	play_sfx("hurt")


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
	c.position = Vector2(vp.x / 2.0, vp.y / 2.0)
	c.area_entered.connect(_on_chest_touched.bind(c))
	return c


func _on_chest_touched(other: Area2D, chest: Area2D) -> void:
	if other != player or not is_instance_valid(chest) or not chest.is_in_group("chest"):
		return
	play_sfx("powerup")
	chest.remove_from_group("chest")
	chest.queue_free()
