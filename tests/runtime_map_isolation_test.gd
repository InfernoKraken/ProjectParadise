extends SceneTree
func _initialize() -> void:
	var main = load("res://world/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var count := 0
	main._set_active_visual_region("rainforest")
	for node in main.world.find_children("*","CollisionObject3D",true,false):
		if int(node.get_meta("visual_layer",0)) == 1 and node != main.player:
			count += 1

	for surface in main.traversal_surfaces:
		if int(surface.get("visual_layer",1)) < 12: continue
		main.player.position = surface.center + Vector3(0,0.65,0)
		main.active_traversal_surface = surface
		main.active_traversal_layer = 1
		main._update_traversal_surface(main.player.position)
		assert(main.active_traversal_layer == 0 and is_equal_approx(main.player.position.y,0.65),"A foreign bridge must not constrain clearing movement.")
		print("FOREIGN_BRIDGE_ISOLATION_PASSED ",surface.name)
	main._set_active_visual_region("rainforest")
	var start := Time.get_ticks_usec()
	for i in 60: main._set_active_visual_region("rainforest")
	print("REGION_UPDATE_MS ",(Time.get_ticks_usec()-start)/60000.0," COUNT ",count)
	for node in main.world.find_children("*","CollisionObject3D",true,false):
		if node == main.player: continue
		if int(node.get_meta("visual_layer",1)) != 1: assert(node.collision_layer == 0,"Foreign-map collider remained enabled: " + str(node.get_path()))
	print("RUNTIME_MAP_ISOLATION_TESTS_PASSED")
	quit()
