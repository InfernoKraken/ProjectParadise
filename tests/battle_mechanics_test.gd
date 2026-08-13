extends SceneTree


func _initialize() -> void:
	var scene := load("res://battle/battle.tscn") as PackedScene
	assert(scene != null, "Battle scene must load.")
	var battle := scene.instantiate()
	root.add_child(battle)
	await process_frame
	print("BATTLE_TEST_READY")

	var test_mon := {
		"name": "Test Fakemon", "type": "Light", "gender": "Genderless", "level": 5,
		"max_hp": 40, "attack": 10, "defense": 10, "special_attack": 10,
		"special_defense": 10, "speed": 10, "moves": ["discern"]
	}
	battle._ensure_condition_fields(test_mon)
	for use in 4:
		battle._apply_stat_changes(test_mon, [{"stat": "special_defense", "amount": 0.3}])
	assert(is_equal_approx(test_mon["stat_modifiers"]["special_defense"], 1.9), "Positive stat modifiers must cap at +90%.")
	assert(battle.message_label.text.contains("Test Fakemon's Special Defense cannot go up any further!"), "Capped stats must report the global cap message.")

	test_mon["stat_modifiers"]["special_attack"] = 1.85
	test_mon["stat_modifiers"]["special_defense"] = 1.9
	battle._apply_stat_changes(test_mon, battle.battle_data["moves"]["flutter"]["stat_changes"])
	assert(is_equal_approx(test_mon["stat_modifiers"]["special_attack"], 1.9), "A below-cap stat in a multi-stat move must clamp independently.")
	assert(is_equal_approx(test_mon["stat_modifiers"]["special_defense"], 1.9), "A capped stat in a multi-stat move must remain capped.")
	battle.message_label.text = "Old turn. " + "Recent turn. ".repeat(80)
	battle._cap_battle_log()
	assert(battle.message_label.text.length() <= battle.MAX_BATTLE_LOG_CHARACTERS + 2 and battle.message_label.text.begins_with("… "), "Battle messages must retain a capped recent log.")
	assert(battle.message_panel.position.y + battle.message_panel.size.y == 540.0 and battle.message_label.clip_text, "The battle message panel must reach the bottom of the viewport and clip overflow safely.")

	battle._set_weather("Celestial Chorus")
	assert(battle.weather_turns_remaining == 3, "Weather must begin with three turns.")
	battle._advance_weather()
	battle._advance_weather()
	assert(battle.weather == "Celestial Chorus", "Weather must persist through its first two turns.")
	battle._advance_weather()
	assert(battle.weather.is_empty(), "Weather must fade after three turns.")

	assert(battle.battle_data["moves"]["brilliant_light"]["ignore_resistance"], "Brilliant Light must ignore resistances.")
	assert(battle.battle_data["moves"]["remembrance"]["calls_another_move"], "Remembrance must use the reusable move-caller flag.")
	assert(battle._get_type_effectiveness("Light", "Psychic") == 2.0, "Psychic must be weak to Light.")
	assert(battle._get_type_effectiveness("Dark", "Psychic") == 2.0, "Psychic must be weak to Dark.")
	assert(battle._get_type_effectiveness("Ghost", "Psychic") == 2.0, "Psychic must be weak to Ghost.")
	assert(battle._get_type_effectiveness("Psychic", "Light") == 0.5 and battle._get_type_effectiveness("Psychic", "Dark") == 0.5 and battle._get_type_effectiveness("Psychic", "Ghost") == 0.5, "Light, Dark, and Ghost must resist Psychic.")
	assert(battle._get_type_effectiveness("Psychic", "Normal") == 2.0 and battle._get_type_effectiveness("Normal", "Psychic") == 0.5, "Psychic must be strong against and resist Normal.")
	assert(battle._get_type_effectiveness("Fighting", "Normal") == 2.0 and battle._get_type_effectiveness("Fighting", "Bug") == 2.0, "Fighting must be strong against Normal and Bug.")
	assert(battle._get_type_effectiveness("Fighting", "Ghost") == 0.5 and battle._get_type_effectiveness("Fighting", "Air") == 0.5 and battle._get_type_effectiveness("Fighting", "Psychic") == 0.5, "Ghost, Air, and Psychic must resist Fighting.")
	assert(battle._get_type_effectiveness("Air", "Fighting") == 2.0 and battle._get_type_effectiveness("Psychic", "Fighting") == 2.0 and battle._get_type_effectiveness("Ghost", "Fighting") == 1.0, "Fighting must be weak to Air and Psychic but neutral to Ghost.")
	assert(battle._get_type_effectiveness("Psychic", "Poison") == 2.0 and battle._get_type_effectiveness("Poison", "Psychic") == 0.5, "Poison must be weak to Psychic, while Psychic resists Poison.")
	assert(battle._get_type_effectiveness("Poison", "Normal") == 2.0 and battle._get_type_effectiveness("Poison", "Water") == 2.0 and battle._get_type_effectiveness("Poison", "Plant") == 2.0, "Poison must be strong against Normal, Water, and Plant.")
	for move_id: String in ["peck", "flutter", "photon_beam", "flip_turn", "aqua_jet", "dazzle", "brilliant_light", "veil", "disable", "scald", "smite", "aureal_flood", "remembrance", "celestial_chorus", "prayer", "discern", "fin_flash"]:
		assert(battle.battle_data["moves"].has(move_id), "Requested move '%s' must be defined." % move_id)
	var sylvafin: Dictionary = battle.battle_data["fakemon"][1]
	var scorchick: Dictionary = battle.battle_data["fakemon"][0]
	assert(float(scorchick["male_ratio"]) == 0.5 and not scorchick.has("gender"), "Gendered species data must store a male ratio instead of a fixed gender.")
	assert(battle.create_fakemon({"male_ratio": 1.0})["gender"] == "Male", "A male ratio of 1 must always produce a male Fakemon.")
	assert(battle.create_fakemon({"male_ratio": 0.0})["gender"] == "Female", "A male ratio of 0 must always produce a female Fakemon.")
	assert(battle.create_fakemon({"male_ratio": null})["gender"] == "Genderless", "A null male ratio must produce a Genderless Fakemon.")
	assert(scorchick["moves"] == ["squawk", "ignite", "peck", "mimic"], "Level 5 Scorchick must know its four currently accessible moves.")
	assert(scorchick["learnset"].size() == 21, "Scorchick's complete level-gated learnset must be recorded.")
	assert(String(scorchick["learnset"][4]["move"]) == "scratch" and int(scorchick["learnset"][4]["level"]) == 7 and String(scorchick["learnset"][20]["move"]) == "inferno" and int(scorchick["learnset"][20]["level"]) == 60, "Scorchick's learnset levels must remain ordered and data-driven.")
	assert(sylvafin["moves"] == ["peck", "soak", "flutter", "photon_beam"], "Level 5 Sylvafin must know its four currently accessible moves.")
	assert(sylvafin["learnset"].size() == 19, "Sylvafin's complete level-gated learnset must be recorded.")
	assert(String(sylvafin["learnset"][4]["move"]) == "flip_turn" and int(sylvafin["learnset"][4]["level"]) == 7 and String(sylvafin["learnset"][18]["move"]) == "celestial_chorus" and int(sylvafin["learnset"][18]["level"]) == 55, "Sylvafin's learnset levels must remain ordered and data-driven.")
	var flip_turn: Dictionary = battle.battle_data["moves"]["flip_turn"]
	assert(flip_turn["power"] == 40 and flip_turn["type"] == "Water" and flip_turn["damage_class"] == "Physical", "Flip Turn must deal 40-power Physical Water damage.")
	assert(flip_turn["random_party_switch"] and flip_turn["passes_stat_modifiers"], "Flip Turn must randomly switch and transfer stat modifiers.")
	var partner := test_mon.duplicate(true)
	partner["name"] = "Switch Partner"
	battle._ensure_condition_fields(partner)
	battle.battle_party.clear()
	battle.battle_party.append(test_mon)
	battle.battle_party.append(partner)
	battle.party_hp.clear()
	battle.party_hp.append(40)
	battle.party_hp.append(40)
	battle.active_party_index = 0
	battle.player = test_mon
	battle.player_hp = 40
	battle.opponent = partner.duplicate(true)
	battle.opponent_hp = 40
	test_mon["stat_modifiers"]["special_defense"] = 1.6
	battle._random_switch_player(true)
	assert(battle.player == partner and battle.active_party_index == 1, "Flip Turn must switch to another conscious party member.")
	assert(is_equal_approx(partner["stat_modifiers"]["special_defense"], 1.6), "Flip Turn must pass stat modifiers to the incoming party member.")
	assert(is_equal_approx(test_mon["stat_modifiers"]["special_defense"], 1.0), "The outgoing party member's passed modifiers must reset to neutral.")
	assert(battle._available_random_switch_indices() == [0], "Only conscious non-active party members may be random switch targets.")
	var dual_type_mon := {"types": ["Air", "Bug"]}
	assert(battle._fakemon_types(dual_type_mon) == ["Air", "Bug"], "Dual typings must preserve both unique types.")
	assert(battle._get_combined_type_effectiveness("Fire", dual_type_mon) == 4.0, "Two defensive weaknesses must combine to 4x damage.")
	assert(battle._get_combined_type_effectiveness("Bug", dual_type_mon) == 0.5, "A dual type must multiply each defensive matchup.")
	var mixed_matchup_mon := {"types": ["Psychic", "Bug"]}
	assert(battle._get_combined_type_effectiveness("Light", mixed_matchup_mon) == 1.0, "A weakness and resistance must combine to neutral damage.")
	assert(battle._get_combined_type_effectiveness("Light", mixed_matchup_mon, true) == 2.0, "Resistance-ignoring moves must ignore each resisted component while preserving weaknesses.")
	print("BATTLE_TEST_EXISTING_MECHANICS_PASSED")

	var new_move_ids := ["squawk", "ignite", "peck", "mimic", "scratch", "heat_up", "singe", "intercept", "fire_charge", "nest", "fireheart", "whirlwind", "wingbeat", "burn_off", "skyfall", "phoenix_charge", "challenging_call", "harsh_sunlight", "inferno_plume", "inner_focus", "inferno"]
	for move_id: String in new_move_ids:
		assert(battle.battle_data["moves"].has(move_id), "New move '%s' must be defined." % move_id)
	var expected_definitions := {
		"squawk": ["Air", "Status", 0], "ignite": ["Fire", "Special", 40], "peck": ["Air", "Physical", 40],
		"mimic": ["Air", "Status", 0], "scratch": ["Normal", "Physical", 40], "heat_up": ["Fire", "Special", 10],
		"singe": ["Fire", "Status", 0], "intercept": ["Air", "Physical", 50], "fire_charge": ["Fire", "Physical", 80],
		"nest": ["Air", "Status", 0], "fireheart": ["Fire", "Status", 0], "whirlwind": ["Air", "Status", 0],
		"wingbeat": ["Air", "Physical", 85], "burn_off": ["Fire", "Status", 0], "skyfall": ["Air", "Physical", 65],
		"phoenix_charge": ["Fire", "Physical", 120], "challenging_call": ["Air", "Status", 0],
		"harsh_sunlight": ["Fire", "Status", 0], "inferno_plume": ["Fire", "Physical", 180],
		"inner_focus": ["Psychic", "Status", 0], "inferno": ["Fire", "Special", 300]
	}
	for move_id: String in expected_definitions:
		var definition: Dictionary = battle.battle_data["moves"][move_id]
		var expected: Array = expected_definitions[move_id]
		assert(definition["type"] == expected[0] and definition["damage_class"] == expected[1] and int(definition["power"]) == expected[2], "Move '%s' must preserve its specified type, category, and power." % move_id)
	assert(battle.battle_data["moves"]["intercept"]["priority"] == 1, "Intercept must use reusable move priority.")
	assert(battle.battle_data["moves"]["ignite"]["condition_chance"] == 0.2, "Ignite must have a 20% Burn chance.")
	assert(battle.battle_data["weather"]["Harsh Sunlight"]["damage_multipliers"] == {"Fire": 1.5, "Plant": 1.5, "Water": 0.5}, "Harsh Sunlight must boost Fire and Plant while weakening Water.")
	print("BATTLE_TEST_NEW_DEFINITIONS_PASSED")

	var nest_user := {"name": "Nester", "types": ["Air", "Fire"], "gender": "Genderless", "level": 10, "max_hp": 100, "attack": 20, "defense": 20, "special_attack": 20, "special_defense": 20, "speed": 20, "moves": ["nest"]}
	battle._ensure_condition_fields(nest_user)
	battle.battle_party.clear()
	battle.battle_party.append(nest_user)
	battle.party_hp.clear()
	battle.party_hp.append(10)
	battle.active_party_index = 0
	battle.player = nest_user
	battle.player_hp = 10
	battle._apply_nest(nest_user, true)
	assert(battle._fakemon_types(nest_user) == ["Fire"] and battle.player_hp == 43, "Nest must remove Air and heal an Air user for 33% maximum HP.")
	battle._tick_temporary_state(nest_user)
	assert(battle._fakemon_types(nest_user) == ["Fire"], "Nest's removed typing must persist through the first turn boundary.")
	battle._tick_temporary_state(nest_user)
	assert(battle._fakemon_types(nest_user) == ["Air", "Fire"], "Nest must restore Air after the user's next turn.")
	print("BATTLE_TEST_NEST_PASSED")

	var target := nest_user.duplicate(true)
	target["name"] = "Target"
	target["type"] = "Normal"
	target.erase("types")
	battle._ensure_condition_fields(target)
	target["defense"] = 30
	target["stat_modifiers"]["defense"] = 1.3
	var sky_user := target.duplicate(true)
	sky_user["name"] = "Sky User"
	sky_user["type"] = "Air"
	sky_user["attack"] = 5
	battle._ensure_condition_fields(sky_user)
	var control_user := sky_user.duplicate(true)
	control_user["attack"] = 39
	var control_move: Dictionary = battle.battle_data["moves"]["skyfall"].duplicate(true)
	control_move.erase("uses_target_defense_as_attack")
	seed(12345)
	var skyfall_damage: Dictionary = battle._calculate_damage(sky_user, target, battle.battle_data["moves"]["skyfall"])
	seed(12345)
	var control_damage: Dictionary = battle._calculate_damage(control_user, target, control_move)
	assert(skyfall_damage["damage"] == control_damage["damage"], "Skyfall must use the target's staged Defense as its physical attacking stat.")
	print("BATTLE_TEST_SKYFALL_PASSED")

	battle.battle_party.clear()
	battle.battle_party.append(sky_user)
	battle.party_hp.clear()
	battle.party_hp.append(1)
	battle.active_party_index = 0
	battle.player = sky_user
	battle.player_hp = 1
	battle._apply_cannot_faint(sky_user, 2)
	battle._apply_hp_damage(sky_user, 999, true)
	assert(battle.player_hp == 1, "Fireheart must prevent all damage sources from reducing the user below 1 HP.")

	sky_user["ignore_next_move_self_damage"] = true
	battle.player_hp = 40
	battle.party_hp[0] = 40
	battle._apply_after_damage_effects(sky_user, target, battle.battle_data["moves"]["phoenix_charge"], true)
	assert(battle.player_hp == 40 and int(sky_user["cannot_faint_turns"]) == 2, "Phoenix Charge must apply Fireheart protection before its recoil, and Inner Focus must suppress that recoil.")
	assert(not bool(sky_user["ignore_next_move_self_damage"]), "Inner Focus must expire after the user's next attacking turn.")
	print("BATTLE_TEST_FIREHEART_PHOENIX_INNER_FOCUS_PASSED")

	var reserve := target.duplicate(true)
	reserve["name"] = "Reserve"
	reserve["condition"] = ""
	var fainted_reserve := target.duplicate(true)
	fainted_reserve["name"] = "Fainted Reserve"
	fainted_reserve["condition"] = ""
	battle.battle_party.clear()
	battle.battle_party.append(sky_user)
	battle.battle_party.append(reserve)
	battle.battle_party.append(fainted_reserve)
	battle.party_hp.clear()
	battle.party_hp.append(40)
	battle.party_hp.append(20)
	battle.party_hp.append(0)
	battle.active_party_index = 0
	battle.player = sky_user
	battle.player_hp = 40
	sky_user["cannot_faint_turns"] = 0
	battle.weather = "Celestial Chorus"
	battle.weather_turns_remaining = 2
	battle._apply_after_damage_effects(sky_user, target, battle.battle_data["moves"]["inferno"], true)
	assert(battle.player_hp == 8, "Inferno must deal recoil equal to 80% of current HP.")
	assert(reserve["condition"] == "Burned" and fainted_reserve["condition"].is_empty(), "Inferno must Burn only non-fainted, non-active party members.")
	assert(battle.weather.is_empty(), "Inferno must remove weather other than Harsh Sunlight.")

	var keklid: Dictionary = battle.battle_data["fakemon"][2]
	assert(keklid["moves"] == ["petal_whip", "charm", "stare", "mind_wave"], "Level 5 Keklid must know its four available moves.")
	assert(keklid["learnset"].size() == 20 and keklid["learnset"].any(func(entry: Dictionary) -> bool: return int(entry["level"]) == 37 and String(entry["move"]) == "rootmind"), "Keklid must learn Rootmind at level 37.")
	var evolved_by_name := {}
	for species: Dictionary in battle.battle_data["fakemon"]:
		evolved_by_name[String(species["name"])] = species
	for evolved_name: String in ["Phaloa", "Scorcaw", "Serafin", "Junrift", "Pyravion", "Celestraal"]:
		assert(evolved_by_name.has(evolved_name), "%s must be present in the Fakemon roster." % evolved_name)
		for perspective: String in ["Player", "Wild"]:
			assert(ResourceLoader.exists("res://assets/fakemon/battle/%s_%s.png" % [evolved_name, perspective]), "%s must have %s battle art." % [evolved_name, perspective.to_lower()])
		for direction: String in ["Down", "Up", "Left", "Right"]:
			assert(ResourceLoader.exists("res://assets/fakemon/overworld/%s_Follow_%s.png" % [evolved_name, direction]), "%s must have %s follower art." % [evolved_name, direction.to_lower()])
	var phaloa: Dictionary = evolved_by_name["Phaloa"]
	var scorcaw: Dictionary = evolved_by_name["Scorcaw"]
	var serafin: Dictionary = evolved_by_name["Serafin"]
	var junrift: Dictionary = evolved_by_name["Junrift"]
	var pyravion: Dictionary = evolved_by_name["Pyravion"]
	var celestraal: Dictionary = evolved_by_name["Celestraal"]
	assert(battle._fakemon_types(phaloa) == ["Plant", "Psychic"] and phaloa["moves"] == keklid["moves"] and phaloa["learnset"] == keklid["learnset"], "Phaloa must inherit Keklid's moveset and use Plant/Psychic typing.")
	assert(battle._fakemon_types(scorcaw) == ["Fire", "Air"] and scorcaw["moves"] == scorchick["moves"] and scorcaw["learnset"] == scorchick["learnset"], "Scorcaw must inherit Scorchick's moveset and use Fire/Air typing.")
	assert(battle._fakemon_types(serafin) == ["Water", "Light"] and serafin["moves"] == sylvafin["moves"] and serafin["learnset"] == sylvafin["learnset"], "Serafin must inherit Sylvafin's moveset and use Water/Light typing.")
	assert([int(phaloa["max_hp"]), int(phaloa["attack"]), int(phaloa["defense"]), int(phaloa["special_attack"]), int(phaloa["special_defense"]), int(phaloa["speed"])] == [83, 55, 68, 84, 85, 60], "Phaloa must use its requested stat spread.")
	assert([int(scorcaw["max_hp"]), int(scorcaw["attack"]), int(scorcaw["defense"]), int(scorcaw["special_attack"]), int(scorcaw["special_defense"]), int(scorcaw["speed"])] == [65, 99, 71, 60, 65, 75], "Scorcaw must use its requested stat spread.")
	assert([int(serafin["max_hp"]), int(serafin["attack"]), int(serafin["defense"]), int(serafin["special_attack"]), int(serafin["special_defense"]), int(serafin["speed"])] == [80, 45, 70, 85, 85, 70], "Serafin must use its requested stat spread.")
	assert(battle._fakemon_types(junrift) == ["Plant", "Psychic"] and junrift["moves"] == keklid["moves"] and junrift["learnset"] == keklid["learnset"] and junrift["evolves_from"] == "Phaloa", "Junrift must evolve from Phaloa and inherit Keklid's Plant/Psychic line moveset.")
	assert(battle._fakemon_types(pyravion) == ["Fire", "Air"] and pyravion["moves"] == scorchick["moves"] and pyravion["learnset"] == scorchick["learnset"] and pyravion["evolves_from"] == "Scorcaw", "Pyravion must evolve from Scorcaw and inherit Scorchick's Fire/Air line moveset.")
	assert(battle._fakemon_types(celestraal) == ["Water", "Light"] and celestraal["moves"] == sylvafin["moves"] and celestraal["learnset"] == sylvafin["learnset"] and celestraal["evolves_from"] == "Serafin", "Celestraal must evolve from Serafin and inherit Sylvafin's Water/Light line moveset.")
	assert([int(junrift["max_hp"]), int(junrift["attack"]), int(junrift["defense"]), int(junrift["special_attack"]), int(junrift["special_defense"]), int(junrift["speed"])] == [115, 65, 115, 110, 105, 45], "Junrift must use its requested stat spread.")
	assert([int(pyravion["max_hp"]), int(pyravion["attack"]), int(pyravion["defense"]), int(pyravion["special_attack"]), int(pyravion["special_defense"]), int(pyravion["speed"])] == [90, 120, 85, 65, 80, 115], "Pyravion must use its requested stat spread.")
	assert([int(celestraal["max_hp"]), int(celestraal["attack"]), int(celestraal["defense"]), int(celestraal["special_attack"]), int(celestraal["special_defense"]), int(celestraal["speed"])] == [100, 55, 85, 105, 120, 90], "Celestraal must use its requested stat spread.")
	for evolved: Dictionary in [phaloa, scorcaw, serafin]:
		var bst := int(evolved["max_hp"]) + int(evolved["attack"]) + int(evolved["defense"]) + int(evolved["special_attack"]) + int(evolved["special_defense"]) + int(evolved["speed"])
		assert(bst == 435, "%s's BST must be 435." % evolved["name"])
	for final_evolution: Dictionary in [junrift, pyravion, celestraal]:
		var bst := int(final_evolution["max_hp"]) + int(final_evolution["attack"]) + int(final_evolution["defense"]) + int(final_evolution["special_attack"]) + int(final_evolution["special_defense"]) + int(final_evolution["speed"])
		assert(bst == 555, "%s's BST must be 555." % final_evolution["name"])
	battle._set_fakemon_art(battle.player_square, scorchick, "Player")
	assert(battle.player_square.size == Vector2(125, 125), "Starter battle art must retain its 125-pixel size.")
	var player_art_anchor: Vector2 = battle.player_square.position + Vector2(battle.player_square.size.x * 0.5, battle.player_square.size.y)
	battle._set_fakemon_art(battle.player_square, scorcaw, "Player")
	assert(battle.player_square.size == Vector2(200, 200), "Evolved battle art must preserve a larger size up to the 200-pixel battle cap.")
	assert(battle.player_square.position + Vector2(battle.player_square.size.x * 0.5, battle.player_square.size.y) == player_art_anchor, "Battle art resizing must preserve its bottom-center anchor.")
	for move_id: String in ["charm", "stare", "mind_wave", "constrict", "drain", "vicegrip", "mind_bolt", "bloom", "seed", "regrow", "mycelial_hunt", "drain_toxin", "synaptic_bloom", "hysteria", "chlorophyll_cannon", "vital_cognition"]:
		assert(battle.battle_data["moves"].has(move_id), "Keklid move '%s' must be defined." % move_id)
	var confusion_data: Dictionary = battle.battle_data["conditions"]["Confusion"]
	assert(not confusion_data["persistent"] and int(confusion_data["minimum_turns"]) == 2 and int(confusion_data["maximum_turns"]) == 5, "Confusion must be a two-to-five-turn battle-only condition.")

	var effect_user := {"name": "Effect User", "type": "Plant", "gender": "Genderless", "level": 10, "max_hp": 100, "attack": 20, "defense": 20, "special_attack": 20, "special_defense": 20, "speed": 20, "moves": ["regrow"]}
	var effect_target := effect_user.duplicate(true)
	effect_target["name"] = "Effect Target"
	battle._ensure_condition_fields(effect_user)
	battle._ensure_condition_fields(effect_target)
	var confusion_move := {"condition": "Confusion", "condition_chance": 1.0}
	battle._try_inflict_condition(effect_target, confusion_move, effect_user, true)
	assert(effect_target["condition"] == "Confusion" and int(effect_target["condition_turns"]) >= 2 and int(effect_target["condition_turns"]) <= 5, "Inflicted Confusion must roll a duration from two through five turns.")
	effect_target["moves"] = ["pounce", "quick_bump"]
	effect_target["move_cooldowns"]["pounce"] = 1
	assert(battle._choose_confused_move_id(effect_target) == "quick_bump", "Confusion must choose randomly from currently usable known moves.")
	effect_target["condition_turns"] = 2
	assert(battle._can_use_move(effect_target) and effect_target["condition"] == "Confusion" and int(effect_target["condition_turns"]) == 1, "A confused attack turn must decrement its remaining duration.")
	assert(battle._can_use_move(effect_target) and effect_target["condition"].is_empty(), "Confusion must clear after its final random attack turn.")
	effect_target["condition"] = "Confusion"
	effect_target["condition_turns"] = 4
	battle._clear_confusion(effect_target)
	assert(effect_target["condition"].is_empty() and int(effect_target["condition_turns"]) == 0, "Switching or curing must clear Confusion immediately.")
	battle.battle_party.clear()
	battle.battle_party.append(effect_user)
	battle.battle_party.append(effect_target)
	battle.party_hp.clear()
	battle.party_hp.append(10)
	battle.party_hp.append(100)
	battle.active_party_index = 0
	battle.player = effect_user
	battle.player_hp = 10
	battle.opponent = effect_target
	battle.opponent_hp = 100
	effect_user["condition"] = "Poisoned"
	effect_user["infatuation_stacks"] = 2
	effect_user["stat_modifiers"]["special_attack"] = 1.2
	effect_user["stat_modifiers"]["defense"] = 0.9
	assert(battle._apply_regrow(effect_user, true) == 4, "Regrow must count each condition and each modified stat once, regardless of stacks or stage magnitude.")
	assert(battle.player_hp == 50 and effect_user["condition"].is_empty() and effect_user["infatuation_stacks"] == 0, "Regrow must cure conditions and heal 10% maximum HP per removed effect.")
	assert(not battle._has_any_stat_change(effect_user), "Regrow must reset positive and negative stat stages to neutral.")

	var synaptic := battle.battle_data["moves"]["synaptic_bloom"] as Dictionary
	assert(int(battle._calculate_damage(effect_user, effect_target, synaptic)["power"]) == 80, "Synaptic Bloom must remain 80 power at neutral stages.")
	effect_user["stat_modifiers"]["attack"] = 1.1
	assert(int(battle._calculate_damage(effect_user, effect_target, synaptic)["power"]) == 100, "A positive stage must raise Synaptic Bloom to 100 power.")
	effect_user["stat_modifiers"]["attack"] = 1.0
	effect_user["stat_modifiers"]["defense"] = 0.8
	assert(int(battle._calculate_damage(effect_user, effect_target, synaptic)["power"]) == 100, "A negative stage must raise Synaptic Bloom to 100 power.")
	effect_user["stat_modifiers"]["defense"] = 1.0
	var hunt := battle.battle_data["moves"]["mycelial_hunt"] as Dictionary
	assert(int(battle._calculate_damage(effect_user, effect_target, hunt)["power"]) == 75, "Mycelial Hunt must be 75 power against an unafflicted target.")
	effect_target["condition"] = "Confusion"
	assert(int(battle._calculate_damage(effect_user, effect_target, hunt)["power"]) == 90, "Mycelial Hunt must be 90 power against an afflicted target.")
	effect_target["condition"] = ""

	battle.player_hp = 10
	battle.party_hp[0] = 10
	battle._apply_after_damage_effects(effect_user, effect_target, battle.battle_data["moves"]["drain"], true, 7)
	assert(battle.player_hp == 13, "Drain must heal 50% of actual damage dealt, rounded down.")
	battle.player_hp = 10
	battle.party_hp[0] = 10
	battle._apply_status_move(effect_user, effect_target, battle.battle_data["moves"]["bloom"], true)
	assert(battle.player_hp == 22, "Level 10 Bloom must restore 12% maximum HP using its level-scaled formula.")
	battle.player_hp = 10
	battle.party_hp[0] = 10
	battle._apply_after_damage_effects(effect_user, effect_target, battle.battle_data["moves"]["drain_toxin"], true, 5)
	assert(battle.player_hp == 25 and int(effect_user["weakness_suppressions"]["Poison"]) == 3, "Drain Toxin must heal exactly 15% maximum HP and begin three-turn Poison suppression.")
	battle._tick_temporary_state(effect_user)
	assert(int(effect_user["weakness_suppressions"]["Poison"]) == 2, "Drain Toxin suppression must decrement at the activation turn's end.")
	battle._tick_temporary_state(effect_user)
	assert(int(effect_user["weakness_suppressions"]["Poison"]) == 1, "Drain Toxin suppression must remain for its third counted turn.")
	battle._tick_temporary_state(effect_user)
	assert(not effect_user["weakness_suppressions"].has("Poison"), "Drain Toxin suppression must expire after exactly three end-turn decrements.")

	var vital := battle.battle_data["moves"]["vital_cognition"] as Dictionary
	battle.player_hp = 100
	battle.party_hp[0] = 100
	effect_user["condition"] = ""
	effect_user["stat_modifiers"]["special_attack"] = 1.0
	battle._apply_status_move(effect_user, effect_target, vital, true)
	assert(battle.player_hp == 100 and is_equal_approx(effect_user["stat_modifiers"]["special_attack"], 1.2), "A full-HP healthy user must still receive Vital Cognition's stat boost.")
	battle.player_hp = 50
	battle.party_hp[0] = 50
	effect_user["stat_modifiers"]["special_attack"] = 1.0
	battle._apply_status_move(effect_user, effect_target, vital, true)
	assert(battle.player_hp == 75 and is_equal_approx(effect_user["stat_modifiers"]["special_attack"], 1.2), "Healthy Vital Cognition must heal 25% and raise Special Attack two stages.")
	battle.player_hp = 50
	battle.party_hp[0] = 50
	effect_user["condition"] = "Poisoned"
	effect_user["stat_modifiers"]["special_attack"] = 1.0
	battle._apply_status_move(effect_user, effect_target, vital, true)
	assert(battle.player_hp == 75 and effect_user["condition"].is_empty() and is_equal_approx(effect_user["stat_modifiers"]["special_attack"], 1.0), "Conditioned Vital Cognition must heal and cure instead of boosting.")
	battle.player_hp = 60
	battle.party_hp[0] = 60
	effect_user["stat_modifiers"]["special_attack"] = 1.9
	battle._apply_status_move(effect_user, effect_target, vital, true)
	assert(battle.player_hp == 85 and is_equal_approx(effect_user["stat_modifiers"]["special_attack"], 1.9), "Vital Cognition must still heal while Special Attack is capped.")

	var guaranteed_mind_bolt := (battle.battle_data["moves"]["mind_bolt"] as Dictionary).duplicate(true)
	guaranteed_mind_bolt["random_secondary_chance"] = 1.0
	for iteration in 100:
		effect_target["condition"] = ""
		effect_target["flinched"] = false
		battle._apply_random_secondary_condition(effect_target, effect_user, guaranteed_mind_bolt, true)
		assert(bool(effect_target["flinched"]) != (effect_target["condition"] == "Confusion"), "A successful Mind Bolt proc must apply exactly one of Flinch or Confusion, never both.")

	assert(battle.battle_data["moves"].has("rootmind") and battle.battle_data["moves"]["rootmind"]["sets_weather"] == "Rootmind", "Rootmind must be a weather-setting move.")
	battle._set_weather("Rootmind")
	assert(battle.weather_turns_remaining == 3, "Rootmind must use the global three-turn weather duration.")
	assert(int(battle._calculate_damage(effect_user, effect_target, battle.battle_data["moves"]["petal_whip"])["power"]) == 45, "Rootmind must raise Petal Whip to 45 power.")
	assert(is_equal_approx(battle._move_effect_float(battle.battle_data["moves"]["petal_whip"], "condition_chance", 0.0), 0.3), "Rootmind must raise Petal Whip's Poison chance to 30%.")
	assert(int(battle._calculate_damage(effect_user, effect_target, battle.battle_data["moves"]["constrict"])["power"]) == 50, "Rootmind must raise Constrict to 50 power.")
	assert(int(battle._calculate_damage(effect_user, effect_target, battle.battle_data["moves"]["drain"])["power"]) == 45, "Rootmind must raise Drain to 45 power.")
	assert(is_equal_approx(battle._move_effect_float(battle.battle_data["moves"]["mind_wave"], "condition_chance", 0.0), 0.3), "Rootmind must raise Mind Wave's Confusion chance to 30%.")
	assert(is_equal_approx(battle._move_effect_float(battle.battle_data["moves"]["mind_bolt"], "random_secondary_chance", 0.0), 0.3), "Rootmind must add 10 percentage points to Mind Bolt's secondary chance.")
	effect_target["condition"] = ""
	assert(int(battle._calculate_damage(effect_user, effect_target, battle.battle_data["moves"]["mycelial_hunt"])["power"]) == 90, "Rootmind Mycelial Hunt must start at 90 power.")
	effect_target["condition"] = "Confusion"
	assert(int(battle._calculate_damage(effect_user, effect_target, battle.battle_data["moves"]["mycelial_hunt"])["power"]) == 120, "Rootmind Mycelial Hunt must reach 120 power against an afflicted target.")
	effect_target["condition"] = ""
	for stat: String in battle.COMBAT_STATS:
		effect_user["stat_modifiers"][stat] = 1.0
	assert(int(battle._calculate_damage(effect_user, effect_target, synaptic)["power"]) == 90, "Rootmind Synaptic Bloom must be 90 power at neutral stages.")
	effect_user["stat_modifiers"]["attack"] = 1.1
	assert(int(battle._calculate_damage(effect_user, effect_target, synaptic)["power"]) == 110, "Rootmind Synaptic Bloom must reach 110 power with a stat change.")
	effect_user["stat_modifiers"]["attack"] = 1.0
	assert(int(battle._calculate_damage(effect_user, effect_target, battle.battle_data["moves"]["drain_toxin"])["power"]) == 55, "Rootmind must raise Drain Toxin to 55 power.")
	assert(int(battle._calculate_damage(effect_user, effect_target, battle.battle_data["moves"]["chlorophyll_cannon"])["power"]) == 110, "Rootmind must raise Chlorophyll Cannon to 110 power.")

	battle.battle_party.clear()
	battle.battle_party.append(effect_user)
	battle.party_hp.clear()
	battle.party_hp.append(50)
	battle.active_party_index = 0
	battle.player = effect_user
	battle.player_hp = 50
	battle.opponent = effect_target
	battle.opponent_hp = 60
	battle.opponent_party.clear()
	battle.opponent_party.append(effect_target)
	battle.opponent_party_hp.clear()
	battle.opponent_party_hp.append(60)
	battle.active_opponent_index = 0
	battle._apply_rootmind_healing()
	assert(battle.player_hp == 56 and battle.opponent_hp == 66, "Rootmind must heal every active Plant-type Fakemon for 1/16 maximum HP.")
	battle.player_hp = 50
	battle.party_hp[0] = 50
	effect_user["condition"] = "Poisoned"
	battle._apply_status_move(effect_user, effect_target, battle.battle_data["moves"]["remedy"], true)
	assert(effect_user["condition"].is_empty() and battle.player_hp == 62, "Rootmind Remedy must cure and restore 1/8 maximum HP.")
	battle.player_hp = 50
	battle.party_hp[0] = 50
	battle._apply_status_move(effect_user, effect_target, battle.battle_data["moves"]["bloom"], true)
	assert(battle.player_hp == 67, "Rootmind must add five percentage points to level 10 Bloom's 12% healing.")
	battle.player_hp = 50
	battle.party_hp[0] = 50
	effect_user["weakness_suppressions"].clear()
	battle._apply_after_damage_effects(effect_user, effect_target, battle.battle_data["moves"]["drain_toxin"], true, 5)
	assert(battle.player_hp == 70 and int(effect_user["weakness_suppressions"]["Poison"]) == 5, "Rootmind Drain Toxin must heal 20% and suppress Poison weakness for five turns.")
	battle.player_hp = 50
	battle.party_hp[0] = 50
	effect_user["condition"] = ""
	effect_user["stat_modifiers"]["special_attack"] = 1.0
	battle._apply_status_move(effect_user, effect_target, vital, true)
	assert(battle.player_hp == 83, "Rootmind Vital Cognition must restore one third of maximum HP, rounded down.")
	battle.player_hp = 50
	battle.party_hp[0] = 50
	battle.opponent_hp = 100
	battle.opponent_party_hp[0] = 100
	effect_target["seeded_by_side"] = "player"
	battle._apply_seeded_drain()
	assert(battle.opponent_hp == 85 and battle.player_hp == 65, "Rootmind must increase Seed's drain and matching healing by 20%.")

	effect_target["voluntary_switch_block_turns"] = 0
	battle._apply_after_damage_effects(effect_user, effect_target, battle.battle_data["moves"]["vicegrip"], true, 5)
	battle.battle_party.clear()
	battle.battle_party.append(effect_target)
	battle.battle_party.append(effect_user)
	battle.party_hp.clear()
	battle.party_hp.append(100)
	battle.party_hp.append(100)
	battle.active_party_index = 0
	battle.player = effect_target
	battle.player_hp = 100
	battle.party_hp[0] = 100
	assert(int(effect_target["voluntary_switch_block_turns"]) > 0, "Vicegrip must mark the target as unable to switch voluntarily.")
	battle._random_switch_player(false)
	assert(battle.active_party_index == 1, "Vicegrip's voluntary switch lock must not block forced switching.")

	var slumboth: Dictionary = battle.battle_data["fakemon"].filter(func(mon: Dictionary) -> bool: return mon["name"] == "Slumboth")[0]
	var expected_slumboth_moves := ["doze_off", "sleep_talk", "defense_curl", "scratch", "gnaw", "dream", "punch", "counter", "sleep_off", "bulk_up", "slash", "snore", "hammer_arm", "sleep_swing", "scourge", "kinetic_pummel", "rest"]
	assert(slumboth["learnset"].map(func(entry: Dictionary) -> String: return String(entry["move"])) == expected_slumboth_moves, "Slumboth must have the complete ordered moveset.")
	assert(slumboth["moves"] == ["doze_off", "sleep_talk", "defense_curl"], "Level 5 Slumboth must know its three accessible moves.")
	assert(bool(slumboth["learnset"][6]["evolution_move"]), "Punch must be marked as Slumboth's evolution move.")
	assert(slumboth["egg_groups"] == ["Mammal", "Mineral"], "Slumboth must be in the Mammal and Mineral egg groups.")
	for move_id: String in expected_slumboth_moves:
		assert(battle.battle_data["moves"].has(move_id), "Slumboth move '%s' must be defined." % move_id)
	var hangrowl: Dictionary = battle.battle_data["fakemon"].filter(func(mon: Dictionary) -> bool: return mon["name"] == "Hangrowl")[0]
	var swoleth: Dictionary = battle.battle_data["fakemon"].filter(func(mon: Dictionary) -> bool: return mon["name"] == "Swoleth")[0]
	assert(hangrowl["types"] == ["Normal", "Fighting"] and hangrowl["evolves_from"] == "Slumboth" and int(hangrowl["evolution_level"]) == 15 and hangrowl["moves"] == slumboth["moves"], "Hangrowl must evolve from Slumboth at level 15 with its moveset.")
	assert(swoleth["types"] == ["Normal", "Fighting"] and swoleth["evolves_from"] == "Hangrowl" and int(swoleth["evolution_level"]) == 35 and swoleth["moves"] == slumboth["moves"], "Swoleth must evolve from Hangrowl at level 35 with its moveset.")
	assert(hangrowl["egg_groups"] == ["Mammal", "Mineral"] and swoleth["egg_groups"] == ["Mammal", "Mineral"], "The full Slumboth line must retain its egg groups.")

	var skeeter: Dictionary = battle.battle_data["fakemon"].filter(func(mon: Dictionary) -> bool: return mon["name"] == "Skeeter")[0]
	var expected_gloom_moves := ["gnaw", "buzz", "needle_nip", "bite", "infest", "swoop", "blood_draw", "torment", "evade", "swarm", "gather", "leech_life", "night_dart", "hypnotic_hum", "scourge", "bloodmoon", "plague"]
	assert(skeeter["learnset"].map(func(entry: Dictionary) -> String: return String(entry["move"])) == expected_gloom_moves, "Skeeter must have its complete ordered moveset.")
	assert(skeeter["moves"] == ["gnaw", "buzz", "needle_nip"], "Level 5 Skeeter must know its three accessible moves.")
	for move_id: String in expected_gloom_moves:
		assert(battle.battle_data["moves"].has(move_id), "Skeeter move '%s' must be defined." % move_id)
	var gloomquito: Dictionary = battle.battle_data["fakemon"].filter(func(mon: Dictionary) -> bool: return mon["name"] == "Gloomquito")[0]
	var vamprick: Dictionary = battle.battle_data["fakemon"].filter(func(mon: Dictionary) -> bool: return mon["name"] == "Vamprick")[0]
	assert(battle._fakemon_types(skeeter) == ["Bug"] and skeeter["egg_groups"] == ["Bug", "Demonic"], "Skeeter must be Bug type with Bug/Demonic egg groups.")
	assert(gloomquito["types"] == ["Bug", "Dark"] and gloomquito["evolves_from"] == "Skeeter" and int(gloomquito["evolution_level"]) == 15 and gloomquito["moves"] == skeeter["moves"], "Gloomquito must evolve from Skeeter at level 15 and inherit its moveset.")
	assert(vamprick["types"] == ["Bug", "Dark"] and vamprick["evolves_from"] == "Gloomquito" and int(vamprick["evolution_level"]) == 32 and vamprick["moves"] == skeeter["moves"], "Vamprick must evolve from Gloomquito at level 32 and inherit its moveset.")
	assert(gloomquito["egg_groups"] == ["Bug", "Demonic"] and vamprick["egg_groups"] == ["Bug", "Demonic"], "The Skeeter line must retain Bug/Demonic egg groups.")
	assert(int(skeeter["base_exp"]) == int(slumboth["base_exp"]) and int(gloomquito["base_exp"]) == int(hangrowl["base_exp"]) and int(vamprick["base_exp"]) == int(swoleth["base_exp"]), "The Skeeter line must match the Slumboth line's EXP values by stage.")
	assert(int(battle.battle_data["moves"]["swoop"]["priority"]) == 1 and int(battle.battle_data["moves"]["night_dart"]["priority"]) == 1, "Swoop and Night Dart must share standard move priority so Speed breaks ties.")
	assert(int(battle.battle_data["weather"]["Blood Moon"]["duration"]) == 5, "Blood Moon must last five turns.")
	var gloom_user: Dictionary = battle.create_fakemon(skeeter)
	var gloom_target: Dictionary = battle.create_fakemon(skeeter)
	battle._ensure_condition_fields(gloom_user)
	battle._ensure_condition_fields(gloom_target)
	gloom_target["condition"] = "Asleep"
	seed(44)
	var normal_night_dart: Dictionary = battle.battle_data["moves"]["night_dart"].duplicate(true)
	normal_night_dart.erase("power_multiplier_if_target_conditions")
	var normal_night_damage := int(battle._calculate_damage(gloom_user, gloom_target, normal_night_dart)["damage"])
	seed(44)
	var sleeping_night_damage := int(battle._calculate_damage(gloom_user, gloom_target, battle.battle_data["moves"]["night_dart"])["damage"])
	assert(sleeping_night_damage > normal_night_damage, "Night Dart must double its power against sleeping or confused targets.")
	gloom_target["last_successful_move"] = "gnaw"
	battle._apply_status_move(gloom_user, gloom_target, battle.battle_data["moves"]["torment"], true)
	assert(not battle._is_move_selectable(gloom_target, "gnaw"), "Torment must prevent repeating the target's last move.")
	battle._apply_status_move(gloom_user, gloom_target, battle.battle_data["moves"]["swarm"], true)
	assert(String(gloom_user["charged_type"]) == "Bug" and is_equal_approx(float(gloom_user["charge_multiplier"]), 2.0), "Swarm must double Bug move power on the following turn.")
	battle._apply_status_move(gloom_user, gloom_target, battle.battle_data["moves"]["gather"], true)
	assert(gloom_user["condition_immunities"] == ["Confusion", "Flinch"], "Gather must prepare next-turn immunity to confusion and flinching.")
	battle._set_weather("Blood Moon")
	assert(battle.weather_turns_remaining == 5, "Blood Moon must initialize its full five-turn duration.")

	var dartlet: Dictionary = battle.battle_data["fakemon"].filter(func(mon: Dictionary) -> bool: return mon["name"] == "Dartlet")[0]
	var croacoa: Dictionary = battle.battle_data["fakemon"].filter(func(mon: Dictionary) -> bool: return mon["name"] == "Croacoa")[0]
	var flambian: Dictionary = battle.battle_data["fakemon"].filter(func(mon: Dictionary) -> bool: return mon["name"] == "Flambian")[0]
	var expected_dartlet_moves := ["poison_bubble", "croak", "leap", "poison_tongue", "dartlet_stare", "drain", "incinerate", "cacophony", "singe", "warning_flare", "coat_toxin", "flashcroak", "puff_up", "flamethrower", "harsh_sunlight", "alkaloid_mist", "sun_chorus", "toxic_flare", "grand_display"]
	assert(dartlet["learnset"].map(func(entry: Dictionary) -> String: return String(entry["move"])) == expected_dartlet_moves and dartlet["moves"] == ["poison_bubble", "croak", "leap"], "Dartlet must have its complete ordered learnset and level-five moves.")
	assert(battle._fakemon_types(dartlet) == ["Poison"] and dartlet["egg_groups"] == ["Amphibian", "Cosmic"], "Dartlet must be Poison type with Amphibian/Cosmic egg groups.")
	assert(croacoa["types"] == ["Poison", "Fire"] and croacoa["evolves_from"] == "Dartlet" and int(croacoa["evolution_level"]) == 15 and croacoa["moves"] == dartlet["moves"], "Croacoa must evolve from Dartlet at level 15 with its moveset.")
	assert(flambian["types"] == ["Poison", "Fire"] and flambian["evolves_from"] == "Croacoa" and int(flambian["evolution_level"]) == 35 and flambian["moves"] == dartlet["moves"], "Flambian must evolve from Croacoa at level 35 with its moveset.")
	assert(int(dartlet["base_exp"]) == int(slumboth["base_exp"]) + 5 and int(croacoa["base_exp"]) == int(hangrowl["base_exp"]) + 5 and int(flambian["base_exp"]) == int(swoleth["base_exp"]) + 5, "The Dartlet line must use the requested stage-relative EXP values.")
	var dartlet_user: Dictionary = battle.create_fakemon(dartlet)
	var amphibian_target: Dictionary = battle.create_fakemon(dartlet)
	battle._ensure_condition_fields(dartlet_user)
	battle._ensure_condition_fields(amphibian_target)
	battle._apply_status_move(dartlet_user, amphibian_target, battle.battle_data["moves"]["croak"], true)
	assert(int(amphibian_target["infatuation_stacks"]) == 1 and is_equal_approx(float(amphibian_target["stat_modifiers"]["special_defense"]), 1.0), "Croak must substitute Infatuation for its stat drop against Amphibian targets.")
	battle._apply_after_damage_effects(dartlet_user, amphibian_target, battle.battle_data["moves"]["leap"], true, 5)
	assert(int(dartlet_user["next_move_priority"]) == 1, "Leap must grant priority to the user's next move.")
	battle._apply_status_move(dartlet_user, amphibian_target, battle.battle_data["moves"]["warning_flare"], true)
	assert(String(dartlet_user["reactive_poison_damage_class"]) == "Physical" and int(dartlet_user["reactive_poison_turns"]) == 2, "Warning Flare must arm two turns of physical retaliation poison.")
	amphibian_target["condition"] = "Poisoned"
	seed(72)
	var ordinary_flare: Dictionary = battle.battle_data["moves"]["toxic_flare"].duplicate(true)
	ordinary_flare.erase("power_multiplier_if_target_conditions")
	var ordinary_flare_damage := int(battle._calculate_damage(dartlet_user, amphibian_target, ordinary_flare)["damage"])
	seed(72)
	assert(int(battle._calculate_damage(dartlet_user, amphibian_target, battle.battle_data["moves"]["toxic_flare"])["damage"]) > ordinary_flare_damage, "Toxic Flare must gain power against poisoned targets.")
	var lochirp: Dictionary = battle.battle_data["fakemon"].filter(func(mon: Dictionary) -> bool: return mon["name"] == "Lochirp")[0]
	var paratweet: Dictionary = battle.battle_data["fakemon"].filter(func(mon: Dictionary) -> bool: return mon["name"] == "Paratweet")[0]
	var paradisia: Dictionary = battle.battle_data["fakemon"].filter(func(mon: Dictionary) -> bool: return mon["name"] == "Paradisia")[0]
	var expected_lochirp_moves := ["nectar_drink", "petal_whip", "dazzle", "charm", "remedy", "flutter", "gust", "bloom", "fey_dust", "petalwake", "mist", "lotus_dart", "magic_pulse", "fey_gardens", "solar_ray", "lotus_absolution", "mystic_stream", "paradise_ray", "paradise_bloom"]
	assert(lochirp["learnset"].map(func(entry: Dictionary) -> String: return String(entry["move"])) == expected_lochirp_moves and lochirp["moves"] == ["nectar_drink", "petal_whip", "dazzle", "charm"], "Lochirp must have its complete ordered learnset and level-five moves.")
	assert(lochirp["types"] == ["Plant", "Mystic"] and lochirp["egg_groups"] == ["Bird", "Plant"], "Lochirp must use Plant/Mystic typing and Bird/Plant egg groups.")
	assert(paratweet["evolves_from"] == "Lochirp" and int(paratweet["evolution_level"]) == 16 and paradisia["evolves_from"] == "Paratweet" and int(paradisia["evolution_level"]) == 36, "The Lochirp evolution levels must be data-driven.")
	assert(int(lochirp["base_exp"]) == int(slumboth["base_exp"]) + 5 and int(paratweet["base_exp"]) == int(hangrowl["base_exp"]) + 5 and int(paradisia["base_exp"]) == int(swoleth["base_exp"]) + 5, "The Lochirp line must use the requested EXP values.")
	var bloom_user: Dictionary = battle.create_fakemon(lochirp)
	battle._ensure_condition_fields(bloom_user)
	bloom_user["stat_modifiers"]["speed"] = 1.3
	bloom_user["stat_modifiers"]["defense"] = 0.8
	bloom_user["condition"] = "Poisoned"
	battle.player = bloom_user
	battle.player_hp = 1
	battle.active_party_index = 0
	battle.party_hp.clear()
	battle.party_hp.append(1)
	battle._apply_paradise_bloom(bloom_user, true)
	assert(battle.player_hp == 35, "Paradise Bloom must heal 15% base, 10% per individual stat stage, and 20% per condition.")
	battle._set_weather("Fey Gardens")
	assert(battle.weather_turns_remaining == 3, "Fey Gardens must last three turns.")
	var fey_target: Dictionary = battle.create_fakemon(lochirp)
	battle._ensure_condition_fields(fey_target)
	battle._try_inflict_condition(fey_target, {"condition": "Infatuated", "condition_chance": 1.0}, bloom_user, true)
	assert(int(fey_target["infatuation_stacks"]) == 2, "The first Infatuation applied by each combatant in Fey Gardens must gain an extra stack.")

	var sleeper := {"name": "Sleeper", "type": "Normal", "gender": "Genderless", "level": 20, "max_hp": 100, "attack": 40, "defense": 40, "special_attack": 40, "special_defense": 40, "speed": 20, "moves": ["sleep_talk"]}
	var sleep_target := {"name": "Target", "type": "Normal", "gender": "Genderless", "level": 20, "max_hp": 100, "attack": 40, "defense": 40, "special_attack": 40, "special_defense": 40, "speed": 20, "moves": ["scratch"]}
	battle._ensure_condition_fields(sleeper)
	battle._ensure_condition_fields(sleep_target)
	assert(not battle._move_condition_is_met(sleeper, battle.battle_data["moves"]["sleep_talk"]), "Sleep Talk must fail while awake.")
	sleeper["condition"] = "Asleep"
	sleeper["condition_turns"] = 2
	assert(battle._can_use_move(sleeper, battle.battle_data["moves"]["sleep_talk"]), "Sleep-only moves must act through sleep.")
	var gnaw_result: Dictionary = battle._calculate_move_damage(sleeper, sleep_target, battle.battle_data["moves"]["gnaw"])
	assert(int(gnaw_result["hits"]) >= 2 and int(gnaw_result["hits"]) <= 5, "Gnaw must hit between two and five times.")
	battle.player = sleeper
	battle.opponent = sleep_target
	battle.player_hp = 100
	battle.opponent_hp = 100
	battle.party_hp.clear()
	battle.party_hp.append(100)
	battle.opponent_party_hp.clear()
	battle.opponent_party_hp.append(100)
	battle._apply_move_damage(sleep_target, 999, false, battle.battle_data["moves"]["scourge"])
	assert(battle.opponent_hp == 1, "Scourge must never reduce its target below one HP.")
	sleeper["last_received_damage_class"] = "Physical"
	sleeper["last_received_damage"] = 12
	battle.opponent_hp = 100
	battle._apply_counter(sleeper, sleep_target, true)
	assert(battle.opponent_hp == 76, "Counter must retaliate for twice the last physical damage received.")
	sleeper["last_received_damage_class"] = "Special"
	battle._apply_counter(sleeper, sleep_target, true)
	assert(battle.opponent_hp == 76, "Counter must fail after a Special move.")

	var trainer_test_party: Array[Dictionary] = []
	var trainer_test_player := battle.battle_data["fakemon"][3].duplicate(true) as Dictionary
	trainer_test_player["current_hp"] = int(trainer_test_player["max_hp"])
	trainer_test_party.append(trainer_test_player)
	battle.begin_battle_with_opponent_party(trainer_test_party, 0, [0, 1], false)
	assert(battle.opponent_party.size() == 2 and battle.opponent_party_hp.size() == 2, "Trainer battles must initialize independent opponent party and HP state.")
	assert(battle.active_opponent_index == 0 and battle.opponent["name"] == "Scorchick", "Trainer battles must send out the first party member.")
	battle._apply_whirlwind(true)
	assert(battle.active_opponent_index == 1 and battle.opponent["name"] == "Sylvafin", "Whirlwind must randomly force an eligible trainer party member into battle.")
	battle._switch_opponent(0, false)
	battle.opponent_hp = 0
	battle.opponent_party_hp[0] = 0
	assert(not battle._finish_turn_conditions(), "Fainting a trainer party member must continue the battle while another remains.")
	assert(battle.active_opponent_index == 1 and battle.opponent["name"] == "Sylvafin", "A trainer must automatically send out the next conscious party member.")
	battle.begin_battle_with_opponent_party(trainer_test_party, 0, [0, 1, 2, 3, 4, 5, 0], false)
	assert(battle.opponent_party.size() == 7 and battle.opponent_party_hp.size() == 7, "Trainer and boss battles must support the full seven-Fakemon party limit.")
	battle.forced_switch = false
	battle._show_move_menu()
	assert(battle.move_menu.visible and battle.move_menu.get_child_count() == battle.current_move_ids.size() + 1, "Attack selection must display a Back control without committing a move.")
	battle._cancel_action_selection()
	assert(not battle.move_menu.visible and not battle.switch_panel.visible and not battle.action_button.disabled, "Canceling Attack selection must return to actions without consuming a turn.")
	battle._show_switch_choices()
	assert(battle.switch_panel.visible and (battle.switch_list.get_child(-1) as Button).text == "[Esc] Back", "Voluntary Switch selection must display a Back control.")
	battle._cancel_action_selection()
	assert(not battle.switch_panel.visible and not battle.action_button.disabled, "Canceling Switch selection must return to actions without selecting a Fakemon.")
	battle.forced_switch = true
	battle._show_switch_choices()
	assert(not (battle.switch_list.get_child(-1) is Button and (battle.switch_list.get_child(-1) as Button).text == "[Esc] Back"), "Forced switch selection must not offer cancellation.")
	battle.forced_switch = false
	print("BATTLE_MECHANICS_TEST_PASSED")
	quit()
