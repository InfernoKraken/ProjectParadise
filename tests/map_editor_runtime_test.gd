extends SceneTree

const MapDataLoader := preload("res://world/map_data_loader.gd")

func _initialize() -> void:
	var saved_path := "res://tools/map_editor/tests/generated/eastern_edited.json"
	assert(FileAccess.file_exists(saved_path), "Run the standalone map-editor tests first to generate the fixture.")
	var saved := MapDataLoader._load_json_object(saved_path)
	assert(not saved.is_empty(), "The unchanged game MapDataLoader must load the editor-saved map.")
	var authored := MapDataLoader._load_json_object("res://data/maps/eastern_rainforest_route.json")
	assert(saved["trees"].size() == authored["trees"].size() and saved["tall_flowers"].size() == authored["tall_flowers"].size() + 1, "Saved edited objects must reach the runtime loader without relying on stale fixture counts.")
	var scene := load("res://world/main.tscn") as PackedScene
	var main := scene.instantiate()
	root.add_child(main)
	await process_frame
	assert(main.player != null and main.east_route_origin == Vector3(110,0,30), "Gameplay world must still instantiate successfully.")
	# Focused fixture instantiation through the same runtime construction method.
	var prior_origin: Vector3 = main.east_route_origin
	main._build_side_route(saved, "EditorFixture", true)
	assert(main.east_route_origin == Vector3(110,0,30), "Editor-saved route must instantiate through the unchanged side-route builder.")
	assert(main.world.find_child("EditorFixtureRainforestRouteGround", true, false) != null, "Saved fixture ground must be instantiated.")
	var universal_fixture := {"objects":[
		{"type":"building.house","position":[0,1.5,0],"size":[5,3,4]},
		{"type":"building.medical_ward","position":[7,1.5,0],"size":[5,3,4]},
		{"type":"cave.vine","position":[0,0.5,3]},
		{"type":"block.rock","position":[3,0.5,3],"size":[2,1,2]},
		{"type":"npc.generic","position":[0,0.65,6],"speaker":"GUIDE","dialogue":["Welcome!"]},
		{"type":"npc.opponent","position":[3,0.65,6],"name":"SCOUT","dialogue":["Ready?"],"team":[{"fakemon":"Scorchick","level":9}]}
	]}
	main._build_universal_objects(universal_fixture, Vector3(200,0,200), "UniversalFixture")
	assert(main.world.get_node_or_null("UniversalFixtureUniversalObject0") != null and main.world.get_node_or_null("UniversalFixtureUniversalObject0Collision") != null, "Universal house records must build visible exteriors and collision on any map.")
	assert(main.world.get_node_or_null("UniversalFixtureUniversalObject1") != null and main.world.get_node_or_null("UniversalFixtureUniversalObject1Collision") != null, "Universal medical ward records must use the same exterior construction path.")
	assert(main.world.get_node_or_null("UniversalFixtureUniversalObject2") != null and main.world.get_node_or_null("UniversalFixtureUniversalObject3") != null, "Universal vegetation and terrain records must instantiate through the shared builder.")
	var guide:Node=main.world.get_node_or_null("UniversalFixtureUniversalObject4")
	var trainer:Node=main.world.get_node_or_null("UniversalFixtureUniversalObject5")
	assert(guide!=null and trainer!=null and main.npc_dialogues.has(guide.get_instance_id()) and main.npc_dialogues.has(trainer.get_instance_id()),"Universal NPCs and trainers must register click dialogue in the runtime.")
	assert((main.npc_dialogues[trainer.get_instance_id()].after_dialogue as Callable).is_valid(),"Trainer dialogue must chain to its configured battle team.")
	var authored_team:Array[Dictionary]=main._build_trainer_team([{"fakemon":"Scorchick","level":9},{"fakemon":1,"level":12}])
	assert(authored_team.size()==2 and authored_team[0].name=="Scorchick" and authored_team[0].level==9 and authored_team[1].level==12,"Trainer team records must resolve Fakemon names/indices and preserve authored levels.")
	main.east_route_origin = prior_origin
	print("MAP_EDITOR_RUNTIME_TEST_PASSED")
	quit()
