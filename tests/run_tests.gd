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
	# Když hra nějaké entity vytváří, musí být OPRAVDU ve scéně. Tahle kontrola
	# je tady proto, že chyba uvnitř funkce _make_* (třeba přiřazení vlastnosti,
	# kterou Area2D nemá) funkci přeruší, uzel se vůbec nepřidá – a testy to
	# nezjistí, protože se ptají jen na mince. Přesně takhle přišla hra v PR #9
	# o nepřátele a CI přitom hlásilo úspěch.
	var enemies := get_nodes_in_group("enemy")
	if main.has_method("_make_enemy"):
		_check(enemies.size() > 0, "hra vytvořila nepřátele (nalezeno %d)" % enemies.size())
	if main.has_method("_make_chest"):
		_check(get_nodes_in_group("chest").size() > 0, "hra vytvořila truhlu")

	if enemies.size() > 0:
		var before: Array = []
		for e in enemies:
			before.append(e.position)
		# POZOR: v headless režimu se snímky vykreslují maximální rychlostí,
		# takže „30 snímků" je jen pár milisekund a nepřítel se posune
		# o setiny pixelu (naměřeno 0,0 px). Měří se proto SKUTEČNÝ čas.
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 400:
			await process_frame
		var elapsed := float(Time.get_ticks_msec() - t0) / 1000.0
		var moved := 0.0
		for i in enemies.size():
			moved += before[i].distance_to(enemies[i].position)
		_check(moved > 0.5,
			"nepřátelé se hýbou (celkem %.1f px za %.2f s)" % [moved, elapsed])

		var lvl_node = main.get_node_or_null("Level")
		if lvl_node != null:
			var mimo := 0
			for e in enemies:
				if not lvl_node.is_walkable_at(e.position):
					mimo += 1
			_check(mimo == 0, "nepřátelé zůstávají na průchozích políčkách (%d mimo)" % mimo)

	# -------------------------------------------------- volitelné funkce ----
	# Testy, které se samy zapnou, až hra danou funkci dostane. Rozhoduje se
	# podle zdrojového textu skriptu: dokud v něm funkce není, kontrola se
	# přeskočí (šablona je bez nich); jakmile ji agent přidá, začne platit.
	# Důvod: PR #9 prošel se zeleným CI, a přitom se část scény vůbec nevytvořila.
	var zdroj := FileAccess.get_file_as_string("res://scripts/game.gd")

	if zdroj.contains("Minimap"):
		var mini = main.get_node_or_null("Minimap")
		_check(mini != null, "miniatura mapy je ve scéně")
		if mini != null:
			# „Miniatura" musí být opravdu malá a v rohu. Test na pouhou
			# nenulovou velikost nestačil: TextureRect má výchozí minimální
			# velikost rovnou textuře, takže se nastavených 120×64 tiše zahodilo
			# a miniatura (480×256) zakryla celou obrazovku.
			_check(mini.size.x > 0.0 and mini.size.y > 0.0,
				"miniatura má nenulovou velikost (%s)" % str(mini.size))
			_check(mini.size.x <= 240.0 and mini.size.y <= 140.0,
				"miniatura je malá, ne přes celou obrazovku (%s)" % str(mini.size))
			var vp_rozmer := get_root().get_visible_rect().size
			_check(mini.position.x > vp_rozmer.x / 2.0 and mini.position.y > vp_rozmer.y / 2.0,
				"miniatura je v pravém dolním rohu (%s)" % str(mini.position))

	if zdroj.contains("WinLabel"):
		var win = main.get_node_or_null("WinLabel")
		_check(win != null, "výherní hlášení je ve scéně")
		if win != null:
			_check(not win.visible, "výherní hlášení je na začátku skryté")

	if zdroj.contains("_spin_coins"):
		var mince := get_nodes_in_group("coin")
		if mince.size() > 0:
			var sirky: Array = []
			for c in mince:
				sirky.append(c.scale.x)
			var t_spin := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t_spin < 300:
				await process_frame
			var zmena := 0.0
			for i in mince.size():
				zmena += abs(sirky[i] - mince[i].scale.x)
			_check(zmena > 0.01, "mince se otáčejí (změna šířky %.3f)" % zmena)

	# -------------------------------------------- vlastnosti, ne jen uzly ----
	# U každé funkce od agentů se testuje i CHOVÁNÍ, ne jen to, že uzel existuje.
	# Důvod: uzel může existovat a přesto nic nedělat (u miniatury se zase
	# nastavila jiná velikost, než jaká se požadovala).

	if main.get("lives") != null:
		_check(String(hud.text).contains("Životy"),
			"HUD ukazuje životy: '%s'" % hud.text)
		if enemies.size() > 0:
			var zivoty_pred: int = int(main.lives)
			main._on_enemy_touched(player, enemies[0])
			await process_frame
			_check(int(main.lives) == zivoty_pred - 1,
				"dotek nepřítele ubere život (%d -> %d)" % [zivoty_pred, int(main.lives)])

	if main.has_method("_save_best"):
		var puvodni_best: int = int(main.best)
		main.best = 12345
		main._save_best()
		var cfg := ConfigFile.new()
		var chyba: int = cfg.load("user://best.cfg")
		_check(chyba == OK and int(cfg.get_value("hra", "skore", -1)) == 12345,
			"nejlepší skóre se ukládá do user://best.cfg (chyba %d)" % chyba)
		main.best = puvodni_best
		main._save_best()

	if zdroj.contains("MinimapDot"):
		var mini_uzel = main.get_node_or_null("Minimap")
		var tecka = mini_uzel.get_node_or_null("MinimapDot") if mini_uzel != null else null
		_check(tecka != null, "tečka hráče je na miniatuře mapy")
		if tecka != null and player != null:
			var pozice_pred: Vector2 = tecka.position
			player.position += Vector2(40, 20)
			await process_frame
			await process_frame
			_check(tecka.position != pozice_pred,
				"tečka se posune s hráčem (%s -> %s)" % [str(pozice_pred), str(tecka.position)])
			player.position -= Vector2(40, 20)

	var hudba = main.get_node_or_null("Music")
	if hudba != null and zdroj.contains("stream_paused"):
		var pauza_pred: bool = hudba.stream_paused
		var klavesa := InputEventKey.new()
		klavesa.keycode = KEY_M
		klavesa.pressed = true
		main._input(klavesa)
		await process_frame
		_check(hudba.stream_paused != pauza_pred, "klávesa M vypne/zapne hudbu")

	var vyhra = main.get_node_or_null("WinLabel")
	var truhly := get_nodes_in_group("chest")
	if vyhra != null and truhly.size() > 0 and player != null:
		# Truhla má DVA možné významy a test je bere oba: buď rovnou vyhraje
		# (původní chování), nebo odemkne/posune na další úroveň (jak to navrhl
		# plán „Pokladnice Stínů"). Dřív tu bylo tvrzené „ukáže výherní hlášení",
		# jenže tím se změna, kterou plán chtěl, hlásila jako rozbitá.
		var index_pred_truhla = main.get("aktualni_level_index")
		main._on_chest_touched(player, truhly[0])
		await process_frame
		var posunul_truhla: bool = (index_pred_truhla != null
			and int(main.aktualni_level_index) != int(index_pred_truhla))
		_check(vyhra.visible or posunul_truhla,
			"truhla něco udělá: výherní hlášení, nebo posun dál (výhra %s, posun %s)"
			% [str(vyhra.visible), str(posunul_truhla)])
		if vyhra.visible:
			# Pozor: tenhle skript JE SceneTree, takže se pauza čte přímo z `paused`
			# (get_tree() na sobě samém neexistuje – přesně na tom spadl parse).
			_check(paused, "když hra vyhraje, pauzne se")
			paused = false  # aby zbytek testů mohl běžet

	# -------------------------------------------------- všechny úrovně ----
	# Hra může mít víc úrovní (postup úrovněmi) a musí umět načíst kteroukoli.
	# Kontroluje se každý .json v assets/levels: jde načíst a je celý průchodný.
	# Test se sám rozšíří, když přibude další úroveň.
	var lvls := DirAccess.open("res://assets/levels")
	if lvls != null:
		var skript_levelu = load("res://scripts/level.gd")
		if skript_levelu != null:
			for f in lvls.get_files():
				if not f.ends_with(".json") or f == "manifest.json":
					continue
				var lvl := Node2D.new()
				lvl.set_script(skript_levelu)
				var nacteno: bool = lvl.load_file("res://assets/levels/%s" % f)
				_check(nacteno, "úroveň %s jde načíst" % f)
				if nacteno:
					_check(lvl.reachable_count() == lvl.walkable_count(),
						"úroveň %s je celá průchodná (%d z %d)"
						% [f, lvl.reachable_count(), lvl.walkable_count()])
				lvl.free()

	# -------------------------------------------------- postup úrovněmi ----
	# Když hra umí víc úrovní, musí umět přepnout na další – a ta musí být
	# průchodná. Test se zapne sám, až funkce v kódu je (dřív ne).
	if main.get("aktualni_level_index") != null:
		# Nejdřív se stav NAROVNA: předchozí test s truhlou mohl úroveň posunout
		# (přesně to dělá odemčení východu mincemi), takže by tenhle blok padal
		# na „hra začíná na první úrovni (index 1)" – což nebyla chyba hry, ale
		# závislost testů na pořadí. Testy musí být nezávislé.
		main.aktualni_level_index = 0
		main._add_level()
		await process_frame
		_check(int(main.aktualni_level_index) == 0,
			"hra začíná na první úrovni (index %d)" % int(main.aktualni_level_index))
		var prvni_lvl = main.get_node_or_null("Level")
		_check(prvni_lvl != null and str(prvni_lvl.source).ends_with("/main.json"),
			"první úroveň se načetla z main.json (%s)"
			% (prvni_lvl.source if prvni_lvl != null else "?"))
		main.aktualni_level_index = 1
		main._add_level()
		await process_frame
		var druha_lvl = main.get_node_or_null("Level")
		_check(druha_lvl != null and str(druha_lvl.source).ends_with("/level_2.json"),
			"po přepnutí na index 1 se načte level_2.json (%s)"
			% (druha_lvl.source if druha_lvl != null else "?"))
		if druha_lvl != null:
			_check(druha_lvl.reachable_count() == druha_lvl.walkable_count(),
				"i druhá úroveň je celá průchodná (%d z %d)"
				% [druha_lvl.reachable_count(), druha_lvl.walkable_count()])
		# zpět na první úroveň, aby zbytek testů pracoval s původním stavem
		main.aktualni_level_index = 0
		main._add_level()
		await process_frame

	# -------------------------------------------------- herní smyčka ----
	# Doteď se testovaly jednotlivé funkce. Tohle je poprvé, co se ptáme na
	# CELEK: dá se hra vůbec dohrát? Nasbírat mince → dostat se k východu →
	# postoupit dál (nebo vyhrát). Test je záměrně shovívavý k tomu, jak je
	# odemčení udělané: projde, když se po truhle postoupí na další úroveň,
	# i když se rovnou vyhraje.
	if player != null and main.get("aktualni_level_index") != null:
		var mince_hry := get_nodes_in_group("coin")
		var pocet_minci := mince_hry.size()
		var skore_pred_hry: int = int(main.score)
		var sebrano := 0
		for c in mince_hry:
			if is_instance_valid(c):
				main._on_coin_touched(player, c)
				await process_frame
				sebrano += 1
		# Skóre se bere jako PŘÍRŮSTEK – jeden coin už mohl sebrat dřívější test.
		_check(sebrano > 0 and int(main.score) == skore_pred_hry + sebrano,
			"hráč posbíral všechny mince v úrovni (%d, skóre %d → %d)"
			% [sebrano, skore_pred_hry, main.score])

		var truhly_hry := get_nodes_in_group("chest")
		if truhly_hry.size() > 0:
			var index_pred: int = int(main.aktualni_level_index)
			var skore_pred: int = int(main.score)
			main._on_chest_touched(player, truhly_hry[0])
			await process_frame
			var posunul: bool = int(main.aktualni_level_index) > index_pred
			var vyhra_label = main.get_node_or_null("WinLabel")
			var vyhral: bool = vyhra_label != null and vyhra_label.visible
			_check(posunul or vyhral,
				"po truhle se postoupí dál nebo se vyhraje (index %d → %d, výhra %s)"
				% [index_pred, int(main.aktualni_level_index), str(vyhral)])
			paused = false

	_finish()


func _finish() -> void:
	_done = true
	print("\n[test] %d kontrol, %d selhání" % [checks, failures])
	quit(failures)

# GameForge: overeno AI
