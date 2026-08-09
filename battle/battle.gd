extends Control

signal battle_finished(player_won: bool, escaped: bool, captured_mon: Dictionary, experience_earned: int, experience_recipient: int, final_active_index: int, final_party_hp: Array[int], final_party_conditions: Array[Dictionary])
signal fakemon_selected(index: int)

const DATA_PATH := "res://data/battle_data.json"
const TYPE_EFFECTIVENESS := {
	"Fire": {"Plant": 2.0, "Fire": 0.5, "Water": 0.5},
	"Water": {"Fire": 2.0, "Water": 0.5, "Plant": 0.5, "Light": 0.5},
	"Plant": {"Water": 2.0, "Plant": 0.5, "Fire": 0.5, "Light": 2.0},
	"Light": {"Dark": 2.0, "Water": 2.0, "Plant": 0.5},
	"Dark": {"Light": 0.5},
	"Normal": {}
}

var battle_data: Dictionary
var player: Dictionary
var opponent: Dictionary
var player_hp: int
var opponent_hp: int
var battle_over := false
var player_won := false
var selecting_for_adventure := false
var is_wild_battle := false
var captured_mon: Dictionary = {}
var experience_earned := 0
var battle_party: Array[Dictionary] = []
var party_hp: Array[int] = []
var active_party_index := 0
var experience_recipient := -1
var forced_switch := false
var escaped := false
var run_attempts := 0
var current_move_ids: Array[String] = []

var selection_screen: Control
var battle_screen: Control
var player_name_label: Label
var opponent_name_label: Label
var player_hp_label: Label
var opponent_hp_label: Label
var player_hp_bar: ProgressBar
var opponent_hp_bar: ProgressBar
var player_square: ColorRect
var opponent_square: ColorRect
var message_panel: Panel
var message_label: Label
var move_menu: GridContainer
var action_panel: Panel
var action_button: Button
var capture_button: Button
var switch_button: Button
var run_button: Button
var switch_panel: PanelContainer
var switch_list: VBoxContainer
var restart_button: Button


func _ready() -> void:
	battle_data = _load_battle_data()
	if battle_data.is_empty():
		return
	_build_background()
	_build_selection_screen()
	_build_battle_screen()
	_show_selection()


func begin_battle_with_party(party_members: Array[Dictionary], starting_index: int, opponent_index: int, wild_battle: bool) -> void:
	selecting_for_adventure = false
	battle_party.clear()
	party_hp.clear()
	for mon: Dictionary in party_members:
		var battle_mon := mon.duplicate(true)
		_ensure_condition_fields(battle_mon)
		battle_party.append(battle_mon)
		party_hp.append(int(mon.get("current_hp", mon["max_hp"])))
	active_party_index = clampi(starting_index, 0, battle_party.size() - 1)
	player = battle_party[active_party_index]
	opponent = battle_data["fakemon"][opponent_index].duplicate(true)
	_ensure_condition_fields(opponent)
	is_wild_battle = wild_battle
	selection_screen.hide()
	battle_screen.show()
	show()
	_start_battle()


func begin_adventure_selection() -> void:
	selecting_for_adventure = true
	battle_over = true
	selection_screen.show()
	battle_screen.hide()
	show()


func _load_battle_data() -> Dictionary:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not open battle data at %s" % DATA_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Battle data is not valid JSON.")
		return {}
	var data := parsed as Dictionary
	if not _validate_fakemon_moves(data):
		return {}
	return data


func _validate_fakemon_moves(data: Dictionary) -> bool:
	for mon: Dictionary in data["fakemon"]:
		var move_ids: Array = mon.get("moves", [])
		if move_ids.size() < 1 or move_ids.size() > 6:
			push_error("%s must know between 1 and 6 moves." % mon.get("name", "Unnamed Fakemon"))
			return false
		for move_id: String in move_ids:
			if not data["moves"].has(move_id):
				push_error("%s references missing move '%s'." % [mon["name"], move_id])
				return false
			var damage_class := String(data["moves"][move_id].get("damage_class", ""))
			if damage_class != "Physical" and damage_class != "Special" and damage_class != "Status":
				push_error("Move '%s' must be Physical, Special, or Status." % move_id)
				return false
	return true


func _build_background() -> void:
	var background := ColorRect.new()
	background.color = Color("#d9ead3")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)


func _build_selection_screen() -> void:
	selection_screen = Control.new()
	selection_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(selection_screen)

	var title := Label.new()
	title.text = "CHOOSE YOUR FAKEMON"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("#203029"))
	title.position = Vector2(0, 18)
	title.size = Vector2(960, 45)
	selection_screen.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Each Fakemon can know between 1 and 6 moves."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.position = Vector2(0, 62)
	subtitle.size = Vector2(960, 30)
	subtitle.add_theme_color_override("font_color", Color("#31463b"))
	selection_screen.add_child(subtitle)

	var roster: Array = battle_data["fakemon"]
	for index in roster.size():
		var mon: Dictionary = roster[index]
		var card := Button.new()
		card.position = Vector2(65 + (index % 3) * 295, 105 + floori(float(index) / 3.0) * 205)
		card.size = Vector2(240, 180)
		card.pressed.connect(_on_fakemon_selected.bind(index))
		selection_screen.add_child(card)

		var square := ColorRect.new()
		square.color = Color(mon["color"])
		square.position = Vector2(14, 25)
		square.size = Vector2(90, 110)
		square.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(square)

		var placeholder := Label.new()
		placeholder.text = "FAKEMON\nPLACEHOLDER"
		placeholder.position = Vector2(3, 31)
		placeholder.size = Vector2(84, 50)
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		placeholder.add_theme_font_size_override("font_size", 12)
		placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		placeholder.clip_text = true
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		square.add_child(placeholder)

		var description := Label.new()
		description.text = "%s\nType: %s\nGender: %s\nMoves: %d" % [mon["name"], mon["type"], mon["gender"], mon["moves"].size()]
		description.position = Vector2(112, 23)
		description.size = Vector2(114, 135)
		description.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		description.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.clip_text = true
		description.add_theme_font_size_override("font_size", 13)
		description.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(description)

func _build_battle_screen() -> void:
	battle_screen = Control.new()
	battle_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(battle_screen)

	var title := Label.new()
	title.text = "PROJECT PARADISE — BATTLE TEST"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.position = Vector2(0, 18)
	title.size = Vector2(960, 40)
	battle_screen.add_child(title)

	var opponent_parts := _create_combatant_panel(Vector2(55, 80), Vector2(660, 95))
	opponent_name_label = opponent_parts["name"]
	opponent_hp_bar = opponent_parts["bar"]
	opponent_hp_label = opponent_parts["hp"]
	opponent_square = opponent_parts["square"]

	var player_parts := _create_combatant_panel(Vector2(510, 250), Vector2(240, 245))
	player_name_label = player_parts["name"]
	player_hp_bar = player_parts["bar"]
	player_hp_label = player_parts["hp"]
	player_square = player_parts["square"]

	message_panel = Panel.new()
	message_panel.position = Vector2(33, 385)
	message_panel.size = Vector2(600, 126)
	battle_screen.add_child(message_panel)

	message_label = Label.new()
	message_label.position = Vector2(20, 14)
	message_label.size = Vector2(560, 92)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.add_theme_font_size_override("font_size", 19)
	message_panel.add_child(message_label)

	move_menu = GridContainer.new()
	move_menu.columns = 2
	move_menu.position = Vector2(16, 10)
	move_menu.size = Vector2(568, 106)
	move_menu.add_theme_constant_override("h_separation", 8)
	move_menu.add_theme_constant_override("v_separation", 5)
	move_menu.hide()
	message_panel.add_child(move_menu)

	action_panel = Panel.new()
	action_panel.position = Vector2(648, 385)
	action_panel.size = Vector2(279, 126)
	battle_screen.add_child(action_panel)

	action_button = Button.new()
	action_button.text = "[1/A] Attack"
	action_button.position = Vector2(12, 12)
	action_button.size = Vector2(122, 42)
	action_button.add_theme_font_size_override("font_size", 18)
	action_button.pressed.connect(_on_attack_pressed)
	action_panel.add_child(action_button)

	capture_button = Button.new()
	capture_button.text = "[2/C] Capture"
	capture_button.position = Vector2(145, 12)
	capture_button.size = Vector2(122, 42)
	capture_button.pressed.connect(_on_capture_pressed)
	action_panel.add_child(capture_button)

	switch_button = Button.new()
	switch_button.text = "[3/S] Switch"
	switch_button.position = Vector2(12, 66)
	switch_button.size = Vector2(122, 42)
	switch_button.pressed.connect(_on_switch_pressed)
	action_panel.add_child(switch_button)

	run_button = Button.new()
	run_button.text = "[4/R] Run"
	run_button.position = Vector2(145, 66)
	run_button.size = Vector2(122, 42)
	run_button.pressed.connect(_on_run_pressed)
	action_panel.add_child(run_button)

	switch_panel = PanelContainer.new()
	switch_panel.position = Vector2(610, 125)
	switch_panel.size = Vector2(325, 245)
	switch_list = VBoxContainer.new()
	switch_panel.add_child(switch_list)
	switch_panel.hide()
	battle_screen.add_child(switch_panel)

	restart_button = Button.new()
	restart_button.text = "Return to Map"
	restart_button.position = Vector2(12, 35)
	restart_button.size = Vector2(255, 50)
	restart_button.pressed.connect(_on_return_pressed)
	restart_button.hide()
	switch_panel.hide()
	action_panel.add_child(restart_button)


func _create_combatant_panel(panel_position: Vector2, square_position: Vector2) -> Dictionary:
	var panel := Panel.new()
	panel.position = panel_position
	panel.size = Vector2(390, 115)
	battle_screen.add_child(panel)

	var name_label := Label.new()
	name_label.position = Vector2(18, 12)
	name_label.size = Vector2(350, 28)
	name_label.add_theme_font_size_override("font_size", 18)
	panel.add_child(name_label)

	var hp_caption := Label.new()
	hp_caption.text = "HP"
	hp_caption.position = Vector2(18, 48)
	hp_caption.size = Vector2(32, 25)
	panel.add_child(hp_caption)

	var hp_bar := ProgressBar.new()
	hp_bar.position = Vector2(52, 48)
	hp_bar.size = Vector2(315, 24)
	hp_bar.show_percentage = false
	panel.add_child(hp_bar)

	var hp_label := Label.new()
	hp_label.position = Vector2(52, 78)
	hp_label.size = Vector2(315, 25)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(hp_label)

	var square := ColorRect.new()
	square.position = square_position
	square.size = Vector2(125, 125)
	battle_screen.add_child(square)

	var placeholder := Label.new()
	placeholder.text = "FAKEMON\nPLACEHOLDER"
	placeholder.position = Vector2(5, 39)
	placeholder.size = Vector2(115, 50)
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	square.add_child(placeholder)

	return {"name": name_label, "bar": hp_bar, "hp": hp_label, "square": square}


func _on_fakemon_selected(index: int) -> void:
	if selecting_for_adventure:
		selecting_for_adventure = false
		hide()
		fakemon_selected.emit(index)
		return
	player = battle_data["fakemon"][index].duplicate(true)
	battle_party = [player]
	party_hp = [int(player["max_hp"])]
	active_party_index = 0
	opponent = battle_data["fakemon"].pick_random().duplicate(true)
	selection_screen.hide()
	battle_screen.show()
	_start_battle()


func _show_selection() -> void:
	battle_over = true
	selection_screen.show()
	battle_screen.hide()


func _start_battle() -> void:
	player_hp = party_hp[active_party_index]
	opponent_hp = int(opponent["max_hp"])
	battle_over = false
	player_won = false
	captured_mon = {}
	experience_earned = 0
	experience_recipient = -1
	forced_switch = false
	escaped = false
	run_attempts = 0
	player_name_label.text = "%s   Lv. %d   [%s]   SPD %d" % [player["name"], player["level"], player["type"], player["speed"]]
	opponent_name_label.text = "%s   Lv. %d   [%s]   SPD %d" % [opponent["name"], opponent["level"], opponent["type"], opponent["speed"]]
	player_square.color = Color(player["color"])
	opponent_square.color = Color(opponent["color"])
	action_button.text = "[1/A] Attack"
	action_button.show()
	capture_button.show()
	switch_button.show()
	run_button.show()
	action_button.disabled = false
	capture_button.disabled = false
	run_button.disabled = not is_wild_battle
	switch_button.disabled = _next_available_party_index() == -1
	_set_action_buttons_disabled(false)
	restart_button.hide()
	move_menu.hide()
	message_label.show()
	message_label.text = "A wild %s appeared! Choose an action." % opponent["name"]
	_update_hp_ui()


func _on_attack_pressed() -> void:
	if battle_over:
		return
	_show_move_menu()


func _show_move_menu() -> void:
	for child in move_menu.get_children():
		child.queue_free()
	current_move_ids.clear()
	for move_id: String in player["moves"]:
		current_move_ids.append(move_id)
		var move: Dictionary = battle_data["moves"][move_id]
		var choice := Button.new()
		var class_label: String = String({"Physical": "Phys", "Special": "Spec", "Status": "Status"}.get(String(move["damage_class"]), String(move["damage_class"])))
		choice.text = "[%d] %s | %s | %s%s" % [current_move_ids.size(), move["name"], move["type"], class_label, "" if int(move["power"]) == 0 else " | P%d" % move["power"]]
		choice.custom_minimum_size = Vector2(275, 28)
		choice.add_theme_font_size_override("font_size", 13)
		choice.pressed.connect(_on_move_selected.bind(move_id))
		move_menu.add_child(choice)
	message_label.hide()
	move_menu.show()
	_set_action_buttons_disabled(true)


func _on_move_selected(move_id: String) -> void:
	if battle_over or not battle_data["moves"].has(move_id):
		return
	move_menu.hide()
	message_label.show()
	var selected_move: Dictionary = battle_data["moves"][move_id]
	_set_action_buttons_disabled(true)
	if int(player["speed"]) >= int(opponent["speed"]):
		if _perform_player_attack(selected_move):
			return
		await get_tree().create_timer(0.6).timeout
		_perform_enemy_attack(true)
	else:
		if _perform_enemy_attack(false):
			return
		_set_action_buttons_disabled(true)
		await get_tree().create_timer(0.6).timeout
		if not _perform_player_attack(selected_move) and not _finish_turn_conditions():
			_set_action_buttons_disabled(false)


func _perform_player_attack(move: Dictionary) -> bool:
	if not _can_use_move(player):
		return false
	if String(move["damage_class"]) == "Status":
		message_label.text = "%s used %s!" % [player["name"], move["name"]]
		if bool(move.get("cures_conditions", false)):
			_cure_conditions(player)
		else:
			_try_inflict_condition(opponent, move, player, true)
		_apply_burn_after_move(true)
		_update_hp_ui()
		return _finish_turn_conditions() if player_hp == 0 else false
	var result := _calculate_damage(player, opponent, move)
	opponent_hp = maxi(0, opponent_hp - result["damage"])
	message_label.text = _attack_message(player, move, result)
	_try_inflict_condition(opponent, move, player, true)
	_apply_condemned_backlash(player, true, move)
	_apply_burn_after_move(true)
	_update_hp_ui()
	if opponent_hp == 0:
		return _finish_turn_conditions()
	if player_hp == 0:
		return _finish_turn_conditions()
	return false


func _perform_enemy_attack(end_turn: bool = true) -> bool:
	if battle_over:
		return true
	if not _can_use_move(opponent):
		if end_turn:
			if _finish_turn_conditions():
				return true
			_set_action_buttons_disabled(false)
		return false
	var opponent_move_ids: Array = opponent["moves"]
	var move: Dictionary = battle_data["moves"][opponent_move_ids.pick_random()]
	if String(move["damage_class"]) == "Status":
		message_label.text = "%s used %s!" % [opponent["name"], move["name"]]
		if bool(move.get("cures_conditions", false)):
			_cure_conditions(opponent)
		else:
			_try_inflict_condition(player, move, opponent, false)
		_apply_burn_after_move(false)
		_update_hp_ui()
		if end_turn:
			if _finish_turn_conditions():
				return true
			_set_action_buttons_disabled(false)
		return false
	var result := _calculate_damage(opponent, player, move)
	player_hp = maxi(0, player_hp - result["damage"])
	party_hp[active_party_index] = player_hp
	message_label.text = _attack_message(opponent, move, result)
	_try_inflict_condition(player, move, opponent, false)
	_apply_condemned_backlash(opponent, false, move)
	_apply_burn_after_move(false)
	_update_hp_ui()
	if player_hp == 0:
		return _finish_turn_conditions()
	if opponent_hp == 0:
		return _finish_turn_conditions()
	if end_turn:
		if _finish_turn_conditions():
			return true
		_set_action_buttons_disabled(false)
	return false


func _ensure_condition_fields(mon: Dictionary) -> void:
	mon["condition"] = String(mon.get("condition", ""))
	mon["condition_turns"] = int(mon.get("condition_turns", 0))
	mon["flinched"] = false
	mon["infatuation_stacks"] = 0
	mon["infatuation_source_gender"] = ""
	mon["infatuation_source_side"] = ""
	mon["infatuation_source_index"] = -1
	mon["light_exposed"] = false
	mon["dark_exposed"] = false


func _can_use_move(mon: Dictionary) -> bool:
	if bool(mon.get("flinched", false)):
		mon["flinched"] = false
		message_label.text = "%s flinched and couldn't move!" % mon["name"]
		return false
	var condition := String(mon.get("condition", ""))
	if condition == "Despairing" and randf() < float(battle_data["conditions"]["Despairing"]["move_failure_chance"]):
		message_label.text = "%s despaired and lost its turn!" % mon["name"]
		return false
	if condition == "Paralyzed" and randf() < float(battle_data["conditions"]["Paralyzed"]["move_failure_chance"]):
		message_label.text = "%s is paralyzed and couldn't move!" % mon["name"]
		return false
	if condition == "Frozen" or condition == "Asleep":
		mon["condition_turns"] = maxi(0, int(mon["condition_turns"]) - 1)
		var verb := "frozen solid" if condition == "Frozen" else "asleep"
		message_label.text = "%s is %s and cannot move!" % [mon["name"], verb]
		if int(mon["condition_turns"]) == 0:
			mon["condition"] = ""
			message_label.text += " It will recover next turn."
		return false
	var stacks := int(mon.get("infatuation_stacks", 0))
	if stacks > 0 and _genders_are_opposite(String(mon.get("gender", "Genderless")), String(mon.get("infatuation_source_gender", ""))):
		var failure_chance := float(battle_data["conditions"]["Infatuated"]["failure_chance_per_stack"]) * stacks
		if randf() < failure_chance:
			message_label.text = "%s ignored the command due to infatuation!" % mon["name"]
			return false
	return true


func _try_inflict_condition(target: Dictionary, move: Dictionary, source: Dictionary, source_is_player: bool) -> void:
	var condition := String(move.get("condition", ""))
	if condition.is_empty() or randf() >= float(move.get("condition_chance", 0.0)):
		return
	if condition == "Flinch":
		target["flinched"] = true
		message_label.text += " %s flinched!" % target["name"]
		return
	if condition == "Infatuated":
		var maximum := int(battle_data["conditions"]["Infatuated"]["maximum_stacks"])
		target["infatuation_stacks"] = mini(maximum, int(target.get("infatuation_stacks", 0)) + 1)
		target["infatuation_source_gender"] = String(source.get("gender", "Genderless"))
		target["infatuation_source_side"] = "player" if source_is_player else "opponent"
		target["infatuation_source_index"] = active_party_index if source_is_player else -1
		message_label.text += " %s gained Infatuation stack %d!" % [target["name"], target["infatuation_stacks"]]
		return
	if not String(target.get("condition", "")).is_empty():
		return
	target["condition"] = condition
	if condition == "Frozen" or condition == "Asleep":
		var condition_data: Dictionary = battle_data["conditions"][condition]
		target["condition_turns"] = randi_range(int(condition_data["minimum_turns"]), int(condition_data["maximum_turns"]))
	else:
		target["condition_turns"] = 0
	message_label.text += " %s became %s!" % [target["name"], condition.to_lower()]


func _genders_are_opposite(first: String, second: String) -> bool:
	return (first == "Male" and second == "Female") or (first == "Female" and second == "Male")


func _clear_infatuation(mon: Dictionary) -> void:
	mon["infatuation_stacks"] = 0
	mon["infatuation_source_gender"] = ""
	mon["infatuation_source_side"] = ""
	mon["infatuation_source_index"] = -1


func _cure_conditions(mon: Dictionary) -> void:
	var old_condition := String(mon.get("condition", ""))
	var old_stacks := int(mon.get("infatuation_stacks", 0))
	if old_condition == "Condemned":
		mon["light_exposed"] = true
	elif old_condition == "Despairing":
		mon["dark_exposed"] = true
	mon["condition"] = ""
	mon["condition_turns"] = 0
	mon["flinched"] = false
	_clear_infatuation(mon)
	if old_condition.is_empty() and old_stacks == 0:
		message_label.text += " But there were no conditions to remove."
	else:
		message_label.text += " Its special conditions were removed."


func _apply_condemned_backlash(mon: Dictionary, player_side: bool, move: Dictionary) -> void:
	if String(mon.get("condition", "")) != "Condemned" or String(move["damage_class"]) != "Special":
		return
	var condition_data: Dictionary = battle_data["conditions"]["Condemned"]
	var level := float(mon["level"])
	var power := float(condition_data["backlash_power"])
	var special_attack := float(mon["special_attack"])
	var special_defense := maxf(1.0, float(mon["special_defense"]) * float(condition_data["special_defense_multiplier"]))
	var damage := maxi(1, int(floor(((((2.0 * level / 5.0 + 2.0) * power * special_attack / special_defense) / 50.0) + 2.0))))
	if player_side:
		player_hp = maxi(0, player_hp - damage)
		party_hp[active_party_index] = player_hp
	else:
		opponent_hp = maxi(0, opponent_hp - damage)
	message_label.text += " Condemnation dealt %d damage to %s." % [damage, mon["name"]]


func _apply_burn_after_move(player_side: bool) -> void:
	var mon := player if player_side else opponent
	if String(mon.get("condition", "")) != "Burned":
		return
	var damage_fraction := float(battle_data["conditions"]["Burned"]["post_move_hp_fraction"])
	var damage := maxi(1, int(floor(float(mon["max_hp"]) * damage_fraction)))
	if player_side:
		player_hp = maxi(0, player_hp - damage)
		party_hp[active_party_index] = player_hp
	else:
		opponent_hp = maxi(0, opponent_hp - damage)
	message_label.text += " %s lost %d HP from its burn." % [mon["name"], damage]


func _finish_turn_conditions() -> bool:
	if String(player.get("condition", "")) == "Poisoned" and player_hp > 0:
		var poison_fraction := float(battle_data["conditions"]["Poisoned"]["end_turn_hp_fraction"])
		var player_damage := maxi(1, int(floor(float(player["max_hp"]) * poison_fraction)))
		player_hp = maxi(0, player_hp - player_damage)
		party_hp[active_party_index] = player_hp
		message_label.text += " %s lost %d HP from poison." % [player["name"], player_damage]
	if String(opponent.get("condition", "")) == "Poisoned" and opponent_hp > 0:
		var poison_fraction := float(battle_data["conditions"]["Poisoned"]["end_turn_hp_fraction"])
		var opponent_damage := maxi(1, int(floor(float(opponent["max_hp"]) * poison_fraction)))
		opponent_hp = maxi(0, opponent_hp - opponent_damage)
		message_label.text += " %s lost %d HP from poison." % [opponent["name"], opponent_damage]
	_update_hp_ui()
	if opponent_hp == 0:
		player_won = true
		experience_earned = _calculate_experience_reward()
		experience_recipient = active_party_index
		_end_battle("%s fainted. You win! Earned %d EXP." % [opponent["name"], experience_earned])
		return true
	if player_hp == 0:
		return _handle_player_faint()
	return false


func _enemy_turn() -> void:
	_perform_enemy_attack()


func _handle_player_faint() -> bool:
	if String(opponent.get("infatuation_source_side", "")) == "player" and int(opponent.get("infatuation_source_index", -1)) == active_party_index:
		_clear_infatuation(opponent)
	var next_index := _next_available_party_index()
	if next_index == -1:
		_end_battle("Every party member has fainted. You lose!")
		return true
	forced_switch = true
	action_button.disabled = true
	capture_button.disabled = true
	run_button.disabled = true
	switch_button.disabled = false
	switch_button.text = "[3/S] Switch!"
	message_label.text += "\n%s fainted. Switch to a conscious party member." % player["name"]
	return true


func _on_switch_pressed() -> void:
	if battle_over or (String(player.get("condition", "")) == "Paralyzed" and not forced_switch):
		return
	_show_switch_choices()


func _show_switch_choices() -> void:
	for child in switch_list.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = "Choose a conscious Fakemon"
	switch_list.add_child(title)
	for index in battle_party.size():
		var mon: Dictionary = battle_party[index]
		var choice := Button.new()
		var status := _condition_display(mon)
		choice.text = "[%d] %s  Lv.%d  HP %d/%d  %s" % [index + 1, mon["name"], mon["level"], party_hp[index], mon["max_hp"], status]
		choice.disabled = index == active_party_index or party_hp[index] <= 0
		choice.pressed.connect(_select_battle_party_mon.bind(index))
		switch_list.add_child(choice)
	switch_panel.show()
	action_button.disabled = true
	capture_button.disabled = true


func _select_battle_party_mon(next_index: int) -> void:
	if next_index < 0 or next_index >= battle_party.size() or party_hp[next_index] <= 0 or next_index == active_party_index:
		return
	var was_forced := forced_switch
	player["light_exposed"] = false
	player["dark_exposed"] = false
	active_party_index = next_index
	player = battle_party[active_party_index]
	player_hp = party_hp[active_party_index]
	forced_switch = false
	switch_button.text = "[3/S] Switch"
	switch_panel.hide()
	_update_active_player_ui()
	message_label.text = "Go, %s!" % player["name"]
	_set_action_buttons_disabled(false)
	if not was_forced:
		_set_action_buttons_disabled(true)
		await get_tree().create_timer(0.6).timeout
		_enemy_turn()


func _next_available_party_index() -> int:
	for offset in range(1, battle_party.size()):
		var candidate := (active_party_index + offset) % battle_party.size()
		if party_hp[candidate] > 0:
			return candidate
	return -1


func _set_action_buttons_disabled(disabled: bool) -> void:
	var paralyzed := String(player.get("condition", "")) == "Paralyzed"
	action_button.disabled = disabled
	capture_button.disabled = disabled
	switch_button.disabled = disabled or _next_available_party_index() == -1 or (paralyzed and not forced_switch)
	run_button.disabled = disabled or not is_wild_battle or paralyzed


func _on_capture_pressed() -> void:
	if battle_over:
		return
	_set_action_buttons_disabled(true)
	if not is_wild_battle:
		message_label.text = "You cannot capture another trainer's Fakemon! Your action was used."
		await get_tree().create_timer(0.8).timeout
		_enemy_turn()
		return
	var hp_factor := 1.0 - (float(opponent_hp) / float(opponent["max_hp"])) * 0.66
	var capture_chance := clampf((float(opponent["catch_rate"]) / 255.0) * hp_factor, 0.02, 0.95)
	if randf() <= capture_chance:
		captured_mon = opponent.duplicate(true)
		captured_mon["experience"] = int(pow(float(captured_mon["level"]), 3.0))
		captured_mon["current_hp"] = opponent_hp
		player_won = true
		_end_battle("Captured %s!" % opponent["name"])
		return
	message_label.text = "%s broke free! Your action was used." % opponent["name"]
	await get_tree().create_timer(0.8).timeout
	_enemy_turn()


func _on_run_pressed() -> void:
	if battle_over or not is_wild_battle or String(player.get("condition", "")) == "Paralyzed":
		return
	_set_action_buttons_disabled(true)
	run_attempts += 1
	var escape_score := int(float(player["speed"]) * 128.0 / maxf(1.0, float(opponent["speed"]))) + 30 * run_attempts
	if escape_score > randi_range(0, 255):
		escaped = true
		_end_battle("Got away safely!")
		return
	message_label.text = "Couldn't escape! The wild Fakemon gets its turn."
	await get_tree().create_timer(0.8).timeout
	_enemy_turn()


func _calculate_experience_reward() -> int:
	return maxi(1, int(float(opponent["base_exp"]) * float(opponent["level"]) / 7.0))


func _calculate_damage(attacker: Dictionary, defender: Dictionary, move: Dictionary) -> Dictionary:
	var level := float(attacker["level"])
	var burn_data: Dictionary = battle_data["conditions"]["Burned"]
	var is_physical := String(move["damage_class"]) == "Physical"
	var attack := float(attacker["attack"] if is_physical else attacker["special_attack"])
	var defense := float(defender["defense"] if is_physical else defender["special_defense"])
	var infatuation_stacks := int(attacker.get("infatuation_stacks", 0))
	if String(attacker.get("gender", "Genderless")) == "Genderless" and infatuation_stacks > 0:
		var penalty_per_stack := float(battle_data["conditions"]["Infatuated"]["genderless_attack_multiplier_per_stack"])
		attack *= maxf(0.0, 1.0 - penalty_per_stack * infatuation_stacks)
	if is_physical and String(attacker.get("condition", "")) == "Burned":
		attack *= float(burn_data["attack_multiplier"])
	if is_physical and String(defender.get("condition", "")) == "Burned":
		defense *= float(burn_data["defense_multiplier"])
	if not is_physical and String(defender.get("condition", "")) == "Condemned":
		defense *= float(battle_data["conditions"]["Condemned"]["special_defense_multiplier"])
	defense = maxf(1.0, defense)
	var power := float(move["power"])
	var base_damage := (((2.0 * level / 5.0 + 2.0) * power * attack / defense) / 50.0) + 2.0
	var stab := 1.5 if move["type"] == attacker["type"] else 1.0
	var effectiveness := _get_type_effectiveness(move["type"], defender["type"])
	if String(move["type"]) == "Light" and bool(defender.get("light_exposed", false)):
		effectiveness *= 2.0
	if String(move["type"]) == "Dark" and bool(defender.get("dark_exposed", false)):
		effectiveness *= 2.0
	var random_modifier := randf_range(0.85, 1.0)
	var damage := maxi(1, int(floor(base_damage * stab * effectiveness * random_modifier)))
	return {"damage": damage, "effectiveness": effectiveness}


func _get_type_effectiveness(move_type: String, defender_type: String) -> float:
	var attack_chart: Dictionary = TYPE_EFFECTIVENESS.get(move_type, {})
	return float(attack_chart.get(defender_type, 1.0))


func _attack_message(attacker: Dictionary, move: Dictionary, result: Dictionary) -> String:
	var text := "%s used %s! It dealt %d damage." % [attacker["name"], move["name"], result["damage"]]
	if result["effectiveness"] > 1.0:
		text += " It's super effective!"
	elif result["effectiveness"] < 1.0:
		text += " It's not very effective."
	return text


func _update_hp_ui() -> void:
	player_hp_bar.max_value = player["max_hp"]
	player_hp_bar.value = player_hp
	var current_exp := int(player.get("experience", int(pow(float(player["level"]), 3.0))))
	var next_exp := int(pow(float(int(player["level"]) + 1), 3.0))
	var player_status := _condition_display(player)
	player_hp_label.text = "%d / %d    EXP %d / %d    %s" % [player_hp, player["max_hp"], current_exp, next_exp, player_status]
	opponent_hp_bar.max_value = opponent["max_hp"]
	opponent_hp_bar.value = opponent_hp
	var opponent_status := _condition_display(opponent)
	opponent_hp_label.text = "%d / %d    %s" % [opponent_hp, opponent["max_hp"], opponent_status]


func _condition_display(mon: Dictionary) -> String:
	var parts: Array[String] = []
	var condition := String(mon.get("condition", ""))
	if not condition.is_empty():
		parts.append(condition)
	var stacks := int(mon.get("infatuation_stacks", 0))
	if stacks > 0:
		parts.append("Infatuated x%d" % stacks)
	if bool(mon.get("light_exposed", false)):
		parts.append("Light-weak")
	if bool(mon.get("dark_exposed", false)):
		parts.append("Dark-weak")
	return "Healthy" if parts.is_empty() else ", ".join(parts)


func _update_active_player_ui() -> void:
	var condition_text := "" if String(player.get("condition", "")).is_empty() else "   {%s}" % player["condition"]
	player_name_label.text = "%s   Lv. %d   [%s]   SPD %d%s" % [player["name"], player["level"], player["type"], player["speed"], condition_text]
	player_square.color = Color(player["color"])
	action_button.text = "[1/A] Attack"
	_update_hp_ui()


func _input(event: InputEvent) -> void:
	if not visible or battle_screen == null or not battle_screen.visible or not event is InputEventKey:
		return
	if not event.pressed or event.echo:
		return
	var key_event := event as InputEventKey
	var key: Key = key_event.keycode
	if battle_over:
		if key == KEY_ENTER or key == KEY_ESCAPE:
			_on_return_pressed()
		return
	var number := _number_from_key(key)
	if move_menu.visible:
		if number >= 1 and number <= current_move_ids.size():
			_on_move_selected(current_move_ids[number - 1])
		elif key == KEY_ESCAPE:
			move_menu.hide()
			message_label.show()
			_set_action_buttons_disabled(false)
		return
	if switch_panel.visible:
		if number >= 1 and number <= battle_party.size():
			_select_battle_party_mon(number - 1)
		elif key == KEY_ESCAPE and not forced_switch:
			switch_panel.hide()
			_set_action_buttons_disabled(false)
		return
	if (number == 1 or key == KEY_A) and not action_button.disabled:
		_on_attack_pressed()
	elif (number == 2 or key == KEY_C) and not capture_button.disabled:
		_on_capture_pressed()
	elif (number == 3 or key == KEY_S) and not switch_button.disabled:
		_on_switch_pressed()
	elif (number == 4 or key == KEY_R) and not run_button.disabled:
		_on_run_pressed()


func _number_from_key(key: Key) -> int:
	if key >= KEY_1 and key <= KEY_7:
		return int(key - KEY_1) + 1
	return 0


func _end_battle(result: String) -> void:
	battle_over = true
	action_button.disabled = true
	capture_button.disabled = true
	switch_button.disabled = true
	run_button.disabled = true
	action_button.hide()
	capture_button.hide()
	switch_button.hide()
	run_button.hide()
	move_menu.hide()
	message_label.show()
	switch_panel.hide()
	restart_button.show()
	message_label.text += "\n" + result


func _on_return_pressed() -> void:
	hide()
	var final_conditions: Array[Dictionary] = []
	for mon: Dictionary in battle_party:
		var condition := String(mon.get("condition", ""))
		final_conditions.append({"condition": "" if condition == "Flinch" else condition, "condition_turns": int(mon.get("condition_turns", 0))})
	battle_finished.emit(player_won, escaped, captured_mon, experience_earned, experience_recipient, active_party_index, party_hp, final_conditions)
