class_name MapDataLoader
extends RefCounted


static func load_world(index_path: String) -> Dictionary:
	var index := _load_json_object(index_path)
	if index.is_empty():
		return {}
	var base_directory := index_path.get_base_dir()
	var root_file := String(index.get("root", ""))
	if root_file.is_empty():
		push_error("Map index is missing its root map: %s" % index_path)
		return {}
	var world := _load_json_object(base_directory.path_join(root_file))
	if world.is_empty():
		return {}
	var sections: Dictionary = index.get("sections", {})
	for section_name: String in sections:
		var section := _load_json_object(base_directory.path_join(String(sections[section_name])))
		if section.is_empty():
			return {}
		world[section_name] = section
	var nested_sections: Dictionary = index.get("nested_sections", {})
	for parent_name: String in nested_sections:
		if not world.get(parent_name) is Dictionary:
			push_error("Map index references unknown parent map '%s'." % parent_name)
			return {}
		var parent: Dictionary = world[parent_name]
		var children: Dictionary = nested_sections[parent_name]
		for section_name: String in children:
			var section := _load_json_object(base_directory.path_join(String(children[section_name])))
			if section.is_empty():
				return {}
			parent[section_name] = section
	return world


static func _load_json_object(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open map data: %s" % path)
		return {}
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		push_error("Invalid map JSON in %s at line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if not json.data is Dictionary:
		push_error("Map data must be a JSON object: %s" % path)
		return {}
	return json.data


static func outdoor_destination(source: Dictionary, warp_field: String) -> Dictionary:
	for value: Variant in source.get("outdoor_connections", []):
		if value is Dictionary and String(value.get("warp", "")) == warp_field:
			return value
	return {}


static func arrival_position(source: Dictionary, warp_field: String, target: Dictionary, legacy_arrival: String) -> Array:
	var connection := outdoor_destination(source, warp_field)
	var arrival_name := String(connection.get("arrival", legacy_arrival))
	var arrivals: Dictionary = target.get("arrival_points", {})
	var position: Variant = arrivals.get(arrival_name, target.get(arrival_name, []))
	return position if position is Array else []
