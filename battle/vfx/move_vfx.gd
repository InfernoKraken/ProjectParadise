class_name MoveVFX
extends Node2D

signal impact

const PRESETS := [
	"target_hit", "caster_lunge", "projectile", "target_burst",
	"buff_swirl", "field_overlay", "target_shake", "floating_icon"
]

var _active_tween: Tween
var _caster: CanvasItem
var _target: CanvasItem
var _caster_origin := Vector2.ZERO
var _target_origin := Vector2.ZERO


func play(effect_preset: String, caster: CanvasItem, target: CanvasItem, color := Color.WHITE) -> void:
	_cleanup()
	_caster = caster
	_target = target
	_caster_origin = caster.position
	_target_origin = target.position
	var preset := effect_preset if PRESETS.has(effect_preset) else "target_hit"
	match preset:
		"caster_lunge": await _play_lunge(color)
		"projectile": await _play_projectile(color)
		"target_burst": await _play_burst(color)
		"buff_swirl": await _play_buff(color)
		"field_overlay": await _play_overlay(color)
		"target_shake": await _play_shake()
		"floating_icon": await _play_icon(color)
		_: await _play_hit(color)
	_cleanup()


func _play_hit(color: Color) -> void:
	impact.emit()
	var original := _target.modulate
	_target.modulate = color.lightened(0.65)
	_active_tween = create_tween()
	_active_tween.tween_property(_target, "position", _target_origin + (_target_origin - _caster_origin).normalized() * 18.0, 0.08)
	_active_tween.parallel().tween_property(_target, "modulate", original, 0.14)
	_active_tween.tween_property(_target, "position", _target_origin, 0.12).set_trans(Tween.TRANS_BACK)
	await _active_tween.finished


func _play_lunge(color: Color) -> void:
	var destination := _caster_origin.lerp(_target_origin, 0.32)
	_active_tween = create_tween()
	_active_tween.tween_property(_caster, "position", destination, 0.12).set_trans(Tween.TRANS_QUAD)
	await _active_tween.finished
	impact.emit()
	await _flash_disc(_target_origin, color)
	_active_tween = create_tween()
	_active_tween.tween_property(_caster, "position", _caster_origin, 0.16).set_trans(Tween.TRANS_BACK)
	await _active_tween.finished


func _play_projectile(color: Color) -> void:
	var projectile := _disc(10.0, color)
	projectile.position = _center_of(_caster)
	add_child(projectile)
	_active_tween = create_tween()
	_active_tween.tween_property(projectile, "position", _center_of(_target), 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_active_tween.parallel().tween_property(projectile, "scale", Vector2(1.6, 1.6), 0.28)
	await _active_tween.finished
	impact.emit()
	projectile.queue_free()
	await _flash_disc(_center_of(_target), color)


func _play_burst(color: Color) -> void:
	impact.emit()
	var particles := GPUParticles2D.new()
	particles.position = _center_of(_target)
	particles.amount = 18
	particles.lifetime = 0.35
	particles.one_shot = true
	particles.explosiveness = 0.9
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(0, -1, 0)
	material.spread = 180.0
	material.initial_velocity_min = 70.0
	material.initial_velocity_max = 130.0
	material.gravity = Vector3(0, 90, 0)
	material.color = color
	particles.process_material = material
	particles.texture = _circle_texture(color)
	add_child(particles)
	particles.emitting = true
	await get_tree().create_timer(0.42).timeout


func _play_buff(color: Color) -> void:
	var center := _center_of(_caster)
	var dots: Array[Polygon2D] = []
	for index in 6:
		var dot := _disc(5.0, color)
		dot.position = center + Vector2.from_angle(TAU * index / 6.0) * 32.0
		add_child(dot)
		dots.append(dot)
	impact.emit()
	_active_tween = create_tween().set_parallel(true)
	for index in dots.size():
		_active_tween.tween_property(dots[index], "position", center + Vector2.from_angle(TAU * index / 6.0 + PI) * 8.0 - Vector2(0, 45), 0.45)
		_active_tween.tween_property(dots[index], "modulate:a", 0.0, 0.45)
	await _active_tween.finished


func _play_overlay(color: Color) -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(color, 0.0)
	overlay.position = Vector2.ZERO
	overlay.size = get_viewport_rect().size
	add_child(overlay)
	_active_tween = create_tween()
	_active_tween.tween_property(overlay, "color:a", 0.28, 0.2)
	await _active_tween.finished
	impact.emit()
	_active_tween = create_tween()
	_active_tween.tween_interval(0.18)
	_active_tween.tween_property(overlay, "color:a", 0.0, 0.25)
	await _active_tween.finished


func _play_shake() -> void:
	impact.emit()
	_active_tween = create_tween()
	for offset in [Vector2(9, 0), Vector2(-9, 0), Vector2(6, 0), Vector2(-6, 0), Vector2.ZERO]:
		_active_tween.tween_property(_target, "position", _target_origin + offset, 0.045)
	await _active_tween.finished


func _play_icon(color: Color) -> void:
	var icon := _diamond(11.0, color)
	icon.position = _center_of(_target) - Vector2(0, 30)
	add_child(icon)
	impact.emit()
	_active_tween = create_tween()
	_active_tween.tween_property(icon, "position", icon.position - Vector2(0, 42), 0.5)
	_active_tween.parallel().tween_property(icon, "scale", Vector2(1.35, 1.35), 0.25)
	_active_tween.parallel().tween_property(icon, "modulate:a", 0.0, 0.5).set_delay(0.18)
	await _active_tween.finished


func _flash_disc(at: Vector2, color: Color) -> void:
	var flash := _disc(15.0, color)
	flash.position = at
	flash.scale = Vector2(0.3, 0.3)
	add_child(flash)
	_active_tween = create_tween().set_parallel(true)
	_active_tween.tween_property(flash, "scale", Vector2(2.4, 2.4), 0.16)
	_active_tween.tween_property(flash, "modulate:a", 0.0, 0.16)
	await _active_tween.finished


func _center_of(item: Control) -> Vector2:
	return item.position + item.size * 0.5


func _disc(radius: float, color: Color) -> Polygon2D:
	var polygon := Polygon2D.new()
	var points := PackedVector2Array()
	for index in 12:
		points.append(Vector2.from_angle(TAU * index / 12.0) * radius)
	polygon.polygon = points
	polygon.color = color
	return polygon


func _diamond(radius: float, color: Color) -> Polygon2D:
	var polygon := Polygon2D.new()
	polygon.polygon = PackedVector2Array([Vector2(0, -radius), Vector2(radius, 0), Vector2(0, radius), Vector2(-radius, 0)])
	polygon.color = color
	return polygon


func _circle_texture(color: Color) -> ImageTexture:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 8:
			image.set_pixel(x, y, color if Vector2(x - 3.5, y - 3.5).length() <= 3.5 else Color.TRANSPARENT)
	return ImageTexture.create_from_image(image)


func _cleanup() -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	if is_instance_valid(_caster):
		_caster.position = _caster_origin
	if is_instance_valid(_target):
		_target.position = _target_origin
	for child in get_children():
		child.queue_free()
