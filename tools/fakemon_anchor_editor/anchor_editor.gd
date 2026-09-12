extends Control

const AnchorEncoding := preload("res://tools/fakemon_anchor_editor/core/anchor_encoding.gd")
const AnchorMapCodec := preload("res://tools/fakemon_anchor_editor/core/anchor_map.gd")
const Validator := preload("res://tools/fakemon_anchor_editor/core/anchor_validator.gd")
const Geometry := preload("res://battle/battle_sprite_geometry.gd")
const BattleSceneEditorScript := preload("res://tools/fakemon_anchor_editor/battle_scene_editor.gd")
const SPRITE_DIR := "res://assets/fakemon/battle"
const GENERATED_PATH := "res://data/generated_battle_anchors.json"

var species_option: OptionButton
var side_option: OptionButton
var anchor_list: ItemList
var canvas: FakemonAnchorCanvas
var status_label: Label
var preview_button: Button
var current_species := ""
var current_side := "Player"
var source_image: Image
var anchors: Dictionary = {}
var declared_customs: Array[String] = []
var undo_stack: Array[Dictionary] = []
var fakemon_body: HBoxContainer
var battle_scene_editor: Control


func _ready() -> void:
	_build_ui()
	_populate_species()
	if species_option.item_count > 0:
		_load_document()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	add_child(root)
	var title := Label.new()
	title.text = "Anchor Editor"
	title.add_theme_font_size_override("font_size", 25)
	root.add_child(title)
	var tabs := TabBar.new()
	tabs.add_tab("Fakemon Anchors")
	tabs.add_tab("Battle Scene Anchors")
	tabs.tab_changed.connect(_on_tab_changed)
	root.add_child(tabs)
	fakemon_body = HBoxContainer.new()
	fakemon_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(fakemon_body)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 260
	fakemon_body.add_child(sidebar)
	species_option = OptionButton.new()
	species_option.item_selected.connect(func(_index): _load_document())
	sidebar.add_child(species_option)
	side_option = OptionButton.new()
	side_option.add_item("Player")
	side_option.add_item("Wild")
	side_option.item_selected.connect(func(_index): _load_document())
	sidebar.add_child(side_option)
	anchor_list = ItemList.new()
	anchor_list.custom_minimum_size.y = 340
	anchor_list.item_selected.connect(_on_anchor_selected)
	sidebar.add_child(anchor_list)
	_add_button(sidebar, "+ Custom Anchor", _add_custom)
	_add_button(sidebar, "Clear Selected", _clear_selected)
	_add_button(sidebar, "Undo", _undo)
	_add_button(sidebar, "Save + Generate", _save)
	preview_button = _add_button(sidebar, "Preview Processed", _toggle_preview)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(status_label)
	canvas = FakemonAnchorCanvas.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.anchor_changed.connect(_on_anchor_changed)
	fakemon_body.add_child(canvas)
	battle_scene_editor = BattleSceneEditorScript.new()
	battle_scene_editor.visible = false
	root.add_child(battle_scene_editor)


func _on_tab_changed(index: int) -> void:
	fakemon_body.visible = index == 0
	battle_scene_editor.visible = index == 1


func _add_button(parent: Control, label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _populate_species() -> void:
	var found := {}
	for file_name in DirAccess.get_files_at(SPRITE_DIR):
		if file_name.ends_with("_Player.png") or file_name.ends_with("_Wild.png"):
			found[file_name.trim_suffix("_Player.png").trim_suffix("_Wild.png")] = true
	var names := found.keys()
	names.sort()
	for species: String in names:
		species_option.add_item(species)


func _load_document() -> void:
	if species_option.item_count == 0:
		return
	current_species = species_option.get_item_text(species_option.selected)
	current_side = side_option.get_item_text(side_option.selected)
	var sprite_path := _sprite_path()
	source_image = Image.load_from_file(ProjectSettings.globalize_path(sprite_path))
	anchors.clear()
	declared_customs.clear()
	undo_stack.clear()
	if source_image == null or source_image.is_empty():
		status_label.text = "Source sprite is missing: %s" % sprite_path
		return
	var map_path := _map_path()
	if FileAccess.file_exists(map_path):
		var anchor_image := Image.load_from_file(ProjectSettings.globalize_path(map_path))
		if anchor_image != null:
			var loaded := AnchorMapCodec.extract(anchor_image)
			for anchor_name: String in loaded.anchors:
				anchors[anchor_name] = Vector2i((loaded.anchors[anchor_name] as Vector2).round())
				if anchor_name.begins_with("custom_"):
					declared_customs.append(anchor_name)
	canvas.set_document(source_image, anchors)
	_refresh_anchor_list()
	status_label.text = "%s %s — source %s" % [current_species, current_side, source_image.get_size()]
	preview_button.text = "Preview Processed"


func _refresh_anchor_list(selected := "") -> void:
	anchor_list.clear()
	var names: Array[String] = []
	for anchor_name: StringName in AnchorEncoding.REQUIRED + AnchorEncoding.OPTIONAL:
		names.append(String(anchor_name))
	var customs: Array[String] = []
	for anchor_name: String in anchors:
		if anchor_name.begins_with("custom_"):
			customs.append(anchor_name)
	for anchor_name: String in declared_customs:
		if not customs.has(anchor_name):
			customs.append(anchor_name)
	customs.sort_custom(func(a, b): return int(a.trim_prefix("custom_")) < int(b.trim_prefix("custom_")))
	names.append_array(customs)
	for anchor_name in names:
		var required := AnchorEncoding.REQUIRED.has(StringName(anchor_name))
		anchor_list.add_item("%s %s%s" % ["✓" if anchors.has(anchor_name) else "○", anchor_name, " (required)" if required else ""])
		anchor_list.set_item_metadata(anchor_list.item_count - 1, anchor_name)
		if anchor_name == selected:
			anchor_list.select(anchor_list.item_count - 1)
	if anchor_list.get_selected_items().is_empty() and anchor_list.item_count > 0:
		anchor_list.select(0)
	_on_anchor_selected(anchor_list.get_selected_items()[0])


func _on_anchor_selected(index: int) -> void:
	canvas.selected_anchor = anchor_list.get_item_metadata(index)
	canvas.queue_redraw()


func _on_anchor_changed(anchor_name: String, point: Vector2i) -> void:
	_push_undo()
	anchors[anchor_name] = point
	canvas.anchors = anchors.duplicate(true)
	_refresh_anchor_list(anchor_name)
	status_label.text = "%s placed at %s (unsaved)" % [anchor_name, point]


func _push_undo() -> void:
	undo_stack.append(anchors.duplicate(true))
	if undo_stack.size() > 30:
		undo_stack.pop_front()


func _undo() -> void:
	if undo_stack.is_empty():
		return
	anchors = undo_stack.pop_back()
	canvas.anchors = anchors.duplicate(true)
	canvas.queue_redraw()
	_refresh_anchor_list(canvas.selected_anchor)


func _clear_selected() -> void:
	var name := canvas.selected_anchor
	if AnchorEncoding.REQUIRED.has(StringName(name)):
		status_label.text = "Required anchor '%s' cannot be cleared; reposition it instead." % name
		return
	if anchors.has(name):
		_push_undo()
		anchors.erase(name)
		canvas.anchors = anchors.duplicate(true)
		_refresh_anchor_list()
		canvas.queue_redraw()


func _add_custom() -> void:
	var custom_id := 1
	while anchors.has("custom_%d" % custom_id):
		custom_id += 1
	var name := "custom_%d" % custom_id
	if not declared_customs.has(name):
		declared_customs.append(name)
	_refresh_anchor_list(name)
	status_label.text = "Click the sprite to place %s." % name


func _save() -> void:
	var anchor_image := AnchorMapCodec.create_image(source_image.get_size(), anchors)
	var errors := Validator.validate(source_image, anchor_image)
	if not errors.is_empty():
		status_label.text = "Cannot save:\n• " + "\n• ".join(errors)
		return
	var error := anchor_image.save_png(ProjectSettings.globalize_path(_map_path()))
	if error != OK:
		status_label.text = "Could not save anchor PNG (error %d)." % error
		return
	var processed := AnchorMapCodec.process_and_extract(anchor_image)
	var generated := _load_generated()
	generated["format_version"] = 1
	generated.get_or_add("sprites", {})
	var sprite_key := "%s_%s" % [current_species, current_side]
	var points := {}
	for anchor_name: String in processed.anchors:
		var point: Vector2 = processed.anchors[anchor_name]
		points[anchor_name] = [snappedf(point.x, 0.001), snappedf(point.y, 0.001)]
	generated.sprites[sprite_key] = {"processed_size": [processed.image.get_width(), processed.image.get_height()], "anchors": points}
	var file := FileAccess.open(GENERATED_PATH, FileAccess.WRITE)
	if file == null:
		status_label.text = "Anchor PNG saved, but generated JSON could not be opened."
		return
	file.store_string(JSON.stringify(generated, "  ") + "\n")
	status_label.text = "Saved %s and regenerated %s." % [_map_path(), GENERATED_PATH]


func _toggle_preview() -> void:
	if canvas.processed_preview:
		canvas.set_document(source_image, anchors)
		preview_button.text = "Preview Processed"
		return
	var anchor_image := AnchorMapCodec.create_image(source_image.get_size(), anchors)
	var processed_sprite := Geometry.process_image(source_image)
	var processed := AnchorMapCodec.process_and_extract(anchor_image)
	canvas.set_preview(processed_sprite, processed.anchors)
	preview_button.text = "Show Source"
	status_label.text = "Processed preview: %s. Markers are extracted centroids." % processed_sprite.get_size()


func _load_generated() -> Dictionary:
	if not FileAccess.file_exists(GENERATED_PATH):
		return {"format_version": 1, "sprites": {}}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(GENERATED_PATH))
	return parsed if parsed is Dictionary else {"format_version": 1, "sprites": {}}


func _sprite_path() -> String:
	return "%s/%s_%s.png" % [SPRITE_DIR, current_species, current_side]


func _map_path() -> String:
	return "%s/%s_%s.anchors.png" % [SPRITE_DIR, current_species, current_side]
