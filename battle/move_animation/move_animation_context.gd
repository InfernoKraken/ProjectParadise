class_name MoveAnimationContext
extends RefCounted

var user: CanvasItem
var target: CanvasItem
var user_art_id := ""
var target_art_id := ""
var user_effect_data: Dictionary = {}
var target_effect_data: Dictionary = {}
var user_side := "Player"
var target_side := "Wild"
var anchor_repository: GeneratedAnchorRepository
var effect_layer: Node2D
var background_overlay: ColorRect

func battler(which: String) -> CanvasItem:
	return user if which == "user" else target

func battler_side(which: String) -> String:
	return user_side if which == "user" else target_side

func resolve(position: Dictionary) -> Vector2:
	var which := String(position.get("battler", "user"))
	var node := battler(which)
	var art_id := user_art_id if which == "user" else target_art_id
	var side := user_side if which == "user" else target_side
	var local := anchor_repository.get_battle_anchor(art_id, side, String(position.get("anchor", "origin")))
	var offset: Array = position.get("offset", [0, 0])
	return node.position + local + Vector2(float(offset[0]), float(offset[1]))
