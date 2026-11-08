extends SceneTree

func _initialize()->void:
	var main=load("res://world/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_physics_process(false)
	main.set_process(false)
	var map:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/tropical_research_lab.json"))
	var origin:=Vector3(1000,0,1000)
	main._build_universal_objects({"objects":[map.objects[0]]},origin,"EntranceFixture",true)
	assert(main.world.get_node_or_null("EntranceFixtureUniversalObject0Collision")==null,"An authored building polygon must replace the hidden default box.")
	assert(main.world.get_node_or_null("EntranceFixtureUniversalObject0AssetPolygonCollision")!=null,"The editor-authored building polygon must still block the building wings.")
	main.player.collision_mask=1 | main.TERRAIN_OBSTACLE_LAYER
	await physics_frame
	await physics_frame
	var entrance:=origin+Vector3(float(map.warp_2[0]),0.65,float(map.warp_2[2]))
	var approach:=entrance+Vector3(0,0,2)
	assert(not main.player.test_move(Transform3D(Basis.IDENTITY,approach),entrance-approach),"The player's full collider must be able to reach the entrance warp through the stairs.")
	assert(main.player.test_move(Transform3D(Basis.IDENTITY,approach+Vector3(-2,0,0)),entrance-approach+Vector3(0,0,-1)),"The building wing must remain solid beside the entrance.")
	print("BUILDING_ENTRANCE_COLLISION_TEST_PASSED")
	quit()
