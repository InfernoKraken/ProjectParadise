extends RefCounted

const Registry = preload("command_registry.gd")

# Optional map root fields; path nodes are ordered map-local [X, Z] pairs.
static func inspect(map: Dictionary) -> Dictionary:
	var result := {"paths":{}, "diagnostics":[], "move_path":[], "follow_path":[]}
	var raw: Variant = map.get("script_paths", [])
	var aliases: Variant = map.get("script_sprite_names", {})
	if not aliases is Dictionary: issue(result, "script_sprite_names", "Expected an alias table.")
	else:
		var refs := actor_references(map)
		for name: Variant in aliases:
			if not name is String or not name in refs.sprite or name in ["Player", "North", "South", "East", "West"] or String(name).begins_with("NPC") and String(name).trim_prefix("NPC").is_valid_int(): issue(result, str(name), "Invalid/reserved alias or missing NPC ID.")
	if not raw is Array:
		issue(result, "script_paths", "Expected an array."); return result
	var seen := {}
	for value: Variant in raw:
		if not value is Dictionary: issue(result, "script_paths", "Expected a path record."); continue
		var name: Variant = value.get("name")
		if not name is String or not Registry.identifier(name): issue(result, str(name), "Invalid path name."); continue
		if seen.has(name): issue(result, name, "Duplicate path name."); result.paths.erase(name); continue
		seen[name] = true
		if value.get("type") not in ["MOVE", "FOLLOW"]: issue(result, name, "Expected MOVE or FOLLOW type."); continue
		var nodes: Variant = value.get("nodes")
		var minimum := 2 if value.type == "FOLLOW" else 1
		if not nodes is Array or nodes.size() < minimum: issue(result, name, "Requires at least %d node(s)." % minimum); continue
		var valid := true
		for node: Variant in nodes:
			if not node is Array or node.size() != 2 or not node.all(func(n):return (n is int or n is float) and is_finite(float(n)) and absf(float(n)) <= 1000000.0): valid = false
		if not valid: issue(result, name, "Nodes must be finite [X, Z] pairs within ±1000000."); continue
		if value.type == "FOLLOW" and not nodes.any(func(node):return node != nodes[0]): issue(result, name, "FOLLOW requires distinct route nodes."); continue
		result.paths[name] = value
	for name: String in result.paths:
		result["move_path" if result.paths[name].type == "MOVE" else "follow_path"].append(name)
	return result

static func issue(result: Dictionary, name: String, message: String) -> void:
	result.diagnostics.append({"severity":"error", "line":0, "token":name, "message":name + ": " + message})

static func actor_id(map: Dictionary, token: String) -> int:
	var aliases: Variant = map.get("script_sprite_names", {})
	if aliases is Dictionary and aliases.has(token):
		var value: Variant = aliases[token]
		if (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)): return int(value)
	var number := token.trim_prefix("NPC")
	return int(number) if number.is_valid_int() else -1

static func actor_references(map: Dictionary) -> Dictionary:
	var sprites: Array[String] = []
	var placements: Variant = map.get("npcs", [])
	if not placements is Array: placements = []
	for record: Variant in placements:
		if record is Dictionary and record.has("id"):
			sprites.append(str(int(record.id))); sprites.append("NPC" + str(int(record.id)))
	var aliases: Variant = map.get("script_sprite_names", {})
	if aliases is Dictionary:
		for name: Variant in aliases:
			if name is String and Registry.identifier(name) and str(actor_id(map, name)) in sprites and not name in ["Player", "North", "South", "East", "West"] and not (String(name).begins_with("NPC") and String(name).trim_prefix("NPC").is_valid_int()): sprites.append(name)
	return {"sprite":sprites, "actor":["Player"] + sprites, "target":["Player"] + sprites, "facing":["North", "South", "East", "West", "Player"] + sprites}

# An assigned interaction owns actors it moves, including commands in called Blocks.
static func movement_actors(map: Dictionary) -> Dictionary:
	var owned := {}
	var table: Variant = map.get("script_interactions", {})
	var source: Variant = map.get("script_source", "")
	if not table is Dictionary or not source is String: return owned
	var parsed: Dictionary = preload("script_parser.gd").parse(source)
	var pending: Array = table.values().duplicate()
	var visited := {}
	while not pending.is_empty():
		var block := str(pending.pop_back())
		if visited.has(block): continue
		visited[block] = true
		for instruction: Dictionary in parsed.blocks.get(block, []):
			if instruction.command in ["MoveSprite", "FollowSprite"]:
				var id := actor_id(map, str(instruction.arguments[0]))
				if id >= 0: owned[id] = true
			var types: Array = Registry.DEFINITIONS[instruction.command]
			for index in instruction.arguments.size():
				if types[index] == "block": pending.append(instruction.arguments[index])
	return owned
