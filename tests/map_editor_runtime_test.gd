extends SceneTree

const MapDataLoader := preload("res://world/map_data_loader.gd")
const TerrainTransitionResolver := preload("res://world/terrain_transition_resolver.gd")

func _initialize() -> void:
	var saved_path := "res://tools/map_editor/tests/generated/eastern_edited.json"
	assert(FileAccess.file_exists(saved_path), "Run the standalone map-editor tests first to generate the fixture.")
	var saved := MapDataLoader._load_json_object(saved_path)
	assert(not saved.is_empty(), "The unchanged game MapDataLoader must load the editor-saved map.")
	var authored := MapDataLoader._load_json_object("res://data/maps/eastern_rainforest_route.json")
	assert(saved["trees"].size() == authored["trees"].size() and saved["tall_flowers"].size() == authored["tall_flowers"].size() + 1, "Saved edited objects must reach the runtime loader without relying on stale fixture counts.")
	assert(saved.terrain_tiles[0].positions.any(func(position):return int(position[0])==8 and int(position[1])==8) and not TerrainTransitionResolver.resolve(TerrainTransitionResolver.terrain_grid(saved),"editor_saved_eastern").is_empty(),"The runtime transition resolver must consume the editor-painted cell after reload.")
	var scene := load("res://world/main.tscn") as PackedScene
	var main := scene.instantiate()
	root.add_child(main)
	await process_frame
	assert(main._test_map_filename_from_args(PackedStringArray(["--test-map=jalovea_city.json"]))=="jalovea_city.json","The game must recognize map-editor test launch arguments.")
	assert(main.player != null and main.east_route_origin == Vector3(110,0,30), "Gameplay world must still instantiate successfully.")
	var authored_warp:Node=main.world.get_node_or_null("EditorWarp_eastern_rainforest_route_warp_3")
	assert(authored_warp is Area3D and authored_warp.position==Vector3(109,0.12,28),"Editor-authored warp_3 must build the same visible runtime Area3D as legacy warps, including its map origin.")
	assert(MapDataLoader.warp_field_for_id(main.map_data._map_files["jalovea_city.json"],1)=="return_warp","Editor-authored destinations must resolve their saved Entrance Map Warp ID to the return point field.")
	assert(main._location_for_map_file("jalovea_city.json")=="authored:jalovea_city","Editor-authored maps must retain their own runtime location instead of aliasing an existing city.")
	assert(main._active_visual_layer("authored:jalovea_city")!=main._active_visual_layer("city"),"Editor-authored maps must render on a layer isolated from Mossvale.")
	main._on_editor_authored_warp_entered(main.player,"eastern_rainforest_route.json","warp_3",main.map_data._map_files["eastern_rainforest_route.json"].warp_metadata.warp_3)
	assert(main.player.position==Vector3(300,0.12,10) and main.active_authored_map_id=="jalovea_city" and not main.inside_city and main.map_title.text=="Jalovea City","Editor-authored warps must enter the registered Jalovea City map at its requested return warp without becoming Mossvale.")
	main._set_active_visual_region("authored:jalovea_city");main._update_sort_canvas()
	var jalovea_fillers:Array=main.object_sort_entries.filter(func(entry:Dictionary)->bool:return String(entry.name).begins_with("AuthoredMap_JaloveaCityUniversalObject") and String(entry.name).contains("Filler_"))
	assert(not jalovea_fillers.is_empty() and jalovea_fillers.all(func(entry:Dictionary)->bool:
		var visual:Sprite2D=(entry.sort_root as Node2D).get_node("Visual") as Sprite2D
		return visual.material==null and not visual.region_enabled and visual.get_rect().size==visual.texture.get_size() and not entry.has("clip_start") and not entry.has("clip_finish")
	),"Every Jalovea wall filler must render its complete native texture without region cropping, masking, or endpoint shader state.")
	var jalovea_tree:Dictionary=main.tree_sort_entries.filter(func(entry):return entry.placement==Vector3(293,1.5,-9))[0]
	var jalovea_apartment:Dictionary=main.background_object_sort_entries.filter(func(entry):return entry.placement==Vector3(292,3,-18))[0]
	_assert_visual_contact(main,jalovea_tree,"Rainforest Tree")
	_assert_visual_contact(main,jalovea_apartment,"City Apartment 01")
	var tree_contact:Vector2=main.camera.unproject_position(Vector3(293,0,-9));var apartment_contact:Vector2=main.camera.unproject_position(Vector3(292,0,-18))
	var tree_root:=jalovea_tree.sort_root as Node2D;var apartment_root:=jalovea_apartment.sort_root as Node2D
	var tree_visual:=tree_root.get_node("Visual") as Sprite2D;var apartment_visual:=apartment_root.get_node("Visual") as Sprite2D
	var rendered_delta:=(tree_root.position+tree_visual.position+Vector2(0,tree_visual.texture.get_height()*tree_visual.scale.y*0.5))-(apartment_root.position+apartment_visual.position+Vector2(0,apartment_visual.texture.get_height()*apartment_visual.scale.y*0.5))
	assert(rendered_delta.distance_to(tree_contact-apartment_contact)<0.001,"Tree/apartment runtime contact composition must exactly equal their camera-projected saved X/Z relationship.")
	# Existing Jalovea cardinal wall records must continue to load without editor
	# re-authoring. Derive expected geometry from the data so map-art changes do
	# not turn object-array indices into a runtime contract.
	var jalovea_walls:Array=main.map_data._map_files["jalovea_city.json"].objects.filter(func(value:Dictionary)->bool:return String(value.get("type",""))=="wall.fence")
	assert(not jalovea_walls.is_empty(),"Jalovea City must retain its authored wall geometry.")
	for object_index in main.map_data._map_files["jalovea_city.json"].objects.size():
		var wall_record:Variant=main.map_data._map_files["jalovea_city.json"].objects[object_index]
		if not wall_record is Dictionary or String(wall_record.get("type",""))!="wall.fence":continue
		var prefix:="AuthoredMap_JaloveaCityUniversalObject%d"%object_index
		var anchors:Array=wall_record.get("points",[]);var unique_anchors:={};var cardinal_runs:=0
		for anchor:Variant in anchors:
			if anchor is Array and anchor.size()>=2:unique_anchors["%.6f,%.6f"%[float(anchor[0]),float(anchor[1])]]=true
		for anchor_index in range(1,anchors.size()):
			if anchors[anchor_index-1] is Array and anchors[anchor_index] is Array and anchors[anchor_index-1].size()>=2 and anchors[anchor_index].size()>=2:
				var delta:=Vector2(float(anchors[anchor_index][0])-float(anchors[anchor_index-1][0]),float(anchors[anchor_index][1])-float(anchors[anchor_index-1][1]))
				if is_zero_approx(delta.x) != is_zero_approx(delta.y):cardinal_runs+=1
		assert(not main.world.find_children(prefix+"Filler_*", "Sprite3D", false, false).is_empty(),"Each Jalovea cardinal wall must produce filler artwork.")
		assert(main.world.find_children(prefix+"Post_*", "Sprite3D", false, false).size()==unique_anchors.size(),"Jalovea wall posts must match unique serialized anchors.")
		assert(main.world.find_children(prefix+"_*Collision", "StaticBody3D", false, false).size()==cardinal_runs,"Each Jalovea cardinal run must create exactly one collision strip.")
	# Focused fixture instantiation through the same runtime construction method.
	var prior_origin: Vector3 = main.east_route_origin
	var prepared_saved:=TerrainTransitionResolver.prepare_map(saved,"editor_saved_eastern")
	main._build_side_route(prepared_saved, "EditorFixture", true)
	assert(main.east_route_origin == Vector3(110,0,30), "Editor-saved route must instantiate through the unchanged side-route builder.")
	assert(main.world.find_child("EditorFixtureRainforestRouteGround", true, false) != null, "Saved fixture ground must be instantiated.")
	assert(main.world.find_child("EditorFixtureRouteCanonicalBase_*_sand",false,false)!=null and main.world.find_child("EditorFixtureRouteCanonicalBase_*_water",false,false)!=null,"The editor-saved route must still render canonical terrain and its transition-ready shoreline in-game.")
	var universal_fixture := {"objects":[
		{"type":"building.house","position":[0,1.5,0],"size":[5,3,4]},
		{"type":"building.medical_ward","position":[7,1.5,0],"size":[5,3,4]},
		{"type":"background.citybuilding_00","position":[14,3,0],"size":[10,6,4]},
		{"type":"cave.vine","position":[0,0.5,3]},
		{"type":"block.rock","position":[3,0.5,3],"size":[2,1,2]},
		{"type":"npc.generic","position":[0,0.65,6],"speaker":"GUIDE","dialogue":["Welcome!"]},
		{"type":"npc.opponent","position":[3,0.65,6],"name":"SCOUT","dialogue":["Ready?"],"team":[{"fakemon":"Scorchick","level":9}]},
		{"type":"overlay.vine_leafy_arch","asset_path":"res://assets/overworld/overlay_vine_leafy_arch.png","position":[0,0,9],"size":[1,1,1],"height":1.4,"rotation_degrees":37.5}
	]}
	main._build_universal_objects(universal_fixture, Vector3(200,0,200), "UniversalFixture")
	assert(main.world.get_node_or_null("UniversalFixtureUniversalObject0") != null and main.world.get_node_or_null("UniversalFixtureUniversalObject0Collision") != null, "Universal house records must build visible exteriors and collision on any map.")
	assert(main.world.get_node("UniversalFixtureUniversalObject0Collision").position == Vector3(200,1.5,198), "House collision must remain entirely behind its visible front/entry contact line.")
	assert(main.world.get_node_or_null("UniversalFixtureUniversalObject1") != null and main.world.get_node_or_null("UniversalFixtureUniversalObject1Collision") != null, "Universal medical ward records must use the same exterior construction path.")
	assert(main.world.get_node_or_null("UniversalFixtureUniversalObject2") != null and main.world.get_node_or_null("UniversalFixtureUniversalObject2Collision") != null, "City background buildings must build non-interactable art and collision on any map.")
	assert(main.background_object_sort_entries[-1].name=="UniversalFixtureUniversalObject2BackgroundRoot","City background buildings must use the dedicated behind-house render layer.")
	assert(main.world.get_node("UniversalFixtureUniversalObject2Collision").position==Vector3(214,3,198),"Background-building collision must extend behind its bottom visual anchor, leaving the foreground walkable.")
	assert(main.world.get_node_or_null("UniversalFixtureUniversalObject3") != null and main.world.get_node_or_null("UniversalFixtureUniversalObject4") != null, "Universal vegetation and terrain records must instantiate through the shared builder.")
	var guide:Node=main.world.get_node_or_null("UniversalFixtureUniversalObject5")
	var trainer:Node=main.world.get_node_or_null("UniversalFixtureUniversalObject6")
	assert(guide!=null and trainer!=null and main.npc_dialogues.has(guide.get_instance_id()) and main.npc_dialogues.has(trainer.get_instance_id()),"Universal NPCs and trainers must register click dialogue in the runtime.")
	assert((main.npc_dialogues[trainer.get_instance_id()].after_dialogue as Callable).is_valid(),"Trainer dialogue must chain to its configured battle team.")
	var overlay_source:=main.world.get_node_or_null("UniversalFixtureUniversalObject7") as Sprite3D
	assert(overlay_source!=null and not overlay_source.visible,"Overlay objects must build visual-only source art for the sorted canvas.")
	assert(main.world.get_node_or_null("UniversalFixtureUniversalObject7Collision")==null,"Overlay objects must never create collision.")
	var overlay_entry:Dictionary=main.overlay_sort_entries[-1]
	assert(overlay_entry.name=="UniversalFixtureUniversalObject7OverlayRoot" and is_equal_approx(float(overlay_entry.rotation_degrees),37.5),"Runtime overlay entries must preserve authored arbitrary rotation.")
	var authored_team:Array[Dictionary]=main._build_trainer_team([{"fakemon":"Scorchick","level":9},{"fakemon":1,"level":12}])
	assert(authored_team.size()==2 and authored_team[0].name=="Scorchick" and authored_team[0].level==9 and authored_team[1].level==12,"Trainer team records must resolve Fakemon names/indices and preserve authored levels.")
	var catalog_trainer:Dictionary=main._resolved_trainer({"trainer_id":"caver_bex","position":[5,0.65,-5]})
	assert(catalog_trainer.name=="CAVER BEX" and catalog_trainer.team[0].fakemon=="Keklid" and catalog_trainer.team[0].level==5,"Runtime trainer placement references must resolve reusable definitions and explicit Fakemon/level team rows from data/trainers.json.")
	var legacy_trainer:Dictionary=main._resolved_trainer({"name":"LEGACY TRAINER","party":[2],"position":[5,0.65,-5]})
	assert(legacy_trainer.name=="LEGACY TRAINER" and legacy_trainer.party==[2],"Inline legacy trainer records without trainer_id must remain usable.")
	main._build_universal_objects({"objects":[{"type":"tree.main","position":[0,1.5,0],"height":6.5}]},Vector3(260,0,260),"ScaleFixture")
	assert(is_equal_approx(float(main.tree_sort_entries[-1].height),6.5),"The runtime must consume the same authored tree height shown by the editor preview.")
	var wall_fixture := {"objects":[{"type":"wall.fence","wall_set":"generic_wall","points":[[0,0],[2,0],[2,2],[4,2],[4,4]],"baked_segments":[{"from":[0,0],"to":[2,0],"direction":"horizontal"},{"from":[2,0],"to":[2,2],"direction":"vertical"},{"from":[2,2],"to":[4,2],"direction":"horizontal"},{"from":[4,2],"to":[4,4],"direction":"vertical"}],"baked_collision":[{"thickness":0.22,"offset":0.0},{"thickness":0.22,"offset":0.0},{"thickness":0.22,"offset":0.0},{"thickness":0.22,"offset":0.0}]},{"type":"wall.fence","wall_set":"generic_wall","points":[[0,0],[2,2]],"baked_segments":[{"from":[0,0],"to":[2,2],"direction":"diagonal_nw"}],"baked_collision":[{"thickness":0.22,"offset":0.0}]}]}
	var wall_entry_count: int = main.object_sort_entries.size()
	main._build_universal_objects(wall_fixture, Vector3(280,0,280), "WallFixture")
	var wall_collisions: Array[Node] = main.world.find_children("WallFixtureUniversalObject0_*Collision", "StaticBody3D", false, false)
	assert(wall_collisions.size() == 4, "A position-less wall.fence must build its horizontal and vertical collision strips.")
	assert(main.world.find_children("WallFixtureUniversalObject0Post_*", "Sprite3D", false, false).size() == 5, "Each authored cardinal-wall anchor must create exactly one post.")
	assert(main.world.find_children("WallFixtureUniversalObject1Filler_*", "Sprite3D", false, false).is_empty() and main.world.find_children("WallFixtureUniversalObject1_*Collision", "StaticBody3D", false, false).is_empty(), "Legacy diagonal segments must be ignored by runtime visuals and collision.")
	assert((main.world.get_node("WallFixtureUniversalObject0Filler_0_0") as Sprite3D).texture.resource_path.ends_with("wall_horizontal_generic.png"), "Horizontal runs must use the authored horizontal filler.")
	assert((main.world.get_node("WallFixtureUniversalObject0Filler_1_0") as Sprite3D).texture.resource_path.ends_with("wall_vertical_generic.png"), "Vertical runs must use the authored vertical filler.")
	assert(main.world.find_children("WallFixtureUniversalObject0Filler_0_*", "Sprite3D", false, false).size()==1 and main.world.find_children("WallFixtureUniversalObject0Filler_1_*", "Sprite3D", false, false).size()==1,"A two-unit run must omit any native filler repeat that would extend beyond its terminal post.")
	var wall_visuals:Array[Sprite3D]=[main.world.get_node("WallFixtureUniversalObject0Filler_0_0"),main.world.get_node("WallFixtureUniversalObject0Filler_1_0"),main.world.get_node("WallFixtureUniversalObject0Post_0")]
	assert(wall_visuals.all(func(visual:Sprite3D)->bool:return is_equal_approx(visual.pixel_size,main.WALL_PIXELS_TO_WORLD)), "Every wall filler and post must use one shared pixels-to-world scale.")
	var first_filler := main.world.get_node("WallFixtureUniversalObject0Filler_0_0") as Sprite3D
	var last_filler := main.world.get_node("WallFixtureUniversalObject0Filler_0_1") as Sprite3D
	assert(is_equal_approx(first_filler.position.x,281.0) and is_equal_approx(last_filler.position.x,283.0), "Horizontal fillers must repeat at geometry-defined interval midpoints.")
	assert(main.object_sort_entries.size() > wall_entry_count, "Wall pieces and posts must create generated per-piece sort entries.")
	var wall_collision := main.world.get_node("WallFixtureUniversalObject0_0Collision") as StaticBody3D
	assert(is_equal_approx(wall_collision.position.y, 0.5) and is_equal_approx(((wall_collision.get_child(0) as CollisionShape3D).shape as BoxShape3D).size.y, 1.0), "Wall collision must start from the ground-contact line rather than from the visual sprite center.")
	main.east_route_origin = prior_origin
	print("MAP_EDITOR_RUNTIME_TEST_PASSED")
	quit()


func _assert_visual_contact(main:Node,entry:Dictionary,label:String)->void:
	var sort_point:=entry.sort_root as Node2D;var visual:=sort_point.get_node("Visual") as Sprite2D
	var rendered_bottom:Vector2=sort_point.position+visual.position+Vector2(0,visual.texture.get_height()*visual.scale.y*0.5)
	var placement:Vector3=entry.placement;var expected:Vector2=main.camera.unproject_position(Vector3(placement.x,0,placement.z))
	var expected_pixel_height:float=float(entry.height)*get_root().get_visible_rect().size.y/main.camera.size
	assert(rendered_bottom.distance_to(expected)<0.001,"%s artwork bottom must equal its projected saved X/Z contact."%label)
	assert(absf(visual.texture.get_height()*visual.scale.y-expected_pixel_height)<0.001,"%s apparent visual height must remain unchanged."%label)
	print("%s contact expected=%s rendered=%s height_px=%.3f"%[label,expected,rendered_bottom,expected_pixel_height])
