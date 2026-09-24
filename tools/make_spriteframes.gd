extends SceneTree
## Uloží SpriteFrames resource z framů vygenerovaných pipeline GameForge.
##
## PROČ TO EXISTUJE: ručně zapsaný .tres Godot neparsoval ("Parse Error:
## Expected identifier" – formát textových resource je citlivý na detaily).
## Když resource ukládá sám Godot, je formát vždy správný.
##
## Spuštění (z pipeline to dělá `forge anim`):
##   godot --headless --path <projekt> --script res://tools/make_spriteframes.gd -- \
##         <nazev> <fps> res://assets/sprites/<nazev>_0.png ...

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("Pouziti: -- <nazev> <fps> <frame1.png> [frame2.png ...]")
		quit(2)
		return

	var anim_name: String = args[0]
	var fps: float = float(args[1])
	var paths: Array = args.slice(2)

	var frames := SpriteFrames.new()
	if frames.has_animation("default"):
		frames.remove_animation("default")
	frames.add_animation(anim_name)
	frames.set_animation_speed(anim_name, fps)
	frames.set_animation_loop(anim_name, true)

	var count := 0
	for path in paths:
		var tex = load(str(path))
		if tex == null:
			push_error("Nenacetl se frame: " + str(path))
			quit(3)
			return
		frames.add_frame(anim_name, tex)
		count += 1

	var out_path := "res://assets/%s.tres" % anim_name
	var err := ResourceSaver.save(frames, out_path)
	if err != OK:
		push_error("Ulozeni selhalo (chyba %d): %s" % [err, out_path])
		quit(4)
		return

	print("[spriteframes] ulozeno %s (%d framu, %.1f fps)" % [out_path, count, fps])
	quit(0)
