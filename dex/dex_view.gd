extends Control

signal return_requested

var content: VBoxContainer
var current_mon: Dictionary = {}
var moves_catalog: Dictionary = {}
var move_details: VBoxContainer

const TYPE_PALETTE := preload("res://data/type_palette.gd")
const PORTRAIT_PATH_TEMPLATES := [
	"res://assets/fakemon/battle/%s_Player.png",
	"res://assets/fakemon/overworld/%s_Follow_Down.png"
]


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
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(145, 145)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var portrait_texture := _portrait_texture(current_mon)
	var has_portrait := portrait_texture != null
	if has_portrait:
		portrait.texture = portrait_texture
	header.add_child(portrait)
	var portrait_text := Label.new()
	portrait_text.text = "FAKEMON\nPICTURE\nPLACEHOLDER"
	portrait_text.visible = not has_portrait
	portrait_text.add_theme_color_override("font_color", Color(current_mon["color"]))
	portrait_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait.add_child(portrait_text)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(details)
	var identity := Label.new()
	identity.text = "%s  Lv.%d" % [current_mon["name"], current_mon["level"]]
	identity.add_theme_font_size_override("font_size", 23)
	details.add_child(identity)
	var type_label := Label.new()
	var mon_types := _fakemon_types(current_mon)
	var type_text := "Unknown" if mon_types.is_empty() else mon_types[0]
	if mon_types.size() > 1:
		type_text += " / %s" % mon_types[1]
	type_label.text = "TYPE: %s" % type_text
	type_label.add_theme_color_override("font_color", _type_color(mon_types[0] if not mon_types.is_empty() else ""))
	type_label.add_theme_font_size_override("font_size", 19)
	details.add_child(type_label)
	var hp := int(current_mon.get("current_hp", current_mon["max_hp"]))
	var condition := String(current_mon.get("condition", ""))
	var egg_groups := _egg_groups(current_mon)
	var stats := Label.new()
	stats.text = "Gender: %s    Size: %s\nEgg Groups: %s\nHP: %d/%d    Speed: %d\nAttack: %d    Defense: %d\nSp. Attack: %d    Sp. Defense: %d\nCondition: %s" % [current_mon["gender"], current_mon["size"], " / ".join(egg_groups) if not egg_groups.is_empty() else "Unknown", hp, current_mon["max_hp"], current_mon["speed"], current_mon["attack"], current_mon["defense"], current_mon["special_attack"], current_mon["special_defense"], "Healthy" if condition.is_empty() else condition]
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
	var effect := _move_effect_summary(move)
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


func _move_effect_summary(move: Dictionary) -> String:
	var effects: Array[String] = []
	if move.has("condition"):
		effects.append("%d%% chance to inflict %s." % [roundi(float(move.get("condition_chance", 1.0)) * 100.0), move["condition"]])
	if bool(move.get("cures_conditions", false)):
		effects.append(String(move.get("description", "Removes all special conditions from the user.")))
	var self_stat_effect := _stat_change_summary(move.get("stat_changes", []), "the user's")
	if not self_stat_effect.is_empty():
		effects.append(self_stat_effect)
	var target_stat_effect := _stat_change_summary(move.get("target_stat_changes", []), "the target's")
	if not target_stat_effect.is_empty():
		effects.append(target_stat_effect)
	return "No additional effect." if effects.is_empty() else " ".join(effects)


func _stat_change_summary(changes: Array, subject: String) -> String:
	if changes.is_empty():
		return ""
	var raised: Array[String] = []
	var lowered: Array[String] = []
	var raised_amount := 0.0
	var lowered_amount := 0.0
	for change: Dictionary in changes:
		var stat_name := _display_stat_name(String(change.get("stat", "")))
		var amount := float(change.get("amount", 0.0))
		if stat_name.is_empty() or is_zero_approx(amount):
			continue
		if amount > 0.0:
			raised.append(stat_name)
			raised_amount = amount
		else:
			lowered.append(stat_name)
			lowered_amount = absf(amount)
	var parts: Array[String] = []
	if not raised.is_empty():
		parts.append("Raises %s %s by %d%%." % [subject, _joined_stat_names(raised), roundi(raised_amount * 100.0)])
	if not lowered.is_empty():
		parts.append("Lowers %s %s by %d%%." % [subject, _joined_stat_names(lowered), roundi(lowered_amount * 100.0)])
	return " ".join(parts)


func _joined_stat_names(stat_names: Array[String]) -> String:
	if stat_names.size() < 2:
		return stat_names[0] if not stat_names.is_empty() else ""
	if stat_names.size() == 2:
		return "%s and %s" % [stat_names[0], stat_names[1]]
	return ", ".join(stat_names.slice(0, stat_names.size() - 1)) + ", and " + stat_names[-1]


func _display_stat_name(stat_name: String) -> String:
	return {"attack": "Attack", "defense": "Defense", "special_attack": "Special Attack", "special_defense": "Special Defense", "speed": "Speed"}.get(stat_name, stat_name.capitalize())


func _add_return_button() -> void:
	var return_button := Button.new()
	return_button.text = "Return to Party"
	return_button.pressed.connect(func() -> void: return_requested.emit())
	content.add_child(return_button)


func _type_color(type_name: String) -> Color:
	return TYPE_PALETTE.color_for(type_name)


func _portrait_texture(mon: Dictionary) -> Texture2D:
	var art_id := String(mon.get("art_id", ""))
	if art_id.is_empty():
		return null
	for path_template: String in PORTRAIT_PATH_TEMPLATES:
		var portrait_path := path_template % art_id
		if ResourceLoader.exists(portrait_path):
			return load(portrait_path) as Texture2D
	return null


func _fakemon_types(mon: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if mon.has("types"):
		for type_name: Variant in mon["types"]:
			var normalized := String(type_name)
			if not normalized.is_empty() and not result.has(normalized):
				result.append(normalized)
	elif not String(mon.get("type", "")).is_empty():
		result.append(String(mon["type"]))
	return result


func _egg_groups(mon: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for group_name: Variant in mon.get("egg_groups", []):
		var normalized := String(group_name)
		if not normalized.is_empty() and not result.has(normalized):
			result.append(normalized)
	return result
