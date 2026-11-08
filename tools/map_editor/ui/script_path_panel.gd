extends VBoxContainer

signal paths_changed(paths: Array)
signal selection_changed(path_name: String, node_index: int)
signal add_mode_changed(enabled: bool)
var paths: Array = []
var selected_name := ""
var selected_node := -1
var preview_label: Label
var picker: OptionButton
var name_edit: LineEdit
var node_list: ItemList
var x: SpinBox
var z: SpinBox
var syncing := false
var registry: Script

func configure(command_registry: Script) -> void:
	registry = command_registry
	var header := Label.new(); header.text = "PATHS · map-local X/Z"; add_child(header)
	preview_label = Label.new(); preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(preview_label)
	picker = OptionButton.new(); picker.name = "ScriptPathPicker"; add_child(picker)
	picker.item_selected.connect(func(index):selected_name = str(picker.get_item_metadata(index)); selected_node = -1; refresh())
	name_edit = LineEdit.new(); name_edit.placeholder_text = "Path name"; name_edit.name = "ScriptPathName"; add_child(name_edit)
	var row := HBoxContainer.new(); add_child(row)
	button(row, "Create MOVE", func():create_path("MOVE")); button(row, "Create FOLLOW", func():create_path("FOLLOW"))
	row = HBoxContainer.new(); add_child(row)
	button(row, "Rename", rename_path); button(row, "Delete Path", delete_path)
	var add_mode := CheckButton.new(); add_mode.text = "Add nodes by clicking map"; add_mode.name = "ScriptPathAddMode"; add_mode.toggled.connect(func(enabled):add_mode_changed.emit(enabled)); add_child(add_mode)
	node_list = ItemList.new(); node_list.custom_minimum_size.y = 65; node_list.name = "ScriptPathNodes"; add_child(node_list)
	node_list.item_selected.connect(func(index):selected_node = index; refresh())
	row = HBoxContainer.new(); add_child(row)
	for axis in ["X", "Z"]:
		var spin := SpinBox.new(); spin.min_value = -1000000; spin.max_value = 1000000; spin.step = 0.25; spin.prefix = axis + " "; spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(spin)
		if axis == "X": x = spin
		else: z = spin
		spin.value_changed.connect(func(_value):if not syncing and selected_node >= 0:edit_node(selected_name, selected_node, Vector2(x.value, z.value)))
	row = HBoxContainer.new(); add_child(row)
	button(row, "Add Node", func():add_node(Vector2.ZERO if current().is_empty() or current().nodes.is_empty() else Vector2(current().nodes[-1][0] + 1, current().nodes[-1][1])))
	button(row, "Insert After", insert_node); button(row, "Delete Node", delete_node)

func button(parent: Control, text: String, action: Callable) -> void:
	var control := Button.new(); control.text = text; control.pressed.connect(action); parent.add_child(control)

func set_paths(value: Variant) -> void:
	paths = value.duplicate(true) if value is Array else []
	refresh()

func current() -> Dictionary:
	for value: Variant in paths:
		if value is Dictionary and value.get("name") == selected_name and value.get("nodes") is Array: return value
	return {}

func refresh() -> void:
	syncing = true; picker.clear(); node_list.clear()
	for value: Variant in paths:
		if not value is Dictionary: continue
		var index := picker.item_count; picker.add_item(str(value.get("type", "INVALID")) + " · " + str(value.get("name", "?"))); picker.set_item_metadata(index, value.get("name", ""))
		if value.get("name") == selected_name: picker.select(index)
	var path := current()
	name_edit.text = selected_name
	if not path.is_empty():
		for point: Variant in path.nodes: node_list.add_item(str(node_list.item_count + 1) + " · " + str(point))
		if selected_node >= 0 and selected_node < path.nodes.size():
			node_list.select(selected_node)
			var point: Variant = path.nodes[selected_node]
			if point is Array and point.size() == 2 and (point[0] is int or point[0] is float):
				if (point[1] is int or point[1] is float) and is_finite(float(point[0])) and is_finite(float(point[1])): x.value = point[0]; z.value = point[1]
		else: selected_node = -1
	x.editable = selected_node >= 0; z.editable = selected_node >= 0
	syncing = false; selection_changed.emit(selected_name, selected_node)

func create_path(type: String) -> void:
	var name := name_edit.text.strip_edges()
	if name.is_empty() or name == selected_name:
		var index := 1; name = type.capitalize() + "Path1"
		while paths.any(func(p):return p is Dictionary and p.get("name") == name): index += 1; name = type.capitalize() + "Path" + str(index)
	if not registry.identifier(name) or paths.any(func(p):return p is Dictionary and p.get("name") == name): name_edit.tooltip_text = "Use a unique identifier."; return
	paths.append({"name":name, "type":type, "nodes":[]}); selected_name = name; selected_node = -1; commit()

func rename_path() -> void:
	var name := name_edit.text.strip_edges(); var path := current()
	if path.is_empty() or not registry.identifier(name) or paths.any(func(p):return p is Dictionary and p.get("name") == name): return
	# Source is deliberately not rewritten; stale references get parser diagnostics.
	path.name = name; selected_name = name; commit()

func delete_path() -> void:
	var path := current()
	if path.is_empty(): return
	paths.erase(path); selected_name = ""; selected_node = -1; commit()

func add_node(point: Vector2) -> void:
	var path := current()
	if path.is_empty(): return
	path.nodes.append([point.x, point.y]); selected_node = path.nodes.size() - 1; commit()

func edit_node(path_name: String, index: int, point: Vector2) -> void:
	selected_name = path_name; var path := current()
	if path.is_empty() or index < 0 or index >= path.nodes.size(): return
	path.nodes[index] = [point.x, point.y]; selected_node = index; commit()

func insert_node() -> void:
	var path := current()
	if path.is_empty() or selected_node < 0 or selected_node >= path.nodes.size(): return
	var point: Variant = path.nodes[selected_node]
	if not point is Array or point.size() != 2 or not point.all(func(v):return v is int or v is float): return
	var next: Variant = path.nodes[selected_node + 1] if selected_node + 1 < path.nodes.size() else [point[0] + 2, point[1]]
	if not next is Array or next.size() != 2 or not next.all(func(v):return v is int or v is float): return
	path.nodes.insert(selected_node + 1, [(point[0] + next[0]) / 2.0, (point[1] + next[1]) / 2.0]); selected_node += 1; commit()

func delete_node() -> void:
	var path := current()
	if path.is_empty() or selected_node < 0 or selected_node >= path.nodes.size(): return
	path.nodes.remove_at(selected_node); selected_node = mini(selected_node, path.nodes.size() - 1); commit()

func commit() -> void:
	paths_changed.emit(paths.duplicate(true)); refresh()
