class_name BattleEffectInstance
extends RefCounted

const OWNERS := [&"user_battler", &"target_battler", &"battle"]
const TRIGGERS := [&"start_of_turn", &"end_of_turn"]
const PAYLOAD_KINDS := [&"heal", &"damage", &"condition", &"stat_change"]
const STACKING_MODES := [&"replace_group", &"stack", &"refresh", &"reject"]

var effect_id: StringName
var effect_group: StringName
var owner: StringName
var owner_key: StringName
var owner_battler: Dictionary
var trigger: StringName
var stacking: StringName
var payload: Dictionary
var animation_id: StringName

var source_move: StringName
var source_battler: Dictionary
var target_battler: Dictionary
var remaining_delay: int
var remaining_triggers: int


static func from_recipe(recipe: Dictionary, move_id: String, source: Dictionary, target: Dictionary, resolved_owner_key: String) -> Variant:
	var error := validation_error(recipe)
	if not error.is_empty():
		push_warning("Scheduled effect rejected: %s" % error)
		return null
	var instance := new()
	instance.effect_id = StringName(recipe["effect_id"])
	instance.effect_group = StringName(recipe.get("effect_group", ""))
	instance.owner = StringName(recipe["owner"])
	instance.owner_key = StringName(resolved_owner_key)
	instance.owner_battler = {} if instance.owner == &"battle" else (source if instance.owner == &"user_battler" else target)
	instance.trigger = StringName(recipe["trigger"])
	instance.stacking = StringName(recipe.get("stacking", "replace_group"))
	instance.payload = (recipe["payload"] as Dictionary).duplicate(true)
	instance.animation_id = StringName(recipe.get("animation_id", ""))
	instance.source_move = StringName(move_id)
	instance.source_battler = source
	instance.target_battler = target
	instance.remaining_delay = int(recipe.get("delay_turns", 0))
	instance.remaining_triggers = int(recipe.get("repeat_count", 1))
	return instance


static func validation_error(recipe: Dictionary) -> String:
	if String(recipe.get("effect_id", "")).is_empty(): return "effect_id is required"
	if not StringName(recipe.get("owner", "")) in OWNERS: return "unsupported owner '%s'" % recipe.get("owner", "")
	if not StringName(recipe.get("trigger", "")) in TRIGGERS: return "unsupported trigger '%s'" % recipe.get("trigger", "")
	if int(recipe.get("delay_turns", 0)) < 0: return "delay_turns cannot be negative"
	if int(recipe.get("repeat_count", 1)) < 1: return "repeat_count must be positive"
	if not StringName(recipe.get("stacking", "replace_group")) in STACKING_MODES: return "unsupported stacking mode"
	if StringName(recipe.get("stacking", "replace_group")) != &"replace_group": return "only replace_group is implemented in v1"
	var value: Variant = recipe.get("payload")
	if not value is Dictionary: return "payload must be an object"
	if not StringName((value as Dictionary).get("kind", "")) in PAYLOAD_KINDS: return "unsupported payload kind"
	return ""
