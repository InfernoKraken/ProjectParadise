class_name GeneratedAnchorRepository
extends RefCounted

const DATA_PATH := "res://data/generated_battle_anchors.json"

var _sprites: Dictionary = {}
var warning_handler: Callable


func _init(path := DATA_PATH) -> void:
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		_sprites = parsed.get("sprites", {})


func get_battle_anchor(art_id: String, side: String, anchor_name: String) -> Vector2:
	var sprite: Dictionary = _sprites.get("%s_%s" % [art_id, side], {})
	var anchors: Dictionary = sprite.get("anchors", {})
	var value: Array = anchors.get(anchor_name, [])
	if value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	value = anchors.get("origin", [])
	if value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	_warn("Battle sprite '%s_%s' has no origin anchor; using processed sprite center for requested anchor '%s'." % [art_id, side, anchor_name])
	var processed_size: Array = sprite.get("processed_size", [0, 0])
	if processed_size.size() >= 2:
		return Vector2(float(processed_size[0]), float(processed_size[1])) * 0.5
	return Vector2.ZERO


func _warn(message: String) -> void:
	if warning_handler.is_valid():
		warning_handler.call(message)
	else:
		push_warning(message)


func get_anchor_names(art_id: String, side: String) -> PackedStringArray:
	var sprite: Dictionary = _sprites.get("%s_%s" % [art_id, side], {})
	var anchors: Dictionary = sprite.get("anchors", {})
	var names := PackedStringArray()
	for anchor_name: Variant in anchors.keys():
		names.append(String(anchor_name))
	names.sort()
	return names


func has_battle_sprite(art_id: String, side: String) -> bool:
	return _sprites.has("%s_%s" % [art_id, side])


func has_battle_anchor(art_id: String, side: String, anchor_name: String) -> bool:
	var sprite: Dictionary = _sprites.get("%s_%s" % [art_id, side], {})
	var anchors: Dictionary = sprite.get("anchors", {})
	return anchors.has(anchor_name)
