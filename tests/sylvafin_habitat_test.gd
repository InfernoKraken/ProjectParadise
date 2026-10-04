extends SceneTree

# Collect failures instead of assert(), which can leave a headless SceneTree running.
const Movement := preload("res://world/npc_movement.gd")
const Data := preload("res://world/npc_map_data.gd")
const Visuals := preload("res://world/npc_visual_resolver.gd")
const Anim := preload("res://world/overworld_texture_animation.gd")
var failures: Array[String] = []
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("PASS: " if ok else "FAIL: ", label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var visuals := Visuals.new(ProjectSettings.globalize_path("res://"))
	var placement := {"id":1,"position":[3.0,0.0,4.0],"facing":"left"}
	var map := {"npcs":[placement]}
	var data := Data.new()
	data.definitions["1"] = {"type":"fakemon","sprite":"Sylvafin","interaction_text":"Hello"}
	var resolved := data.resolve(map, visuals)
	check(resolved.size() == 1 and Movement.elevation(resolved[0]) == 0.0, "A1 legacy data defaults to ground elevation")
	data.definitions["1"].merge({"movement_mode":"swimming","height_offset":0.0,"water_region_id":"sylvafin_basin"}, true)
	check(Movement.elevation(data.definitions["1"]) == -0.5, "A2 swimming default elevation")
	data.definitions["1"].height_offset = 0.75
	check(Movement.elevation(data.definitions["1"]) == 0.25 and map.npcs[0] == placement, "A3 additive height preserves authored placement")
	# Exercise the production loader using a temporary companion; never overwrite map assets.
	var companion := "res://tests/.sylvafin_acceptance_fixture_NPC_Data.json"
	var file := FileAccess.open(companion, FileAccess.WRITE)
	if file == null:
		check(false, "A4 companion fixture is writable")
	else:
		file.store_string(JSON.stringify(data.definitions)); file.close()
		var reloaded := Data.new()
		reloaded.load_for_map("res://tests/.sylvafin_acceptance_fixture.json")
		var loaded := reloaded.resolve(JSON.parse_string(JSON.stringify(map)), visuals)
		var same := loaded.size() == 1
		if same:
			var expected: Dictionary = data.resolve(map, visuals)[0]
			for key in ["facing","movement_mode","height_offset","water_region_id"]:
				same = same and loaded[0].get(key) == expected.get(key)
			for axis in 3:
				same = same and float(loaded[0].position[axis]) == float(expected.position[axis])
		check(same, "A4 JSON/load round trip preserves placement, facing, mode, offset and region")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(companion))
	for facing: String in Visuals.FACINGS:
		check(visuals.source_path("fakemon","Sylvafin",facing).ends_with("Sylvafin_Follow_%s.png" % facing.capitalize()) and visuals.texture_for("fakemon","Sylvafin",facing) != null, "F33 centralized direction " + facing)
	var animation := Anim.definition("water_generic_glisten")
	for step in 5:
		check(Anim.frame_index("water_generic_glisten",step * float(animation.frame_duration) + 0.001) == step % 4, "E26 frame sequence step %d" % step)
	Anim.elapsed = 0.31
	var textures: Array[AnimatedTexture] = []
	for i in 500:
		var texture := Anim.shared_texture("sylvafin_fixture_%d" % i,"water_generic_glisten",func(frame): return animation.frames[frame]) as AnimatedTexture
		textures.append(texture)
		if i % 100 == 0: Anim.advance(0.13)
	for delta in [0.0,0.13,0.51,1.0]:
		Anim.advance(delta)
		var expected := Anim.frame_index("water_generic_glisten",Anim.elapsed)
		check(textures.all(func(t): return t.pause and t.speed_scale == 0.0 and t.current_frame == expected), "E27/E28/F36 500 centrally driven textures at tick %s" % delta)
	var original_duration := float(animation.frame_duration)
	Anim.definitions["water_generic_glisten"].frame_duration = 0.5
	Anim.advance(0.5)
	check(textures.all(func(t): return t.current_frame == Anim.frame_index("water_generic_glisten",Anim.elapsed)), "E29 central rate change synchronizes existing instances")
	var paused_frame := textures[0].current_frame
	Anim.advance(0.0)
	check(textures.all(func(t): return t.current_frame == paused_frame), "E32 zero clock advance preserves phase")
	Anim.definitions["water_generic_glisten"].frame_duration = original_duration
	for i in 500: Anim.bindings.erase("sylvafin_fixture_%d" % i)
	await runtime_checks()
	if not "--regression-only" in OS.get_cmdline_user_args():
		contract_checks(data, map, visuals, original_duration)
	print("SYLVAFIN_HABITAT: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func runtime_checks() -> void:
	var main: Node = load("res://world/main.gd").new()
	main.world = Node3D.new(); root.add_child(main.world)
	var grid := {}
	for x in range(-2,3):
		for z in range(-2,3): grid[Vector2i(x,z)] = "water"
	var record := {"id":1,"position":[0,0,0],"facing":"down","type":"fakemon","sprite":"Sylvafin","interaction_text":"Hello","movement_mode":"swimming","height_offset":0.0}
	var fixture := {"_npc_map_file":"sylvafin_test.json","_terrain_grid":grid,"_resolved_npcs":[record]}
	var before := fixture.duplicate(true)
	main._build_placed_npcs(fixture,Vector3(600,0,600))
	var npc: Area3D = main.runtime_npcs["sylvafin_test.json"][1]
	await physics_frame
	check(main._npc_motion_fraction(npc,Vector3(5,0,0)) == 0.0, "C14 movement across shoreline is rejected")
	check(main._npc_motion_fraction(npc,Vector3(1,0,0)) > 0.99, "C16 empty water permits movement")
	var decoration := Node3D.new(); main.world.add_child(decoration)
	decoration.position = npc.position + Vector3(1,0,0)
	check(main._npc_motion_fraction(npc,Vector3(1,0,0)) > 0.99, "C16 noncolliding decoration does not obstruct swimming")
	main._add_static_collision("Rock",Vector3(601,0.5,600),Vector3(0.2,1,1))
	await physics_frame
	check(main._npc_motion_fraction(npc,Vector3(1.5,0,0)) < 0.9, "C15 submerged swimmers respect solid obstacles")
	check(fixture == before, "A5 runtime construction leaves serializable authored position unchanged")
	main._build_placed_npcs(fixture,Vector3(600,0,600))
	check(main.runtime_npcs["sylvafin_test.json"].size() == 1, "F35 duplicate build does not duplicate NPC instances")
	if not "--regression-only" in OS.get_cmdline_user_args():
		check(npc.position == Vector3(600,0,600), "A5/C18 anchor and interaction origin must not move with swimming height")
	main.world.queue_free(); main.queue_free(); await process_frame

func contract_checks(data: RefCounted, map: Dictionary, visuals: RefCounted, duration: float) -> void:
	data.definitions["1"].water_region_id = "missing_basin"
	check(not data.issues(map,visuals).is_empty(), "A6/C13 unknown named water region must fail validation")
	var habitat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/tropical_research_lab.json"))
	var regions: Array = habitat.get("water_regions",[])
	check(regions.any(func(r): return r is Dictionary and r.get("id","") == "sylvafin_basin" and r.get("swimmable",false)), "B7 final map authors canonical sylvafin_basin polygon")
	check(habitat.get("objects",[]).any(func(o): return o.get("id",o.get("instance_id","")) == "sylvafin_surface"), "D19 final map authors sylvafin_surface overlay")
	var authored := Data.new(); authored.load_for_map("res://data/maps/tropical_research_lab.json")
	check(authored.definitions.values().any(func(d): return d.get("sprite","") == "Sylvafin" and d.get("movement_mode","") == "swimming" and float(d.get("height_offset",0.0)) == 0.0 and d.get("water_region_id","") == "sylvafin_basin"), "habitat checklist: Sylvafin uses zero override and named basin")
	check(is_equal_approx(duration,0.25), "E central default is approximately 4 FPS (currently %s FPS)" % (1.0/duration))

