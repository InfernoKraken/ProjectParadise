extends SceneTree

const Movement := preload("res://world/npc_movement.gd")
const Data := preload("res://world/npc_map_data.gd")
const Visuals := preload("res://world/npc_visual_resolver.gd")

func _initialize() -> void:
	create_timer(45).timeout.connect(func():push_error("NPC_MOVEMENT_TIMEOUT");quit(2))
	var anchor:=Vector3(10,0.25,-20)
	for preset:String in Movement.PRESETS:
		var state:=Movement.new(anchor,{"preset":preset,"range":[2.0,1.0]},42)
		var position:=anchor;var facing:="down";var visited:Dictionary={};var looks:Dictionary={}
		for frame in 2400:
			var update:=state.step(position,facing,0.05);position=update.position;facing=update.facing
			assert(absf(position.x-anchor.x)<=2.00001 and absf(position.z-anchor.z)<=1.00001 and position.y==anchor.y)
			assert(facing in Movement.FACINGS);looks[facing]=true
			if preset in ["stationary","look_around"]:assert(position==anchor)
			if preset=="left_right":assert(position.z==anchor.z)
			if preset=="up_down":assert(position.x==anchor.x)
			if is_equal_approx(absf(position.x-anchor.x),2.0) and is_equal_approx(absf(position.z-anchor.z),1.0):visited[Vector2(position.x,position.z)]=true
		if preset in ["clockwise","counterclockwise"]:assert(visited.size()==4)
		if preset=="look_around":assert(looks.size()==4)
		if preset not in ["stationary","look_around"]:assert(looks.size()>=2)
	# Verify opposite rectangle winding at the first corner.
	for preset in ["clockwise","counterclockwise"]:
		var state:=Movement.new(anchor,{"preset":preset,"range":[2.0,1.0]},7)
		var position:=anchor;var facing:="down"
		for frame in 1000:
			if position.distance_squared_to(anchor+Vector3(-2,0,-1))<=0.000001:break
			var update:=state.step(position,facing,0.1);position=update.position;facing=update.facing
		assert(position.distance_squared_to(anchor+Vector3(-2,0,-1))<=0.000001)
		state.timer=0
		var next:=state.step(position,facing,0.1)
		assert(next.facing==("right" if preset=="clockwise" else "down"))
	for preset:String in Movement.PRESETS:
		var state:=Movement.new(anchor,{"preset":preset,"range":[0,0]},1)
		for frame in 30:assert(state.step(anchor,"down",10).position==anchor)
	var visuals:=Visuals.new(ProjectSettings.globalize_path("res://"))
	var data:=Data.new();var authored:={};data.add_default(authored)
	assert(data.issues(authored,visuals).is_empty(),"Old definitions default to stationary.")
	for bad:Variant in [null,[],{"preset":"bad","range":[1,1]},{"preset":"random","range":[-1,1]},{"preset":"random","range":["1",1]},{"preset":"random","range":[1]}]:
		data.definitions["1"]["movement"]=bad
		assert(not data.issues(authored,visuals).is_empty() and data.resolve(authored,visuals).is_empty())
	print("NPC_MOVEMENT_MODEL_PASSED")
	var main:Node=load("res://world/main.gd").new()
	main.world=Node3D.new();root.add_child(main.world)
	main.adventure_started=true;main.in_battle=false;main.dialog_open=false
	var record:={"id":1,"position":[0,0,0],"facing":"down","type":"human","sprite":"Young Man","interaction_text":"Pause to talk.","movement":{"preset":"left_right","range":[2,1]}}
	var fakemon:={"id":2,"position":[-4,0,0],"facing":"up","type":"fakemon","sprite":"Sylvafin","interaction_text":"Hello.","movement":{"preset":"up_down","range":[2,1]}}
	var fixture:={"_npc_map_file":"npc_movement_fixture.json","_resolved_npcs":[record,fakemon]}
	var before:Dictionary=fixture.duplicate(true)
	main._build_placed_npcs(fixture,Vector3(500,0,500))
	var npc:Area3D=main.runtime_npcs["npc_movement_fixture.json"][1]
	var follower:Area3D=main.runtime_npcs["npc_movement_fixture.json"][2]
	npc.set_meta("visual_layer",main._active_visual_layer())
	follower.set_meta("visual_layer",main._active_visual_layer())
	await physics_frame
	var start:=npc.position
	main._update_placed_npcs(0.1)
	assert(npc.position.x>start.x and npc.get_meta("facing")=="right")
	var visual := npc.get_child(0) as Sprite3D
	assert(visual.texture == main.NpcSpriteLibrary.texture_for("man", "right", 0), "Editor Young Man must use the Citizen walking sheet.")
	main._update_placed_npcs(0.1)
	assert(visual.texture == main.NpcSpriteLibrary.texture_for("man", "right", 1), "Placed NPC walking frames must advance.")
	main._set_npc_pose(npc, "right")
	assert(visual.texture == main.NpcSpriteLibrary.texture_for("man", "right"), "Stopping must select Citizen idle.")
	assert(follower.position.z>start.z and follower.get_meta("facing")=="down")
	main.dialog_open=true;var paused:=npc.position;main._update_placed_npcs(2);assert(npc.position==paused)
	main.dialog_open=false;npc.set_meta("visual_layer",999);main._update_placed_npcs(2);assert(npc.position==paused)
	npc.set_meta("visual_layer",main._active_visual_layer());main.in_battle=true;main._update_placed_npcs(2);assert(npc.position==paused);main.in_battle=false
	# Existing foot collider and shape-cast stop at a wall, with no pathfinding.
	var wall:=StaticBody3D.new();wall.position=start+Vector3(0.9,0.3,0)
	var collider:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(0.2,1,2);collider.shape=box;wall.add_child(collider);main.world.add_child(wall)
	await physics_frame
	for frame in 20:main._update_placed_npcs(0.1)
	assert(npc.position.x<wall.position.x-0.3,"NPCs must stop before walls.")
	assert(fixture==before,"Movement must not modify authored placement or definitions.")
	# Traversal elevation uses authored height plus mode and manual offsets.
	assert(Movement.elevation({}) == 0.0)
	assert(Movement.elevation({"movement_mode":"flying"}) == 2.0)
	assert(is_equal_approx(Movement.elevation({"movement_mode":"swimming","height_offset":-0.8}),-1.3))
	assert(not Movement.traversal_error({"movement_mode":"ghost"}).is_empty())
	assert(not Movement.traversal_error({"height_offset":"high"}).is_empty())
	main._build_placed_npcs({"_npc_map_file":"traversal_fixture.json","_terrain_grid":{Vector2i(0,0):"water",Vector2i(1,0):"water"},"_resolved_npcs":[
		{"id":1,"position":[0,0.25,0],"type":"fakemon","sprite":"Keklid","facing":"right","interaction_text":"","movement_mode":"flying"},
		{"id":2,"position":[0,0,0],"type":"fakemon","sprite":"Sylvafin","facing":"down","interaction_text":"","movement_mode":"swimming","height_offset":-0.8}
	]},Vector3(600,0,0))
	var flyer:Area3D = main.runtime_npcs["traversal_fixture.json"][1]
	var swimmer:Area3D = main.runtime_npcs["traversal_fixture.json"][2]
	assert(is_equal_approx(flyer.position.y,2.25))
	assert(is_equal_approx(swimmer.position.y,-1.3))
	main._add_static_collision("LowFence",Vector3(601,0.5,0),Vector3(0.2,1,1))
	main._add_static_collision("TallWall",Vector3(603,2,0),Vector3(0.2,4,1))
	await physics_frame
	assert(main._npc_motion_fraction(flyer,Vector3(1.5,0,0)) > 0.99,"Flyers should clear low fences.")
	assert(main._npc_motion_fraction(flyer,Vector3(4,0,0)) < 0.9,"Flyers should hit tall walls.")
	assert(main._npc_in_water(swimmer,swimmer.position))
	assert(not main._npc_in_water(swimmer,swimmer.position+Vector3(0,0,1)))
	assert(main._npc_motion_fraction(swimmer,Vector3(0,0,1)) == 0.0)
	assert(main._npc_motion_fraction(swimmer,Vector3(1,0,0)) < 0.9,"Submerged swimmers should still hit shore-level solid obstacles.")
	# Surface is shared environmental geometry, below ordinary sprites.
	main.sort_root = Node2D.new();root.add_child(main.sort_root)
	main.camera = Camera3D.new();main.world.add_child(main.camera);main.camera.position=Vector3(600,10,10);main.camera.look_at(Vector3(600,0,0))
	main._update_npc_water_surfaces(main._visual_layer_for_position(Vector3(600,0,0)))
	var surface:Node2D = main.npc_water_surfaces["traversal_fixture.json"].node
	assert(surface.z_index == -1 and surface.get_child_count() == 2)
	assert((surface.get_child(0) as Polygon2D).polygon.size() == 4)
	main.npc_water_surfaces["traversal_fixture.json"].visual_layer = 12
	main._update_npc_water_surfaces(1)
	assert(not surface.visible,"An overlapping authored map must not leak its water into the clearing.")
	main._update_npc_water_surfaces(12)
	assert(surface.visible)
	main._assign_visual_region(swimmer,12)
	swimmer.set_meta("base_collision_layer",1)
	main._set_active_visual_region("rainforest")
	assert(swimmer.collision_layer == 0,"Inactive NPC interaction areas must not receive raycast clicks.")
	main.authored_visual_regions.append({"id":"fixture","layer":12})
	main._set_active_visual_region("authored:fixture")
	assert(swimmer.collision_layer == 1,"Returning to the owning map restores interactions.")
	main.sort_root.queue_free()
	main.world.queue_free();main.queue_free();await process_frame
	print("NPC_MOVEMENT_TESTS_PASSED: all presets, bounds, winding, zero ranges, look facings, legacy defaults, invalid settings, live movement, pause/inactive maps, collisions, authored isolation")
	quit()
