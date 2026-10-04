extends SceneTree

const Data := preload("res://world/npc_map_data.gd")
const Visuals := preload("res://world/npc_visual_resolver.gd")
const Library := preload("res://world/npc_sprite_library.gd")
const Loader := preload("res://world/map_data_loader.gd")

func _initialize() -> void:
	create_timer(40).timeout.connect(func():push_error("NPC_CHECKPOINT_TIMEOUT");quit(2))
	var visuals := Visuals.new(ProjectSettings.globalize_path("res://"))
	for human in Visuals.HUMANS:
		var source:Image=(load(visuals.source_path("human",human,"down")) as Texture2D).get_image() if visuals.in_game_project else Image.load_from_file(visuals.source_path("human",human,"down"))
		for facing in Visuals.FACINGS:
			var texture:=visuals.texture_for("human",human,facing)
			var expected:Rect2i=Library.SPRITES[human].idle[facing]
			assert(texture!=null and texture.get_image().get_data()==source.get_region(expected).get_data(),"Human must use the existing parser's directional idle crop.")
			assert(texture==Library.texture_for(human,facing,-1,"" if visuals.in_game_project else visuals.root))
	for facing in Visuals.FACINGS:
		var path:=visuals.source_path("fakemon","Sylvafin",facing)
		assert(path.ends_with("Sylvafin_Follow_%s.png"%facing.capitalize()))
		var source:Image=(load(path) as Texture2D).get_image() if visuals.in_game_project else Image.load_from_file(path)
		assert(visuals.texture_for("fakemon","Sylvafin",facing).get_image().get_data()==source.get_data())
	var data:=Data.new()
	assert(data.issues({},visuals).is_empty() and data.issues({"npcs":[]},visuals).is_empty())
	var map:={}
	assert(data.add_default(map)==1 and data.add_default(map)==2 and data.add_default(map)==3)
	map.npcs.remove_at(1);data.definitions.erase("2")
	assert(data.add_default(map)==4)
	var valid:Dictionary=map.duplicate(true)
	var defs:Dictionary=data.definitions.duplicate(true)
	data.load_for_map("res://tests/nonexistent_checkpoint_map.json")
	assert(not data.issues(map,visuals).is_empty() and data.resolve(map,visuals).is_empty())
	data.definitions=defs.duplicate(true)
	data.definitions.erase("1")
	assert(data.resolve(map,visuals).size()==2)
	data.definitions=defs.duplicate(true);data.definitions["1"].sprite="not registered"
	assert(data.resolve(map,visuals).size()==2)
	data.definitions=defs.duplicate(true);map.npcs[0].facing="diagonal"
	assert(data.resolve(map,visuals).size()==2)
	map=valid.duplicate(true);map.npcs.append(map.npcs[0].duplicate(true))
	assert(data.resolve(map,visuals).size()==2,"Both copies of an ambiguous duplicate ID must be skipped.")
	map=valid.duplicate(true);assert(map==valid and data.definitions==defs)
	for bad_facing:Variant in [null,42,[],{}]:
		var malformed:Dictionary=valid.duplicate(true);malformed.npcs[0].facing=bad_facing
		assert(data.resolve(malformed,visuals).size()==2)
	for bad_id:Variant in [0,-1,1.5,"1",null]:
		var malformed:Dictionary=valid.duplicate(true);malformed.npcs[0].id=bad_id
		assert(data.resolve(malformed,visuals).size()==2)
	var malformed_path:="res://tests/npc_invalid_companion_fixture_NPC_Data.json"
	var malformed_file:=FileAccess.open(malformed_path,FileAccess.WRITE)
	malformed_file.store_string("{invalid");malformed_file.close()
	data.load_for_map("res://tests/npc_invalid_companion_fixture.json")
	assert(not data.load_error.is_empty() and data.resolve(valid,visuals).is_empty())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(malformed_path))
	# The fixture comes from the standalone editor test, with both kinds and a shared sprite.
	var fixture:=Loader._load_json_object("res://tools/map_editor/tests/generated/npc_checkpoint.json")
	assert(fixture.get("_resolved_npcs",[]).size()==3,"Run npc_editor_test.gd first.")
	var authored:Dictionary=fixture.duplicate(true)
	var main:=(load("res://world/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	main._build_universal_objects(fixture,Vector3(10,0,20),"NPCCheckpointFixture",true)
	var registry:Dictionary=main.runtime_npcs["npc_checkpoint.json"]
	assert(registry.size()==3)
	for record:Dictionary in fixture._resolved_npcs:
		var npc:Area3D=registry[int(record.id)]
		assert(npc.position==Vector3(10,0,20)+Vector3(record.position[0],record.position[1],record.position[2]))
		assert(npc.get_meta("facing")==record.facing)
		assert((npc.get_child(0) as Sprite3D).texture.get_image().get_data()==visuals.texture_for(record.type,record.sprite,record.facing).get_image().get_data())
		# Supply the same sort roots constructed during normal world startup.
	for entry:Dictionary in main.npc_sort_entries:
		if not entry.has("sort_root"):
			entry["sort_root"]=main._create_sorted_sprite(String(entry.name),(entry.visual as Sprite3D).texture)
			entry["visual_layer"]=main._visual_layer_for_position((entry.node as Area3D).global_position)
			(entry.visual as Sprite3D).hide()
	main.player.position=(registry[1] as Area3D).position+Vector3(0,0,2)
	await physics_frame
	await process_frame
	for record:Dictionary in fixture._resolved_npcs:
		var npc:Area3D=registry[int(record.id)]
		var click:=InputEventMouseButton.new()
		click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
		click.position=main.camera.unproject_position(npc.global_position+Vector3(0,0.4,0))
		main._unhandled_input(click)
		assert(main.dialog_open and main.dialog_label.text==record.interaction_text,"NPC click raycast must reach the existing text panel.")
		main._advance_dialogue()
	var human:Area3D=registry[1]
	main._set_npc_pose(human,"left")
	human.position+=Vector3.ONE
	assert(fixture.npcs==authored.npcs,"Mutable runtime state must not alter authored placements.")
	assert(registry[1]!=registry[3])
	main.queue_free()
	await process_frame
	print("NPC_CHECKPOINT_TESTS_PASSED: four human idle crops, four semantic Fakemon assets, controlled errors, runtime positions/facings/visuals, dialogue, independent instances, authored-state isolation")
	quit()
