class_name BattleAnimator
extends Node

signal move_impacted

@export var animations_enabled := true
@onready var vfx: MoveVFX = $MoveVFX

const TYPE_PALETTE := preload("res://data/type_palette.gd")


func play_move(move: Dictionary, caster: Control, target: Control) -> void:
	if not animations_enabled or not is_inside_tree():
		move_impacted.emit()
		return
	await play_windup(caster, String(move.get("animation_kind", default_preset(move))))
	var did_impact := false
	var mark_impact := func() -> void:
		did_impact = true
		move_impacted.emit()
	vfx.impact.connect(mark_impact, CONNECT_ONE_SHOT)
	await vfx.play(String(move.get("animation_kind", default_preset(move))), caster, target, color_for_move(move))
	if not did_impact:
		move_impacted.emit()


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
