extends SceneTree

var failed:=false

func check(condition:bool,message:String)->void:
	if not condition:failed=true;push_error(message)

func _initialize()->void:
	var main=load("res://world/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_physics_process(false)
	main.set_process(false)
	var filename:="tropical_research_institute_indoor.json"
	var data:Dictionary=main.map_data._map_files[filename]
	var location:String=main._location_for_map_file(filename)
	main._start_map_test(filename)
	check(main.adventure_started and main._current_location()==location,"Test Map must start gameplay in the authored indoor map.")
	check(main.player.position.is_equal_approx(main._array_to_vector3(data.origin)+main._array_to_vector3(data.entry)),"Indoor Test Map must spawn at the saved entry and origin.")
	var layer:int=main._active_visual_layer(location)
	check(layer>=12 and layer!=main._active_visual_layer("authored:new_map"),"The interior must have its own visual layer.")
	check(not main.day_night_controller.is_day_night_enabled(),"Authored interiors must use indoor lighting.")
	var prefix:="AuthoredMap_TropicalResearchInstituteIndoor"
	var ground:MeshInstance3D=main.world.get_node_or_null("AuthoredMap_tropical_research_institute_indoor_Ground")
	check(ground!=null and int(ground.get_meta("visual_layer",0))==layer,"The indoor floor must be built on the interior layer.")
	var walls:Array=main.world.find_children(prefix+"Wall*Collision","StaticBody3D",false,false)
	check(walls.size()==data.wall_blocks.size(),"Every authored indoor wall must produce a collider.")
	check(walls.all(func(body):return body.collision_layer!=0 and int(body.get_meta("visual_layer",0))==layer),"Indoor walls must be active only on their map layer.")
	check(main.object_sort_entries.any(func(entry):return String(entry.name).begins_with(prefix+"UniversalObject") and int(entry.get("visual_layer",0))==layer),"Indoor objects must be visible on the correct layer.")
	main._update_sort_canvas()
	var wall_entries:Array=main.object_sort_entries.filter(func(entry):return entry.has("wall_size") and int(entry.get("visual_layer",0))==layer)
	check(wall_entries.size()==data.wall_blocks.size(),"All indoor walls must participate in the player's sorting layer.")
	for entry:Dictionary in wall_entries:
		var art:Sprite2D=entry.sort_root.get_node("Visual")
		var half:Vector2=entry.wall_size*0.5
		var corner:Vector3=entry.placement-Vector3(half.x,0,half.y)
		check(art.to_global(art.get_rect().position).distance_to(main.camera.unproject_position(corner))<0.01,"Wall footprint mismatch for %s: actual %s expected %s"%[entry.name,art.to_global(art.get_rect().position),main.camera.unproject_position(corner)])
		var behind:Vector2=main.camera.unproject_position(entry.placement+Vector3(0,0,half.y-0.1))
		var front:Vector2=main.camera.unproject_position(entry.placement+Vector3(0,0,half.y+0.1))
		check(behind.y<entry.sort_root.position.y and front.y>entry.sort_root.position.y,"Wall depth must cover players behind its front edge and uncover players in front.")
	var display_entries:Array=main.object_sort_entries.filter(func(entry):return entry.has("interaction_text") and int(entry.get("visual_layer",0))==layer)
	check(not display_entries.is_empty(),"Indoor displays must expose their serialized interaction text.")
	if not display_entries.is_empty():
		var display:Dictionary=display_entries[0]
		display.interaction_text="Research display\nSecond line."
		var art:Sprite2D=display.sort_root.get_node("Visual")
		check(main._try_display_text_click(art.global_position),"Clicking an indoor display must open its textbox.")
		check(main.active_dialogue==[display.interaction_text],"The dialogue box must preserve the complete authored text.")
		main._advance_dialogue()
	if "--capture" in OS.get_cmdline_user_args():
		var wall:Dictionary=wall_entries[-1]
		main.player.position=wall.placement+Vector3(0,0.65,wall.wall_size.y*0.5-0.2)
		main._update_sort_canvas()
		await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://tests/generated")
		get_root().get_texture().get_image().save_png("res://tests/generated/indoor_wall_preview.png")
	check(main.npc_sort_entries.any(func(entry):return int(entry.get("visual_layer",0))==layer),"Indoor placed NPCs must be built on the correct layer.")
	var warp:Area3D=main.world.get_node_or_null("EditorWarp_tropical_research_institute_indoor_return_warp")
	check(warp!=null and warp.monitoring and int(warp.get_meta("visual_layer",0))==layer,"The indoor exit warp must be active.")
	check(warp!=null and warp.get_node_or_null("WarpRugArt") is MeshInstance3D,"Indoor authored warps must use the shared rug visual.")
	# Suppress save writes while exercising the same callbacks as gameplay.
	main.adventure_started=false
	main.door_warp_ready=true
	main._on_editor_authored_warp_entered(main.player,filename,"return_warp",data.warp_metadata.return_warp)
	check(main._current_location()=="authored:new_map","The indoor exit must return to the lab exterior.")
	check(walls.all(func(body):return body.collision_layer==0),"Interior wall collision must turn off after leaving.")
	main.door_warp_ready=true
	var exterior:Dictionary=main.map_data._map_files["tropical_research_lab.json"]
	main._on_editor_authored_warp_entered(main.player,"tropical_research_lab.json","warp_2",exterior.warp_metadata.warp_2)
	check(main._current_location()==location and walls.all(func(body):return body.collision_layer!=0),"The exterior entrance must re-enter the interior and restore wall collision.")
	var added:=StaticBody3D.new()
	added.set_meta("visual_layer",layer)
	added.collision_layer=1
	main.world.add_child(added)
	main._set_active_visual_region("authored:new_map")
	check(added.collision_layer==0,"Adding a collider must invalidate the region cache and isolate it from other maps.")
	main._set_active_visual_region(location)
	check(added.collision_layer==1,"A collider added after startup must regain its base collision layer on entry.")
	added.free()
	main._set_active_visual_region(location)
	main._add_map_blocks(Vector3(1000,0,1000),[[0,1.2,0,4,0.3,2,{"enabled":true,"offset":[0,0,0.5],"size":[4,0.3,1]}]],"WallControlFixture",main.TEX_WALL_GENERIC,Color.WHITE,true)
	var custom:StaticBody3D=main.world.get_node("WallControlFixtureCollision")
	check(custom.position.is_equal_approx(Vector3(1000,1.2,1000.5)),"Wall collider offset must be independent of its visual position.")
	check(custom.get_child(0).shape.size.is_equal_approx(Vector3(4,0.3,1)),"Wall collider dimensions must use the authored override.")
	main._add_map_blocks(Vector3.ZERO,[[0,1.2,0,4,0.3,2,{"enabled":false}]],"DisabledWallFixture",main.TEX_WALL_GENERIC,Color.WHITE,true)
	check(main.world.get_node_or_null("DisabledWallFixtureCollision")==null,"Disabling a wall collider must preserve art without a blocking body.")
	main._apply_loaded_location(location)
	check(main.world_environment.background_color==Color("#3d453d"),"Loading an authored indoor save must retain its indoor background.")
	for legacy_file in ["rainforest_house.json","rainforest_medical_ward.json","mossvale_medical_ward.json"]:
		main.adventure_started=false
		main._start_map_test(legacy_file)
		check(main._current_location()==main._location_for_map_file(legacy_file),"Test Map must enter the correct legacy interior: "+legacy_file)
	print("INDOOR_MAP_RUNTIME_TEST_PASSED" if not failed else "INDOOR_MAP_RUNTIME_TEST_FAILED")
	quit(1 if failed else 0)
