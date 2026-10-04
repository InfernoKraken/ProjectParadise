extends RefCounted

const Movement := preload("npc_movement.gd")

const FACINGS := ["down", "up", "left", "right"]
var definitions: Dictionary = {}
var load_error := ""

static func companion_path(map_path: String) -> String:
	return map_path.get_basename() + "_NPC_Data.json"

func load_for_map(map_path: String) -> void:
	definitions = {}
	load_error = ""
	var path := companion_path(map_path)
	if not FileAccess.file_exists(path): return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		load_error = "Could not read NPC companion: " + path
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		load_error = "Invalid NPC companion JSON: " + path
		return
	definitions = json.data

static func valid_id(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 1 and float(value) == floorf(float(value))

func next_id(placements: Array) -> int:
	var highest := 0
	for record: Variant in placements:
		if record is Dictionary and valid_id(record.get("id")): highest = maxi(highest, int(record.id))
	for key: Variant in definitions:
		if String(key).is_valid_int(): highest = maxi(highest, int(key))
	return highest + 1

func add_default(map: Dictionary) -> int:
	if not map.has("npcs"): map["npcs"] = []
	if not map.npcs is Array or not load_error.is_empty(): return -1
	var id := next_id(map.npcs)
	map.npcs.append({"id":id, "position":[0.0,0.0,0.0], "facing":"down"})
	definitions[str(id)] = {"type":"human", "sprite":"Young Man", "interaction_text":""}
	return id

func issues(map: Dictionary, visuals: RefCounted) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not load_error.is_empty(): result.append(_issue("$.npcs", load_error))
	var placements: Variant = map.get("npcs", [])
	if not placements is Array:
		result.append(_issue("$.npcs", "Expected an NPC placement array."))
		return result
	var seen := {}
	for i in placements.size():
		var path := "$.npcs[%d]" % i
		var record: Variant = placements[i]
		if not record is Dictionary:
			result.append(_issue(path, "Expected an NPC placement record.")); continue
		if not valid_id(record.get("id")):
			result.append(_issue(path, "NPC ID must be a positive integer.")); continue
		var id := int(record.id)
		if seen.has(id): result.append(_issue(path, "Duplicate map-local NPC ID %d." % id))
		seen[id] = true
		if record.size() != 3 or not record.has("position") or not record.has("facing"):
			result.append(_issue(path, "NPC placements may contain only id, position, facing."))
		var p: Variant = record.get("position")
		if not p is Array or p.size() != 3 or not p.all(func(v): return (v is int or v is float) and is_finite(float(v))):
			result.append(_issue(path, "NPC position must contain three finite numbers."))
		if record.get("facing") not in FACINGS: result.append(_issue(path, "Invalid NPC facing; expected down, up, left, right."))
		var definition: Variant = definitions.get(str(id))
		if not definition is Dictionary:
			result.append(_issue(path, "Missing NPC definition %d in companion file." % id)); continue
		if not definition.get("type") is String or not definition.get("sprite") is String or not visuals.available(String(definition.get("type", "")), String(definition.get("sprite", ""))):
			result.append(_issue(path, "Unavailable NPC type/sprite for ID %d." % id))
		if not definition.get("interaction_text") is String: result.append(_issue(path, "NPC interaction_text must be a string."))
		var traversal_error := Movement.traversal_error(definition)
		if not traversal_error.is_empty(): result.append(_issue(path, traversal_error))
		if definition.has("movement"):
			var movement_error := Movement.validation_error(definition.movement)
			if not movement_error.is_empty():result.append(_issue(path, movement_error))
	return result

func resolve(map: Dictionary, visuals: RefCounted) -> Array[Dictionary]:
	var errors := issues(map, visuals)
	var invalid := {}
	for issue in errors: invalid[String(issue.path)] = true
	var result: Array[Dictionary] = []
	if invalid.has("$.npcs"): return result
	var duplicates := {}
	for record: Variant in map.get("npcs", []):
		if record is Dictionary and valid_id(record.get("id")):
			var id := int(record.id)
			duplicates[id] = int(duplicates.get(id, 0)) + 1
	for i in map.get("npcs", []).size():
		if invalid.has("$.npcs[%d]" % i): continue
		var record: Dictionary = map.npcs[i]
		if int(duplicates[int(record.id)]) > 1: continue
		var resolved: Dictionary = record.duplicate(true)
		resolved.merge(definitions[str(int(record.id))].duplicate(true))
		result.append(resolved)
	return result

static func _issue(path: String, message: String) -> Dictionary:
	return {"severity":"error", "path":path, "message":message}
