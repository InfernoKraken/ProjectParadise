extends SceneTree

func _initialize()->void:
	var main=load("res://world/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false);main.set_physics_process(false)
	main.adventure_started=false
	var total:=0
	var legacy_total:=0
	for index in 20:
		var started:=Time.get_ticks_usec()
		main._set_route_location("authored:tropical_research_institute_indoor" if index%2==0 else "authored:new_map",Vector3.ZERO,"Profile","")
		total+=Time.get_ticks_usec()-started
	for index in 20:
		var location:="authored:tropical_research_institute_indoor" if index%2==0 else "authored:new_map"
		var started:=Time.get_ticks_usec()
		var layer:int=main._active_visual_layer(location)
		for node in main.world.find_children("*","CollisionObject3D",true,false):
			if node==main.player or not node.has_meta("visual_layer"):continue
			var enabled:=int(node.get_meta("visual_layer"))==layer
			node.collision_layer=int(node.get_meta("base_collision_layer",node.collision_layer)) if enabled else 0
			if node is Area3D:node.monitoring=enabled;node.monitorable=enabled
		main.day_night_controller.set_map_type(main._map_type_for_location(location))
		legacy_total+=Time.get_ticks_usec()-started
	print("LAB_TRANSITION_AVERAGE_MS ",float(total)/20000.0," LEGACY_SWITCH_MS ",float(legacy_total)/20000.0," COLLIDERS ",main.world.find_children("*","CollisionObject3D",true,false).size())
	quit()
