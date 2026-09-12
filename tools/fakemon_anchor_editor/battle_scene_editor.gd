class_name BattleSceneAnchorEditor
extends HBoxContainer

const DATA_PATH := "res://data/battle_scenes.json"
const Repository := preload("res://battle/battle_scene_anchor_repository.gd")
const SceneCanvasScript := preload("res://tools/fakemon_anchor_editor/battle_scene_canvas.gd")

var scene_option: OptionButton
var anchor_list: ItemList
var canvas: Control
var status_label: Label
var data: Dictionary = {}
var scene_id := ""
var undo_stack: Array[Dictionary] = []


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()
	_load_data()


func _build_ui() -> void:
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 260
	add_child(sidebar)
	var heading := Label.new()
	heading.text = "Battle scene"
	sidebar.add_child(heading)
	scene_option = OptionButton.new()
	scene_option.item_selected.connect(_select_scene)
	sidebar.add_child(scene_option)
	anchor_list = ItemList.new()
	anchor_list.custom_minimum_size.y = 390
	anchor_list.item_selected.connect(_select_anchor)
	sidebar.add_child(anchor_list)
	var help := Label.new()
	help.text = "Drag points to move them.\nDrag a region to move it.\nDrag its lower-right handle to resize."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(help)
	_add_button(sidebar, "Undo", _undo)
	_add_button(sidebar, "Save Scene Anchors", _save)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(status_label)
	canvas = SceneCanvasScript.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.document_changed.connect(_record_undo)
	add_child(canvas)


func _add_button(parent: Control, label: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.pressed.connect(callback)
	parent.add_child(button)


func _load_data() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not parsed is Dictionary:
		status_label.text = "Could not load %s." % DATA_PATH
		return
	data = parsed
	var names: Array = data.get("scenes", {}).keys()
	names.sort()
	for name: String in names:
		scene_option.add_item(name)
	if scene_option.item_count > 0:
		_select_scene(0)


func _select_scene(index: int) -> void:
	scene_id = scene_option.get_item_text(index)
	undo_stack.clear()
	var scene: Dictionary = data.scenes[scene_id]
	var texture := load(String(scene.get("background", ""))) as Texture2D
	canvas.set_document(texture, scene)
	anchor_list.clear()
	for name: String in Repository.VIEWPORT_ANCHORS:
		anchor_list.add_item("◆ %s (automatic)" % name)
		anchor_list.set_item_disabled(anchor_list.item_count - 1, true)
	for name: String in Repository.POINT_ANCHORS:
		anchor_list.add_item("● %s" % name)
		anchor_list.set_item_metadata(anchor_list.item_count - 1, name)
	for name: String in Repository.REGION_ANCHORS:
		anchor_list.add_item("▭ %s (region)" % name)
		anchor_list.set_item_metadata(anchor_list.item_count - 1, name)
	anchor_list.select(Repository.VIEWPORT_ANCHORS.size())
	_select_anchor(Repository.VIEWPORT_ANCHORS.size())
	status_label.text = "%s — %s" % [scene_id, scene.get("background", "")]


func _select_anchor(index: int) -> void:
	var metadata = anchor_list.get_item_metadata(index)
	if metadata != null:
		canvas.selected_anchor = String(metadata)
		canvas.queue_redraw()


func _record_undo(before: Dictionary) -> void:
	undo_stack.append(before)
	if undo_stack.size() > 30:
		undo_stack.pop_front()
	status_label.text = "%s changed (unsaved)." % canvas.selected_anchor


func _undo() -> void:
	if undo_stack.is_empty():
		return
	canvas.document = undo_stack.pop_back()
	canvas.queue_redraw()
	status_label.text = "Last scene-anchor edit undone."


func _save() -> void:
	var errors := _validate(canvas.document)
	if not errors.is_empty():
		status_label.text = "Cannot save:\n• " + "\n• ".join(errors)
		return
	data.scenes[scene_id] = canvas.document.duplicate(true)
	var file := FileAccess.open(DATA_PATH, FileAccess.WRITE)
	if file == null:
		status_label.text = "Could not write %s." % DATA_PATH
		return
	file.store_string(JSON.stringify(data, "  ") + "\n")
	status_label.text = "Saved scene anchors to %s." % DATA_PATH


static func _validate(scene: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var size_values: Array = scene.get("reference_size", [])
	if size_values.size() < 2 or float(size_values[0]) <= 0 or float(size_values[1]) <= 0:
		errors.append("reference_size must contain a positive width and height.")
		return errors
	var bounds := Rect2(Vector2.ZERO, Vector2(float(size_values[0]), float(size_values[1])))
	for name: String in Repository.POINT_ANCHORS:
		var value: Array = scene.get("anchors", {}).get(name, [])
		if value.size() < 2:
			errors.append("Point anchor '%s' is missing." % name)
		elif not bounds.has_point(Vector2(float(value[0]), float(value[1]))):
			errors.append("Point anchor '%s' lies outside the reference bounds." % name)
	for name: String in Repository.REGION_ANCHORS:
		var value: Dictionary = scene.get("regions", {}).get(name, {})
		var region := Rect2(float(value.get("x", -1)), float(value.get("y", -1)), float(value.get("width", 0)), float(value.get("height", 0)))
		if region.size.x <= 0 or region.size.y <= 0:
			errors.append("Region '%s' must have positive width and height." % name)
		elif not bounds.encloses(region):
			errors.append("Region '%s' lies outside the reference bounds." % name)
	return errors
