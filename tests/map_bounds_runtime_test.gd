extends SceneTree

const Bounds:=preload("res://tools/map_editor/core/map_bounds.gd")
const Resolver:=preload("res://world/terrain_transition_resolver.gd")

func _initialize()->void:
	call_deferred("_test_bounds")

func _test_bounds()->void:
	# South-only expansion: north stays at -10, south moves from 10 to 20.
	var data:Dictionary={"size":[20,30],"bounds_center":[0,5],"origin":[100,0,200],"map_metadata":{"layout_type":"outdoor"},"base_terrain_type":"forest_floor","terrain_tiles":[{"terrain_type":"sand","position":[0,18]},{"terrain_type":"water","position":[0,-12]}],"objects":[{"type":"block.rock","position":[2,0,3],"size":[1,1,1]}]}
	var bounds:=Bounds.rect(data)
	assert(bounds.position==Vector2(-10,-10) and bounds.end==Vector2(10,20))
	var grid:=Resolver.terrain_grid(data)
	assert(grid.get(Vector2i(0,18))=="sand" and not grid.has(Vector2i(0,-12)))
	assert(grid.has(Vector2i(0,19)) and not grid.has(Vector2i(0,20)))
	assert(Resolver.canonical_terrain_issues({"size":[20,30],"bounds_center":[0,5],"terrain_tiles":[{"terrain_type":"sand","position":[0,18]}]}).is_empty())
	assert(Bounds.center({})==Vector2.ZERO,"Existing maps must retain centered bounds.")
	for filename:String in DirAccess.get_files_at("res://data/maps"):
		if not filename.ends_with(".json") or filename.ends_with("_NPC_Data.json"):continue
		var existing:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/"+filename))
		if existing is Dictionary and not existing.has("bounds_center"):
			assert(Resolver.terrain_grid(existing)==_original_grid(existing),"Unresized map terrain must match the original resolver: "+filename)
	data["_terrain_grid"]=grid;data["_terrain_transitions"]=[]
	var main=load("res://world/main.gd").new()
	main.world=Node3D.new();root.add_child(main.world)
	main.player=CharacterBody3D.new();main.world.add_child(main.player)
	main.map_data={"authored_maps":{"fixture":data}}
	main._build_authored_maps()
	var ground:MeshInstance3D=main.world.get_node("AuthoredMap_fixture_Ground")
	assert(ground.position.is_equal_approx(Vector3(100,-0.1,205)))
	assert(ground.mesh.size==Vector3(20,0.2,30))
	var sand_batch:MeshInstance3D=main.world.get_node("AuthoredMap_FixtureCanonicalBase_sand_0_1")
	var sand_bounds:AABB=sand_batch.mesh.get_aabb()
	assert(is_equal_approx(sand_batch.position.z+sand_bounds.get_center().z,218),"Batched terrain must preserve world placement.")
	assert(main.world.get_node("AuthoredMap_FixtureUniversalObject0").position.is_equal_approx(Vector3(102,0,203)),"Objects must keep their original world positions.")
	main.player.position=Vector3(100,0.65,218)
	main._clamp_player_to_region(Vector3(100,0,200)+Bounds.offset(data),data.size)
	assert(main.player.position.z==218,"The player can reach the expanded south region.")
	main.player.position.z=180
	main._clamp_player_to_region(Vector3(100,0,200)+Bounds.offset(data),data.size)
	assert(is_equal_approx(main.player.position.z,190.6),"The original north limit must remain fixed.")
	var clipped:Dictionary=main._clip_terrain_block(Vector3(0,0,18),Vector3(2,1,8),data)
	assert(clipped.position.z==17 and clipped.size.z==6)
	main.free()
	print("MAP_BOUNDS_RUNTIME_PASSED");quit()

func _original_grid(data:Dictionary)->Dictionary:
	# Snapshot of the pre-offset grid algorithm, for compatibility with authored maps.
	var grid:Dictionary={};var dimensions:Variant=data.get("size",data.get("map_size",[]))
	if dimensions is Array and dimensions.size()==2:
		var terrain:=String(data.get("base_terrain_type","forest_floor"))
		if Resolver.TERRAIN.has(terrain):
			var width:=maxi(0,int(dimensions[0]));var depth:=maxi(0,int(dimensions[1]))
			var x0:=floori(-float(width)*0.5);var z0:=floori(-float(depth)*0.5)
			for x in range(x0,x0+width):
				for z in range(z0,z0+depth):grid[Vector2i(x,z)]=terrain
	for entry:Variant in data.get("terrain_tiles",[]):
		if not entry is Dictionary:continue
		var terrain:=String(entry.get("terrain_type",entry.get("terrain","")))
		if not Resolver.TERRAIN.has(terrain):continue
		for point:Vector2i in Resolver._entry_positions(entry):grid[point]=terrain
	if dimensions is Array and dimensions.size()>=2:
		var half:=Vector2(float(dimensions[0]),float(dimensions[1]))*0.5
		for point:Vector2i in grid.keys():
			if point.x-0.5 < -half.x or point.x+0.5 > half.x or point.y-0.5 < -half.y or point.y+0.5 > half.y:grid.erase(point)
	return grid
