extends RefCounted

const Parser = preload("script_parser.gd")
const Registry = preload("command_registry.gd")
const ALLOWED = ["ShowSprite", "HideSprite", "FaceSprite", "SetFlag", "ClearFlag", "Call", "IfFlag", "IfNotFlag", "Return", "End"]

static func entries(map: Dictionary) -> Array:
	var result: Array = []
	if map.has("map_script_header"): result.append(map.map_script_header)
	if map.get("map_script_headers") is Array: result.append_array(map.map_script_headers)
	return result

static func inspect(map: Dictionary, references: Dictionary = {}) -> Dictionary:
	var out := {"valid":true, "diagnostics":[], "headers":entries(map), "header":{}}
	if map.has("map_script_headers") and not map.map_script_headers is Array: issue(out, "Map Scripts must be an array.")
	for index in out.headers.size():
		var inspected := _inspect_one({"map_script_header":out.headers[index], "script_source":map.get("script_source", "")}, references)
		if index == 0: out.header = inspected.header
		if not inspected.valid: out.valid = false
		for diagnostic: Dictionary in inspected.diagnostics:
			diagnostic.message = "Map Script %d: " % (index + 1) + diagnostic.message
			out.diagnostics.append(diagnostic)
	return out

static func _inspect_one(map: Dictionary, references: Dictionary = {}) -> Dictionary:
	var out := {"valid":true, "diagnostics":[], "header":{}}
	if not map.has("map_script_header"): return out
	var header: Variant = map.map_script_header
	if not header is Dictionary:
		issue(out, "Expected flag, true_block and false_block fields."); return out
	out.header = header
	for field in ["flag", "true_block", "false_block"]:
		if not header.get(field) is String or not Registry.identifier(str(header.get(field, ""))):
			issue(out, ("Flag must be a nonempty identifier." if field == "flag" else "The %s field needs a Block name, not a command. Put commands such as '%s' in its multiline commands editor." % [field, str(header.get(field, ""))]))
	if not out.valid: return out
	var parsed := Parser.parse(str(map.get("script_source", "")), references)
	for diagnostic: Dictionary in parsed.diagnostics:
		if diagnostic.severity == "error": issue(out, "Source line %d: %s" % [diagnostic.line, diagnostic.message])
	var pending: Array = [{"block":header.true_block, "trail":[]}, {"block":header.false_block, "trail":[]}]
	var visited := {}
	while not pending.is_empty():
		var item: Dictionary = pending.pop_back()
		var block: String = item.block
		if block in item.trail: issue(out, "Recursive header Block: " + block); continue
		if visited.has(block): continue
		visited[block] = true
		if not parsed.blocks.has(block): issue(out, "Header target Block does not exist: " + block); continue
		var trail: Array = item.trail.duplicate(); trail.append(block)
		for instruction: Dictionary in parsed.blocks[block]:
			if not instruction.command in ALLOWED: issue(out, "Header Block %s cannot execute %s (immediate commands only)." % [block, instruction.command])
			var types: Array = Registry.DEFINITIONS[instruction.command]
			for index in instruction.arguments.size():
				if types[index] == "block": pending.append({"block":str(instruction.arguments[index]), "trail":trail})
	return out

static func issue(out: Dictionary, message: String) -> void:
	out.valid = false
	out.diagnostics.append({"severity":"error", "path":"$.map_script_header", "line":0, "message":message})
