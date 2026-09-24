extends SceneTree
## Testy projektu – spouští se bez okna i bez grafické karty:
##
##     godot --headless --path <projekt> --script res://tests/run_tests.gd
##
## Když všechny kontroly projdou, skončí s kódem 0. Každé selhání kód zvýší,
## takže se výsledek dá použít v CI i v ručním ověření.
##
## POZOR – HLÍDAČ: testy musí skončit VŽDY. Když se nepodaří načíst skript hry
## (typicky chyba v kódu od agenta), GDScript přeruší běh _run() a na quit()
## se nikdy nedostane – proces pak visí, dokud ho nezabije CI. Naměřeno: 14
## minut čekání v GitHub Actions místo okamžitého selhání. Proto běží hlídač,
## který po HARD_LIMIT_SECONDS skončí sám (a řekne, že šlo o zaseknutí).
##
## Žebříček limitů (musí na sebe navazovat): hlídač 90 s < vnější `timeout 150`
## v CI < timeout kroku 3 min. Když zamrzne samotný engine (nekonečná smyčka),
## hlídač se nedostane ke slovu – proto je tam i ten vnější.

const HARD_LIMIT_SECONDS := 90.0

var failures := 0
var checks := 0
var _deadline := 0.0
var _done := false


func _initialize() -> void:
	_deadline = Time.get_ticks_msec() / 1000.0 + HARD_LIMIT_SECONDS
	_run()


func _process(_delta: float) -> bool:
	"""Hlídač: kdyby se _run() zasekl nebo přerušil, stejně se skončí."""
	if _done:
		return true
	if Time.get_ticks_msec() / 1000.0 > _deadline:
		print("[test] FAIL překročen tvrdý limit %.0f s – testy se zasekly."
			% HARD_LIMIT_SECONDS)
		print("[test]      Nejpravděpodobnější příčina: skript hry se nepodařilo "
			+ "načíst (chyba v kódu), takže se _run() přerušil.")
		failures += 1
		_finish()
	return false


func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("[test] OK   ", label)
	else:
		failures += 1
		print("[test] FAIL ", label)


func _run() -> void:
	await process_frame

	var packed := load("res://main.tscn")
	_check(packed != null, "main.tscn jde načíst")
	if packed == null:
		_finish()
		return

	var main = packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	# Když se skript hry vůbec nenačetl (parse error), nemá cenu pokračovat:
	# volání na null by přerušilo tenhle běh a testy by nikdy neskončily.
	var main_script = main.get_script()
	_check(main_script != null, "skript hry jde načíst (žádná chyba v kódu)")
	if main_script == null:
		_finish()
		return

	var player = main.get_node_or_null("Player")
	_check(player != null, "scéna vytvořila uzel Player")

	var expected := 5
	var consts = main_script.get_script_constant_map()
	if consts.has("COIN_COUNT"):
		expected = consts["COIN_COUNT"]
	# S úrovní určuje počet mincí mapa, ne konstanta.
	var ct = main.get("coin_total")
	if ct != null:
		expected = int(ct)
	var coins := get_nodes_in_group("coin")
	_check(coins.size() == expected,
		"počet mincí odpovídá očekávání (%d, nalezeno %d)" % [expected, coins.size()])

	var hud = main.get_node_or_null("Hud")
	_check(hud != null, "HUD s výsledkem existuje")
	if hud != null:
		_check(String(hud.text).contains("0"), "HUD ukazuje počáteční skóre: '%s'" % hud.text)

	if player != null and coins.size() > 0:
		var before: int = main.score
		main._on_coin_touched(player, coins[0])
		await process_frame
		_check(main.score == before + 1,
			"sebrání mince zvýší skóre (%d -> %d)" % [before, main.score])

	# Všechno, co je v projektu k dispozici, musí jít načíst.
	var missing := 0
	var loaded := 0
	for dir_path in ["res://assets/sprites", "res://assets/audio/sfx",
					 "res://assets/audio/music", "res://assets/tiles", "res://assets/ui",
					 "res://assets/levels"]:
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		for f in d.get_files():
			if f.ends_with(".import") or f.begins_with("."):
				continue
			var res_path: String = str(dir_path) + "/" + str(f)
			if ResourceLoader.exists(res_path) and load(res_path) != null:
				loaded += 1
			else:
				missing += 1
				print("[test]      nelze načíst: ", res_path)
	_check(missing == 0, "všechny assety jdou načíst (%d OK, %d chybí)" % [loaded, missing])

	# Animace: co je v assets/animations.json, se musí dát načíst jako SpriteFrames.
	# Tohle je zároveň ověření, že ručně zapisovaný formát .tres sedí.
	var anim_file := "res://assets/animations.json"
	if FileAccess.file_exists(anim_file):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(anim_file))
		var anims: Array = []
		if parsed is Dictionary:
			anims = parsed.get("animations", [])
		_check(anims.size() > 0, "animations.json obsahuje %d animací" % anims.size())
		for a in anims:
			var res: String = str(a.get("sprite_frames_resource", ""))
			_check(ResourceLoader.exists(res), "resource animace existuje: %s" % res)
			if not ResourceLoader.exists(res):
				continue
			var res_frames = load(res)
			_check(res_frames is SpriteFrames, "načte se jako SpriteFrames: %s" % res)
			if res_frames is SpriteFrames:
				var nm: String = str(a.get("name", ""))
				_check(res_frames.has_animation(nm), "animace '%s' je v resource" % nm)
				if res_frames.has_animation(nm):
					var n: int = res_frames.get_frame_count(nm)
					var expected_frames: int = (a.get("frames", []) as Array).size()
					_check(n == expected_frames,
						"počet framů animace '%s' sedí (%d)" % [nm, n])

	# ------------------------------------------------------------- úroveň ----
	# Mapa se testuje vlastnostmi, ne vzhledem: musí se z ní dát projít všude,
	# mince musí ležet na průchozích políčkách a zeď musí hráče zastavit.
	if FileAccess.file_exists("res://assets/levels/main.json"):
		_check(true, "úroveň main.json je v projektu")
		var lvl = main.get_node_or_null("Level")
		_check(lvl != null, "mapa je postavená ve scéně")
		if lvl != null:
			_check(lvl.is_walkable_cell(lvl.spawn_cell.x, lvl.spawn_cell.y),
				"spawn je na průchozím políčku %s" % str(lvl.spawn_cell))
			_check(lvl.reachable_count() == lvl.walkable_count(),
				"z každého políčka se dá dojít na spawn (%d z %d)"
				% [lvl.reachable_count(), lvl.walkable_count()])
			_check(lvl.get_child_count() == lvl.width * lvl.height,
				"mapa má dlaždici pro každé políčko (%d)" % lvl.get_child_count())

			# Vrstvy: mapa musí být nad pozadím (jinak ji celoobrazovková tráva
			# schová) a hráč nad mapou. Testy dřív prošly, i když mapa nebyla
			# vidět – dlaždice ve scéně byly, jen se kreslily pod pozadím.
			var bg_node = main.get_node_or_null("Background")
			var bg_z: int = bg_node.z_index if bg_node != null else -99
			if bg_node != null:
				_check(lvl.z_index > bg_z,
					"mapa se kreslí nad pozadím (mapa %d, pozadí %d)" % [lvl.z_index, bg_z])
			if player != null:
				_check(player.z_index > lvl.z_index + 1,
					"hráč se kreslí nad mapou (hráč %d, zeď %d)"
					% [player.z_index, lvl.z_index + 1])

			var bad_markers := 0
			for kind in ["coin", "exit", "spawn"]:
				for pos in lvl.marker_positions(kind):
					if not lvl.is_walkable_at(pos):
						bad_markers += 1
			_check(bad_markers == 0, "všechny značky leží na průchozích políčkách")

			if player != null:
				_check(lvl.is_walkable_at(player.position),
					"hráč startuje na průchozím políčku %s" % str(player.position))

				# Najdi zeď vedle průchozího políčka a zkus do ní vstoupit.
				var from_cell := Vector2i(-1, -1)
				var wall_cell := Vector2i(-1, -1)
				for y in lvl.height:
					for x in lvl.width:
						if not lvl.is_walkable_cell(x, y):
							continue
						for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
							var n: Vector2i = Vector2i(x, y) + d
							if n.x > 0 and n.y > 0 and n.x < lvl.width - 1 and n.y < lvl.height - 1 \
									and not lvl.is_walkable_cell(n.x, n.y):
								from_cell = Vector2i(x, y)
								wall_cell = n
								break
						if wall_cell.x >= 0:
							break
					if wall_cell.x >= 0:
						break
				_check(wall_cell.x >= 0, "našla se zeď sousedící s chodbou")
				if wall_cell.x >= 0:
					var back: Vector2 = player.position
					player.position = lvl.cell_center(from_cell.x, from_cell.y)
					var moved: Vector2 = player._step(lvl.cell_center(wall_cell.x, wall_cell.y))
					_check(lvl.cell_at(moved) != wall_cell,
						"hráč se nedostane do zdi %s (skončil v %s)"
						% [str(wall_cell), str(lvl.cell_at(moved))])
					_check(lvl.is_walkable_at(moved),
						"i po nárazu do zdi zůstane hráč na průchozím políčku")
					player.position = back

	# ---------------------------------------------------------- dlaždice ----
	# Dlaždice a UI musí být nejen na disku, ale i VE SCÉNĚ.
	# Tohle je regresní test na konkrétní vadu: pozadí se sice načetlo, ale mělo
	# nulovou velikost, takže se vůbec nevykreslilo (odhalil to až vision model
	# nad snímkem hry). Test to teď pozná sám.
	if ResourceLoader.exists("res://assets/tiles/grass.png"):
		var bg = main.get_node_or_null("Background")
		_check(bg != null, "dlaždicové pozadí je ve scéně")
		if bg != null:
			_check(bg.size.x > 0.0 and bg.size.y > 0.0,
				"pozadí má nenulovou velikost (%s)" % str(bg.size))

	if ResourceLoader.exists("res://assets/ui/panel.png"):
		_check(main.get_node_or_null("HudPanel") != null, "UI panel je ve scéně")

	# Hudba: soubor na disku nestačí, musí hrát a mít zapnutou smyčku.
	if DirAccess.open("res://assets/audio/music") != null:
		var music = main.get_node_or_null("Music")
		_check(music != null, "hudba je ve scéně")
		if music != null and music.stream is AudioStreamWAV:
			_check(music.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD,
				"hudba má zapnutou smyčku")
			# Konec smyčky musí odpovídat CELÉ délce skladby, jinak se hudba
			# uřízne (přesně to se stalo, když se počet vzorků počítal z bajtů).
			var expected_loop_end: int = int(music.stream.get_length() * music.stream.mix_rate)
			_check(abs(music.stream.loop_end - expected_loop_end) <= 2,
				"konec smyčky sedí s délkou skladby (%d vs %d)" % [music.stream.loop_end, expected_loop_end])

	# ------------------------------------------------------------ entity ----
	# Nepřátelé (když je projekt má) se musí hýbat a nesmí vlézt do zdi.
	# Test vznikl proto, že tahle vlastnost přišla od agenta bez testu – na
	# rozbití by se přišlo až ve hře.
	var enemies := get_nodes_in_group("enemy")
	if enemies.size() > 0:
		var before: Array = []
		for e in enemies:
			before.append(e.position)
		for i in 30:
			await process_frame
		var moved := 0.0
		for i in enemies.size():
			moved += before[i].distance_to(enemies[i].position)
		_check(moved > 0.5, "nepřátelé se hýbou (celkem %.1f px za 30 snímků)" % moved)

		var lvl_node = main.get_node_or_null("Level")
		if lvl_node != null:
			var mimo := 0
			for e in enemies:
				if not lvl_node.is_walkable_at(e.position):
					mimo += 1
			_check(mimo == 0, "nepřátelé zůstávají na průchozích políčkách (%d mimo)" % mimo)

	_finish()


func _finish() -> void:
	_done = true
	print("\n[test] %d kontrol, %d selhání" % [checks, failures])
	quit(failures)

# GameForge: overeno AI
