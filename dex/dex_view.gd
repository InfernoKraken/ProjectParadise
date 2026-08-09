extends Control

signal return_requested

var content: VBoxContainer
var current_mon: Dictionary = {}
var moves_catalog: Dictionary = {}
var move_details: VBoxContainer


func _ready() -> void:
	var dex_theme := Theme.new()
	dex_theme.set_color("font_color", "Label", Color("#18251f"))
	dex_theme.set_color("font_color", "Button", Color("#ffffff"))
	dex_theme.set_color("font_hover_color", "Button", Color("#ffffff"))
	dex_theme.set_color("font_pressed_color", "Button", Color("#ffffff"))
	dex_theme.set_color("font_disabled_color", "Button", Color("#26332c"))
	theme = dex_theme
	var background := ColorRect.new()
	background.color = Color("#f2f6ec")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 90)
	margin.add_theme_constant_override("margin_right", 90)
	margin.add_theme_constant_override("margin_top", 25)
	margin.add_theme_constant_override("margin_bottom", 25)
	add_child(margin)
	content = VBoxContainer.new()
	margin.add_child(content)
	hide()


func show_entry(mon: Dictionary, all_moves: Dictionary) -> void:
	current_mon = mon
	moves_catalog = all_moves
	_show_overview_page()
	show()


func _build_page_shell(active_page: String) -> void:
	for child in content.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = "FAKEMON DEX - %s" % current_mon["name"]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 27)
	content.add_child(title)
	var navigation := HBoxContainer.new()
	content.add_child(navigation)
	var overview_button := Button.new()
	overview_button.text = "Overview"
	overview_button.disabled = active_page == "overview"
	overview_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overview_button.pressed.connect(_show_overview_page)
	navigation.add_child(overview_button)
	var moves_button := Button.new()
	moves_button.text = "Moves (%d)" % current_mon["moves"].size()
	moves_button.disabled = active_page == "moves"
	moves_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	moves_button.pressed.connect(_show_moves_page)
	navigation.add_child(moves_button)


func _show_overview_page() -> void:
	_build_page_shell("overview")
	var header := HBoxContainer.new()
	content.add_child(header)
	var portrait := ColorRect.new()
	portrait.color = Color(current_mon["color"])
	portrait.custom_minimum_size = Vector2(145, 145)
	header.add_child(portrait)
	var portrait_text := Label.new()
	portrait_text.text = "FAKEMON\nPICTURE\nPLACEHOLDER"
	portrait_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait_text.add_theme_color_override("font_color", Color.WHITE)
	portrait.add_child(portrait_text)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(details)
	var identity := Label.new()
	identity.text = "%s  Lv.%d" % [current_mon["name"], current_mon["level"]]
	identity.add_theme_font_size_override("font_size", 23)
	details.add_child(identity)
	var type_label := Label.new()
	type_label.text = "TYPE: %s" % current_mon["type"]
	type_label.add_theme_color_override("font_color", _type_color(current_mon["type"]))
	type_label.add_theme_font_size_override("font_size", 19)
	details.add_child(type_label)
	var hp := int(current_mon.get("current_hp", current_mon["max_hp"]))
	var condition := String(current_mon.get("condition", ""))
	var stats := Label.new()
	stats.text = "Gender: %s    Size: %s\nHP: %d/%d    Speed: %d\nAttack: %d    Defense: %d\nSp. Attack: %d    Sp. Defense: %d\nCondition: %s" % [current_mon["gender"], current_mon["size"], hp, current_mon["max_hp"], current_mon["speed"], current_mon["attack"], current_mon["defense"], current_mon["special_attack"], current_mon["special_defense"], "Healthy" if condition.is_empty() else condition]
	details.add_child(stats)
	var description_title := Label.new()
	description_title.text = "Description"
	description_title.add_theme_font_size_override("font_size", 17)
	content.add_child(description_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 125)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var description := Label.new()
	description.text = current_mon["description"]
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size = Vector2(720, 240)
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(description)
	_add_return_button()


func _show_moves_page() -> void:
	_build_page_shell("moves")
	var page := HBoxContainer.new()
	page.add_theme_constant_override("separation", 18)
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(page)
	var move_scroll := ScrollContainer.new()
	move_scroll.custom_minimum_size = Vector2(280, 0)
	page.add_child(move_scroll)
	var move_list := VBoxContainer.new()
	move_list.add_theme_constant_override("separation", 6)
	move_list.custom_minimum_size = Vector2(260, 0)
	move_scroll.add_child(move_list)
	var details_panel := PanelContainer.new()
	details_panel.custom_minimum_size = Vector2(400, 260)
	details_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(details_panel)
	var details_margin := MarginContainer.new()
	details_margin.add_theme_constant_override("margin_left", 18)
	details_margin.add_theme_constant_override("margin_right", 18)
	details_margin.add_theme_constant_override("margin_top", 14)
	details_margin.add_theme_constant_override("margin_bottom", 14)
	details_panel.add_child(details_margin)
	move_details = VBoxContainer.new()
	move_details.add_theme_constant_override("separation", 10)
	details_margin.add_child(move_details)
	for move_id: String in current_mon["moves"]:
		var move: Dictionary = moves_catalog[move_id]
		var button := Button.new()
		button.text = "%s  [%s]" % [move["name"], move["type"]]
		button.pressed.connect(_show_move_details.bind(move_id))
		move_list.add_child(button)
	if not current_mon["moves"].is_empty():
		_show_move_details(current_mon["moves"][0])
	_add_return_button()


func _show_move_details(move_id: String) -> void:
	for child in move_details.get_children():
		child.queue_free()
	var move: Dictionary = moves_catalog[move_id]
	var effect := "No additional effect."
	if move.has("condition"):
		effect = "%d%% chance to inflict %s." % [roundi(float(move["condition_chance"]) * 100.0), move["condition"]]
	elif bool(move.get("cures_conditions", false)):
		effect = String(move.get("description", "Removes all special conditions from the user."))
	var name_label := Label.new()
	name_label.text = move["name"]
	name_label.add_theme_font_size_override("font_size", 21)
	move_details.add_child(name_label)
	var type_label := Label.new()
	type_label.text = "Type: %s" % move["type"]
	type_label.add_theme_color_override("font_color", _type_color(move["type"]))
	type_label.add_theme_font_size_override("font_size", 17)
	move_details.add_child(type_label)
	var power_text := "--" if int(move["power"]) == 0 else str(int(move["power"]))
	var attributes := Label.new()
	attributes.text = "Class: %s\nPower: %s" % [move["damage_class"], power_text]
	attributes.add_theme_font_size_override("font_size", 16)
	move_details.add_child(attributes)
	var effect_label := Label.new()
	effect_label.text = effect
	effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	effect_label.add_theme_font_size_override("font_size", 16)
	move_details.add_child(effect_label)


func _add_return_button() -> void:
	var return_button := Button.new()
	return_button.text = "Return to Party"
	return_button.pressed.connect(func() -> void: return_requested.emit())
	content.add_child(return_button)


func _type_color(type_name: String) -> Color:
	return {"Fire": Color("#a72d20"), "Water": Color("#155ca5"), "Plant": Color("#176d32"), "Normal": Color("#544b42"), "Light": Color("#8a6500"), "Dark": Color("#4b3268")}.get(type_name, Color("#18251f"))
