extends SceneTree
## Testy projektu – spouští se bez okna i bez grafické karty:
##
##     godot --headless --path <projekt> --script res://tests/run_tests.gd
##
## Když všechny kontroly projdou, skončí s kódem 0. Každé selhání kód zvýší,
## takže se výsledek dá použít v CI i v ručním ověření.

var failures := 0
var checks := 0


func _initialize() -> void:
	_run()


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

	var player = main.get_node_or_null("Player")
	_check(player != null, "scéna vytvořila uzel Player")

	var expected := 5
	var consts = main.get_script().get_script_constant_map()
	if consts.has("COIN_COUNT"):
		expected = consts["COIN_COUNT"]
	var coins := get_nodes_in_group("coin")
	_check(coins.size() == expected,
		"počet mincí odpovídá COIN_COUNT (%d, nalezeno %d)" % [expected, coins.size()])

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
					 "res://assets/tiles", "res://assets/ui"]:
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

	_finish()


func _finish() -> void:
	print("\n[test] %d kontrol, %d selhání" % [checks, failures])
	quit(failures)
