extends SceneTree


func _initialize() -> void:
	var scene := load("res://world/main.tscn") as PackedScene
	assert(scene != null, "Main scene must load.")
	var main := scene.instantiate()
	root.add_child(main)
	await process_frame
	assert(main.player != null, "Player placeholder must be created.")
	assert(main.opponent != null, "Trainer placeholder must be created.")
	assert(main.world.visible == false, "Fakemon selection must appear before the map.")
	assert(main.battle.visible == true, "Selection overlay must be visible at startup.")
	print("WORLD_SMOKE_TEST_PASSED")
	quit()
