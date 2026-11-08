extends SceneTree

const Loader = preload("res://world/map_data_loader.gd")

func _initialize() -> void:
	var loaded := Loader.load_world("res://data/maps/map_index.json")
	assert(not loaded.is_empty())
	var template := {
		"shared_layout":true, "origin":[0,0,0], "size":[12,12],
		"objects":[{"id":"table"}], "npcs":[], "_npc_definitions":{"1":{"type":"human","sprite":"Young Man","interaction_text":"Hello"}},
		"script_source":"base", "warp_metadata":{"return_warp":{"id":1,"entrance_map":"city.json","entrance_map_warp_id":1}},
		"layout_instances":[
			{"id":"west", "npcs":[{"id":1,"position":[2,0,1],"facing":"down"}], "script_source":"west", "warp_destinations":{"return_warp":{"entrance_map_warp_id":2}}},
			{"id":"east", "npcs":[], "script_source":"east", "warp_destinations":{"return_warp":{"entrance_map_warp_id":3}}}
		]
	}
	var files := {"house.json":template}
	var maps := {"house":template}
	var ids := {"house.json":"house"}
	Loader._expand_shared_layouts(maps, files, ids)
	assert(files.size() == 3 and maps.size() == 3)
	var west: Dictionary = files[Loader.instance_file("house.json", "west")]
	var east: Dictionary = files["house.json#east"]
	assert(west.objects == template.objects and east.objects == template.objects)
	assert(west.script_source == "west" and east.script_source == "east")
	assert(west._resolved_npcs.size() == 1 and east._resolved_npcs.is_empty())
	assert(west._resolved_npcs[0].interaction_text == "Hello" and west._npc_issues.is_empty())
	assert(west.warp_metadata.return_warp.entrance_map_warp_id == 2)
	assert(east.warp_metadata.return_warp.entrance_map_warp_id == 3)
	assert(west.origin != east.origin and west._npc_map_file != east._npc_map_file)
	west.objects[0].id = "changed"
	assert(east.objects[0].id == "table" and template.objects[0].id == "table")
	assert(ids["house.json#west"] == "house#west")
	assert(Loader.instance_file("city.json", "") == "city.json")
	print("SHARED_LAYOUT_TESTS_PASSED")
	quit()
