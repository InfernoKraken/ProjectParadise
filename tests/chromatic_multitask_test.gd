extends SceneTree


func _initialize() -> void:
	var scene := load("res://battle/battle.tscn") as PackedScene
	assert(scene != null, "Battle scene must load.")
	var battle := scene.instantiate()
	root.add_child(battle)
	await process_frame
	var mon := {
		"name": "Test Fakemon", "type": "Psychic", "gender": "Genderless", "level": 20,
		"max_hp": 100, "attack": 50, "defense": 50, "special_attack": 50,
		"special_defense": 50, "speed": 50, "moves": ["chromatic_thought", "multitask"]
	}
	battle._ensure_condition_fields(mon)
	battle.player = mon
	battle.player_hp = 50
	battle.party_hp.resize(1)
	battle.party_hp[0] = 50
	var chromatic: Dictionary = battle.battle_data["moves"]["chromatic_thought"]
	var expected := {
		"Harsh Sunlight": {"attack": 1.2, "special_attack": 1.2},
		"Monsoon": {"speed": 1.2, "hp": 70},
		"Rootmind": {"special_attack": 1.2, "special_defense": 1.2},
		"Blood Moon": {"special_attack": 1.2, "speed": 1.2},
		"Fey Gardens": {"special_defense": 1.2, "hp": 70},
		"Celestial Chorus": {"defense": 1.2, "special_defense": 1.2},
		"Unknown Weather": {"attack": 1.2, "speed": 1.2}
	}
	for weather_name: String in expected:
		_reset_user(battle, mon)
		battle.weather = weather_name
		battle._apply_weather_stat_effect(mon, chromatic, true)
		for key: String in expected[weather_name]:
			if key == "hp":
				assert(battle.player_hp == int(expected[weather_name][key]), "%s Chromatic Thought healing is incorrect." % weather_name)
			else:
				assert(is_equal_approx(float(mon["stat_modifiers"][key]), float(expected[weather_name][key])), "%s Chromatic Thought stat effect is incorrect." % weather_name)
	_reset_user(battle, mon)
	battle.weather = ""
	battle._apply_weather_stat_effect(mon, chromatic, true)
	assert(battle.player_hp == 55, "Clear-weather Chromatic Thought must heal 5% maximum HP.")
	for stat: String in battle.COMBAT_STATS:
		assert(is_equal_approx(float(mon["stat_modifiers"][stat]), 1.1), "Clear-weather Chromatic Thought must raise every stat one stage.")

	_reset_user(battle, mon)
	seed(12345)
	var selected: Array[String] = battle._apply_random_stat_or_hp_boosts(mon, battle.battle_data["moves"]["multitask"]["random_stat_or_hp_boosts"], true)
	assert(selected.size() == 3 and selected.duplicate().all(func(choice): return selected.count(choice) == 1), "Multitask must select three different random stats.")
	var applied := 1 if selected.has("hp") and battle.player_hp == 60 else 0
	for stat: String in battle.COMBAT_STATS:
		if selected.has(stat) and is_equal_approx(float(mon["stat_modifiers"][stat]), 1.1):
			applied += 1
	assert(applied == 3, "Multitask must apply all three selected boosts, treating 10% maximum-HP healing as HP.")
	print("CHROMATIC_MULTITASK_TEST_PASSED")
	quit()


func _reset_user(battle: Node, mon: Dictionary) -> void:
	for stat: String in battle.COMBAT_STATS:
		mon["stat_modifiers"][stat] = 1.0
	battle.player_hp = 50
	battle.party_hp[0] = 50
