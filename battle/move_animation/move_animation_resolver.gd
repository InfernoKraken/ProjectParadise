class_name MoveAnimationResolver
extends RefCounted

const ANIMATION_DIRECTORY := "res://data/move_animations"
const FALLBACK_PRESETS := [
	"target_hit", "caster_lunge", "projectile", "target_burst",
	"buff_swirl", "field_overlay", "target_shake", "floating_icon"
]


static func resolve(move_id: String, move: Dictionary, default_fallback := "") -> Dictionary:
	var result := {"animation_id": "", "fallback_animation": "", "warnings": PackedStringArray()}
	var warnings: PackedStringArray = result["warnings"]
	var custom_value: Variant = move.get("animation_id", "")
	if move.has("animation_id") and (not custom_value is String or String(custom_value).is_empty() or not String(custom_value).is_valid_identifier()):
		warnings.append("Move '%s' has malformed animation_id '%s'." % [move_id, custom_value])
	else:
		var animation_id := String(custom_value)
		if not animation_id.is_empty():
			var path := "%s/%s.json" % [ANIMATION_DIRECTORY, animation_id]
			var definition := MoveAnimationDefinition.load_file(path)
			if definition == null:
				warnings.append("Move '%s' references unknown animation_id '%s'." % [move_id, animation_id])
			elif String(definition.data.get("id", "")) != animation_id or not definition.validation_errors().is_empty():
				warnings.append("Move '%s' references invalid animation_id '%s'." % [move_id, animation_id])
			else:
				result["animation_id"] = animation_id

	if move.has("fallback_animation") and move.has("animation_kind"):
		warnings.append("Move '%s' defines fallback_animation and deprecated animation_kind; fallback_animation takes precedence." % move_id)
	var fallback_value: Variant = move.get("fallback_animation", move.get("animation_kind", default_fallback))
	if not fallback_value is String or (not String(fallback_value).is_empty() and not FALLBACK_PRESETS.has(String(fallback_value))):
		warnings.append("Move '%s' has malformed fallback_animation '%s'." % [move_id, fallback_value])
	else:
		result["fallback_animation"] = String(fallback_value)
	return result
