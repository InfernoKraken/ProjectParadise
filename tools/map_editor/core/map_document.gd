class_name MapDocument
extends RefCounted

const MapSchemaRef := preload("res://core/map_schema.gd")

var path := ""
var source_text := ""
var data: Dictionary = {}
var original_data: Dictionary = {}
var number_tokens: Dictionary = {}
var parse_error := ""
var dirty := false
var kind := "unknown"

static func load_file(file_path: String) -> MapDocument:
	var doc := MapDocument.new()
	doc.path = file_path
	doc.kind = MapSchemaRef.kind_for_file(file_path)
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		doc.parse_error = "Could not open file: %s" % file_path
		return doc
	doc.source_text = file.get_as_text()
	doc._parse()
	return doc

static func from_text(text: String, file_path := "") -> MapDocument:
	var doc := MapDocument.new()
	doc.path = file_path
	doc.kind = MapSchemaRef.kind_for_file(file_path)
	doc.source_text = text
	doc._parse()
	return doc

func _parse() -> void:
	var json := JSON.new()
	var error := json.parse(source_text)
	if error != OK:
		parse_error = "Line %d: %s" % [json.get_error_line(), json.get_error_message()]
		return
	if not json.data is Dictionary:
		parse_error = "Map root must be a JSON object."
		return
	data = json.data
	original_data = data.duplicate(true)
	number_tokens = _scan_number_tokens(source_text)

func semantic_equivalent(other: MapDocument) -> bool:
	return parse_error.is_empty() and other.parse_error.is_empty() and _semantic_equal(data, other.data)

func set_value(json_path: String, value: Variant) -> bool:
	var parts := _path_parts(json_path)
	if parts.is_empty(): return false
	var target: Variant = data
	for i in parts.size() - 1:
		var part: Variant = parts[i]
		if part is int:
			if not target is Array or part < 0 or part >= target.size(): return false
			target = target[part]
		else:
			if not target is Dictionary or not target.has(part): return false
			target = target[part]
	var last: Variant = parts[-1]
	if last is int:
		if not target is Array or last < 0 or last >= target.size(): return false
		target[last] = value
	else:
		if not target is Dictionary: return false
		target[last] = value
	dirty = true
	return true

func deterministic_json() -> String:
	return _encode(data, "$", 0) + "\n"

func save_atomic(destination: String, issues: Array = []) -> Error:
	for issue in issues:
		if String(issue.get("severity", "")) == "error": return ERR_INVALID_DATA
	var text := deterministic_json()
	var check := MapDocument.from_text(text, destination)
	if not check.parse_error.is_empty() or not _semantic_equal(check.data, data): return ERR_INVALID_DATA
	var temp := destination + ".tmp"
	var backup := destination + ".bak"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	file.close()
	if FileAccess.file_exists(destination):
		if FileAccess.file_exists(backup): DirAccess.remove_absolute(backup)
		var copy_error := _copy_file(destination, backup)
		if copy_error != OK:
			DirAccess.remove_absolute(temp)
			return copy_error
	var rename_error := DirAccess.rename_absolute(temp, destination)
	if rename_error != OK:
		DirAccess.remove_absolute(temp)
		return rename_error
	path = destination
	source_text = text
	original_data = data.duplicate(true)
	number_tokens = check.number_tokens
	dirty = false
	return OK

func _copy_file(source: String, destination: String) -> Error:
	var input := FileAccess.open(source, FileAccess.READ)
	if input == null: return FileAccess.get_open_error()
	var output := FileAccess.open(destination, FileAccess.WRITE)
	if output == null: return FileAccess.get_open_error()
	output.store_buffer(input.get_buffer(input.get_length()))
	return OK

func _semantic_equal(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return is_equal_approx(float(a), float(b))
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not _semantic_equal(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in a.size():
			if not _semantic_equal(a[i], b[i]): return false
		return true
	return a == b

func _encode(value: Variant, json_path: String, depth: int) -> String:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort_custom(func(a, b): return String(a) < String(b))
		if keys.is_empty(): return "{}"
		var rows: Array[String] = []
		for key in keys:
			rows.append("\t".repeat(depth + 1) + JSON.stringify(String(key)) + ": " + _encode(value[key], json_path + "." + String(key), depth + 1))
		return "{\n" + ",\n".join(rows) + "\n" + "\t".repeat(depth) + "}"
	if value is Array:
		if value.is_empty(): return "[]"
		var rows: Array[String] = []
		for i in value.size(): rows.append("\t".repeat(depth + 1) + _encode(value[i], "%s[%d]" % [json_path, i], depth + 1))
		return "[\n" + ",\n".join(rows) + "\n" + "\t".repeat(depth) + "]"
	if value is float or value is int:
		if number_tokens.has(json_path) and _original_value(json_path) == value:
			return String(number_tokens[json_path])
		return str(value)
	return JSON.stringify(value)

func _original_value(json_path: String) -> Variant:
	var target: Variant = original_data
	for part in _path_parts(json_path):
		if part is int:
			if not target is Array or part >= target.size(): return null
			target = target[part]
		else:
			if not target is Dictionary or not target.has(part): return null
			target = target[part]
	return target

func _path_parts(json_path: String) -> Array:
	var result: Array = []
	var token := ""
	var i := 1 if json_path.begins_with("$") else 0
	while i < json_path.length():
		var c := json_path[i]
		if c == ".":
			if not token.is_empty(): result.append(token); token = ""
		elif c == "[":
			if not token.is_empty(): result.append(token); token = ""
			var end := json_path.find("]", i)
			result.append(int(json_path.substr(i + 1, end - i - 1)))
			i = end
		else: token += c
		i += 1
	if not token.is_empty(): result.append(token)
	return result

# Lightweight source scanner used only to associate untouched numeric lexemes
# with JSON paths. JSON itself remains the authority for syntax and values.
func _scan_number_tokens(text: String) -> Dictionary:
	var result := {}
	var state := {"i": 0}
	_scan_value(text, state, "$", result)
	return result

func _scan_value(text: String, state: Dictionary, json_path: String, out: Dictionary) -> void:
	_skip_ws(text, state)
	if state.i >= text.length(): return
	var c := text[state.i]
	if c == "{":
		state.i += 1; _skip_ws(text, state)
		while state.i < text.length() and text[state.i] != "}":
			var key := _scan_string(text, state); _skip_ws(text, state)
			if state.i < text.length() and text[state.i] == ":": state.i += 1
			_scan_value(text, state, json_path + "." + key, out); _skip_ws(text, state)
			if state.i < text.length() and text[state.i] == ",": state.i += 1; _skip_ws(text, state)
		if state.i < text.length(): state.i += 1
	elif c == "[":
		state.i += 1; _skip_ws(text, state); var index := 0
		while state.i < text.length() and text[state.i] != "]":
			_scan_value(text, state, "%s[%d]" % [json_path, index], out); index += 1; _skip_ws(text, state)
			if state.i < text.length() and text[state.i] == ",": state.i += 1; _skip_ws(text, state)
		if state.i < text.length(): state.i += 1
	elif c == "\"": _scan_string(text, state)
	elif c == "-" or c.is_valid_int():
		var start: int = state.i
		while state.i < text.length() and text[state.i] in ["-", "+", ".", "e", "E", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]: state.i += 1
		out[json_path] = text.substr(start, state.i - start)
	else:
		while state.i < text.length() and not text[state.i] in [",", "]", "}", " ", "\n", "\r", "\t"]: state.i += 1

func _scan_string(text: String, state: Dictionary) -> String:
	if state.i >= text.length() or text[state.i] != "\"": return ""
	var start: int = state.i; state.i += 1; var escaped := false
	while state.i < text.length():
		var c := text[state.i]; state.i += 1
		if escaped: escaped = false
		elif c == "\\": escaped = true
		elif c == "\"": break
	var raw := text.substr(start, state.i - start)
	var parsed: Variant = JSON.parse_string(raw)
	return String(parsed) if parsed != null else ""

func _skip_ws(text: String, state: Dictionary) -> void:
	while state.i < text.length() and text[state.i] in [" ", "\n", "\r", "\t"]: state.i += 1
