extends Control

signal battle_finished(player_won: bool, escaped: bool, captured_mon: Dictionary, experience_earned: int, experience_recipients: Array[int], final_active_index: int, final_party_hp: Array[int], final_party_conditions: Array[Dictionary])
signal fakemon_selected(index: int)

const DATA_PATH := "res://data/battle_data.json"
const EVOLVED_DATA_PATH := "res://data/evolved_fakemon.json"
const EGG_GROUP_DATA_PATH := "res://data/egg_groups.json"
const BATTLE_BACKGROUND := preload("res://assets/battle/battle_background.png")
const OPPONENT_ART_POSITION := Vector2(610, 115)
const PLAYER_ART_POSITION := Vector2(245, 260)
const DEFAULT_BATTLE_ART_SIZE := Vector2(125, 125)
const MAX_BATTLE_ART_DIMENSION := 200.0
const MAX_POSITIVE_STAT_MODIFIER := 1.9
const NEUTRAL_STAT_MODIFIER := 1.0
const COMBAT_STATS := ["attack", "defense", "special_attack", "special_defense", "speed"]
const TYPE_EFFECTIVENESS := {
	"Fire": {"Plant": 2.0, "Fire": 0.5, "Water": 0.5, "Air": 2.0, "Bug": 2.0},
	"Water": {"Fire": 2.0, "Water": 0.5, "Plant": 0.5, "Light": 0.5},
	"Plant": {"Water": 2.0, "Plant": 0.5, "Fire": 0.5, "Light": 2.0, "Air": 2.0, "Bug": 0.5},
	"Light": {"Dark": 2.0, "Water": 2.0, "Plant": 0.5, "Bug": 0.5, "Ghost": 2.0, "Psychic": 2.0},
	"Dark": {"Light": 0.5, "Bug": 0.5, "Ghost": 2.0, "Psychic": 2.0},
	"Normal": {"Bug": 2.0, "Ghost": 0.5, "Psychic": 0.5},
	"Air": {"Fire": 2.0, "Plant": 0.5, "Bug": 2.0},
	"Bug": {"Fire": 0.5, "Plant": 2.0, "Normal": 0.5, "Light": 2.0, "Dark": 2.0, "Air": 0.5},
	"Mystic": {},
	"Ghost": {"Normal": 0.5, "Light": 0.5, "Dark": 0.5, "Psychic": 2.0},
	"Psychic": {"Normal": 2.0, "Light": 0.5, "Dark": 0.5, "Ghost": 0.5}
}

var battle_data: Dictionary
var player: Dictionary
var opponent: Dictionary
var opponent_party: Array[Dictionary] = []
var opponent_party_hp: Array[int] = []
var active_opponent_index := 0
var opponent_was_replaced_this_action := false
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
var participating_party_indices: Array[int] = []
var forced_switch := false
var escaped := false
var run_attempts := 0
var current_move_ids: Array[String] = []
var weather := ""
var weather_turns_remaining := 0

var selection_screen: Control
var battle_screen: Control
var player_name_label: Label
var opponent_name_label: Label
var player_hp_label: Label
var opponent_hp_label: Label
var player_hp_bar: ProgressBar
var opponent_hp_bar: ProgressBar
var player_square: TextureRect
var opponent_square: TextureRect
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
	begin_battle_with_opponent_party(party_members, starting_index, [opponent_index], wild_battle)


func begin_battle_with_opponent_party(party_members: Array[Dictionary], starting_index: int, opponent_indices: Array, wild_battle: bool) -> void:
	if opponent_indices.is_empty() or opponent_indices.size() > 7:
		push_error("Enemy parties must contain between 1 and 7 Fakemon indices.")
		return
	var enemy_members: Array[Dictionary] = []
	for opponent_index: Variant in opponent_indices:
		var index := int(opponent_index)
		if index >= 0 and index < battle_data["fakemon"].size():
			enemy_members.append(create_fakemon(battle_data["fakemon"][index]))
	begin_battle_with_enemy_party(party_members, starting_index, enemy_members, wild_battle)


func begin_battle_with_enemy_party(party_members: Array[Dictionary], starting_index: int, enemy_members: Array[Dictionary], wild_battle: bool) -> void:
	if enemy_members.is_empty() or enemy_members.size() > 7:
		push_error("Enemy parties must contain between 1 and 7 Fakemon.")
		return
	if wild_battle and enemy_members.size() != 1:
		push_error("Wild battles currently support exactly one opposing Fakemon.")
		return
	selecting_for_adventure = false
	battle_party.clear()
	party_hp.clear()
	for mon: Dictionary in party_members:
		var battle_mon := mon.duplicate(true)
		_ensure_gender(battle_mon)
		_ensure_condition_fields(battle_mon)
		battle_party.append(battle_mon)
		party_hp.append(int(mon.get("current_hp", mon["max_hp"])))
	active_party_index = clampi(starting_index, 0, battle_party.size() - 1)
	participating_party_indices = [active_party_index]
	player = battle_party[active_party_index]
	opponent_party.clear()
	opponent_party_hp.clear()
	for enemy: Dictionary in enemy_members:
		var battle_enemy := enemy.duplicate(true)
		_ensure_gender(battle_enemy)
		_ensure_condition_fields(battle_enemy)
		opponent_party.append(battle_enemy)
		opponent_party_hp.append(int(enemy.get("current_hp", enemy["max_hp"])))
	active_opponent_index = 0
	opponent = opponent_party[active_opponent_index]
	is_wild_battle = wild_battle
	weather = ""
	weather_turns_remaining = 0
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
	if not _append_evolved_fakemon(data):
		return {}
	if not _append_egg_groups(data):
		return {}
	if not _validate_fakemon_moves(data):
		return {}
	return data


func _append_evolved_fakemon(data: Dictionary) -> bool:
	var file := FileAccess.open(EVOLVED_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not open evolved Fakemon data at %s" % EVOLVED_DATA_PATH)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		push_error("Evolved Fakemon data is not valid JSON.")
		return false
	var species_by_name := {}
	for species: Dictionary in data["fakemon"]:
		species_by_name[String(species["name"])] = species
	for evolved: Dictionary in parsed:
		var previous_name := String(evolved.get("evolves_from", ""))
		if not species_by_name.has(previous_name):
			push_error("%s references missing prior evolution '%s'." % [evolved.get("name", "Unnamed Fakemon"), previous_name])
			return false
		if int(evolved.get("evolution_level", 0)) < 1:
			push_error("%s must define a positive evolution level." % evolved.get("name", "Unnamed Fakemon"))
			return false
		var source_name := String(evolved.get("moveset_source", ""))
		if not species_by_name.has(source_name):
			push_error("%s references missing moveset source '%s'." % [evolved.get("name", "Unnamed Fakemon"), source_name])
			return false
		var source: Dictionary = species_by_name[source_name]
		evolved["moves"] = source["moves"].duplicate(true)
		evolved["learnset"] = source.get("learnset", []).duplicate(true)
		data["fakemon"].append(evolved)
		species_by_name[String(evolved["name"])] = evolved
	return true


func _append_egg_groups(data: Dictionary) -> bool:
	var file := FileAccess.open(EGG_GROUP_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not open egg group data at %s" % EGG_GROUP_DATA_PATH)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Egg group data is not valid JSON.")
		return false
	var egg_group_data := parsed as Dictionary
	var catalog: Array = egg_group_data.get("groups", [])
	var default_groups: Array = egg_group_data.get("default_groups", [])
	var assignments: Dictionary = egg_group_data.get("assignments", {})
	if catalog.is_empty() or default_groups.size() != 2:
		push_error("Egg group data must define a catalog and two default groups.")
		return false
	data["egg_group_catalog"] = catalog.duplicate(true)
	for species: Dictionary in data["fakemon"]:
		species["egg_groups"] = assignments.get(String(species["name"]), default_groups).duplicate(true)
	return true


func create_fakemon(species: Dictionary) -> Dictionary:
	var mon := species.duplicate(true)
	_ensure_gender(mon)
	return mon


func _ensure_gender(mon: Dictionary) -> void:
	if mon.has("gender"):
		return
	var ratio: Variant = mon.get("male_ratio")
	mon["gender"] = "Genderless" if ratio == null else ("Male" if randf() < clampf(float(ratio), 0.0, 1.0) else "Female")


func _gender_ratio_display(species: Dictionary) -> String:
	var ratio: Variant = species.get("male_ratio")
	if ratio == null:
		return "Genderless"
	return "%d%% male" % roundi(clampf(float(ratio), 0.0, 1.0) * 100.0)


func _validate_fakemon_moves(data: Dictionary) -> bool:
	var egg_group_catalog: Array = data.get("egg_group_catalog", [])
	if egg_group_catalog.is_empty():
		push_error("Battle data must define an egg group catalog.")
		return false
	for mon: Dictionary in data["fakemon"]:
		var egg_groups: Array = mon.get("egg_groups", [])
		if egg_groups.size() != 2:
			push_error("%s must define exactly two egg groups." % mon.get("name", "Unnamed Fakemon"))
			return false
		for egg_group: Variant in egg_groups:
			if not egg_group_catalog.has(String(egg_group)):
				push_error("%s references unknown egg group '%s'." % [mon.get("name", "Unnamed Fakemon"), egg_group])
				return false
		if not mon.has("male_ratio"):
			push_error("%s must define a male gender ratio or null for Genderless." % mon.get("name", "Unnamed Fakemon"))
			return false
		var ratio: Variant = mon["male_ratio"]
		if ratio != null and (float(ratio) < 0.0 or float(ratio) > 1.0):
			push_error("%s's male gender ratio must be between 0 and 1." % mon.get("name", "Unnamed Fakemon"))
			return false
		var mon_types := _fakemon_types(mon)
		if mon_types.is_empty() or mon_types.size() > 2:
			push_error("%s must have one or two types." % mon.get("name", "Unnamed Fakemon"))
			return false
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
		for learn_entry: Dictionary in mon.get("learnset", []):
			var learned_move_id := String(learn_entry.get("move", ""))
			if not data["moves"].has(learned_move_id) or int(learn_entry.get("level", 0)) < 1:
				push_error("%s has an invalid learnset entry for '%s'." % [mon["name"], learned_move_id])
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
	# Because the starters are the first three entries in the dex, this works:
	for index in 3:
		var mon: Dictionary = roster[index]
		var card := Button.new()
		card.position = Vector2(65 + (index % 3) * 295, 105 + floori(float(index) / 3.0) * 205)
		card.size = Vector2(240, 180)
		card.pressed.connect(_on_fakemon_selected.bind(index))
		selection_screen.add_child(card)

		var square := _create_fakemon_art(mon, "Player", Vector2(90, 110))
		square.position = Vector2(14, 25)
		square.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(square)

		var description := Label.new()
		description.text = "%s\nType: %s\nGender: %s\nMoves: %d" % [mon["name"], _type_display(mon), _gender_ratio_display(mon), mon["moves"].size()]
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

	var background := TextureRect.new()
	background.name = "BattleBackgroundArt"
	background.texture = BATTLE_BACKGROUND
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	battle_screen.add_child(background)

	var title := Label.new()
	title.text = "PROJECT PARADISE — BATTLE TEST"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.position = Vector2(0, 18)
	title.size = Vector2(960, 40)
	battle_screen.add_child(title)

	var opponent_parts := _create_combatant_panel(Vector2(55, 80), OPPONENT_ART_POSITION)
	opponent_name_label = opponent_parts["name"]
	opponent_hp_bar = opponent_parts["bar"]
	opponent_hp_label = opponent_parts["hp"]
	opponent_square = opponent_parts["square"]

	var player_parts := _create_combatant_panel(Vector2(510, 250), PLAYER_ART_POSITION)
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

	var square := _create_fakemon_art({}, "Wild", DEFAULT_BATTLE_ART_SIZE)
	square.position = square_position
	square.set_meta("battle_art_anchor", square_position + Vector2(DEFAULT_BATTLE_ART_SIZE.x * 0.5, DEFAULT_BATTLE_ART_SIZE.y))
	battle_screen.add_child(square)

	return {"name": name_label, "bar": hp_bar, "hp": hp_label, "square": square}


func _on_fakemon_selected(index: int) -> void:
	if selecting_for_adventure:
		selecting_for_adventure = false
		hide()
		fakemon_selected.emit(index)
		return
	player = create_fakemon(battle_data["fakemon"][index])
	battle_party = [player]
	party_hp = [int(player["max_hp"])]
	active_party_index = 0
	participating_party_indices = [0]
	opponent = create_fakemon(battle_data["fakemon"].pick_random())
	_ensure_condition_fields(opponent)
	opponent_party.clear()
	opponent_party.append(opponent)
	opponent_party_hp.clear()
	opponent_party_hp.append(int(opponent["max_hp"]))
	active_opponent_index = 0
	selection_screen.hide()
	battle_screen.show()
	_start_battle()


func _show_selection() -> void:
	battle_over = true
	selection_screen.show()
	battle_screen.hide()


func _start_battle() -> void:
	player_hp = party_hp[active_party_index]
	opponent_hp = opponent_party_hp[active_opponent_index] if not opponent_party_hp.is_empty() else int(opponent["max_hp"])
	battle_over = false
	player_won = false
	captured_mon = {}
	experience_earned = 0
	forced_switch = false
	escaped = false
	run_attempts = 0
	player_name_label.text = "%s   Lv. %d   [%s]   %s" % [player["name"], player["level"], _type_display(player), player["gender"]]
	_update_active_opponent_ui()
	_set_fakemon_art(player_square, player, "Player")
	_set_fakemon_art(opponent_square, opponent, "Wild")
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
	if String(player.get("condition", "")) == "Confusion":
		var random_move_id := _choose_confused_move_id(player)
		if random_move_id.is_empty():
			message_label.text = "%s is confused, but has no usable move! " % player["name"]
			return
		message_label.text = "%s is confused and chose a move at random! " % player["name"]
		_resolve_player_move(random_move_id)
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
		choice.disabled = not _is_move_selectable(player, move_id)
		if choice.disabled:
			choice.tooltip_text = _move_unavailable_reason(player, move_id)
		move_menu.add_child(choice)
	message_label.hide()
	move_menu.show()
	_set_action_buttons_disabled(true)


func _on_move_selected(move_id: String) -> void:
	if battle_over or not battle_data["moves"].has(move_id) or not _is_move_selectable(player, move_id):
		return
	if bool(battle_data["moves"][move_id].get("calls_another_move", false)) and not bool(battle_data["moves"][move_id].get("copies_opponent_last_move", false)):
		_show_called_move_menu(move_id)
		return
	_resolve_player_move(move_id)


func _show_called_move_menu(caller_id: String) -> void:
	for child in move_menu.get_children():
		child.queue_free()
	var available: Array[String] = []
	for learn_entry: Dictionary in player.get("learnset", []):
		if int(learn_entry.get("level", 1)) > int(player["level"]):
			continue
		var candidate_id := String(learn_entry.get("move", ""))
		if candidate_id == caller_id or player["moves"].has(candidate_id) or not battle_data["moves"].has(candidate_id):
			continue
		if bool(battle_data["moves"][candidate_id].get("calls_another_move", false)):
			continue
		available.append(candidate_id)
	if available.is_empty():
		move_menu.hide()
		message_label.show()
		message_label.text = "%s used %s, but it could not recall an eligible move! " % [player["name"], battle_data["moves"][caller_id]["name"]]
		_record_successful_move(player, caller_id)
		await get_tree().create_timer(0.6).timeout
		_enemy_turn()
		return
	for candidate_id: String in available:
		var candidate: Dictionary = battle_data["moves"][candidate_id]
		var choice := Button.new()
		choice.text = "%s | %s | %s" % [candidate["name"], candidate["type"], candidate["damage_class"]]
		choice.pressed.connect(_on_called_move_selected.bind(caller_id, candidate_id))
		move_menu.add_child(choice)


func _on_called_move_selected(caller_id: String, called_move_id: String) -> void:
	_resolve_player_move(called_move_id, caller_id)


func _resolve_player_move(move_id: String, spent_move_id: String = "") -> void:
	move_menu.hide()
	message_label.show()
	var selected_move: Dictionary = battle_data["moves"][move_id]
	if spent_move_id.is_empty():
		spent_move_id = move_id
	opponent_was_replaced_this_action = false
	_set_action_buttons_disabled(true)
	var enemy_move_id := _choose_enemy_move_id()
	var player_priority := int(selected_move.get("priority", 0))
	var enemy_priority := int(battle_data["moves"][enemy_move_id].get("priority", 0))
	var player_goes_first := player_priority > enemy_priority or (player_priority == enemy_priority and _effective_stat(player, "speed") >= _effective_stat(opponent, "speed"))
	if player_goes_first:
		if _perform_player_attack(selected_move, spent_move_id):
			return
		await get_tree().create_timer(0.6).timeout
		_perform_enemy_attack(true, enemy_move_id)
	else:
		if _perform_enemy_attack(false, enemy_move_id):
			return
		_set_action_buttons_disabled(true)
		await get_tree().create_timer(0.6).timeout
		if not _perform_player_attack(selected_move, spent_move_id) and not _finish_turn_conditions():
			_set_action_buttons_disabled(false)


func _perform_player_attack(move: Dictionary, move_id: String = "") -> bool:
	if not _can_use_move(player):
		return false
	if move_id.is_empty():
		move_id = _move_id_for(move)
	_record_successful_move(player, move_id)
	if bool(move.get("copies_opponent_last_move", false)):
		var copied_move := _copy_last_move(opponent)
		if copied_move.is_empty():
			message_label.text = "%s used %s, but it failed because the foe had no valid last move! " % [player["name"], move["name"]]
			return false
		message_label.text = "%s used Mimic and copied %s! " % [player["name"], copied_move["name"]]
		move = copied_move
	if bool(move.get("random_party_switch", false)) and _available_random_switch_indices().is_empty():
		message_label.text = "%s used %s, but it failed because no other conscious party member could switch in! " % [player["name"], move["name"]]
		_apply_burn_after_move(true)
		_update_hp_ui()
		return _finish_turn_conditions() if player_hp == 0 else false
	if String(move["damage_class"]) == "Status":
		message_label.text += "%s used %s!" % [player["name"], move["name"]]
		if bool(move.get("force_random_opponent_switch", false)):
			if _apply_whirlwind(true):
				return true
			_apply_burn_after_move(true)
			return false
		_apply_status_move(player, opponent, move, true)
		_apply_burn_after_move(true)
		_update_hp_ui()
		return _finish_turn_conditions() if player_hp == 0 else false
	var result := _calculate_damage(player, opponent, move)
	if bool(opponent.get("protected", false)):
		result["damage"] = 0
		message_label.text = "%s used %s! %s protected itself! " % [player["name"], move["name"], opponent["name"]]
	else:
		result["damage"] = _apply_hp_damage(opponent, int(result["damage"]), false)
		message_label.text = _attack_message(player, move, result)
	if int(result["damage"]) > 0:
		_try_inflict_condition(opponent, move, player, true)
		if randf() < float(move.get("target_stat_change_chance", 1.0)):
			_apply_stat_changes(opponent, move.get("target_stat_changes", []))
	_apply_after_damage_effects(player, opponent, move, true, int(result["damage"]))
	if bool(move.get("cleanse_user_party", false)):
		_cleanse_party(battle_party)
	_apply_condemned_backlash(player, true, move)
	_apply_burn_after_move(true)
	_update_hp_ui()
	if bool(move.get("random_party_switch", false)) and player_hp > 0:
		_random_switch_player(bool(move.get("passes_stat_modifiers", false)))
	if opponent_hp == 0:
		return _finish_turn_conditions()
	if player_hp == 0:
		return _finish_turn_conditions()
	return false


func _choose_enemy_move_id() -> String:
	var opponent_move_ids: Array = opponent["moves"]
	var available_move_ids := opponent_move_ids.filter(func(id: String) -> bool: return _is_move_selectable(opponent, id))
	if available_move_ids.is_empty():
		available_move_ids = opponent_move_ids
	return String(available_move_ids.pick_random())


func _choose_confused_move_id(mon: Dictionary) -> String:
	var available: Array[String] = []
	for move_id: String in mon.get("moves", []):
		if battle_data["moves"].has(move_id) and _is_move_selectable(mon, move_id):
			available.append(move_id)
	return "" if available.is_empty() else String(available.pick_random())


func _perform_enemy_attack(end_turn: bool = true, selected_move_id: String = "") -> bool:
	if battle_over:
		return true
	if not _can_use_move(opponent):
		if end_turn:
			if _finish_turn_conditions():
				return true
			_set_action_buttons_disabled(false)
		return false
	var move_id := selected_move_id if not selected_move_id.is_empty() else _choose_enemy_move_id()
	if opponent_was_replaced_this_action or not opponent["moves"].has(move_id):
		move_id = _choose_enemy_move_id()
	opponent_was_replaced_this_action = false
	var move: Dictionary = battle_data["moves"][move_id]
	_record_successful_move(opponent, move_id)
	if bool(move.get("copies_opponent_last_move", false)):
		var copied_move := _copy_last_move(player)
		if copied_move.is_empty():
			message_label.text = "%s used %s, but it failed because the foe had no valid last move! " % [opponent["name"], move["name"]]
			return false
		message_label.text = "%s used Mimic and copied %s! " % [opponent["name"], copied_move["name"]]
		move = copied_move
	if bool(move.get("random_party_switch", false)):
		message_label.text = "%s used %s, but it failed because no other conscious party member could switch in! " % [opponent["name"], move["name"]]
		_apply_burn_after_move(false)
		_update_hp_ui()
		if end_turn:
			if _finish_turn_conditions():
				return true
			_set_action_buttons_disabled(false)
		return false
	if String(move["damage_class"]) == "Status":
		message_label.text += "%s used %s! " % [opponent["name"], move["name"]]
		if bool(move.get("force_random_opponent_switch", false)):
			if _apply_whirlwind(false):
				return true
			if end_turn:
				_finish_turn_conditions()
			return false
		_apply_status_move(opponent, player, move, false)
		_apply_burn_after_move(false)
		_update_hp_ui()
		if end_turn:
			if _finish_turn_conditions():
				return true
			_set_action_buttons_disabled(false)
		return false
	var result := _calculate_damage(opponent, player, move)
	if bool(player.get("protected", false)):
		result["damage"] = 0
		message_label.text = "%s used %s! %s protected itself! " % [opponent["name"], move["name"], player["name"]]
	else:
		result["damage"] = _apply_hp_damage(player, int(result["damage"]), true)
		message_label.text = _attack_message(opponent, move, result)
	if int(result["damage"]) > 0:
		_try_inflict_condition(player, move, opponent, false)
		if randf() < float(move.get("target_stat_change_chance", 1.0)):
			_apply_stat_changes(player, move.get("target_stat_changes", []))
	_apply_after_damage_effects(opponent, player, move, false, int(result["damage"]))
	if bool(move.get("cleanse_user_party", false)):
		_cleanse_party([opponent])
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
	mon["stat_modifiers"] = {}
	for stat: String in COMBAT_STATS:
		mon["stat_modifiers"][stat] = NEUTRAL_STAT_MODIFIER
	mon["move_cooldowns"] = {}
	mon["last_successful_move"] = ""
	mon["disabled_move"] = ""
	mon["disabled_turns"] = 0
	mon["protected"] = false
	mon["protect_chain"] = 0
	mon["prayer_pending"] = false
	mon["battle_types_override"] = []
	mon["nest_turns"] = 0
	mon["cannot_faint_turns"] = 0
	mon["must_recharge"] = false
	mon["ignore_next_move_self_damage"] = false
	mon["voluntary_switch_block_turns"] = 0
	mon["seeded_by_side"] = ""
	mon["weakness_suppressions"] = {}


func _apply_status_move(user: Dictionary, target: Dictionary, move: Dictionary, user_is_player: bool) -> void:
	var had_condition := _has_any_special_condition(user)
	var fixed_heal_fraction := _move_effect_float(move, "fixed_max_hp_heal_fraction", 0.0)
	if fixed_heal_fraction > 0.0:
		_heal_fixed_max_hp(user, fixed_heal_fraction, user_is_player)
	if bool(move.get("cures_conditions", false)):
		_cure_conditions(user)
	if move.has("stat_changes"):
		_apply_stat_changes(user, move["stat_changes"])
	if move.has("target_stat_changes"):
		_apply_stat_changes(target, move["target_stat_changes"])
	if not String(move.get("condition", "")).is_empty():
		var condition_move := move
		var conditional: Dictionary = move.get("condition_chance_if_target_type", {})
		if not conditional.is_empty() and _fakemon_types(target).has(String(conditional.get("type", ""))):
			condition_move = move.duplicate(true)
			condition_move["condition_chance"] = float(conditional.get("chance", move.get("condition_chance", 0.0)))
		_try_inflict_condition(target, condition_move, user, user_is_player)
	if bool(move.get("protect", false)):
		_apply_protection(user)
	if int(move.get("disable_last_move_turns", 0)) > 0:
		_disable_last_move(target, int(move["disable_last_move_turns"]))
	if not String(move.get("sets_weather", "")).is_empty():
		_set_weather(String(move["sets_weather"]))
	if bool(move.get("nest", false)):
		_apply_nest(user, user_is_player)
	if int(move.get("cannot_faint_turns", 0)) > 0:
		_apply_cannot_faint(user, int(move["cannot_faint_turns"]))
	if bool(move.get("reset_all_stat_changes", false)):
		_reset_all_stat_changes()
	if bool(move.get("ignore_next_move_self_damage", false)):
		user["ignore_next_move_self_damage"] = true
		message_label.text += " %s focused inward. " % user["name"]
	if bool(move.get("bloom_healing", false)):
		var heal_percent := 10 + int(floor(float(user["level"]) / 5.0)) + int(_move_effect_float(move, "bloom_heal_percent_bonus", 0.0))
		_heal_mon(user, int(floor(float(user["max_hp"]) * float(heal_percent) / 100.0)), user_is_player)
	if bool(move.get("seed_target", false)):
		if not String(target.get("seeded_by_side ", "")).is_empty():
			message_label.text += " But %s is already seeded. " % target["name"]
		else:
			target["seeded_by_side"] = "player" if user_is_player else "opponent"
			message_label.text += " %s was seeded! " % target["name"]
	if bool(move.get("regrow", false)):
		_apply_regrow(user, user_is_player, _move_effect_float(move, "regrow_heal_fraction", 0.1))
	if move.has("cure_or_stat_change"):
		if had_condition:
			_remove_all_removable_conditions(user)
			message_label.text += " %s's conditions were cured. " % user["name"]
		else:
			_apply_stat_changes(user, move["cure_or_stat_change "])
	if float(move.get("delayed_heal_fraction", 0.0)) > 0.0:
		if bool(user.get("prayer_pending", false)):
			message_label.text += " But a Prayer is already pending. "
		else:
			user["prayer_pending"] = true
			message_label.text += " %s began praying. " % user["name"]


func _apply_stat_changes(mon: Dictionary, changes: Array) -> void:
	var modifiers: Dictionary = mon["stat_modifiers"]
	for change: Dictionary in changes:
		var stat := String(change["stat"])
		if not COMBAT_STATS.has(stat):
			continue
		var amount := float(change["amount"])
		var current := float(modifiers.get(stat, NEUTRAL_STAT_MODIFIER))
		if amount > 0.0 and current >= MAX_POSITIVE_STAT_MODIFIER:
			message_label.text += " %s's %s cannot go up any further! " % [mon["name"], _stat_display_name(stat)]
			continue
		var updated := minf(MAX_POSITIVE_STAT_MODIFIER, current + amount) if amount > 0.0 else current + amount
		modifiers[stat] = updated
		message_label.text += " %s's %s %s!" % [mon["name"], _stat_display_name(stat), "rose" if amount > 0.0 else "fell"]


func _stat_display_name(stat: String) -> String:
	return {"attack": "Attack", "defense": "Defense", "special_attack": "Special Attack", "special_defense": "Special Defense", "speed": "Speed"}.get(stat, stat.capitalize())


func _effective_stat(mon: Dictionary, stat: String) -> float:
	var modifier := float(mon.get("stat_modifiers", {}).get(stat, NEUTRAL_STAT_MODIFIER))
	var value := float(mon[stat]) * modifier
	if stat == "speed" and String(mon.get("condition", "")) == "Slowed":
		value *= float(battle_data["conditions"]["Slowed"]["speed_multiplier"])
	return value


func _has_any_stat_change(mon: Dictionary) -> bool:
	for stat: String in COMBAT_STATS:
		if not is_equal_approx(float(mon.get("stat_modifiers", {}).get(stat, NEUTRAL_STAT_MODIFIER)), NEUTRAL_STAT_MODIFIER):
			return true
	return false


func _has_any_special_condition(mon: Dictionary) -> bool:
	return not String(mon.get("condition", "")).is_empty() or int(mon.get("infatuation_stacks", 0)) > 0 or not String(mon.get("seeded_by_side", "")).is_empty()


func _remove_all_removable_conditions(mon: Dictionary) -> int:
	var removed := 0
	if not String(mon.get("condition", "")).is_empty():
		removed += 1
	if int(mon.get("infatuation_stacks", 0)) > 0:
		removed += 1
	if not String(mon.get("seeded_by_side", "")).is_empty():
		removed += 1
	mon["condition"] = ""
	mon["condition_turns"] = 0
	mon["flinched"] = false
	mon["seeded_by_side"] = ""
	_clear_infatuation(mon)
	return removed


func _apply_regrow(mon: Dictionary, player_side: bool, heal_fraction: float = 0.1) -> int:
	var removed := _remove_all_removable_conditions(mon)
	for stat: String in COMBAT_STATS:
		if not is_equal_approx(float(mon["stat_modifiers"].get(stat, NEUTRAL_STAT_MODIFIER)), NEUTRAL_STAT_MODIFIER):
			removed += 1
			mon["stat_modifiers"][stat] = NEUTRAL_STAT_MODIFIER
	if removed > 0:
		_heal_mon(mon, int(floor(float(mon["max_hp"]) * heal_fraction * float(removed))), player_side)
		message_label.text += " Regrow removed %d effects. " % removed
	else:
		message_label.text += " But there was nothing to regrow from. "
	return removed


func _heal_fixed_max_hp(mon: Dictionary, fraction: float, player_side: bool) -> void:
	_heal_mon(mon, maxi(1, int(floor(float(mon["max_hp"]) * fraction))), player_side)


func _apply_protection(mon: Dictionary) -> void:
	var chain := int(mon.get("protect_chain", 0))
	var success_chance := pow(1.0 / 3.0, chain)
	if randf() <= success_chance:
		mon["protected"] = true
		mon["protect_chain"] = chain + 1
		message_label.text += " %s is protected. " % mon["name"]
	else:
		mon["protected"] = false
		message_label.text += " But it failed."


func _disable_last_move(target: Dictionary, turns: int) -> void:
	var last_move := String(target.get("last_successful_move", ""))
	if last_move.is_empty():
		message_label.text += " But there was no move to disable. "
		return
	target["disabled_move"] = last_move
	target["disabled_turns"] = turns
	message_label.text += " %s's %s was disabled! " % [target["name"], battle_data["moves"][last_move]["name"]]


func _set_weather(weather_name: String) -> void:
	weather = weather_name
	weather_turns_remaining = int(battle_data.get("weather", {}).get(weather_name, {}).get("duration", 3))
	message_label.text += " The weather became %s! " % weather_name


func _move_effect_value(move: Dictionary, key: String, default_value: Variant) -> Variant:
	var overrides: Dictionary = move.get("weather_overrides", {})
	if not weather.is_empty() and overrides.has(weather):
		var weather_values: Dictionary = overrides[weather]
		if weather_values.has(key):
			return weather_values[key]
	return move.get(key, default_value)


func _move_effect_float(move: Dictionary, key: String, default_value: float) -> float:
	return float(_move_effect_value(move, key, default_value))


func _clear_weather() -> void:
	if weather.is_empty():
		return
	message_label.text += " The %s weather cleared. " % weather
	weather = ""
	weather_turns_remaining = 0


func _apply_nest(mon: Dictionary, player_side: bool) -> void:
	var types := _fakemon_types(mon)
	var healing_fraction := 0.15
	if types.has("Air"):
		healing_fraction = 0.33
		types.erase("Air")
		if types.is_empty():
			types.append("Normal")
		mon["battle_types_override"] = types
		mon["nest_turns"] = 2
		message_label.text += " %s temporarily lost its Air typing. " % mon["name"]
	_heal_mon(mon, maxi(1, int(floor(float(mon["max_hp"]) * healing_fraction))), player_side)


func _heal_mon(mon: Dictionary, amount: int, player_side: bool) -> void:
	if player_side:
		var old_hp := player_hp
		player_hp = mini(int(mon["max_hp"]), player_hp + amount)
		party_hp[active_party_index] = player_hp
		message_label.text += " %s restored %d HP. " % [mon["name"], player_hp - old_hp]
	else:
		var old_hp := opponent_hp
		opponent_hp = mini(int(mon["max_hp"]), opponent_hp + amount)
		if active_opponent_index < opponent_party_hp.size():
			opponent_party_hp[active_opponent_index] = opponent_hp
		message_label.text += " %s restored %d HP. " % [mon["name"], opponent_hp - old_hp]


func _apply_cannot_faint(mon: Dictionary, turns: int) -> void:
	mon["cannot_faint_turns"] = maxi(int(mon.get("cannot_faint_turns", 0)), turns)
	message_label.text += " %s cannot be reduced below 1 HP! " % mon["name"]


func _reset_all_stat_changes() -> void:
	for mon: Dictionary in [player, opponent]:
		for stat: String in COMBAT_STATS:
			mon["stat_modifiers"][stat] = NEUTRAL_STAT_MODIFIER
	message_label.text += " All stat changes were reset. "


func _tick_temporary_state(mon: Dictionary) -> void:
	if int(mon.get("nest_turns", 0)) > 0:
		mon["nest_turns"] = int(mon["nest_turns"]) - 1
		if int(mon["nest_turns"]) == 0:
			mon["battle_types_override"] = []
			message_label.text += " %s regained its Air typing. " % mon["name"]
	if int(mon.get("cannot_faint_turns", 0)) > 0:
		mon["cannot_faint_turns"] = int(mon["cannot_faint_turns"]) - 1
	if int(mon.get("voluntary_switch_block_turns", 0)) > 0:
		mon["voluntary_switch_block_turns"] = int(mon["voluntary_switch_block_turns"]) - 1
	var suppressions: Dictionary = mon.get("weakness_suppressions", {})
	for suppressed_type: String in suppressions.keys():
		suppressions[suppressed_type] = int(suppressions[suppressed_type]) - 1
		if int(suppressions[suppressed_type]) <= 0:
			suppressions.erase(suppressed_type)


func _is_move_selectable(mon: Dictionary, move_id: String) -> bool:
	if String(mon.get("disabled_move", "")) == move_id and int(mon.get("disabled_turns", 0)) > 0:
		return false
	return int(mon.get("move_cooldowns", {}).get(move_id, 0)) <= 0


func _move_unavailable_reason(mon: Dictionary, move_id: String) -> String:
	if String(mon.get("disabled_move", "")) == move_id:
		return "This move is disabled. "
	return "This move cannot be used on consecutive turns. "


func _record_successful_move(mon: Dictionary, move_id: String) -> void:
	var cooldowns: Dictionary = mon["move_cooldowns"]
	for cooling_move: String in cooldowns.keys():
		if cooling_move != move_id:
			cooldowns[cooling_move] = maxi(0, int(cooldowns[cooling_move]) - 1)
	if int(mon.get("disabled_turns", 0)) > 0:
		mon["disabled_turns"] = int(mon["disabled_turns"]) - 1
		if int(mon["disabled_turns"]) <= 0:
			mon["disabled_move"] = ""
	if not move_id.is_empty():
		var move: Dictionary = battle_data["moves"][move_id]
		if int(move.get("reuse_delay", 0)) > 0:
			cooldowns[move_id] = int(move["reuse_delay"])
		if not bool(move.get("protect", false)):
			mon["protect_chain"] = 0
		mon["last_successful_move"] = move_id


func _move_id_for(move: Dictionary) -> String:
	for move_id: String in battle_data["moves"]:
		if battle_data["moves"][move_id] == move:
			return move_id
	return ""


func _copy_last_move(target: Dictionary) -> Dictionary:
	var last_move_id := String(target.get("last_successful_move", ""))
	if last_move_id.is_empty() or not battle_data["moves"].has(last_move_id):
		return {}
	var copied: Dictionary = battle_data["moves"][last_move_id]
	if bool(copied.get("calls_another_move", false)) or bool(copied.get("copies_opponent_last_move", false)):
		return {}
	return copied


func _apply_whirlwind(user_is_player: bool = true) -> bool:
	if is_wild_battle:
		escaped = true
		_end_battle("The wild battle ended in a whirlwind! ")
		return true
	if user_is_player:
		var available := _available_opponent_switch_indices()
		if available.is_empty():
			message_label.text += " But it failed because the trainer has no other conscious Fakemon. "
			return false
		_switch_opponent(int(available.pick_random()), true)
	else:
		var available := _available_random_switch_indices()
		if available.is_empty():
			message_label.text += " But it failed because there is no other conscious party member. "
			return false
		_random_switch_player(false)
	return false


func _resolve_pending_prayer(mon: Dictionary, player_side: bool) -> void:
	if not bool(mon.get("prayer_pending", false)):
		return
	mon["prayer_pending"] = false
	var multiplier := 1.0
	if weather == "Celestial Chorus":
		multiplier = float(battle_data["weather"][weather].get("prayer_healing_multiplier", 1.0))
	var healing := maxi(1, int(floor(float(mon["max_hp"]) * 0.33 * multiplier)))
	if player_side:
		player_hp = mini(int(mon["max_hp"]), player_hp + healing)
		party_hp[active_party_index] = player_hp
	else:
		opponent_hp = mini(int(mon["max_hp"]), opponent_hp + healing)
	message_label.text += " %s's prayer restored %d HP. " % [mon["name"], healing]


func _cleanse_party(members: Array) -> void:
	for member: Dictionary in members:
		member["condition"] = ""
		member["condition_turns"] = 0
		member["flinched"] = false
		_clear_infatuation(member)
	message_label.text += " The user's party was cleansed. "


func _can_use_move(mon: Dictionary) -> bool:
	_resolve_pending_prayer(mon, mon == player)
	if bool(mon.get("must_recharge", false)):
		mon["must_recharge"] = false
		message_label.text = "%s must recover and cannot act! " % mon["name"]
		return false
	if bool(mon.get("flinched", false)):
		mon["flinched"] = false
		message_label.text = "%s flinched and couldn't move! " % mon["name"]
		return false
	var condition := String(mon.get("condition", ""))
	if condition == "Despairing" and randf() < float(battle_data["conditions"]["Despairing"]["move_failure_chance"]):
		message_label.text = "%s despaired and lost its turn! " % mon["name"]
		return false
	if condition == "Paralyzed" and randf() < float(battle_data["conditions"]["Paralyzed"]["move_failure_chance"]):
		message_label.text = "%s is paralyzed and couldn't move! " % mon["name"]
		return false
	if condition == "Frozen" or condition == "Asleep":
		mon["condition_turns"] = maxi(0, int(mon["condition_turns"]) - 1)
		var verb := "frozen solid" if condition == "Frozen" else "asleep"
		message_label.text = "%s is %s and cannot move! " % [mon["name"], verb]
		if int(mon["condition_turns"]) == 0:
			mon["condition"] = ""
			message_label.text += " It will recover next turn. "
		return false
	if condition == "Confusion":
		mon["condition_turns"] = maxi(0, int(mon.get("condition_turns", 1)) - 1)
		message_label.text = "%s is confused and acts unpredictably! " % mon["name"]
		if int(mon["condition_turns"]) == 0:
			mon["condition"] = ""
			message_label.text += " It snapped out of confusion after this move. "
	var stacks := int(mon.get("infatuation_stacks", 0))
	if stacks > 0 and _genders_are_opposite(String(mon.get("gender", "Genderless")), String(mon.get("infatuation_source_gender", ""))):
		var failure_chance := float(battle_data["conditions"]["Infatuated"]["failure_chance_per_stack"]) * stacks
		if randf() < failure_chance:
			message_label.text = "%s ignored the command due to infatuation! " % mon["name"]
			return false
	return true


func _try_inflict_condition(target: Dictionary, move: Dictionary, source: Dictionary, source_is_player: bool) -> void:
	var condition := String(move.get("condition", ""))
	if condition.is_empty() or randf() >= _move_effect_float(move, "condition_chance", 0.0):
		return
	if condition == "Flinch":
		target["flinched"] = true
		message_label.text += " %s flinched! " % target["name"]
		return
	if condition == "Infatuated":
		var maximum := int(battle_data["conditions"]["Infatuated"]["maximum_stacks"])
		target["infatuation_stacks"] = mini(maximum, int(target.get("infatuation_stacks", 0)) + 1)
		target["infatuation_source_gender"] = String(source.get("gender", "Genderless"))
		target["infatuation_source_side"] = "player" if source_is_player else "opponent"
		target["infatuation_source_index"] = active_party_index if source_is_player else -1
		message_label.text += " %s gained Infatuation stack %d! " % [target["name"], target["infatuation_stacks"]]
		return
	if not String(target.get("condition", "")).is_empty():
		return
	target["condition"] = condition
	if condition == "Frozen" or condition == "Asleep" or condition == "Confusion":
		var condition_data: Dictionary = battle_data["conditions"][condition]
		target["condition_turns"] = randi_range(int(condition_data["minimum_turns"]), int(condition_data["maximum_turns"]))
	else:
		target["condition_turns"] = 0
	message_label.text += " %s became %s! " % [target["name"], condition.to_lower()]


func _genders_are_opposite(first: String, second: String) -> bool:
	return (first == "Male" and second == "Female") or (first == "Female" and second == "Male")


func _clear_infatuation(mon: Dictionary) -> void:
	mon["infatuation_stacks"] = 0
	mon["infatuation_source_gender"] = ""
	mon["infatuation_source_side"] = ""
	mon["infatuation_source_index"] = -1


func _clear_confusion(mon: Dictionary) -> void:
	if String(mon.get("condition", "")) == "Confusion":
		mon["condition"] = ""
		mon["condition_turns"] = 0


func _cure_conditions(mon: Dictionary) -> void:
	var old_condition := String(mon.get("condition", ""))
	var old_stacks := int(mon.get("infatuation_stacks", 0))
	var was_seeded := not String(mon.get("seeded_by_side", "")).is_empty()
	if old_condition == "Condemned":
		mon["light_exposed"] = true
	elif old_condition == "Despairing":
		mon["dark_exposed"] = true
	mon["condition"] = ""
	mon["condition_turns"] = 0
	mon["flinched"] = false
	mon["seeded_by_side"] = ""
	_clear_infatuation(mon)
	if old_condition.is_empty() and old_stacks == 0 and not was_seeded:
		message_label.text += " But there were no conditions to remove. "
	else:
		message_label.text += " Its special conditions were removed. "


func _apply_condemned_backlash(mon: Dictionary, player_side: bool, move: Dictionary) -> void:
	if String(mon.get("condition", "")) != "Condemned" or String(move["damage_class"]) != "Special":
		return
	var condition_data: Dictionary = battle_data["conditions"]["Condemned"]
	var level := float(mon["level"])
	var power := float(condition_data["backlash_power"])
	var special_attack := float(mon["special_attack"])
	var special_defense := maxf(1.0, float(mon["special_defense"]) * float(condition_data["special_defense_multiplier"]))
	var damage := maxi(1, int(floor(((((2.0 * level / 5.0 + 2.0) * power * special_attack / special_defense) / 50.0) + 2.0))))
	_apply_hp_damage(mon, damage, player_side)
	message_label.text += " Condemnation dealt %d damage to %s. " % [damage, mon["name"]]


func _apply_burn_after_move(player_side: bool) -> void:
	var mon := player if player_side else opponent
	if String(mon.get("condition", "")) != "Burned":
		return
	var damage_fraction := float(battle_data["conditions"]["Burned"]["post_move_hp_fraction"])
	var damage := maxi(1, int(floor(float(mon["max_hp"]) * damage_fraction)))
	_apply_hp_damage(mon, damage, player_side)
	message_label.text += " %s lost %d HP from its burn. " % [mon["name"], damage]


func _apply_hp_damage(mon: Dictionary, amount: int, player_side: bool) -> int:
	var current_hp := player_hp if player_side else opponent_hp
	var minimum_hp := 1 if int(mon.get("cannot_faint_turns", 0)) > 0 and current_hp > 0 else 0
	var next_hp := maxi(minimum_hp, current_hp - maxi(0, amount))
	if player_side:
		player_hp = next_hp
		party_hp[active_party_index] = player_hp
	else:
		opponent_hp = next_hp
		if active_opponent_index < opponent_party_hp.size():
			opponent_party_hp[active_opponent_index] = opponent_hp
	return current_hp - next_hp


func _apply_recoil(mon: Dictionary, player_side: bool, fraction: float) -> void:
	if fraction <= 0.0:
		return
	if bool(mon.get("ignore_next_move_self_damage", false)):
		message_label.text += " %s ignored the move's recoil. " % mon["name"]
		return
	var current_hp := player_hp if player_side else opponent_hp
	var recoil := maxi(1, int(floor(float(current_hp) * fraction)))
	var dealt := _apply_hp_damage(mon, recoil, player_side)
	message_label.text += " %s took %d recoil damage. " % [mon["name"], dealt]


func _apply_after_damage_effects(user: Dictionary, target: Dictionary, move: Dictionary, user_is_player: bool, actual_damage: int = 1) -> void:
	var dealt_damage := actual_damage > 0
	if move.has("stat_changes"):
		_apply_stat_changes(user, move["stat_changes"])
	if dealt_damage and int(move.get("cannot_faint_turns", 0)) > 0:
		_apply_cannot_faint(user, int(move["cannot_faint_turns"]))
	_apply_recoil(user, user_is_player, float(move.get("recoil_current_hp_fraction", 0.0)))
	if bool(move.get("must_recharge", false)):
		user["must_recharge"] = true
	if bool(move.get("burn_user_party", false)) and user_is_player:
		_burn_non_active_user_party()
	if dealt_damage and float(move.get("drain_damage_fraction", 0.0)) > 0.0:
		_heal_mon(user, maxi(1, int(floor(float(actual_damage) * float(move["drain_damage_fraction"])))), user_is_player)
	var fixed_heal_fraction := _move_effect_float(move, "fixed_max_hp_heal_fraction", 0.0)
	if dealt_damage and fixed_heal_fraction > 0.0:
		_heal_fixed_max_hp(user, fixed_heal_fraction, user_is_player)
	if dealt_damage and int(move.get("prevent_voluntary_switch_turns", 0)) > 0:
		target["voluntary_switch_block_turns"] = maxi(int(target.get("voluntary_switch_block_turns", 0)), int(move["prevent_voluntary_switch_turns"]))
		message_label.text += " %s cannot switch voluntarily. " % target["name"]
	if dealt_damage and not move.get("random_secondary_conditions", []).is_empty():
		_apply_random_secondary_condition(target, user, move, user_is_player)
	if dealt_damage and not String(move.get("suppress_weakness_type", "")).is_empty():
		var suppressed_type := String(move["suppress_weakness_type"])
		user["weakness_suppressions"][suppressed_type] = int(_move_effect_value(move, "suppress_weakness_turns", 0))
		message_label.text += " %s's %s weakness was suppressed. " % [user["name"], suppressed_type]
	var preserved_weather := String(move.get("preserve_weather", ""))
	if move.has("preserve_weather") and weather != preserved_weather:
		_clear_weather()
	if bool(user.get("ignore_next_move_self_damage", false)):
		user["ignore_next_move_self_damage"] = false


func _apply_random_secondary_condition(target: Dictionary, source: Dictionary, move: Dictionary, source_is_player: bool) -> String:
	if randf() >= _move_effect_float(move, "random_secondary_chance", 0.0):
		return ""
	var choices: Array = move.get("random_secondary_conditions", [])
	if choices.is_empty():
		return ""
	var chosen := String(choices.pick_random())
	var condition_move := {"condition": chosen, "condition_chance": 1.0}
	_try_inflict_condition(target, condition_move, source, source_is_player)
	return chosen


func _burn_non_active_user_party() -> void:
	var burn_move := {"condition": "Burned", "condition_chance": 1.0}
	for index in battle_party.size():
		if index == active_party_index or party_hp[index] <= 0:
			continue
		_try_inflict_condition(battle_party[index], burn_move, player, true)


func _finish_turn_conditions() -> bool:
	_apply_rootmind_healing()
	_apply_seeded_drain()
	if String(player.get("condition", "")) == "Poisoned" and player_hp > 0:
		var poison_fraction := float(battle_data["conditions"]["Poisoned"]["end_turn_hp_fraction"])
		var player_damage := maxi(1, int(floor(float(player["max_hp"]) * poison_fraction)))
		_apply_hp_damage(player, player_damage, true)
		message_label.text += " %s lost %d HP from poison. " % [player["name"], player_damage]
	if String(opponent.get("condition", "")) == "Poisoned" and opponent_hp > 0:
		var poison_fraction := float(battle_data["conditions"]["Poisoned"]["end_turn_hp_fraction"])
		var opponent_damage := maxi(1, int(floor(float(opponent["max_hp"]) * poison_fraction)))
		_apply_hp_damage(opponent, opponent_damage, false)
		message_label.text += " %s lost %d HP from poison. " % [opponent["name"], opponent_damage]
	player["protected"] = false
	opponent["protected"] = false
	_tick_temporary_state(player)
	_tick_temporary_state(opponent)
	_advance_weather()
	_update_hp_ui()
	if opponent_hp == 0:
		var fainted_name := String(opponent["name"])
		experience_earned += _calculate_experience_reward()
		var next_opponent := _next_available_opponent_index()
		if next_opponent != -1:
			_switch_opponent(next_opponent, false)
			message_label.text += " %s fainted. The trainer sent out %s! " % [fainted_name, opponent["name"]]
			return false
		player_won = true
		_end_battle("%s fainted. You win! The participants share %d EXP. " % [fainted_name, experience_earned])
		return true
	if player_hp == 0:
		return _handle_player_faint()
	return false


func _apply_seeded_drain() -> void:
	var seed_multiplier := _move_effect_float(battle_data["moves"]["seed"], "seed_drain_multiplier", 1.0)
	if not String(player.get("seeded_by_side", "")).is_empty() and player_hp > 0:
		var requested := maxi(1, int(floor(float(player["max_hp"]) * 0.125 * seed_multiplier)))
		var drained := _apply_hp_damage(player, requested, true)
		if String(player["seeded_by_side"]) == "opponent" and opponent_hp > 0:
			_heal_mon(opponent, drained, false)
		message_label.text += " %s lost %d HP to Seed. " % [player["name"], drained]
	if not String(opponent.get("seeded_by_side", "")).is_empty() and opponent_hp > 0:
		var requested := maxi(1, int(floor(float(opponent["max_hp"]) * 0.125 * seed_multiplier)))
		var drained := _apply_hp_damage(opponent, requested, false)
		if String(opponent["seeded_by_side"]) == "player" and player_hp > 0:
			_heal_mon(player, drained, true)
		message_label.text += " %s lost %d HP to Seed. " % [opponent["name"], drained]


func _apply_rootmind_healing() -> void:
	if weather != "Rootmind":
		return
	var fraction := float(battle_data["weather"]["Rootmind"].get("plant_end_turn_heal_fraction", 0.0625))
	if player_hp > 0 and _fakemon_types(player).has("Plant"):
		_heal_fixed_max_hp(player, fraction, true)
	if opponent_hp > 0 and _fakemon_types(opponent).has("Plant"):
		_heal_fixed_max_hp(opponent, fraction, false)


func _advance_weather() -> void:
	if weather.is_empty():
		return
	weather_turns_remaining = maxi(0, weather_turns_remaining - 1)
	if weather_turns_remaining == 0:
		message_label.text += " The %s weather faded. " % weather
		weather = ""


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
	message_label.text += "\n%s fainted. Switch to a conscious party member. " % player["name"]
	return true


func _on_switch_pressed() -> void:
	if battle_over or (String(player.get("condition", "")) == "Paralyzed" and not forced_switch):
		return
	if int(player.get("voluntary_switch_block_turns", 0)) > 0 and not forced_switch:
		message_label.text = "%s cannot switch voluntarily! " % player["name"]
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
	_clear_confusion(player)
	player["light_exposed"] = false
	player["dark_exposed"] = false
	player["seeded_by_side"] = ""
	active_party_index = next_index
	if not participating_party_indices.has(active_party_index):
		participating_party_indices.append(active_party_index)
	player = battle_party[active_party_index]
	player_hp = party_hp[active_party_index]
	forced_switch = false
	switch_button.text = "[3/S] Switch"
	switch_panel.hide()
	_update_active_player_ui()
	message_label.text = "Go, %s! " % player["name"]
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


func _available_opponent_switch_indices() -> Array[int]:
	var available: Array[int] = []
	for index in opponent_party.size():
		if index != active_opponent_index and opponent_party_hp[index] > 0:
			available.append(index)
	return available


func _next_available_opponent_index() -> int:
	var available := _available_opponent_switch_indices()
	return -1 if available.is_empty() else int(available[0])


func _switch_opponent(next_index: int, forced_by_move: bool) -> void:
	if next_index < 0 or next_index >= opponent_party.size() or next_index == active_opponent_index or opponent_party_hp[next_index] <= 0:
		return
	_clear_confusion(opponent)
	opponent["light_exposed"] = false
	opponent["dark_exposed"] = false
	opponent["seeded_by_side"] = ""
	active_opponent_index = next_index
	opponent = opponent_party[active_opponent_index]
	opponent_hp = opponent_party_hp[active_opponent_index]
	opponent_was_replaced_this_action = true
	_update_active_opponent_ui()
	if forced_by_move:
		message_label.text += " The trainer was forced to send out %s! " % opponent["name"]


func _available_random_switch_indices() -> Array[int]:
	var available: Array[int] = []
	for index in battle_party.size():
		if index != active_party_index and party_hp[index] > 0:
			available.append(index)
	return available


func _random_switch_player(pass_stat_modifiers: bool) -> void:
	var available := _available_random_switch_indices()
	if available.is_empty():
		return
	var outgoing := player
	_clear_confusion(outgoing)
	var outgoing_name := String(outgoing["name"])
	var passed_modifiers: Dictionary = outgoing.get("stat_modifiers", {}).duplicate(true)
	for stat: String in COMBAT_STATS:
		outgoing["stat_modifiers"][stat] = NEUTRAL_STAT_MODIFIER
	outgoing["light_exposed"] = false
	outgoing["dark_exposed"] = false
	outgoing["seeded_by_side"] = ""
	active_party_index = int(available.pick_random())
	if not participating_party_indices.has(active_party_index):
		participating_party_indices.append(active_party_index)
	player = battle_party[active_party_index]
	player_hp = party_hp[active_party_index]
	if pass_stat_modifiers:
		player["stat_modifiers"] = passed_modifiers
	_update_active_player_ui()
	message_label.text += " %s switched with %s" % [outgoing_name, player["name"]]
	if pass_stat_modifiers:
		message_label.text += " and passed along its stat changes"
	message_label.text += "! "


func _set_action_buttons_disabled(disabled: bool) -> void:
	var paralyzed := String(player.get("condition", "")) == "Paralyzed"
	var switch_blocked := int(player.get("voluntary_switch_block_turns", 0)) > 0
	action_button.disabled = disabled
	capture_button.disabled = disabled
	switch_button.disabled = disabled or _next_available_party_index() == -1 or ((paralyzed or switch_blocked) and not forced_switch)
	run_button.disabled = disabled or not is_wild_battle or paralyzed


func _on_capture_pressed() -> void:
	if battle_over:
		return
	_set_action_buttons_disabled(true)
	if not is_wild_battle:
		message_label.text = "You cannot capture another trainer's Fakemon! Your action was used. "
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
	message_label.text = "%s broke free! Your action was used. " % opponent["name"]
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
	message_label.text = "Couldn't escape! The wild Fakemon gets its turn. "
	await get_tree().create_timer(0.8).timeout
	_enemy_turn()


func _calculate_experience_reward() -> int:
	return maxi(1, int(float(opponent["base_exp"]) * float(opponent["level"]) / 7.0))


func _calculate_damage(attacker: Dictionary, defender: Dictionary, move: Dictionary) -> Dictionary:
	var level := float(attacker["level"])
	var burn_data: Dictionary = battle_data["conditions"]["Burned"]
	var is_physical := String(move["damage_class"]) == "Physical"
	var attack_stat := "attack" if is_physical else "special_attack"
	var defense_stat := "defense" if is_physical else "special_defense"
	var attack := _effective_stat(attacker, attack_stat)
	var defense := _effective_stat(defender, defense_stat)
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
	if bool(move.get("uses_target_defense_as_attack", false)):
		attack = defense
	defense = maxf(1.0, defense)
	var power := _move_effect_float(move, "power", float(move["power"]))
	var raised_stat_power: Dictionary = move.get("raised_stat_power", {})
	if not raised_stat_power.is_empty():
		var checked_stat := String(raised_stat_power["stat"])
		if float(attacker.get("stat_modifiers", {}).get(checked_stat, NEUTRAL_STAT_MODIFIER)) > NEUTRAL_STAT_MODIFIER:
			power = float(raised_stat_power["power"])
	if move.has("power_if_target_has_condition") and _has_any_special_condition(defender):
		power = _move_effect_float(move, "power_if_target_has_condition", float(move["power_if_target_has_condition"]))
	if move.has("power_if_user_has_stat_change") and _has_any_stat_change(attacker):
		power = _move_effect_float(move, "power_if_user_has_stat_change", float(move["power_if_user_has_stat_change"]))
	var base_damage := (((2.0 * level / 5.0 + 2.0) * power * attack / defense) / 50.0) + 2.0
	var stab := 1.5 if _fakemon_types(attacker).has(String(move["type"])) else 1.0
	var effectiveness := _get_combined_type_effectiveness(String(move["type"]), defender, bool(move.get("ignore_resistance", false)))
	if String(move["type"]) == "Light" and bool(defender.get("light_exposed", false)):
		effectiveness *= 2.0
	if String(move["type"]) == "Dark" and bool(defender.get("dark_exposed", false)):
		effectiveness *= 2.0
	var weather_multiplier := 1.0
	if not weather.is_empty():
		weather_multiplier = float(battle_data["weather"].get(weather, {}).get("damage_multipliers", {}).get(String(move["type"]), 1.0))
	var random_modifier := randf_range(0.85, 1.0)
	var damage := 0 if effectiveness == 0.0 else maxi(1, int(floor(base_damage * stab * effectiveness * weather_multiplier * random_modifier)))
	return {"damage": damage, "effectiveness": effectiveness, "power": power}


func _get_type_effectiveness(move_type: String, defender_type: String) -> float:
	var attack_chart: Dictionary = TYPE_EFFECTIVENESS.get(move_type, {})
	return float(attack_chart.get(defender_type, 1.0))


func _get_combined_type_effectiveness(move_type: String, defender: Dictionary, ignore_resistance: bool = false) -> float:
	var combined := 1.0
	for defender_type: String in _fakemon_types(defender):
		var matchup := _get_type_effectiveness(move_type, defender_type)
		if int(defender.get("weakness_suppressions", {}).get(move_type, 0)) > 0 and matchup > 1.0:
			matchup = 1.0
		if ignore_resistance and matchup > 0.0 and matchup < 1.0:
			matchup = 1.0
		combined *= matchup
	return combined


func _fakemon_types(mon: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if not mon.get("battle_types_override", []).is_empty():
		for type_name: Variant in mon["battle_types_override"]:
			var normalized := String(type_name)
			if not normalized.is_empty() and not result.has(normalized):
				result.append(normalized)
	elif mon.has("types"):
		for type_name: Variant in mon["types"]:
			var normalized := String(type_name)
			if not normalized.is_empty() and not result.has(normalized):
				result.append(normalized)
	elif not String(mon.get("type", "")).is_empty():
		result.append(String(mon["type"]))
	return result


func _type_display(mon: Dictionary) -> String:
	var types := _fakemon_types(mon)
	if types.is_empty():
		return "Unknown"
	return types[0] if types.size() == 1 else "%s / %s" % [types[0], types[1]]


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
	if not String(mon.get("seeded_by_side", "")).is_empty():
		parts.append("Seeded")
	if int(mon.get("voluntary_switch_block_turns", 0)) > 0:
		parts.append("Switch-locked")
	return "Healthy" if parts.is_empty() else ", ".join(parts)


func _update_active_player_ui() -> void:
	var condition_text := "" if String(player.get("condition", "")).is_empty() else "   {%s}" % player["condition"]
	player_name_label.text = "%s   Lv. %d   [%s]   %s%s" % [player["name"], player["level"], _type_display(player), player["gender"], condition_text]
	_set_fakemon_art(player_square, player, "Player")
	action_button.text = "[1/A] Attack"
	_update_hp_ui()


func _update_active_opponent_ui() -> void:
	var party_text := "" if is_wild_battle or opponent_party.size() <= 1 else "   (%d/%d)" % [active_opponent_index + 1, opponent_party.size()]
	opponent_name_label.text = "%s   Lv. %d   [%s]   %s%s" % [opponent["name"], opponent["level"], _type_display(opponent), opponent["gender"], party_text]
	_set_fakemon_art(opponent_square, opponent, "Wild")
	if opponent_hp_bar != null:
		_update_hp_ui()


func _create_fakemon_art(mon: Dictionary, role: String, art_size: Vector2) -> TextureRect:
	var art := TextureRect.new()
	art.size = art_size
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var placeholder := Label.new()
	placeholder.name = "Placeholder"
	placeholder.text = "FAKEMON\nPLACEHOLDER"
	placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_child(placeholder)
	_set_fakemon_art(art, mon, role)
	return art


func _set_fakemon_art(art: TextureRect, mon: Dictionary, role: String) -> void:
	var art_id := String(mon.get("art_id", ""))
	var path := "res://assets/fakemon/battle/%s_%s.png" % [art_id, role]
	var has_art := not art_id.is_empty() and ResourceLoader.exists(path)
	art.texture = load(path) if has_art else _color_texture(Color(mon.get("color", "777777")))
	if art.has_meta("battle_art_anchor"):
		_resize_battle_art(art, has_art)
	var placeholder := art.get_node_or_null("Placeholder") as Label
	if placeholder != null:
		placeholder.visible = not has_art


func _resize_battle_art(art: TextureRect, has_art: bool) -> void:
	var target_size := DEFAULT_BATTLE_ART_SIZE
	if has_art and art.texture != null:
		var source_size := art.texture.get_size()
		var largest_dimension := maxf(source_size.x, source_size.y)
		if largest_dimension > 0.0:
			target_size = source_size * minf(1.0, MAX_BATTLE_ART_DIMENSION / largest_dimension)
	var anchor: Vector2 = art.get_meta("battle_art_anchor")
	art.size = target_size
	art.position = anchor - Vector2(target_size.x * 0.5, target_size.y)


func _color_texture(color: Color) -> ImageTexture:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


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
	for mon: Dictionary in battle_party:
		_clear_confusion(mon)
	for mon: Dictionary in opponent_party:
		_clear_confusion(mon)
	if not captured_mon.is_empty():
		_clear_confusion(captured_mon)
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
	battle_finished.emit(player_won, escaped, captured_mon, experience_earned, participating_party_indices, active_party_index, party_hp, final_conditions)
