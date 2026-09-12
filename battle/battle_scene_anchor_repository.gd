class_name BattleSceneAnchorRepository
extends RefCounted

const DATA_PATH := "res://data/battle_scenes.json"
const VIEWPORT_ANCHORS := ["SCREEN_TOP", "SCREEN_BOTTOM", "SCREEN_LEFT", "SCREEN_RIGHT", "SCREEN_CENTER"]
const POINT_ANCHORS := ["BACKGROUND_CENTER", "FIELD_CENTER", "ALLY_FIELD", "ENEMY_FIELD"]
const REGION_ANCHORS := ["RANDOM_SCREEN", "RANDOM_GROUND"]

var scene: Dictionary = {}


func _init(scene_id := "", path := DATA_PATH) -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not parsed is Dictionary:
		return
	var selected_id := scene_id if not scene_id.is_empty() else String(parsed.get("default_scene", ""))
	scene = parsed.get("scenes", {}).get(selected_id, {})


func resolve(anchor_name: String, viewport_size: Vector2, item_size := Vector2.ZERO) -> Vector2:
	match anchor_name:
		"SCREEN_TOP": return Vector2((viewport_size.x - item_size.x) * 0.5, 20)
		"SCREEN_BOTTOM": return Vector2((viewport_size.x - item_size.x) * 0.5, viewport_size.y - item_size.y - 20)
		"SCREEN_LEFT": return Vector2(20, (viewport_size.y - item_size.y) * 0.5)
		"SCREEN_RIGHT": return Vector2(viewport_size.x - item_size.x - 20, (viewport_size.y - item_size.y) * 0.5)
		"SCREEN_CENTER": return (viewport_size - item_size) * 0.5
	var reference_size := _reference_size()
	var scale := Vector2(viewport_size.x / reference_size.x, viewport_size.y / reference_size.y)
	if REGION_ANCHORS.has(anchor_name):
		var region := region_rect(anchor_name)
		var position := Vector2(
			randf_range(region.position.x, maxf(region.position.x, region.end.x - item_size.x / scale.x)),
			randf_range(region.position.y, maxf(region.position.y, region.end.y - item_size.y / scale.y))
		)
		return position * scale
	var values: Array = scene.get("anchors", {}).get(anchor_name, [])
	if values.size() < 2:
		return (viewport_size - item_size) * 0.5
	var point := Vector2(float(values[0]), float(values[1])) * scale
	if anchor_name == "ALLY_FIELD" or anchor_name == "ENEMY_FIELD":
		return point - Vector2(item_size.x * 0.5, item_size.y)
	return point - item_size * 0.5


func point(anchor_name: String) -> Vector2:
	var values: Array = scene.get("anchors", {}).get(anchor_name, [])
	return Vector2(float(values[0]), float(values[1])) if values.size() >= 2 else Vector2.ZERO


func region_rect(anchor_name: String) -> Rect2:
	var value: Dictionary = scene.get("regions", {}).get(anchor_name, {})
	return Rect2(float(value.get("x", 0)), float(value.get("y", 0)), float(value.get("width", 0)), float(value.get("height", 0)))


func _reference_size() -> Vector2:
	var values: Array = scene.get("reference_size", [960, 540])
	return Vector2(float(values[0]), float(values[1]))
