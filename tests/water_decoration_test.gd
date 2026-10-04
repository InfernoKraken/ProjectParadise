extends SceneTree

const Decoration := preload("res://world/water_decoration.gd")
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
	print("PASS: " if ok else "FAIL: ", message)

func _initialize() -> void:
	create_timer(45).timeout.connect(func(): push_error("WATER_DECORATION_TIMEOUT"); quit(2))
	call_deferred("run")

func run() -> void:
	check(Decoration.kind("res://assets/overworld/semi_submerged_water_props_driftwood_00.png").is_empty(),"semi-submerged is excluded from these rules")
	var main: Node = load("res://world/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false); main.set_physics_process(false)
	var original_surfaces: int = main.npc_water_surfaces.size()
	var original_entries: int = main.overlay_sort_entries.size()
	var original_nodes: int = main.world.get_child_count()
	var assets := ["floater_water_lily","floater_water_generic","submerged_water_props_generic_00","submerged_water_props_generic_01"]
	var objects: Array = []
	for name: String in assets:
		objects.append({"type":"asset."+name.trim_suffix("_00").trim_suffix("_01"),"asset_path":"res://assets/overworld/"+name+".png","position":[0,0,0],"height":1.5,"rotation_degrees":37.0})
	var grid := {Vector2i.ZERO:"water",Vector2i(1,0):"water",Vector2i(2,0):"sand"}
	var fixture := {"_npc_map_file":"water_decoration_fixture.json","_terrain_grid":grid,"objects":objects.slice(0,2)}
	var origin := Vector3(600,0,600)
	main._build_universal_objects(fixture,origin,"FloaterFixture")
	check(main.npc_water_surfaces.size() == original_surfaces,"floaters alone do not require a surface")
	fixture.objects = objects.slice(2)
	main._build_universal_objects(fixture,origin,"SubmergedFixture")
	check(main.npc_water_surfaces.size() == original_surfaces+1,"two submerged props enable one surface without swimmers")
	check(main.world.get_child_count() == original_nodes+4,"four decorations create art only, no collision or navigation nodes")
	var entries: Array = main.overlay_sort_entries.slice(original_entries)
	check(entries.size() == 4 and entries.all(func(e): return e.height == 1.5 and e.rotation_degrees == 37.0),"authored scale and rotation reach render entries")
	main._build_sort_canvas()
	main._update_npc_water_surfaces(main._visual_layer_for_position(origin))
	var surface: Dictionary = main.npc_water_surfaces["water_decoration_fixture.json"]
	var surface_node: Node2D = surface.node
	check(surface_node.get_child_count() == 2 and surface_node.z_index == -1,"surface geometry covers canonical water cells only")
	check(entries.slice(2).all(func(e): return e.sort_root.z_index == -3),"submerged decorations render below swimmers (-2) and water (-1)")
	check(entries.slice(0,2).all(func(e): return e.sort_root.z_index == 0),"floaters render above water with ordinary world sprites")
	check(entries.all(func(e): return not e.sort_root.is_processing() and e.sort_root.find_children("*","Timer",true,false).is_empty()),"decorations have no independent processing or timers")
	for i in 500: main._ensure_water_surface(fixture,origin,"IgnoredPrefix")
	main._update_npc_water_surfaces(main._visual_layer_for_position(origin))
	check(main.npc_water_surfaces.size() == original_surfaces+1 and surface.node == surface_node and surface_node.get_child_count() == 2,"500 requests reuse surface and mask nodes")
	surface.visual_layer = 999
	main._update_npc_water_surfaces(0)
	check(not surface_node.visible,"inactive-map surface is hidden")
	main._update_npc_water_surfaces(999)
	check(surface_node.visible,"owning-map surface is restored")
	# Adding a swimmer later must reuse the decoration-created surface.
	fixture["_resolved_npcs"] = [{"id":1,"position":[0,0,0],"type":"fakemon","sprite":"Sylvafin","facing":"down","interaction_text":"","movement_mode":"swimming"}]
	# First build recorded an empty NPC set; use a fresh runtime build state.
	main.runtime_npcs.erase("water_decoration_fixture.json")
	main._build_placed_npcs(fixture,origin)
	check(main.npc_water_surfaces.size() == original_surfaces+1 and surface.node == surface_node,"swimmer shares the prop-created surface")
	if "--render-check" in OS.get_cmdline_user_args():
		await render_checks(entries,surface_node)
	main.queue_free(); await process_frame
	print("WATER_DECORATION_TEST: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func render_checks(entries: Array, surface: Node2D) -> void:
	# Render the production sort roots and surface container with diagnostic solid
	# art. This tests compositing separately from supplied sprites' artwork colors.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128,128)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)
	var floor_root: Node2D = entries[2].sort_root
	var floater_root: Node2D = entries[0].sort_root
	for pair in [[floor_root,Color.RED,Vector2(64,64)],[floater_root,Color.GREEN,Vector2(40,64)]]:
		var node: Node2D = pair[0]
		node.reparent(viewport); node.visible = true; node.position = pair[2]; node.rotation = 0
		var art := node.get_node("Visual") as Sprite2D
		var image := Image.create(96 if node == floor_root else 16,32,false,Image.FORMAT_RGBA8)
		image.fill(pair[1]); art.texture = ImageTexture.create_from_image(image)
		art.position = Vector2.ZERO; art.scale = Vector2.ONE; art.material = null
	var swimmer := Sprite2D.new()
	var swimmer_image := Image.create(16,32,false,Image.FORMAT_RGBA8)
	swimmer_image.fill(Color.WHITE)
	swimmer.texture = ImageTexture.create_from_image(swimmer_image)
	swimmer.position = Vector2(64,64); swimmer.z_index = -2; viewport.add_child(swimmer)
	surface.reparent(viewport); surface.visible = true
	for child in surface.get_children(): surface.remove_child(child); child.queue_free()
	var mask := Polygon2D.new()
	mask.polygon = PackedVector2Array([Vector2(16,48),Vector2(80,48),Vector2(80,80),Vector2(16,80)])
	mask.color = Color(0.12,0.52,0.72,0.32); surface.add_child(mask)
	await process_frame
	await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image()
	check(result != null and not result.is_empty(),"diagnostic viewport renders an image")
	if result != null and not result.is_empty():
		check(result.get_pixel(24,64).b > 0.15 and result.get_pixel(24,64).r < 0.9,"surface composites above submerged floor art")
		check(result.get_pixel(64,64).r > 0.6 and result.get_pixel(64,64).g > 0.7,"swimmer composites above floor art and below surface")
		check(result.get_pixel(40,64).is_equal_approx(Color.GREEN),"floater remains untinted above the surface")
		check(result.get_pixel(100,64).is_equal_approx(Color.RED),"surface does not spill beyond its polygon")
		result.save_png("res://tests/.water_decoration_render.png")
	viewport.queue_free(); await process_frame
