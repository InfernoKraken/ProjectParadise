class_name MapDataLoader
extends RefCounted

const NpcMapData := preload("res://world/npc_map_data.gd")
const NpcVisualResolver := preload("res://world/npc_visual_resolver.gd")
static var _npc_visuals: RefCounted

const TerrainTransitionResolver := preload("res://world/terrain_transition_resolver.gd")


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
	var map_files := {index_path.get_file():index, root_file:world}
	var sections: Dictionary = index.get("sections", {})
	for section_name: String in sections:
		var section_file := String(sections[section_name]); var section := _load_json_object(base_directory.path_join(section_file))
		if section.is_empty():
			return {}
		world[section_name] = section
		map_files[section_file] = section
	var nested_sections: Dictionary = index.get("nested_sections", {})
	for parent_name: String in nested_sections:
		if not world.get(parent_name) is Dictionary:
			push_error("Map index references unknown parent map '%s'." % parent_name)
			return {}
		var parent: Dictionary = world[parent_name]
		var children: Dictionary = nested_sections[parent_name]
		for section_name: String in children:
			var section_file := String(children[section_name]); var section := _load_json_object(base_directory.path_join(section_file))
			if section.is_empty():
				return {}
			parent[section_name] = section
			map_files[section_file] = section
	var authored_maps:={}
	var authored_file_ids:={}
	for map_id in Dictionary(index.get("maps",{})):
		var authored_file:=String(index.maps[map_id]);var authored:Dictionary=map_files.get(authored_file,{})
		if authored.is_empty():authored=_load_json_object(base_directory.path_join(authored_file))
		if authored.is_empty():return {}
		authored_maps[String(map_id)]=authored
		map_files[authored_file] = authored
		authored_file_ids[authored_file]=String(map_id)
	world["authored_maps"]=authored_maps
	_expand_shared_layouts(authored_maps, map_files, authored_file_ids)
	world["_map_files"] = map_files
	world["_authored_file_ids"] = authored_file_ids
	_prepare_terrain_recursive(world,"world")
	return world


# Virtual filenames preserve the existing map-local NPC, script and save identities.
static func instance_file(filename: String, instance_id: String) -> String:
	return filename + "#" + instance_id if not instance_id.is_empty() else filename


static func _expand_shared_layouts(maps: Dictionary, files: Dictionary, file_ids: Dictionary) -> void:
	var slot := 0
	for filename: String in file_ids.keys():
		var template: Dictionary = files[filename]
		if not bool(template.get("shared_layout", false)): continue
		var instances: Variant = template.get("layout_instances", [])
		if not instances is Array:
			push_error("Shared layout instances must be an array: " + filename); continue
		var seen := {}
		for record: Variant in instances:
			if not record is Dictionary or not record.get("id") is String or String(record.id).is_empty() or String(record.id).contains("#"):
				push_error("Shared layout instance requires a nonempty ID without #: " + filename); continue
			var id: String = record.id
			if seen.has(id):
				push_error("Duplicate shared layout instance: " + filename + "#" + id); continue
			seen[id] = true
			var instance := template.duplicate(true)
			instance.erase("layout_instances")
			# Only behavior and placements vary; geometry always comes from the template.
			for field in ["npcs", "script_source", "script_interactions", "script_sprite_names", "script_paths", "map_script_header", "map_script_headers"]:
				if record.has(field): instance[field] = record[field].duplicate(true) if record[field] is Array or record[field] is Dictionary else record[field]
			var warps: Dictionary = instance.get("warp_metadata", {}).duplicate(true)
			if record.has("warp_destinations") and not record.warp_destinations is Dictionary:
				push_error("Invalid shared layout warp destinations: " + filename + "#" + id); continue
			for field: String in Dictionary(record.get("warp_destinations", {})):
				if warps.has(field) and record.warp_destinations[field] is Dictionary:
					for key in ["entrance_map", "entrance_map_warp_id", "entrance_instance_id"]:
						if record.warp_destinations[field].has(key): warps[field][key] = record.warp_destinations[field][key]
			instance["warp_metadata"] = warps
			var virtual_file := instance_file(filename, id)
			var runtime_id := String(file_ids[filename]) + "#" + id
			# Runtime currently builds maps together: reserve isolated world-space slots.
			slot += 1
			instance["origin"] = [10000.0 + slot * 1000.0, 0, 10000.0]
			instance["_npc_map_file"] = virtual_file
			var npcs := NpcMapData.new()
			if template.has("_npc_definitions"): npcs.definitions = template._npc_definitions
			instance["_resolved_npcs"] = npcs.resolve(instance, _npc_visuals)
			instance["_npc_issues"] = npcs.issues(instance, _npc_visuals)
			files[virtual_file] = instance
			file_ids[virtual_file] = runtime_id
			maps[runtime_id] = instance


static func _prepare_terrain_recursive(value: Dictionary,map_seed:String) -> void:
	if value.has("terrain_tiles") or value.has("water_blocks") or value.has("sand_blocks") or value.has("objects"):
		var prepared := TerrainTransitionResolver.prepare_map(value,map_seed)
		value["_terrain_grid"] = prepared["_terrain_grid"]
		value["_terrain_issues"] = prepared["_terrain_issues"]
		value["_terrain_transitions"] = prepared["_terrain_transitions"]
	for key: Variant in value.keys():
		if String(key).begins_with("_"): continue
		var child: Variant = value[key]
		if child is Dictionary:
			_prepare_terrain_recursive(child,map_seed+"/"+String(key))


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
	var map: Dictionary = json.data
	# Resolve once per load; cached map-file records are reused by load_world.
	if not path.ends_with("_NPC_Data.json"):
		if _npc_visuals == null: _npc_visuals = NpcVisualResolver.new(ProjectSettings.globalize_path("res://"))
		var npcs := NpcMapData.new()
		npcs.load_for_map(path)
		map["_npc_definitions"] = npcs.definitions
		map["_resolved_npcs"] = npcs.resolve(map, _npc_visuals)
		map["_npc_issues"] = npcs.issues(map, _npc_visuals)
		map["_npc_map_file"] = path.get_file()
		for issue: Dictionary in map._npc_issues: push_warning("%s %s: %s" % [path, issue.path, issue.message])
	return map


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


static func warp_field_for_id(map: Dictionary, warp_id: int) -> String:
	var metadata: Variant = map.get("warp_metadata", {})
	if not metadata is Dictionary:
		return ""
	for field: Variant in metadata:
		var record: Variant = metadata[field]
		if record is Dictionary and int(record.get("id", 0)) == warp_id:
			return String(field)
	return ""
