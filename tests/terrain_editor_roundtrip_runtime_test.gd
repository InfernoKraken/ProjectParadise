extends SceneTree

const MapDataLoader:=preload("res://world/map_data_loader.gd")
const TerrainTransitionResolver:=preload("res://world/terrain_transition_resolver.gd")

func _initialize()->void:
	var saved:=MapDataLoader._load_json_object("res://tools/map_editor/tests/generated/eastern_edited.json")
	assert(saved.terrain_tiles[0].positions.any(func(position):return int(position[0])==8 and int(position[1])==8),"The editor-painted cell must reload through the runtime JSON loader.")
	var prepared:=TerrainTransitionResolver.prepare_map(saved,"editor_saved_eastern")
	assert(not prepared._terrain_transitions.is_empty(),"The saved route must still resolve canonical terrain transitions.")
	var main:Node=load("res://world/main.tscn").instantiate();root.add_child(main);await process_frame
	main._build_side_route(prepared,"TerrainEditorFixture",true)
	assert(main.world.find_child("TerrainEditorFixtureRouteCanonicalBase_*_sand",false,false)!=null,"The saved sand terrain must render in-game.")
	assert(main.world.find_child("TerrainEditorFixtureRouteCanonicalBase_*_water",false,false)!=null,"The saved water terrain must render in-game.")
	print("TERRAIN_EDITOR_ROUNDTRIP_RUNTIME_TEST_PASSED");quit()
