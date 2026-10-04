extends SceneTree

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func(): quit(1))
	var main = load("res://world/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var expected := {"Celestraal":2.0,"Croacoa":0.5,"Dartlet":0.5,"Flambian":1.0,"Lochirp":0.5,"Paradisia":0.5,"Paratweet":0.5,"Pyravion":2.0,"Scorcaw":1.0,"Scorchick":0.5,"Serafin":2.0,"Sylvafin":0.5}
	var actual := {}
	for species: Dictionary in main.battle.battle_data.fakemon:
		if bool(species.get("light_source", false)):
			actual[species.name] = float(species.light_strength)
	assert(actual == expected, "Exactly the requested twelve species must emit the configured radii.")
	main.adventure_started = true
	main.party.clear()
	main.party.append(main.battle.create_fakemon(main._overworld_light_species("Celestraal")))
	main.active_party_index = 0
	main._update_follower_appearance()
	main.follower.show()
	main.sort_canvas.show()
	main._update_sort_canvas()
	var controller = main.day_night_controller
	assert(controller.light_count == 1)
	var art: Sprite2D = main.follower_sort_root.get_node("Visual")
	assert(art.material == controller.emissive_material, "Source sprite must bypass night tint.")
	var before: Color = controller.light_data_image.get_pixel(0, 0)
	main.follower.position.x += 3.0
	main._update_sort_canvas()
	var after: Color = controller.light_data_image.get_pixel(0, 0)
	assert(not is_equal_approx(before.r, after.r), "The light must move without leaving a trail.")
	main.party.clear()
	main.party.append(main.battle.create_fakemon(main._overworld_light_species("Moach")))
	main._update_follower_appearance()
	main._update_sort_canvas()
	assert(controller.light_count == 0 and art.material == controller.canvas_light_material, "Changing follower must remove emission and immunity.")
	var npc: Area3D = main._add_talking_npc("LightingTestNPC", main.player.position, Color.WHITE, "Croacoa", [])
	npc.set_meta("npc_definition", {"type":"fakemon", "sprite":"Croacoa"})
	var entry: Dictionary = main.npc_sort_entries[-1]
	entry["visual_layer"] = main._active_visual_layer()
	entry["sort_root"] = main._create_sorted_sprite("LightingTestNPCSort", entry.visual.texture)
	entry.visual.hide()
	main._update_sort_canvas()
	assert(controller.light_count == 1 and entry.sort_root.get_node("Visual").material == controller.emissive_material, "Placed Fakemon must use species emission.")
	controller.set_map_type("Indoor")
	main._update_sort_canvas()
	assert(controller.light_count == 0 and controller.canvas_modulate.color == Color.WHITE)
	controller.set_map_type("Rainforest")
	main._update_sort_canvas()
	assert(controller.light_count == 1)
	entry.sort_root.hide()
	main._update_fakemon_lights()
	assert(controller.light_count == 0, "Hidden NPCs must not illuminate the active map.")
	var generation:int = controller.material_update_generation
	for frame in 20: main._update_fakemon_lights()
	assert(controller.material_update_generation == generation,"Stable light state must not rebuild material uniforms.")
	assert(not controller.canvas_lighting_dirty)
	controller.clock.set_time(0,0)
	main._update_fakemon_lights()
	assert(controller.material_update_generation > generation,"Clock changes must refresh cached lighting.")
	main._add_prop_billboard("LightingStreetLamp", main.player.position, load("res://assets/overworld/outdoor_street_lamp.png"), 1.5)
	var lamp: Dictionary = main.object_sort_entries[-1]
	lamp["sort_root"] = main._create_sorted_sprite("LightingStreetLampSort", lamp.texture)
	main._update_fakemon_lights()
	assert(lamp.light_source and is_equal_approx(float(lamp.light_strength), 1.0), "Street lamp metadata must configure medium emission.")
	assert(controller.light_count == 1 and lamp.sort_root.get_node("Visual").material == controller.emissive_material, "Visible street lamp must emit and bypass the night tint.")
	lamp.sort_root.hide()
	main._update_fakemon_lights()
	assert(controller.light_count == 0, "Hidden street lamps must not illuminate another map.")
	print("FAKEMON_LIGHTING_TEST_PASSED")
	quit()
