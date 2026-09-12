class_name MoveCreatorModel
extends RefCounted

const BATTLE_EFFECT_INSTANCE := preload("res://battle/battle_effect_instance.gd")
const DATA_PATH := "res://data/battle_data.json"
const ANIMATION_DIR := "res://data/move_animations"
const DAMAGE_CLASSES := ["Physical", "Special", "Status"]
const STATS := ["attack", "defense", "special_attack", "special_defense", "speed"]
const FALLBACK_ANIMATIONS := ["target_hit", "caster_lunge", "projectile", "target_burst", "buff_swirl", "field_overlay", "target_shake", "floating_icon"]
const FIELD_REGISTRY := {
	"name": {"label":"Name", "type":"string", "default":""},
	"description": {"label":"Description", "type":"string", "default":""},
	"power": {"label":"Power", "type":"integer", "default":0, "min":0},
	"type": {"label":"Type", "type":"choice"},
	"damage_class": {"label":"Damage Class", "type":"choice"},
	"animation_id": {"label":"Animation ID", "type":"choice", "optional":true},
	"fallback_animation": {"label":"Fallback Animation", "type":"choice", "optional":true},
	"condition": {"label":"Condition", "type":"choice", "optional":true},
	"condition_chance": {"label":"Condition Chance", "type":"float", "min":0.0, "max":1.0, "optional":true},
	"stat_changes": {"label":"Stat Changes", "type":"array", "optional":true},
	"priority": {"label":"Priority", "type":"integer", "optional":true},
	"min_hits": {"label":"Minimum Hits", "type":"integer", "optional":true},
	"max_hits": {"label":"Maximum Hits", "type":"integer", "optional":true},
	"scheduled_effect": {"label":"Scheduled Effect", "type":"dictionary", "optional":true}
}

var data: Dictionary = {}
var path := DATA_PATH
var selected_id := ""
var selected_move: Dictionary = {}
var dirty := false
var is_new := false

func load_database(source_path := DATA_PATH) -> Error:
	path = source_path
	if not FileAccess.file_exists(path): return ERR_FILE_NOT_FOUND
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary: return ERR_PARSE_ERROR
	data = parser.data
	if not data.get("moves", {}) is Dictionary: return ERR_INVALID_DATA
	return OK

func move_ids() -> PackedStringArray:
	var values: Array[String] = []
	for move_id: Variant in data.get("moves", {}).keys(): values.append(String(move_id))
	values.sort_custom(func(a: String, b: String): return display_label(a).naturalnocasecmp_to(display_label(b)) < 0)
	return PackedStringArray(values)

func display_label(move_id: String) -> String:
	var move: Dictionary = data.get("moves", {}).get(move_id, {})
	var name := String(move.get("name", move_id))
	var duplicate := false
	for other_id: Variant in data.get("moves", {}).keys():
		if String(other_id) != move_id and String(data["moves"][other_id].get("name", "")) == name: duplicate = true; break
	return "%s (%s)" % [name, move_id] if duplicate else name

func missing_description_move_ids() -> PackedStringArray:
	var result: Array[String] = []
	for move_id: Variant in data.get("moves", {}).keys():
		var move: Dictionary = data["moves"][move_id]
		if String(move.get("description", "")).strip_edges().is_empty(): result.append(String(move_id))
	result.sort_custom(func(a: String, b: String): return display_label(a).naturalnocasecmp_to(display_label(b)) < 0)
	return PackedStringArray(result)

func select_move(move_id: String) -> bool:
	if not data.get("moves", {}).has(move_id): return false
	selected_id = move_id; selected_move = (data["moves"][move_id] as Dictionary).duplicate(true); dirty = false; is_new = false
	if not selected_move.has("fallback_animation") and selected_move.has("animation_kind"):
		selected_move["fallback_animation"] = selected_move["animation_kind"]
	return true

func create_move(move_id: String, name: String, type: String, damage_class: String) -> PackedStringArray:
	var errors := PackedStringArray()
	if not MoveAnimationDefinition.is_valid_animation_id(move_id): errors.append("Move ID must use lowercase snake_case.")
	if data.get("moves", {}).has(move_id): errors.append("Move ID '%s' already exists." % move_id)
	if name.strip_edges().is_empty(): errors.append("Name is required.")
	if not types().has(type): errors.append("Type is invalid.")
	if not DAMAGE_CLASSES.has(damage_class): errors.append("Damage Class is invalid.")
	if not errors.is_empty(): return errors
	selected_id = move_id; selected_move = {"name":name, "description":"", "power":0, "type":type, "damage_class":damage_class}; dirty = true; is_new = true
	return errors

func set_field(key: String, value: Variant) -> void:
	if not FIELD_REGISTRY.has(key): return
	if value == null or (value is String and String(value).is_empty() and bool(FIELD_REGISTRY[key].get("optional", false))): selected_move.erase(key)
	else: selected_move[key] = value
	dirty = true

func multi_hit_enabled() -> bool:
	return selected_move.has("min_hits") or selected_move.has("max_hits")

func set_multi_hit_enabled(enabled: bool) -> void:
	if enabled:
		selected_move["min_hits"] = maxi(int(selected_move.get("min_hits", 2)), 1)
		selected_move["max_hits"] = maxi(int(selected_move.get("max_hits", selected_move["min_hits"])), int(selected_move["min_hits"]))
	else:
		selected_move.erase("min_hits"); selected_move.erase("max_hits")
	dirty = true

func scheduled_effect_enabled() -> bool:
	return selected_move.get("scheduled_effect") is Dictionary

func set_scheduled_effect_enabled(enabled: bool) -> void:
	if enabled and not scheduled_effect_enabled():
		var ids := effect_ids(); var effect_id := ids[0] if not ids.is_empty() else "effect"
		selected_move["scheduled_effect"] = {"effect_id":effect_id,"effect_group":"after_move_effect","owner":"target_battler","trigger":"end_of_turn","delay_turns":0,"repeat_count":1,"stacking":"replace_group","payload":{"kind":"heal","amount":0.1},"animation_id":""}
	elif not enabled: selected_move.erase("scheduled_effect")
	dirty = true

func set_scheduled_effect_field(key: String, value: Variant) -> void:
	if not scheduled_effect_enabled(): return
	var recipe: Dictionary = selected_move["scheduled_effect"]
	if value == null or (value is String and String(value).is_empty() and key == "animation_id"): recipe.erase(key)
	else: recipe[key] = value
	dirty = true

func set_scheduled_payload_kind(kind: String) -> void:
	if not scheduled_effect_enabled() or not effect_payload_kinds().has(kind): return
	var payload := {"kind":kind}
	match kind:
		"heal", "damage": payload["amount"] = 0.1
		"condition": payload["condition"] = conditions()[0] if not conditions().is_empty() else ""; payload["chance"] = 1.0
		"stat_change": payload["stat"] = "attack"; payload["amount"] = 0.1
	selected_move["scheduled_effect"]["payload"] = payload; dirty = true

func set_scheduled_payload_field(key: String, value: Variant) -> void:
	if not scheduled_effect_enabled(): return
	var recipe: Dictionary = selected_move["scheduled_effect"]; var payload: Dictionary = recipe.get("payload", {}).duplicate(true); payload[key] = value; recipe["payload"] = payload; dirty = true

func effect_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for move: Dictionary in data.get("moves", {}).values():
		var recipe: Variant = move.get("scheduled_effect")
		if recipe is Dictionary:
			var effect_id := String(recipe.get("effect_id", "")); if not effect_id.is_empty() and not result.has(effect_id): result.append(effect_id)
	result.sort(); return result

func effect_groups() -> PackedStringArray:
	var result := PackedStringArray()
	for move: Dictionary in data.get("moves", {}).values():
		var recipe: Variant = move.get("scheduled_effect")
		if recipe is Dictionary:
			var group := String(recipe.get("effect_group", "")); if not group.is_empty() and not result.has(group): result.append(group)
	result.sort(); return result

func effect_owners() -> PackedStringArray:
	var result := PackedStringArray()
	for value: StringName in BATTLE_EFFECT_INSTANCE.OWNERS: result.append(String(value))
	return result

func effect_triggers() -> PackedStringArray:
	var result := PackedStringArray()
	for value: StringName in BATTLE_EFFECT_INSTANCE.TRIGGERS: result.append(String(value))
	return result

func effect_payload_kinds() -> PackedStringArray:
	var result := PackedStringArray()
	for value: StringName in BATTLE_EFFECT_INSTANCE.PAYLOAD_KINDS: result.append(String(value))
	return result

func add_stat_change(stat := "attack", amount := 0.1) -> void:
	var changes: Array = selected_move.get("stat_changes", []).duplicate(true); changes.append({"stat":stat,"amount":amount}); selected_move["stat_changes"] = changes; dirty = true

func remove_stat_change(index: int) -> void:
	var changes: Array = selected_move.get("stat_changes", []).duplicate(true)
	if index >= 0 and index < changes.size(): changes.remove_at(index)
	if changes.is_empty(): selected_move.erase("stat_changes")
	else: selected_move["stat_changes"] = changes
	dirty = true

func set_stat_change(index: int, stat: String, amount: float) -> void:
	var changes: Array = selected_move.get("stat_changes", []).duplicate(true)
	if index >= 0 and index < changes.size(): changes[index] = {"stat":stat,"amount":amount}; selected_move["stat_changes"] = changes; dirty = true

func unknown_fields() -> Dictionary:
	var result := {}
	for key: Variant in selected_move.keys():
		if not FIELD_REGISTRY.has(String(key)) and String(key) != "animation_kind": result[key] = selected_move[key]
	return result

func apply_additional_fields_json(text: String) -> String:
	var parser := JSON.new()
	if parser.parse(text) != OK: return "Invalid JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
	if not parser.data is Dictionary: return "Additional fields must be a JSON object of key-value pairs."
	for key: Variant in parser.data.keys():
		if FIELD_REGISTRY.has(String(key)) or String(key) == "animation_kind": return "'%s' is a structured field; edit it with its dedicated control." % key
	for key: Variant in unknown_fields().keys(): selected_move.erase(key)
	for key: Variant in parser.data.keys(): selected_move[String(key)] = parser.data[key]
	dirty = true
	return ""

func apply_raw_move_json(text: String) -> String:
	var parser := JSON.new()
	if parser.parse(text) != OK: return "Invalid JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
	if not parser.data is Dictionary: return "A move must be a JSON object."
	selected_move = (parser.data as Dictionary).duplicate(true); dirty = true
	return ""

func validation_errors(animation_ids := PackedStringArray()) -> PackedStringArray:
	var errors := PackedStringArray()
	if not MoveAnimationDefinition.is_valid_animation_id(selected_id): errors.append("Move ID must use lowercase snake_case.")
	if String(selected_move.get("name", "")).strip_edges().is_empty(): errors.append("Name is required.")
	if not types().has(String(selected_move.get("type", ""))): errors.append("Type is invalid.")
	if not DAMAGE_CLASSES.has(String(selected_move.get("damage_class", ""))): errors.append("Damage Class is invalid.")
	if float(selected_move.get("power", -1)) < 0: errors.append("Power must be zero or greater.")
	var condition := String(selected_move.get("condition", ""))
	if not condition.is_empty() and not conditions().has(condition): errors.append("Condition is invalid.")
	if selected_move.has("condition_chance") and (float(selected_move["condition_chance"]) < 0.0 or float(selected_move["condition_chance"]) > 1.0): errors.append("Condition Chance must be between 0 and 1.")
	for change: Variant in selected_move.get("stat_changes", []):
		if not change is Dictionary or not STATS.has(String(change.get("stat", ""))) or not change.has("amount"): errors.append("Stat Changes contain an invalid row.")
	var animation_id := String(selected_move.get("animation_id", ""))
	if not animation_id.is_empty() and not animation_ids.has(animation_id): errors.append("Custom animation '%s' does not exist." % animation_id)
	var fallback := String(selected_move.get("fallback_animation", selected_move.get("animation_kind", "")))
	if not fallback.is_empty() and not FALLBACK_ANIMATIONS.has(fallback): errors.append("Fallback Animation is invalid.")
	if multi_hit_enabled():
		var minimum := int(selected_move.get("min_hits", 0)); var maximum := int(selected_move.get("max_hits", 0))
		if minimum < 1 or maximum < 1: errors.append("Multi-Hit counts must be positive.")
		elif minimum > maximum: errors.append("Multi-Hit minimum cannot exceed maximum.")
	if scheduled_effect_enabled():
		var recipe: Dictionary = selected_move["scheduled_effect"]; var recipe_error := BATTLE_EFFECT_INSTANCE.validation_error(recipe)
		if not recipe_error.is_empty(): errors.append("Scheduled Effect: %s." % recipe_error)
		var payload: Variant = recipe.get("payload")
		if payload is Dictionary:
			var kind := String(payload.get("kind", ""))
			if kind in ["heal", "damage"] and (not payload.has("amount") or float(payload.get("amount", -1.0)) < 0.0): errors.append("Scheduled Effect %s payload requires a non-negative amount." % kind)
			elif kind == "condition":
				if not conditions().has(String(payload.get("condition", ""))): errors.append("Scheduled Effect condition payload is invalid.")
				var chance := float(payload.get("chance", -1.0)); if chance < 0.0 or chance > 1.0: errors.append("Scheduled Effect condition chance must be between 0 and 1.")
			elif kind == "stat_change":
				if not STATS.has(String(payload.get("stat", ""))) or not payload.has("amount"): errors.append("Scheduled Effect stat-change payload is invalid.")
		var effect_animation := String(recipe.get("animation_id", ""))
		if not effect_animation.is_empty() and not animation_ids.has(effect_animation): errors.append("Scheduled Effect activation animation '%s' does not exist." % effect_animation)
	return errors

func save(animation_ids := PackedStringArray()) -> Error:
	if not validation_errors(animation_ids).is_empty(): return ERR_INVALID_DATA
	var merged := selected_move.duplicate(true)
	if merged.has("fallback_animation"): merged.erase("animation_kind")
	data["moves"][selected_id] = merged
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "  ") + "\n")
	dirty = false; is_new = false; selected_move = merged.duplicate(true)
	return OK

func animation_reference_count(animation_id: String, excluding_move_id := "") -> int:
	if animation_id.is_empty(): return 0
	var count := 0
	for move_id: Variant in data.get("moves", {}).keys():
		if String(move_id) == excluding_move_id: continue
		var move: Dictionary = data["moves"][move_id]
		if String(move.get("animation_id", "")) == animation_id: count += 1
		var recipe: Variant = move.get("scheduled_effect")
		if recipe is Dictionary and String(recipe.get("animation_id", "")) == animation_id: count += 1
	return count

func delete_selected_move() -> Error:
	if selected_id.is_empty() or not data.get("moves", {}).has(selected_id): return ERR_DOES_NOT_EXIST
	var updated := data.duplicate(true); updated["moves"].erase(selected_id)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(updated, "  ") + "\n")
	data = updated; selected_id = ""; selected_move = {}; dirty = false; is_new = false
	return OK

func types() -> PackedStringArray:
	var result := PackedStringArray()
	for move: Dictionary in data.get("moves", {}).values():
		var value := String(move.get("type", "")); if not value.is_empty() and not result.has(value): result.append(value)
	result.sort(); return result

func conditions() -> PackedStringArray:
	var result := PackedStringArray()
	for condition: Variant in data.get("conditions", {}).keys(): result.append(String(condition))
	result.sort(); return result
