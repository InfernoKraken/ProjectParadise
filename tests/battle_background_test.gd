extends SceneTree

func _initialize() -> void:
	var scene := load("res://battle/battle.tscn") as PackedScene
	assert(scene != null, "Battle scene must load.")
	var battle := scene.instantiate()
	root.add_child(battle)
	await process_frame
	var background := battle.battle_screen.get_node("BattleBackgroundArt") as TextureRect
	assert(battle.set_battle_background("Rainforest") == battle.DEFAULT_BATTLE_BACKGROUND_PATH)
	assert(background.texture.resource_path.ends_with("battle_background.png"), "Rainforest must use the default rainforest background.")
	assert(battle.set_battle_background("Lush_Cave").ends_with("battle_background_cave.png"))
	assert(background.texture.resource_path.ends_with("battle_background_cave.png"), "Lush caves must use cave art.")
	assert(battle.set_battle_background("City").ends_with("battle_background_city.png"))
	assert(background.texture.resource_path.ends_with("battle_background_city.png"), "Cities must use city art.")
	assert(battle.set_battle_background("Indoor") == battle.DEFAULT_BATTLE_BACKGROUND_PATH)
	assert(background.texture.resource_path.ends_with("battle_background.png"), "A missing indoor asset must gracefully fall back.")
	assert(battle.set_battle_background("Future_Map_Type") == battle.DEFAULT_BATTLE_BACKGROUND_PATH, "Unknown map types must gracefully fall back.")
	assert(battle.set_battle_background("Indoor", true).ends_with("battle_background_swimming.png"))
	assert(background.texture.resource_path.ends_with("battle_background_swimming.png"), "Swimming must override the map-type background.")
	print("BATTLE_BACKGROUND_TEST_PASSED")
	battle.queue_free()
	await process_frame
	quit()
