class_name BattleAnimator
extends Node

signal move_impacted
signal move_animation_marker(marker_name: String)

@export var animations_enabled := true
@onready var vfx: MoveVFX = $MoveVFX

const TYPE_PALETTE := preload("res://data/type_palette.gd")

var definition_player: MoveAnimationPlayer


func _ready() -> void:
	definition_player = MoveAnimationPlayer.new()
	definition_player.name = "MoveAnimationPlayer"
	definition_player.marker_reached.connect(func(marker_name: String):
		move_animation_marker.emit(marker_name)
		if marker_name == "impact": move_impacted.emit()
	)
	add_child(definition_player)


func play_definition(animation_id: String, context: MoveAnimationContext) -> bool:
	var definition := MoveAnimationDefinition.load_file("res://data/move_animations/%s.json" % animation_id)
	if definition == null or String(definition.data.get("id", "")) != animation_id or not definition.validation_errors().is_empty():
		push_warning("Move animation '%s' could not be loaded." % animation_id)
		return false
	return await definition_player.play(definition, context)


func stop_definition() -> void:
	if definition_player != null: definition_player.cancel()


func play_move(move: Dictionary, caster: Control, target: Control, move_id := "", semantic_marker := "") -> void:
	if not animations_enabled or not is_inside_tree():
		move_impacted.emit()
		_emit_semantic_marker(semantic_marker)
		return
	var selection := MoveAnimationResolver.resolve(move_id, move, default_preset(move))
	for warning: String in selection["warnings"]:
		push_warning(warning)
	var animation_id := String(selection["animation_id"])
	if not animation_id.is_empty():
		var context := _create_context(caster, target)
		var custom_did_impact := false
		var note_custom_impact := func() -> void:
			custom_did_impact = true
			_emit_semantic_marker(semantic_marker)
		move_impacted.connect(note_custom_impact, CONNECT_ONE_SHOT)
		var played := await play_definition(animation_id, context)
		if played:
			if not custom_did_impact:
				move_impacted.emit()
			if not custom_did_impact:
				_emit_semantic_marker(semantic_marker)
			return
	var fallback := String(selection["fallback_animation"])
	if fallback.is_empty():
		move_impacted.emit()
		_emit_semantic_marker(semantic_marker)
		return
	await play_windup(caster, fallback)
	var did_impact := false
	var mark_impact := func() -> void:
		did_impact = true
		move_impacted.emit()
		_emit_semantic_marker(semantic_marker)
	vfx.impact.connect(mark_impact, CONNECT_ONE_SHOT)
	await vfx.play(fallback, caster, target, color_for_move(move))
	if not did_impact:
		move_impacted.emit()
		_emit_semantic_marker(semantic_marker)


func _emit_semantic_marker(marker_name: String) -> void:
	if not marker_name.is_empty():
		move_animation_marker.emit(marker_name)


func _create_context(caster: Control, target: Control) -> MoveAnimationContext:
	var context := MoveAnimationContext.new()
	context.user = caster
	context.target = target
	context.user_art_id = String(caster.get_meta("art_id", ""))
	context.target_art_id = String(target.get_meta("art_id", ""))
	context.user_effect_data = caster.get_meta("move_effect_data", {}).duplicate(true)
	context.target_effect_data = target.get_meta("move_effect_data", {}).duplicate(true)
	context.user_side = String(caster.get_meta("battle_side", "Player"))
	context.target_side = String(target.get_meta("battle_side", "Wild"))
	context.anchor_repository = GeneratedAnchorRepository.new()
	context.effect_layer = vfx
	var overlay := ColorRect.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.hide()
	get_parent().add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	context.background_overlay = overlay
	definition_player.animation_finished.connect(overlay.queue_free, CONNECT_ONE_SHOT)
	definition_player.animation_cancelled.connect(overlay.queue_free, CONNECT_ONE_SHOT)
	return context


func play_windup(caster: Control, preset: String) -> void:
	var original_scale := caster.scale
	var tween := create_tween()
	var windup_scale := Vector2(0.92, 1.08) if preset == "caster_lunge" else Vector2(1.08, 0.94)
	tween.tween_property(caster, "scale", windup_scale, 0.1)
	tween.tween_property(caster, "scale", original_scale, 0.1)
	await tween.finished


func default_preset(move: Dictionary) -> String:
	if not String(move.get("sets_weather", "")).is_empty():
		return "field_overlay"
	if String(move.get("damage_class", "")) == "Status":
		return "buff_swirl" if not move.get("stat_changes", []).is_empty() or bool(move.get("cures_conditions", false)) else "floating_icon"
	if String(move.get("damage_class", "")) == "Physical":
		return "caster_lunge"
	if String(move.get("type", "")) in ["Fire", "Plant", "Mystic"]:
		return "target_burst"
	return "projectile"


func color_for_move(move: Dictionary) -> Color:
	return TYPE_PALETTE.color_for(String(move.get("type", "Normal")))
