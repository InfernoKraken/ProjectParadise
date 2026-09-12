class_name MoveAnimationPlayer
extends Node

const CONTEXTUAL_ASSETS := preload("res://battle/move_animation/contextual_move_effect_resolver.gd")

signal marker_reached(marker_name: String)
signal animation_finished
signal animation_cancelled

var _context: MoveAnimationContext
var _effects := {}
var _tweens: Array[Tween] = []
var _baselines := {}
var _original_z := {}
var _original_scales := {}
var _cancelled := false
var _generation := 0

func play(definition: MoveAnimationDefinition, context: MoveAnimationContext) -> bool:
	cancel(false)
	var generation := _generation
	var errors := definition.validation_errors()
	if not errors.is_empty():
		push_warning("Move animation rejected: %s" % "; ".join(errors)); return false
	_context = context; _cancelled = false
	_baselines = {"user": context.user.position, "target": context.target.position}
	_original_z = {"user": context.user.z_index, "target": context.target.z_index}
	_original_scales = {"user": context.user.scale, "target": context.target.scale}
	var started := Time.get_ticks_msec() / 1000.0
	for event: Dictionary in definition.data.get("events", []):
		var wait_time := float(event.get("time", 0.0)) - (Time.get_ticks_msec() / 1000.0 - started)
		if wait_time > 0.0: await get_tree().create_timer(wait_time).timeout
		if _cancelled or generation != _generation: return false
		_execute(event)
	var remaining := definition.duration() - (Time.get_ticks_msec() / 1000.0 - started)
	if remaining > 0.0: await get_tree().create_timer(remaining).timeout
	if _cancelled or generation != _generation: return false
	_cleanup(); animation_finished.emit(); return true

func cancel(emit_signal := true) -> void:
	var was_active := _context != null
	_generation += 1
	_cancelled = true; _cleanup()
	if was_active and emit_signal: animation_cancelled.emit()

func _execute(event: Dictionary) -> void:
	match String(event.get("type", "")):
		"spawn_sprite": _spawn(event)
		"impact_sprite": _impact_sprite(event)
		"beam": _beam(event)
		"vertical_sprite": _vertical_sprite(event)
		"move_sprite": _tween_effect(event, "position", _context.resolve(event["to"]))
		"fade_sprite": _fade_effect(event)
		"destroy_sprite": _destroy(String(event.get("instance_id", "")))
		"shake_battler": _shake(event)
		"move_battler": _move_battler(event)
		"scale_battler": _scale_battler(event)
		"background_tint": _tint(event)
		"restore_background": _restore_background(float(event.get("duration", 0.0)))
		"marker": marker_reached.emit(String(event.get("name", "")))

func _spawn(event: Dictionary) -> void:
	var sprite := _create_sprite(event)
	_context.effect_layer.add_child(sprite); _effects[String(event["instance_id"])] = sprite
	if event.get("sprite_sheet") is Dictionary: _animate_sheet(sprite, event["sprite_sheet"])

func _create_sprite(event: Dictionary) -> Sprite2D:
	var asset_path: String = CONTEXTUAL_ASSETS.resolve_asset(String(event["asset"]), _context.user_effect_data)
	var sprite := Sprite2D.new(); sprite.texture = MoveEffectAssetRules.load_texture(asset_path); sprite.position = _context.resolve(event["position"])
	sprite.set_meta("resolved_asset_path", asset_path)
	sprite.flip_h = MoveEffectAssetRules.should_flip_h(asset_path, _context.user_side)
	sprite.scale = Vector2.ONE * float(event.get("scale", 1.0)); sprite.rotation_degrees = float(event.get("rotation", 0.0)); sprite.modulate = Color(String(event.get("tint", "#FFFFFF"))); sprite.modulate.a *= float(event.get("opacity", 1.0))
	var sheet: Variant = event.get("sprite_sheet")
	if sheet is Dictionary:
		sprite.hframes = int(sheet.get("columns", 1)); sprite.vframes = int(sheet.get("rows", 1))
	sprite.z_as_relative = false
	sprite.z_index = 5 if bool(event.get("is_behind", false)) else 20
	return sprite

func _impact_sprite(event: Dictionary) -> void:
	var sprite := _create_sprite(event)
	_context.effect_layer.add_child(sprite)
	var instance_id := String(event.get("instance_id", ""))
	if instance_id.is_empty(): instance_id = "__impact_%d" % sprite.get_instance_id()
	_effects[instance_id] = sprite
	if event.get("sprite_sheet") is Dictionary: _animate_sheet(sprite, event["sprite_sheet"])
	var lifetime := create_tween(); _tweens.append(lifetime)
	lifetime.tween_interval(float(event.get("duration", 0.3)))
	lifetime.tween_callback(_destroy.bind(instance_id))

func _beam(event: Dictionary) -> void:
	var asset_path: String = CONTEXTUAL_ASSETS.resolve_asset(String(event.get("asset", "")), _context.user_effect_data)
	var texture := MoveEffectAssetRules.load_texture(asset_path)
	if texture == null: return
	var start := _context.resolve(event.get("from", {})); var end := _context.resolve(event.get("to", {}))
	var vector := end - start; var texture_size := texture.get_size()
	var sprite := Sprite2D.new(); sprite.texture = texture; sprite.position = (start + end) * 0.5; sprite.rotation = vector.angle()
	sprite.set_meta("resolved_asset_path", asset_path)
	sprite.flip_h = MoveEffectAssetRules.should_flip_h(asset_path, _context.user_side)
	sprite.scale = Vector2(vector.length() / maxf(texture_size.x, 1.0), float(event.get("width", 16.0)) / maxf(texture_size.y, 1.0))
	sprite.modulate = Color(String(event.get("tint", "#FFFFFF"))); sprite.modulate.a *= float(event.get("opacity", 1.0)); sprite.z_as_relative = false
	_apply_beam_layer(sprite, String(event.get("layer", "above_battlers")), start, end)
	_context.effect_layer.add_child(sprite)
	var instance_id := String(event.get("instance_id", "")); _effects[instance_id] = sprite
	var duration := float(event.get("duration", 0.5))
	if duration >= 0.0:
		var lifetime := create_tween(); _tweens.append(lifetime); lifetime.tween_interval(duration); lifetime.tween_callback(_destroy.bind(instance_id))

func _vertical_sprite(event: Dictionary) -> void:
	var sprite := _create_sprite({"asset":event.get("asset", ""),"position":event.get("position", {}),"scale":event.get("scale", 1.0),"rotation":event.get("rotation", 0.0),"opacity":event.get("opacity", 1.0),"tint":event.get("tint", "#FFFFFF"),"is_behind":event.get("is_behind", false)})
	var anchor := _context.resolve(event.get("position", {})); var distance := float(event.get("distance", 100.0)); var mode := String(event.get("mode", "fall_to_anchor"))
	var destination := anchor
	if mode == "fall_to_anchor": sprite.position = anchor - Vector2(0.0, distance)
	else: sprite.position = anchor; destination = anchor - Vector2(0.0, distance)
	_context.effect_layer.add_child(sprite); var instance_id := String(event.get("instance_id", "vertical_effect")); _effects[instance_id] = sprite
	var tween := create_tween(); _tweens.append(tween); tween.tween_property(sprite, "position", destination, float(event.get("duration", 0.5))); tween.tween_callback(_destroy.bind(instance_id))

func _apply_beam_layer(sprite: Sprite2D, layer: String, start: Vector2, end: Vector2) -> void:
	match layer:
		"behind_battlers": sprite.z_index = 5
		"above_battlers": sprite.z_index = 20
		"below_user_above_target":
			_context.target.z_index = 9; sprite.z_index = 10; _context.user.z_index = 11
		"between_battlers":
			# Screen depth, rather than Player/Wild side, defines normal battler ordering.
			var user_is_front: bool = _context.user.position.y >= _context.target.position.y
			_context.user.z_index = 11 if user_is_front else 9; _context.target.z_index = 9 if user_is_front else 11; sprite.z_index = 10

func _free_sprite(sprite_reference: WeakRef) -> void:
	var sprite := sprite_reference.get_ref() as Sprite2D
	if sprite != null: sprite.queue_free()

func _animate_sheet(sprite: Sprite2D, sheet: Dictionary) -> void:
	var frame_count := int(sheet["frame_count"]); var fps := float(sheet["fps"]); var loop := bool(sheet.get("loop", false)); var duration := frame_count / fps
	var tween := create_tween(); _tweens.append(tween)
	tween.tween_method(_set_sheet_frame.bind(weakref(sprite), fps, frame_count), 0.0, duration, duration)
	if loop: tween.set_loops()


func _set_sheet_frame(value: float, sprite_reference: WeakRef, fps: float, frame_count: int) -> void:
	var sprite := sprite_reference.get_ref() as Sprite2D
	if sprite != null:
		sprite.frame = mini(int(value * fps), frame_count - 1)

func _tween_effect(event: Dictionary, property: NodePath, value: Variant) -> void:
	var sprite: Sprite2D = _effects.get(String(event.get("instance_id", "")))
	if not is_instance_valid(sprite): push_warning("Inactive move effect reference."); return
	var tween := create_tween(); _tweens.append(tween); tween.tween_property(sprite, property, value, float(event.get("duration", 0.0))).set_trans(_transition(String(event.get("easing", "linear"))))

func _fade_effect(event: Dictionary) -> void:
	var instance_id := String(event.get("instance_id", ""))
	var sprite: Sprite2D = _effects.get(instance_id)
	if not is_instance_valid(sprite): push_warning("Inactive move effect reference."); return
	var tween := create_tween(); _tweens.append(tween)
	tween.tween_property(sprite, "modulate:a", float(event.get("opacity", 1.0)), float(event.get("duration", 0.0)))
	if float(event.get("opacity", 1.0)) <= 0.0: tween.tween_callback(_destroy.bind(instance_id))

func _destroy(id: String) -> void:
	var sprite: Sprite2D = _effects.get(id)
	if is_instance_valid(sprite): sprite.queue_free()
	_effects.erase(id)

func _shake(event: Dictionary) -> void:
	var which := String(event["battler"]); var node := _context.battler(which); var origin: Vector2 = _baselines[which]; var magnitude := float(event.get("magnitude", 6.0)); var duration := float(event.get("duration", 0.2)); var tween := create_tween(); _tweens.append(tween)
	for offset in [magnitude, -magnitude, magnitude * 0.5, -magnitude * 0.5, 0.0]: tween.tween_property(node, "position", origin + Vector2(offset, 0), duration / 5.0)

func _move_battler(event: Dictionary) -> void:
	var which := String(event["battler"]); var node := _context.battler(which); var origin: Vector2 = _baselines[which]; var destination := origin
	var movement := String(event.get("direction", ""))
	if movement in ["vertical", "baseline"]:
		destination = origin + Vector2(0.0, float(event.get("distance", 0.0)))
	else:
		var other: CanvasItem = _context.target if which == "user" else _context.user; var direction: Vector2 = (other.position - origin).normalized()
		if movement == "away_from_target": direction = -direction
		destination += direction * float(event.get("distance", 0.0))
	var tween := create_tween(); _tweens.append(tween); tween.tween_property(node, "position", destination, float(event.get("duration", 0.0)))

func _scale_battler(event: Dictionary) -> void:
	var which := String(event.get("battler", "user")); var node := _context.battler(which); var origin: Vector2 = _original_scales[which]
	var delta := float(event.get("scale_delta_percent", 50.0)) / 100.0; var factor := 1.0 + delta if String(event.get("mode", "stretch")) == "stretch" else 1.0 - delta
	var loop_duration := float(event.get("loop_duration", 0.4)); var tween := create_tween(); _tweens.append(tween)
	for _loop in int(event.get("loops", 1)):
		tween.tween_property(node, "scale", origin * factor, loop_duration * 0.5); tween.tween_property(node, "scale", origin, loop_duration * 0.5)

func _tint(event: Dictionary) -> void:
	if _context.background_overlay == null: return
	_context.background_overlay.visible = true; _context.background_overlay.color = Color(String(event["color"]), 0.0)
	var tween := create_tween(); _tweens.append(tween); tween.tween_property(_context.background_overlay, "color:a", float(event.get("opacity", 1.0)), float(event.get("duration", 0.0)))

func _restore_background(duration: float) -> void:
	if _context.background_overlay == null: return
	var tween := create_tween(); _tweens.append(tween); tween.tween_property(_context.background_overlay, "color:a", 0.0, duration)

func _transition(name: String) -> Tween.TransitionType:
	return Tween.TRANS_QUAD if name != "linear" else Tween.TRANS_LINEAR

func _cleanup() -> void:
	for tween in _tweens:
		if tween != null and tween.is_valid(): tween.kill()
	_tweens.clear()
	for sprite: Variant in _effects.values():
		if is_instance_valid(sprite): sprite.queue_free()
	_effects.clear()
	if _context != null:
		if is_instance_valid(_context.user) and _baselines.has("user"): _context.user.position = _baselines["user"]
		if is_instance_valid(_context.target) and _baselines.has("target"): _context.target.position = _baselines["target"]
		if is_instance_valid(_context.user) and _original_z.has("user"): _context.user.z_index = _original_z["user"]
		if is_instance_valid(_context.target) and _original_z.has("target"): _context.target.z_index = _original_z["target"]
		if is_instance_valid(_context.user) and _original_scales.has("user"): _context.user.scale = _original_scales["user"]
		if is_instance_valid(_context.target) and _original_scales.has("target"): _context.target.scale = _original_scales["target"]
		if is_instance_valid(_context.background_overlay): _context.background_overlay.color.a = 0.0; _context.background_overlay.visible = false
	_context = null; _baselines.clear(); _original_z.clear(); _original_scales.clear()
