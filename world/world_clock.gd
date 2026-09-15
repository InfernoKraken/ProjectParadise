class_name ParadiseWorldClock
extends Node

signal minute_changed(world_minutes: float)
signal day_started(day: int)

const MINUTES_PER_DAY := 1440.0

@export_range(0.0, MINUTES_PER_DAY, 1.0) var world_minutes := 480.0:
	set(value):
		world_minutes = fposmod(value, MINUTES_PER_DAY)
		minute_changed.emit(world_minutes)
@export_range(0.0, 120.0, 0.1) var minutes_per_real_second := 1.0

var day := 0
var paused := false

func _process(delta: float) -> void:
	if paused or minutes_per_real_second <= 0.0:
		return
	var previous := world_minutes
	world_minutes += delta * minutes_per_real_second
	if world_minutes < previous:
		day += 1
		day_started.emit(day)

func get_day_progress() -> float:
	return world_minutes / MINUTES_PER_DAY

func set_time(hour: int, minute: int = 0) -> void:
	world_minutes = clampi(hour, 0, 23) * 60.0 + clampi(minute, 0, 59)

func formatted_time() -> String:
	return "%02d:%02d" % [int(world_minutes) / 60, int(world_minutes) % 60]
