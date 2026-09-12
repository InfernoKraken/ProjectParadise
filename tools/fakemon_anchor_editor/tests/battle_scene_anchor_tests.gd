extends SceneTree

const Repository := preload("res://battle/battle_scene_anchor_repository.gd")
const SceneEditor := preload("res://tools/fakemon_anchor_editor/battle_scene_editor.gd")

var failures: Array[String] = []


func _init() -> void:
	var repository := Repository.new()
	_check(not repository.scene.is_empty(), "Default battle scene did not load.")
	_check(repository.scene.background == "res://assets/battle/battle_background.png", "Example scene does not use the project battle background.")
	_check(repository.resolve("SCREEN_CENTER", Vector2(1200, 700)) == Vector2(600, 350), "Viewport center is not resolution-derived.")
	_check(repository.resolve("SCREEN_RIGHT", Vector2(1200, 700), Vector2(40, 20)) == Vector2(1140, 340), "Viewport right anchor is incorrect.")
	_check(repository.resolve("BACKGROUND_CENTER", Vector2(960, 540), Vector2(20, 10)) == Vector2(470, 125), "Background point no longer matches legacy behavior.")
	_check(repository.resolve("FIELD_CENTER", Vector2(960, 540), Vector2(20, 10)) == Vector2(470, 240), "Field center no longer matches legacy behavior.")
	_check(repository.resolve("ALLY_FIELD", Vector2(960, 540), Vector2(20, 10)) == Vector2(235, 305), "Ally point no longer matches legacy behavior.")
	_check(repository.resolve("ENEMY_FIELD", Vector2(960, 540), Vector2(20, 10)) == Vector2(660, 200), "Enemy point no longer matches legacy behavior.")
	var screen_region := repository.region_rect("RANDOM_SCREEN")
	var ground_region := repository.region_rect("RANDOM_GROUND")
	_check(screen_region == Rect2(10, 15, 940, 335), "Random screen is not represented by the expected region.")
	_check(ground_region == Rect2(90, 220, 780, 165), "Random ground is not represented by the expected region.")
	for index in 50:
		var point := repository.resolve("RANDOM_GROUND", Vector2(960, 540), Vector2(30, 20))
		_check(point.x >= ground_region.position.x and point.y >= ground_region.position.y and point.x <= ground_region.end.x - 30 and point.y <= ground_region.end.y - 20, "Random ground spawn escaped its authored region.")
	_check(SceneEditor._validate(repository.scene).is_empty(), "Default scene schema did not validate.")
	var invalid := repository.scene.duplicate(true)
	invalid.regions.RANDOM_GROUND.width = 0
	_check(not SceneEditor._validate(invalid).is_empty(), "Invalid zero-width region was accepted.")
	if failures.is_empty():
		print("Battle Scene Anchors: 13 tests passed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
