extends VBoxContainer

signal instances_changed(instances: Array, selected_id: String)
signal selection_changed(selected_id: String)

var instances: Array = []
var selected_id := ""
var map_data: Dictionary = {}
var definitions: Dictionary = {}
var destinations: Dictionary = {}
var details: VBoxContainer

func setup(data: Dictionary, npc_definitions: Dictionary, maps: Dictionary, selection: String) -> void:
	map_data = data
	definitions = npc_definitions
	destinations = maps
	instances = data.get("layout_instances", []).duplicate(true)
	selected_id = selection
	_rebuild()

func _label(value: String, parent: Node = null) -> void:
	if parent == null: parent = self
	var label := Label.new(); label.text = value; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; parent.add_child(label)

func _rebuild() -> void:
	for child in get_children(): remove_child(child); child.queue_free()
	_label("SHARED INSTANCES")
	var picker := OptionButton.new(); picker.name = "SharedInstancePicker"; picker.fit_to_longest_item = false; add_child(picker)
	var selected := -1
	for index in instances.size():
		picker.add_item(String(instances[index].get("id", "Invalid instance")))
		if String(instances[index].get("id", "")) == selected_id: selected = index
	if selected < 0 and not instances.is_empty(): selected = 0
	if selected >= 0:
		picker.select(selected); selected_id = String(instances[selected].id)
	picker.disabled = instances.is_empty()
	picker.item_selected.connect(func(index): selected_id = String(instances[index].id); selection_changed.emit(selected_id); _rebuild())
	var add := Button.new(); add.name = "AddSharedInstance"; add.text = "+ Add Instance"; add_child(add)
	add.pressed.connect(_add_instance)
	if selected < 0:
		_label("Add an instance, then choose its NPCs and exit. Changes are saved with the map.")
		return
	details = VBoxContainer.new(); add_child(details)
	_label("Editing: " + selected_id + " (canvas shows the base layout)", details)
	_label("NPCs in this instance", details)
	var placements := _npc_choices()
	if placements.is_empty(): _label("Add NPCs using the normal NPC tools first.", details)
	var current: Array = instances[selected].get("npcs", map_data.get("npcs", []))
	for placement: Dictionary in placements:
		var id := int(placement.id)
		var enabled := CheckBox.new(); enabled.name = "InstanceNpc%d" % id
		enabled.text = "NPC%d · %s" % [id, String(Dictionary(definitions.get(str(id), {})).get("sprite", "NPC"))]
		enabled.button_pressed = current.any(func(record): return int(record.get("id", 0)) == id)
		details.add_child(enabled)
		enabled.toggled.connect(func(value): _set_npc(selected, placement, value))
	_label("Exit / return warp", details)
	var fields: Array = Dictionary(map_data.get("warp_metadata", {})).keys(); fields.sort()
	for field: String in fields:
		_add_exit(selected, field)
	_label("In the city warp Inspector, select this map and instance: " + selected_id + ". Save both maps.", details)
	_label("Unchecked NPCs are excluded explicitly. NPC positions come from existing placements; scripts and custom positions remain available in Advanced JSON.", details)

func _npc_choices() -> Array:
	var choices := {}
	for record: Dictionary in map_data.get("npcs", []): choices[int(record.id)] = record
	for instance: Dictionary in instances:
		for record: Dictionary in instance.get("npcs", []):
			if not choices.has(int(record.id)): choices[int(record.id)] = record
	for key: String in definitions:
		if key.is_valid_int() and not choices.has(int(key)):
			choices[int(key)] = {"id":int(key), "position":[0,0,0], "facing":"down"}
	var ids: Array = choices.keys(); ids.sort()
	var result: Array = []
	for id: int in ids: result.append(choices[id])
	return result

func _add_instance() -> void:
	var number := 1
	while instances.any(func(record): return String(record.get("id", "")) == "house_%d" % number): number += 1
	selected_id = "house_%d" % number
	instances.append({"id":selected_id, "npcs":[], "warp_destinations":{}})
	instances_changed.emit(instances.duplicate(true), selected_id)

func _set_npc(index: int, placement: Dictionary, included: bool) -> void:
	var current: Array = instances[index].get("npcs", map_data.get("npcs", [])).duplicate(true)
	current = current.filter(func(record): return int(record.get("id", 0)) != int(placement.id))
	if included: current.append(placement.duplicate(true))
	instances[index]["npcs"] = current
	instances_changed.emit(instances.duplicate(true), selected_id)

func _add_exit(index: int, field: String) -> void:
	var base: Dictionary = map_data.warp_metadata[field]
	var override: Dictionary = Dictionary(instances[index].get("warp_destinations", {})).get(field, {})
	var filename := String(override.get("entrance_map", base.get("entrance_map", "")))
	var warp_id := int(override.get("entrance_map_warp_id", base.get("entrance_map_warp_id", 1)))
	_label(field, details)
	var map_picker := OptionButton.new(); map_picker.name = "InstanceExitMap_" + field; map_picker.fit_to_longest_item = false; details.add_child(map_picker)
	map_picker.add_item("Choose destination map"); map_picker.set_item_metadata(0, "")
	var filenames: Array = destinations.keys(); filenames.sort()
	for map_file: String in filenames:
		map_picker.add_item(map_file.trim_suffix(".json")); map_picker.set_item_metadata(map_picker.item_count - 1, map_file)
		if map_file == filename: map_picker.select(map_picker.item_count - 1)
	map_picker.item_selected.connect(func(item):
		var target := String(map_picker.get_item_metadata(item))
		var metadata: Dictionary = Dictionary(destinations.get(target, {})).get("warp_metadata", {})
		var first := 1
		if not metadata.is_empty(): first = int(metadata.values()[0].get("id", 1))
		_set_exit(index, field, {"entrance_map":target, "entrance_map_warp_id":first, "entrance_instance_id":""}))
	var warp_picker := OptionButton.new(); warp_picker.name = "InstanceExitWarp_" + field; details.add_child(warp_picker)
	var metadata: Dictionary = Dictionary(destinations.get(filename, {})).get("warp_metadata", {})
	for target_field: String in metadata:
		var id := int(metadata[target_field].get("id", 0))
		warp_picker.add_item("%s (ID %d)" % [target_field, id]); warp_picker.set_item_metadata(warp_picker.item_count - 1, id)
		if id == warp_id: warp_picker.select(warp_picker.item_count - 1)
	warp_picker.disabled = metadata.is_empty()
	warp_picker.item_selected.connect(func(item): _set_exit(index, field, {"entrance_map_warp_id":int(warp_picker.get_item_metadata(item))}))

func _set_exit(index: int, field: String, values: Dictionary) -> void:
	if not instances[index].has("warp_destinations"): instances[index]["warp_destinations"] = {}
	if not instances[index].warp_destinations.has(field): instances[index].warp_destinations[field] = {}
	instances[index].warp_destinations[field].merge(values, true)
	instances_changed.emit(instances.duplicate(true), selected_id)
