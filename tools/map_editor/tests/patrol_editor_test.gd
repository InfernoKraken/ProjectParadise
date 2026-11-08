extends SceneTree

func _initialize() -> void:
	var editor = load("res://map_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	editor._new_document()
	editor._edit_patrols()
	var dialog: AcceptDialog
	for child in editor.get_children():
		if child is AcceptDialog and child.title == "Patrols": dialog = child
	assert(dialog != null)
	var kind: OptionButton = dialog.find_child("PatrolType", true, false)
	var interval: SpinBox = dialog.find_child("PatrolCreationInterval", true, false)
	var nodes: ItemList = dialog.find_child("ScriptPathNodes", true, false)
	assert(kind != null and nodes.item_count == 0)
	var map: Control = dialog.find_child("PatrolMap", true, false)
	assert(map.script_path_add_mode)
	for point in [Vector2.ZERO, Vector2(0, 10)]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = map.world_to_screen(point)
		map._gui_input(click)
	assert(nodes.item_count == 2)
	interval.value = 2.5
	dialog.confirmed.emit()
	assert(editor.document.data.patrols.size() == 1)
	assert(editor.document.data.patrols[0].creation_interval == 2.5)
	await process_frame
	editor._edit_patrols()
	for child in editor.get_children():
		if child is AcceptDialog and child.title == "Patrols": dialog = child
	kind = dialog.find_child("PatrolType", true, false)
	var picker: OptionButton = dialog.find_child("PatrolPicker", true, false)
	var vehicles: TextEdit = dialog.find_child("PatrolVehicles", true, false)
	vehicles.text = "["
	picker.select(0); picker.item_selected.emit(0)
	assert(picker.selected == 0)
	picker.select(1); picker.item_selected.emit(1)
	assert(vehicles.text == "[")
	kind.select(1); kind.item_selected.emit(1)
	assert(kind.selected == 1)
	picker.select(0); picker.item_selected.emit(0)
	# Remove the incomplete second patrol so the first can be saved.
	for button in dialog.find_children("*", "Button", true, false):
		if button.text == "Delete Patrol":
			picker.select(1); picker.item_selected.emit(1)
			button.pressed.emit()
			break
	kind.select(1); kind.item_selected.emit(1)
	var cap: SpinBox = dialog.find_child("PatrolMaxActiveVehicles", true, false)
	assert(cap.visible and cap.value == 8)
	cap.value = 4
	dialog.confirmed.emit()
	assert(editor.document.data.patrols[0].type == "traffic")
	assert(editor.document.data.patrols[0].traffic_vehicle.sprite == "Tug")
	assert(editor.document.data.patrols[0].max_active_vehicles == 4)
	editor.queue_free()
	await process_frame
	print("PATROL_EDITOR_TEST_PASSED")
	quit()
