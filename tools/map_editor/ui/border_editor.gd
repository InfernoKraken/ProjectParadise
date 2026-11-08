extends AcceptDialog

signal checkpoint_requested
signal border_changed(side: String, definition: Dictionary)
signal corner_priority_changed(priority: String)
signal undo_requested
signal redo_requested

const Layout := preload("res://core/map_border_layout.gd")
const BorderCanvas := preload("res://ui/border_canvas.gd")
const Assets := preload("res://core/asset_catalog.gd")
const Bounds := preload("res://core/map_bounds.gd")

var _map: Dictionary
var _catalog: AssetCatalog
var _canvas: Control
var _side: OptionButton
var _enabled: CheckBox
var _depth: SpinBox
var _span: Label
var _priority: OptionButton
var _layer: OptionButton
var _terrain: OptionButton
var _art: OptionButton
var _search: LineEdit
var _scale: SpinBox
var _rotation: SpinBox
var _fill: Button
var _hint: Label
var _refreshing := false
var _stroke_checkpoint := false
var _last_cell := Vector2i(-1, -1)
var _art_options: Array[Dictionary] = []

func build(project_root: String, catalog: AssetCatalog) -> void:
	_catalog = catalog
	title = "Map Border Editor"
	ok_button_text = "Done"
	transient = true
	exclusive = true
	min_size = Vector2i(680, 440)
	var content := VBoxContainer.new()
	add_child(content)
	var row := HFlowContainer.new()
	content.add_child(row)
	_side = OptionButton.new()
	for side in Layout.SIDES: _side.add_item(side.capitalize())
	row.add_child(_side)
	_side.item_selected.connect(func(_index): _refresh(true))
	_enabled = CheckBox.new()
	_enabled.text = "Enabled in game"
	row.add_child(_enabled)
	_enabled.toggled.connect(_set_enabled)
	_span = Label.new()
	row.add_child(_span)
	_depth = _number(row, "Depth", 1, Layout.MAX_DIMENSION, 1, 4)
	_depth.value_changed.connect(func(value): _set_property("depth", int(value)))
	var corner_label := Label.new()
	corner_label.text = "Corner priority"
	row.add_child(corner_label)
	_priority = OptionButton.new()
	_priority.add_item("North / South")
	_priority.add_item("East / West")
	_priority.tooltip_text = "Choose which pair of borders extends into the corners for this map."
	_priority.item_selected.connect(_set_corner_priority)
	row.add_child(_priority)
	_button(row, "Undo", func(): undo_requested.emit())
	_button(row, "Redo", func(): redo_requested.emit())

	var brushes := HFlowContainer.new()
	content.add_child(brushes)
	_layer = OptionButton.new()
	_layer.add_item("Terrain")
	_layer.add_item("Visual asset")
	brushes.add_child(_layer)
	_layer.item_selected.connect(func(_index): _refresh_layer())
	_terrain = OptionButton.new()
	_terrain.fit_to_longest_item = false
	_terrain.custom_minimum_size.x = 175
	brushes.add_child(_terrain)
	_search = LineEdit.new()
	_search.placeholder_text = "Find artwork"
	_search.custom_minimum_size.x = 125
	_search.text_changed.connect(func(_value): _populate_art())
	brushes.add_child(_search)
	_art = OptionButton.new()
	_art.fit_to_longest_item = false
	_art.custom_minimum_size.x = 200
	_art.item_selected.connect(func(_index): _update_art_controls())
	brushes.add_child(_art)
	_scale = _number(brushes, "Scale", 0.1, 8, 0.1, 1)
	_rotation = _number(brushes, "Rotation °", -180, 180, 1, 0)
	var tools := HFlowContainer.new()
	content.add_child(tools)
	var modes := ButtonGroup.new()
	for mode in ["paint", "erase"]:
		var button := _button(tools, mode.capitalize(), func(): _canvas.terrain_brush_mode = mode)
		button.toggle_mode = true
		button.button_group = modes
		button.button_pressed = mode == "paint"
	_fill = _button(tools, "Fill terrain", _fill_terrain)
	_button(tools, "Frame canvas", func(): _canvas.frame_all())
	var preview := CheckBox.new()
	preview.text = "Preview"
	preview.tooltip_text = "Show the artwork with the gameplay ground projection and hide the editing grid."
	preview.toggled.connect(func(value): _canvas.placement_preview = value; _canvas.frame_all())
	tools.add_child(preview)
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_hint)

	_canvas = BorderCanvas.new()
	_canvas.project_root = project_root
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.custom_minimum_size.y = 235
	_canvas.terrain_brush_mode = "paint"
	_canvas.terrain_stroke_started.connect(_reset_stroke)
	_canvas.terrain_stroke_finished.connect(_reset_stroke)
	_canvas.terrain_cell_changed.connect(_paint)
	content.add_child(_canvas)
	_build_palette()
	_refresh_layer()

func open_map(map: Dictionary) -> void:
	_map = map
	popup_centered(Vector2i(1000, 720))
	_refresh()
	_canvas.frame_all.call_deferred()

func refresh_map(map: Dictionary) -> void:
	_map = map
	_refresh()

func _build_palette() -> void:
	for entry: Dictionary in _catalog.entries:
		var type_id := String(entry.get("type_id", ""))
		var serialization: Dictionary = entry.get("serialization", {})
		if serialization.get("kind") == "terrain_tile":
			var terrain := String(serialization.terrain_type)
			_terrain.add_item(String(entry.display_name))
			_terrain.set_item_metadata(_terrain.item_count - 1, terrain)
		var hidden := bool(entry.get("palette_hidden", false)) and not type_id.begins_with("background.citybuilding")
		if type_id.begins_with("terrain.") or hidden or bool(entry.get("non_serializing", false)) or entry.has("palette_choices"):
			continue
		var variants: Array = entry.get("variants", [])
		var artwork_variants := variants.filter(func(value): return value is Dictionary and value.has("preview_texture"))
		if artwork_variants.is_empty(): artwork_variants = [entry]
		for variant: Dictionary in artwork_variants:
			var path := Layout.texture_path({"texture": variant.get("preview_texture", "")})
			if path.is_empty(): continue
			var name := String(entry.display_name)
			if variant != entry: name += " · " + String(variant.get("name", path.get_file()))
			_art_options.append({"name": name, "entry": entry, "texture": path})
	_populate_art()

func _populate_art() -> void:
	_art.clear()
	var query := _search.text.strip_edges().to_lower()
	for art in _art_options:
		if not query.is_empty() and not (art.name + " " + art.texture).to_lower().contains(query): continue
		_art.add_item(art.name)
		_art.set_item_metadata(_art.item_count - 1, art)
	if _art.item_count > 0: _art.select(0)
	_update_art_controls()

func _update_art_controls() -> void:
	var has_art := _art.selected >= 0
	_scale.editable = has_art
	_rotation.editable = has_art

func _refresh_layer() -> void:
	var terrain := _layer.selected == 0
	_terrain.visible = terrain
	_fill.visible = terrain
	for control: Control in [_search, _art, _scale.get_parent(), _rotation.get_parent()]:
		control.visible = not terrain

func _refresh(frame: bool = false) -> void:
	_refreshing = true
	var side := _side_name()
	var definition := Layout.definition(_map, side)
	var dimensions := Layout.dimensions(_map, side, definition)
	var horizontal := Layout.horizontal(side)
	_enabled.set_pressed_no_signal(definition.get("enabled") == true)
	_depth.set_value_no_signal(Layout.depth(definition, side))
	_priority.select(Layout.CORNER_PRIORITIES.find(Layout.corner_priority(_map)))
	_span.text = "Map width · %d tiles" % dimensions.x if horizontal else "Map height · %d tiles" % dimensions.y
	_hint.text = "Drag to paint or erase the selected layer. Middle-drag to pan, wheel to zoom. Shrinking hides cells outside the canvas."
	if not _enabled.button_pressed:
		_hint.text = "This side is hidden in Placement Preview and in game. " + _hint.text
	_canvas.show_border(dimensions, Layout.editable_cells(_map, side, definition), frame)
	_refreshing = false

func _side_name() -> String:
	return Layout.SIDES[_side.selected]

func _set_enabled(enabled: bool) -> void:
	_set_property("enabled", enabled)

func _set_corner_priority(index: int) -> void:
	if _refreshing: return
	var priority: String = Layout.CORNER_PRIORITIES[index]
	if priority == Layout.corner_priority(_map): return
	checkpoint_requested.emit()
	corner_priority_changed.emit(priority)

func _set_property(key: String, value: Variant) -> void:
	if _refreshing: return
	var definition := _editable_definition()
	definition[key] = value
	checkpoint_requested.emit()
	_commit(definition)
	_refresh()

func _editable_definition() -> Dictionary:
	var definition := Layout.definition(_map, _side_name()).duplicate()
	definition.merge({"depth": Layout.depth(definition, _side_name()), "enabled": false})
	definition.erase("width")
	definition.erase("height")
	definition["cells"] = _canvas.cells
	return definition

func _commit(definition: Dictionary) -> void:
	border_changed.emit(_side_name(), definition)
	_canvas.show_border(Layout.dimensions(_map, _side_name(), definition), definition.cells)

func _reset_stroke() -> void:
	_stroke_checkpoint = false
	_last_cell = Vector2i(-1, -1)

func _paint(cell: Vector2i, erase: bool) -> void:
	var definition := _editable_definition()
	var bounds := Rect2i(Vector2i.ZERO, Layout.dimensions(_map, _side_name(), definition))
	if not bounds.has_point(cell):
		_last_cell = Vector2i(-1, -1)
		return
	var layer := "terrain" if _layer.selected == 0 else "art"
	var value: Variant = null
	if not erase:
		value = _terrain.get_selected_metadata() if layer == "terrain" else _selected_art()
		if value == null: return
		if value is Dictionary and value.has("footprint") and bounds.has_point(_last_cell): return
	var cells: Dictionary = definition.get("cells", {}) if definition.get("cells") is Dictionary else {}
	var start := _last_cell if bounds.has_point(_last_cell) else cell
	_last_cell = cell
	var delta := cell - start
	var steps := maxi(1, maxi(absi(delta.x), absi(delta.y)))
	var changed := false
	for index in range(steps + 1):
		var point := Vector2i(Vector2(start).lerp(Vector2(cell), float(index) / steps).round())
		var key := Layout.cell_key(point)
		var existing: Variant = cells.get(key)
		var record: Dictionary = existing.duplicate() if existing is Dictionary else {}
		var placement: Variant = value
		if value is Dictionary and value.has("footprint"):
			placement = _fit_building(point, value, bounds.size)
			if placement == null: continue
		if record.get(layer) == placement: continue
		if not _stroke_checkpoint:
			checkpoint_requested.emit()
			_stroke_checkpoint = true
		if erase: record.erase(layer)
		else: record[layer] = placement
		if record.is_empty(): cells.erase(key)
		else: cells[key] = record
		changed = true
	if changed:
		definition["cells"] = cells
		_commit(definition)

func _fit_building(cell: Vector2i, art: Dictionary, canvas_size: Vector2i) -> Variant:
	var span := Vector2(canvas_size)
	var map_size := Bounds.rect(_map).size
	if Layout.horizontal(_side_name()): span.x = map_size.x
	else: span.y = map_size.y
	var footprint := Layout.building_footprint(art)
	if footprint.x > span.x or footprint.y > span.y:
		_hint.text = "The building footprint is too large for this border at the selected scale."
		return null
	var bounds := Rect2(-Vector2.ONE * 0.5, span)
	var minimum := bounds.position + Vector2(footprint.x * 0.5, footprint.y)
	var maximum := bounds.end - Vector2(footprint.x * 0.5, 0)
	var offset := Vector2(cell).clamp(minimum, maximum) - Vector2(cell)
	var placement := art.duplicate()
	placement["anchor_offset"] = [offset.x, offset.y]
	return placement

func _fill_terrain() -> void:
	if _terrain.selected < 0: return
	var terrain: String = _terrain.get_selected_metadata()
	var definition := _editable_definition()
	var dimensions := Layout.dimensions(_map, _side_name(), definition)
	var cells: Dictionary = definition.get("cells", {}) if definition.get("cells") is Dictionary else {}
	checkpoint_requested.emit()
	for z in dimensions.y:
		for x in dimensions.x:
			var key := Layout.cell_key(Vector2i(x, z))
			var cell: Dictionary = cells.get(key, {}) if cells.get(key) is Dictionary else {}
			cell["terrain"] = terrain
			cells[key] = cell
	definition["cells"] = cells
	_commit(definition)

func _selected_art() -> Variant:
	if _art.selected < 0: return null
	var selection: Dictionary = _art.get_selected_metadata()
	var entry: Dictionary = selection.entry
	var path: String = selection.texture
	var animation := String(entry.get("animation", ""))
	var type_id := String(entry.type_id)
	if type_id == "structure.canal_lock": animation = "canal_lock"
	var texture: Texture2D = _canvas.visual_texture(path, animation)
	if texture == null: return null
	var ratio := float(texture.get_width()) / maxf(1, texture.get_height())
	var metadata := Assets.load_metadata(_canvas.project_root.path_join(path))
	var default_size: Variant = entry.get("default_size")
	if bool(metadata.get("standardize_scale", false)):
		default_size = metadata.get("size", default_size)
	var height := float(entry.get("display_height", 1.0))
	if bool(metadata.get("standardize_scale", false)):
		height = float(metadata.get("visual_height", height))
	var flat: bool = entry.get("scale_mode") == "explicit_size" or type_id.begins_with("tile.")
	var dimensions := Vector2(height * ratio, height)
	if flat:
		dimensions = Vector2(ratio, 1.0)
		match entry.get("serialization", {}).get("kind"):
			"block6": dimensions = Vector2(2, 2)
			"zone": dimensions = Vector2(3, 3)
		if default_size is Array and default_size.size() >= 3:
			dimensions = Vector2(float(default_size[0]), float(default_size[2]))
	elif type_id.begins_with("building.") or type_id.begins_with("background.citybuilding"):
		var width := 10.0 if type_id.begins_with("background.") else 5.0
		if default_size is Array and default_size.size() >= 3: width = float(default_size[0])
		if not type_id.begins_with("background."): width *= 1.08 if type_id == "building.medical_ward" else 1.15
		dimensions = Vector2(width, width / ratio)
	dimensions = (dimensions * _scale.value).clamp(Vector2.ONE * 0.05, Vector2.ONE * Layout.MAX_ART_SIZE)
	var art := {"texture": path, "size": [dimensions.x, dimensions.y], "rotation": _rotation.value, "flat": flat}
	if type_id.begins_with("background.citybuilding") or type_id.begins_with("building."):
		var footprint := Vector2(5, 4)
		if default_size is Array and default_size.size() >= 3:
			footprint = Vector2(float(default_size[0]), float(default_size[2]))
		footprint.y += float(entry.get("front_depth_extension", 0))
		footprint *= _scale.value
		art["footprint"] = [footprint.x, footprint.y]
	if not animation.is_empty(): art["animation"] = animation
	return art

func _button(parent: Control, label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _number(parent: Control, label: String, minimum: float, maximum: float, step: float, initial: float) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var caption := Label.new()
	caption.text = label
	row.add_child(caption)
	var number := SpinBox.new()
	number.min_value = minimum
	number.max_value = maximum
	number.step = step
	number.value = initial
	row.add_child(number)
	return number
