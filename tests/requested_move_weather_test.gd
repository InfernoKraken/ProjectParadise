extends SceneTree


func _initialize() -> void:
	var scene := load("res://battle/battle.tscn") as PackedScene
	assert(scene != null, "Battle scene must load.")
	var battle := scene.instantiate()
	root.add_child(battle)
	await process_frame

	var template := {
		"name": "Test Fakemon", "type": "Normal", "gender": "Genderless", "level": 20,
		"max_hp": 100, "attack": 80, "defense": 80, "special_attack": 80,
		"special_defense": 80, "speed": 80, "moves": ["body_slam"]
	}
	var attacker: Dictionary = template.duplicate(true)
	var defender: Dictionary = template.duplicate(true)
	battle._ensure_condition_fields(attacker)
	battle._ensure_condition_fields(defender)
	var body_slam: Dictionary = battle.battle_data["moves"]["body_slam"]
	for example: Dictionary in [
		{"size": "2.5 m", "power": 125},
		{"size": "500 m", "power": 150},
		{"size": "0.5 m", "power": 25}
	]:
		attacker["size"] = example["size"]
		assert(int(battle._calculate_damage(attacker, defender, body_slam)["power"]) == int(example["power"]), "Body Slam size power must match the requested equation.")
	battle.player = attacker
	battle.player_hp = 50
	battle.party_hp.resize(1)
	battle.party_hp[battle.active_party_index] = 50
	battle._apply_max_hp_recoil(attacker, true, float(body_slam["recoil_max_hp_fraction"]))
	assert(battle.player_hp == 35, "Body Slam must recoil for 15% of maximum HP, not current HP.")

	var hydraulic_user: Dictionary = template.duplicate(true)
	var hydraulic_target: Dictionary = template.duplicate(true)
	battle._ensure_condition_fields(hydraulic_user)
	battle._ensure_condition_fields(hydraulic_target)
	battle._apply_after_damage_effects(hydraulic_user, hydraulic_target, battle.battle_data["moves"]["hydraulic_crash"], false, 1)
	assert(float(hydraulic_user["stat_modifiers"]["defense"]) < 1.0, "Hydraulic Crash must lower the user's Defense.")
	assert(is_equal_approx(float(hydraulic_target["stat_modifiers"]["defense"]), 1.0), "Hydraulic Crash must not lower the target's Defense.")

	var steel_mon: Dictionary = template.duplicate(true)
	steel_mon["type"] = "Steel"
	battle._ensure_condition_fields(steel_mon)
	battle.player = steel_mon
	battle.player_hp = int(steel_mon["max_hp"])
	battle._set_weather("Monsoon")
	assert(battle.weather_turns_remaining == 3, "Monsoon must last three turns.")
	assert(String(steel_mon["condition"]) == "Rusting", "Monsoon must inflict Rusting on Steel Fakemon present.")
	assert(battle.battle_data["weather"]["Monsoon"]["damage_multipliers"] == {"Fire": 0.5, "Plant": 1.5, "Water": 1.5}, "Monsoon multipliers must match the design.")
	assert(battle.battle_data["conditions"]["Rusting"]["end_turn_hp_fraction"] == battle.battle_data["conditions"]["Poisoned"]["end_turn_hp_fraction"], "Rusting must deal the same maximum-HP damage as Poisoned.")

	print("REQUESTED_MOVE_WEATHER_TEST_PASSED")
	quit()
