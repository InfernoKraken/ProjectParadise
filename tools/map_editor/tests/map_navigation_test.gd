extends SceneTree

const Graph = preload("res://core/map_graph.gd")

func _initialize() -> void:
	var editor: Control = load("res://map_editor.gd").new()
	root.add_child(editor)
	await process_frame
	var directory: String = editor.map_directory
	for filename in ["jalovea_city_house_standard.json", "tropical_research_institute_indoor.json"]:
		editor._load_path(directory.path_join(filename))
		assert(not Graph.has_layout_overlap(directory, editor.document.data, filename), "Repaired interior overlaps another map: " + filename)
	editor._new_document()
	assert(not Graph.has_layout_overlap(directory, editor.document.data, ""), "New maps must start in unused world space.")
	# Duplicated/imported interiors and dimensions enlarged after creation use
	# the same allocator when saved. Exercise its proposed position in memory.
	var duplicate := {"origin":[0,0,0], "size":[17,11]}
	assert(Graph.has_layout_overlap(directory, duplicate, "fixture.json"))
	duplicate.origin = Graph.available_origin(directory, duplicate, "fixture.json")
	assert(not Graph.has_layout_overlap(directory, duplicate, "fixture.json"))
	var fixture_directory: String = ProjectSettings.globalize_path("res://tests/generated/map_navigation")
	DirAccess.make_dir_recursive_absolute(fixture_directory)
	var occupied := FileAccess.open(fixture_directory.path_join("occupied.json"), FileAccess.WRITE)
	occupied.store_string(JSON.stringify({"origin":[0,0,0],"size":[20,20]})); occupied.close()
	var manifest := FileAccess.open(fixture_directory.path_join("map_index.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"root":"occupied.json","maps":{}})); manifest.close()
	editor.map_directory = fixture_directory
	editor._new_document()
	editor.document.data.map_metadata.layout_type = "indoor"
	editor.document.data.origin = [0,0,0]
	editor.document.kind = "interior"
	var output := fixture_directory.path_join("relocated.json")
	editor._save_to(output)
	assert(not editor.document.dirty, "Indoor save must succeed after allocating a free origin.")
	assert(not Graph.has_layout_overlap(fixture_directory, editor.document.data, "relocated.json"))
	assert(editor.status_label.text.contains("Moved indoor origin"), "Automatic relocation must be explained in the save status.")
	editor.map_directory = directory
	editor._load_path(directory.path_join("jalovea_city.json"))
	var warp: Dictionary = {}
	var house: Dictionary = {}
	for object: Dictionary in editor.editor_objects:
		if object.path == "$.warp_3": warp = object
		if object.path == "$.objects[28]": house = object
	assert(not warp.is_empty() and not house.is_empty())
	# Keep the overlap fixture independent of changes to the authored city map.
	house.position=warp.position
	var canvas: Control = editor.canvas
	var screen: Vector2 = canvas.world_to_screen(Vector2(warp.position.x, warp.position.z))
	assert(canvas._screen_rect(house).grow(5).has_point(screen), "Fixture must reproduce a house covering the warp.")
	assert(canvas._hit_test(screen).id == warp.id, "Warp must be selectable through the house.")
	assert(canvas._draw_rank(warp) > canvas._draw_rank(house), "Editing mode must draw warp handles above houses.")
	canvas.placement_preview = true
	assert(canvas._draw_rank(warp) == 4, "Preview must retain ordinary runtime depth ordering.")
	canvas.placement_preview = false
	var destination := Graph.destination_for("jalovea_city.json", "$.warp_3", directory)
	assert(destination.map == "jalovea_city_house_standard.json")
	editor._on_object_activated(String(warp.id))
	assert(editor.document.path.get_file() == "jalovea_city_house_standard.json", "Activating the warp must open the house without moving its exterior.")
	for object: Dictionary in editor.editor_objects:
		if object.path == "$.return_warp":
			editor._on_object_activated(String(object.id)); break
	assert(editor.document.path.get_file() == "jalovea_city.json", "Following the exit must return to the city.")
	for object: Dictionary in editor.editor_objects:
		if object.path == "$.warp_4":
			editor.selected_id = String(object.id); editor._refresh_inspector(); break
	var instance_edit: LineEdit = editor.inspector.find_child("WarpEntranceInstanceId", true, false)
	assert(instance_edit != null)
	instance_edit.text = "house_2"
	instance_edit.focus_exited.emit()
	assert(editor.document.data.warp_metadata.warp_4.entrance_instance_id == "house_2", "Instance ID changes must commit without pressing Enter.")
	print("MAP_NAVIGATION_TESTS_PASSED")
	editor.free()
	quit()
