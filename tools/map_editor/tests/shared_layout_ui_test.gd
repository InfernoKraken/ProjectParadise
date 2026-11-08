extends SceneTree

func _initialize() -> void:
	create_timer(45).timeout.connect(func(): push_error("SHARED_LAYOUT_UI_TIMEOUT"); quit(2))
	var editor: Control = load("res://map_editor.gd").new()
	root.add_child(editor)
	await process_frame
	editor._load_path(editor.map_directory.path_join("jalovea_city_house_standard.json"))
	await process_frame
	var helper: VBoxContainer = editor.metadata_box.find_child("SharedInstanceHelper", true, false)
	assert(helper != null)
	if "--capture" in OS.get_cmdline_user_args():
		editor._set_activity(2)
		await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://tests/generated")
		root.get_texture().get_image().save_png("res://tests/generated/shared_layout_helper.png")
	assert(not editor.metadata_box.find_child("LayoutInstances", true, false).visible)
	var picker: OptionButton = helper.find_child("SharedInstancePicker", true, false)
	assert(picker.item_count == 2)
	picker.select(1); picker.item_selected.emit(1)
	await process_frame
	var npc: CheckBox = helper.find_child("InstanceNpc1", true, false)
	assert(not npc.button_pressed)
	npc.button_pressed = true
	assert(editor.document.data.layout_instances[1].npcs.size() == 1)
	assert(editor.document.data.layout_instances[0].npcs.size() == 1)
	await process_frame
	helper = editor.metadata_box.find_child("SharedInstanceHelper", true, false)
	assert(helper.selected_id == "house_2")
	var exit_picker: OptionButton = helper.find_child("InstanceExitWarp_return_warp", true, false)
	for item in exit_picker.item_count:
		if int(exit_picker.get_item_metadata(item)) == 6:
			exit_picker.select(item); exit_picker.item_selected.emit(item); break
	assert(int(editor.document.data.layout_instances[1].warp_destinations.return_warp.entrance_map_warp_id) == 6)
	editor._undo()
	assert(int(editor.document.data.layout_instances[1].warp_destinations.return_warp.entrance_map_warp_id) == 5)
	await process_frame
	helper = editor.metadata_box.find_child("SharedInstanceHelper", true, false)
	helper.find_child("AddSharedInstance", true, false).pressed.emit()
	assert(editor.document.data.layout_instances.size() == 3)
	assert(editor.document.data.layout_instances[2].npcs.is_empty())
	assert(editor.shared_instance_selection == "house_3")
	await process_frame
	var rug: CheckBox = editor.metadata_box.find_child("SharedEntranceRug", true, false)
	rug.button_pressed = false
	assert(not editor.document.data.warp_metadata.return_warp.show_sprite)
	editor._load_path(editor.map_directory.path_join("jalovea_city.json"))
	await process_frame
	for object: Dictionary in editor.editor_objects:
		if object.path == "$.warp_4": editor.selected_id = String(object.id); editor._refresh_inspector(); break
	await process_frame
	var entrance: OptionButton = editor.inspector.find_child("WarpEntranceInstancePicker", true, false)
	assert(entrance.item_count == 3 and entrance.get_item_text(entrance.selected) == "house_1")
	entrance.select(2); entrance.item_selected.emit(2)
	assert(editor.document.data.warp_metadata.warp_4.entrance_instance_id == "house_2")
	print("SHARED_LAYOUT_UI_TESTS_PASSED")
	editor.free()
	quit()
