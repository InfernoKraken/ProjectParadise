extends SceneTree


func _initialize() -> void:
	var scene := load("res://battle/battle.tscn") as PackedScene
	assert(scene != null, "Battle scene must load.")
	var battle := scene.instantiate()
	root.add_child(battle)
	await process_frame
	var attacker := {"name": "Attacker", "type": "Normal", "gender": "Genderless", "level": 20, "max_hp": 100, "attack": 40, "defense": 40, "special_attack": 40, "special_defense": 40, "speed": 20, "moves": ["gnaw"]}
	var defender := attacker.duplicate(true)
	defender["name"] = "Defender"
	battle._ensure_condition_fields(attacker)
	battle._ensure_condition_fields(defender)
	var move: Dictionary = battle.battle_data["moves"]["gnaw"].duplicate(true)
	move["min_hits"] = 3
	move["max_hits"] = 3
	move["hit_chance"] = 1.0
	battle.player = attacker
	battle.opponent = defender
	battle.player_hp = 100
	battle.opponent_hp = 100
	battle.party_hp.clear()
	battle.party_hp.append(100)
	battle.opponent_party_hp.clear()
	battle.opponent_party_hp.append(100)
	battle.battle_animator.animations_enabled = false
	var markers: Array[String] = []
	battle.battle_animator.move_animation_marker.connect(func(marker_name: String) -> void: markers.append(marker_name))
	var result: Dictionary = await battle._resolve_damage_hits(attacker, defender, move, false, battle.player_square, battle.opponent_square)
	assert(int(result["hits"]) == 3, "A forced three-hit move must resolve three individual hits.")
	assert(markers == ["hit_1", "hit_2", "hit_3"], "Each resolved hit must emit an ordered semantic animation marker.")
	assert(battle.opponent_hp == 100 - int(result["damage"]), "Each hit must apply damage directly to the live target HP state.")
	print("MULTIHIT_RESOLUTION_TEST_PASSED")
	quit()
