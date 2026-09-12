extends SceneTree

var battle
var player: Dictionary
var opponent: Dictionary


func _initialize() -> void:
	var scene := load("res://battle/battle.tscn") as PackedScene
	battle = scene.instantiate()
	root.add_child(battle)
	await process_frame
	_setup_battlers()
	battle.battle_animator.animations_enabled = false

	_schedule("one", "a", "user_battler", "start_of_turn", 0, 1, {"kind": "heal", "amount": 0.25})
	battle._process_scheduled_effects("start_of_turn")
	assert(battle.player_hp == 75 and battle.battle_effects.is_empty(), "A one-shot heal must heal once and expire.")

	battle.player_hp = 40; battle.party_hp[0] = 40
	_schedule("repeat", "a", "user_battler", "end_of_turn", 0, 3, {"kind": "heal", "amount": 0.1})
	for turn in 3: battle._process_scheduled_effects("end_of_turn")
	assert(battle.player_hp == 70 and battle.battle_effects.is_empty(), "A multi-trigger heal must execute its repeat count and expire.")

	_schedule("damage", "a", "target_battler", "end_of_turn", 0, 1, {"kind": "damage", "amount": 0.2})
	battle._process_scheduled_effects("end_of_turn")
	assert(battle.opponent_hp == 80, "A delayed damage payload must damage its owner.")

	_schedule("stats", "a", "target_battler", "end_of_turn", 0, 1, {"kind": "stat_change", "stat": "defense", "amount": -0.2})
	battle._process_scheduled_effects("end_of_turn")
	assert(is_equal_approx(float(opponent["stat_modifiers"]["defense"]), 0.8), "A stat-change payload must alter the requested stat.")

	_schedule("status", "a", "target_battler", "end_of_turn", 0, 1, {"kind": "condition", "condition": "Burned", "chance": 1.0})
	battle._process_scheduled_effects("end_of_turn")
	assert(opponent["condition"] == "Burned", "A condition payload must apply its condition.")

	battle.player_hp = 50; battle.party_hp[0] = 50
	_schedule("delay", "a", "user_battler", "end_of_turn", 1, 1, {"kind": "heal", "amount": 0.1})
	battle._process_scheduled_effects("end_of_turn")
	assert(battle.player_hp == 50 and battle.battle_effects[0].remaining_delay == 0, "The first matching phase must consume a one-turn delay without activating.")
	battle._process_scheduled_effects("end_of_turn")
	assert(battle.player_hp == 60 and battle.battle_effects.is_empty(), "A delayed effect must activate on the following matching phase.")

	_schedule("seed", "after_move_effect", "target_battler", "end_of_turn", 0, 3, {"kind": "heal", "amount": 0.1})
	_schedule("prayer", "after_move_effect", "target_battler", "end_of_turn", 0, 1, {"kind": "heal", "amount": 0.2})
	assert(battle.battle_effects.size() == 1 and battle.battle_effects[0].effect_id == &"prayer", "The same owner and group must replace the prior instance.")
	_schedule("other", "unrelated", "target_battler", "end_of_turn", 0, 1, {"kind": "heal", "amount": 0.1})
	assert(battle.battle_effects.size() == 2, "Unrelated groups must coexist on one owner.")
	battle._clear_battle_effects()

	var requested: Array[String] = []
	battle.scheduled_effect_animation_requested.connect(func(id: String, _effect: String): requested.append(id))
	_schedule("animated", "a", "user_battler", "end_of_turn", 0, 1, {"kind": "heal", "amount": 0.1}, "prayer_heal")
	battle._process_scheduled_effects("end_of_turn")
	assert(requested == ["prayer_heal"], "An authored animation ID must be sent to the playback hook.")
	battle.player_hp = 50; battle.party_hp[0] = 50
	_schedule("missing", "a", "user_battler", "end_of_turn", 0, 1, {"kind": "heal", "amount": 0.1}, "missing_animation")
	battle._process_scheduled_effects("end_of_turn")
	assert(battle.player_hp == 60, "A missing animation must not block gameplay payload resolution.")

	battle.opponent_hp = 5; battle.opponent_party_hp[0] = 5
	_schedule("faint", "a", "target_battler", "end_of_turn", 0, 2, {"kind": "damage", "amount": 10})
	battle._process_scheduled_effects("end_of_turn")
	assert(battle.battle_effects.is_empty(), "Faint cleanup must remove battler-owned effects.")
	battle.opponent_hp = 50; battle.opponent_party_hp[0] = 50
	_schedule("switch", "a", "target_battler", "end_of_turn", 0, 2, {"kind": "heal", "amount": 0.1})
	battle._switch_opponent(1, false)
	assert(battle.battle_effects.is_empty(), "Switching must remove effects owned by the outgoing battler.")
	_schedule("battle", "field", "battle", "end_of_turn", 0, 2, {"kind": "damage", "amount": 1.0})
	assert(battle.battle_effects.size() == 1 and battle.battle_effects[0].owner == &"battle", "Battle ownership must be represented in the registry.")
	battle._end_battle("test")
	assert(battle.battle_effects.is_empty(), "Battle end must clear every effect.")

	assert(not battle.battle_data["moves"]["seed"]["scheduled_effect"].has("remaining_delay"), "Runtime counters must not be written into move data.")
	print("SCHEDULED_BATTLE_EFFECTS_TEST_PASSED")
	quit()


func _setup_battlers() -> void:
	player = {"name": "Player", "type": "Light", "gender": "Genderless", "max_hp": 100, "level": 10, "moves": ["prayer"]}
	opponent = {"name": "Opponent", "type": "Plant", "gender": "Genderless", "max_hp": 100, "level": 10, "moves": ["seed"]}
	var reserve := {"name": "Reserve", "type": "Plant", "gender": "Genderless", "max_hp": 100, "level": 10, "moves": ["seed"]}
	for mon in [player, opponent, reserve]: battle._ensure_condition_fields(mon)
	battle.player = player; battle.opponent = opponent
	battle.battle_party.assign([player]); battle.opponent_party.assign([opponent, reserve])
	battle.party_hp.assign([50]); battle.opponent_party_hp.assign([100, 100])
	battle.active_party_index = 0; battle.active_opponent_index = 0
	battle.player_hp = 50; battle.opponent_hp = 100


func _schedule(id: String, group: String, owner: String, trigger: String, delay: int, repeats: int, payload: Dictionary, animation := "") -> void:
	var move := {"name": id, "scheduled_effect": {"effect_id": id, "effect_group": group, "owner": owner, "trigger": trigger, "delay_turns": delay, "repeat_count": repeats, "stacking": "replace_group", "payload": payload, "animation_id": animation}}
	battle._create_scheduled_effect_from_move(move, player, opponent, true)
