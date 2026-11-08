extends RefCounted

# Ranges are distances from the authored anchor, in map X / screen Y (world Z).
const PRESETS := {
	"stationary":"Stationary",
	"left_right":"Walk Left / Right",
	"up_down":"Walk Up / Down",
	"clockwise":"Walk Clockwise",
	"counterclockwise":"Walk Counterclockwise",
	"random":"Random Within Range",
	"look_around":"Idle Look Around",
}
const MODE_OFFSETS := {"ground":0.0, "flying":2.0, "swimming":-0.5}

static func traversal_error(definition: Dictionary) -> String:
	if definition.get("movement_mode", "ground") not in MODE_OFFSETS:
		return "Unknown NPC movement_mode; expected ground, flying, swimming."
	var offset: Variant = definition.get("height_offset", 0.0)
	if not (offset is int or offset is float) or not is_finite(float(offset)):
		return "NPC height_offset must be a finite number."
	return ""

static func elevation(definition: Dictionary) -> float:
	return float(MODE_OFFSETS.get("swimming" if definition.get("type") == "vehicle" else definition.get("movement_mode", "ground"), 0.0)) + float(definition.get("height_offset", 0.0))

const SPEED := 4.5
const FOOT_SIZE := Vector3(0.55, 0.3, 0.45)
const PAUSE := 1.0
const FACINGS := ["down", "up", "left", "right"]

var anchor: Vector3
var extent: Vector2
var preset: String
var target: Vector3
var waypoint := 0
var timer := 0.0
var rng := RandomNumberGenerator.new()

static func settings(definition: Dictionary) -> Dictionary:
	return definition.get("movement", {"preset":"stationary", "range":[2.0,2.0]}).duplicate(true)

static func validation_error(value: Variant) -> String:
	if not value is Dictionary: return "NPC movement must be an object."
	if value.get("preset") not in PRESETS: return "Unknown NPC movement preset."
	var limits: Variant = value.get("range")
	if not limits is Array or limits.size() != 2: return "Movement range must contain X and Y distances."
	for limit: Variant in limits:
		if not (limit is int or limit is float) or not is_finite(float(limit)) or float(limit) < 0:
			return "Movement ranges must be finite, non-negative numbers."
	return ""

func _init(initial_position: Vector3, config: Dictionary, seed_value: int) -> void:
	anchor = initial_position
	target = anchor
	preset = String(config.preset)
	extent = Vector2(float(config.range[0]), float(config.range[1]))
	rng.seed = seed_value

# Release scripted control without changing the authored anchor or preset.
func resume(position: Vector3) -> void:
	target = _in_range(position)
	timer = 0.0
	waypoint = 0

func _in_range(position: Vector3) -> Vector3:
	return Vector3(clampf(position.x,anchor.x-extent.x,anchor.x+extent.x),anchor.y,clampf(position.z,anchor.z-extent.y,anchor.z+extent.y))

# Pure planning state; main.gd applies the proposed displacement with physics.
func step(position: Vector3, facing: String, delta: float) -> Dictionary:
	if preset == "stationary" or delta <= 0: return {"position":position, "facing":facing}
	timer = maxf(0.0, timer - delta)
	if preset == "look_around":
		if timer <= 0:
			var options := FACINGS.duplicate(); options.erase(facing)
			facing = String(options[rng.randi_range(0, options.size()-1)])
			timer = 1.5
		return {"position":position, "facing":facing}
	if timer > 0: return {"position":position, "facing":facing}
	if position.distance_squared_to(target) < 0.000001:
		target = _next_target(position)
	var motion := target - position
	# Every leg is cardinal, including the initial approach to a rectangle corner.
	var destination := position
	if absf(motion.x) > 0.0001:
		destination.x = move_toward(position.x, target.x, SPEED * delta)
		facing = "right" if motion.x > 0 else "left"
	elif absf(motion.z) > 0.0001:
		destination.z = move_toward(position.z, target.z, SPEED * delta)
		facing = "down" if motion.z > 0 else "up"
	# A scripted walk may leave the authored range. Re-enter at walking speed.
	destination.x = clampf(destination.x, minf(position.x,anchor.x-extent.x), maxf(position.x,anchor.x+extent.x))
	destination.z = clampf(destination.z, minf(position.z,anchor.z-extent.y), maxf(position.z,anchor.z+extent.y))
	destination.y = anchor.y
	if destination.distance_squared_to(target) < 0.000001: timer = PAUSE
	return {"position":destination, "facing":facing}

func blocked(position: Vector3) -> void:
	target = position
	timer = PAUSE

func _next_target(position: Vector3) -> Vector3:
	var bounded := _in_range(position)
	if Vector2(position.x-bounded.x,position.z-bounded.z).length_squared() > 0.000001: return bounded
	var point := anchor
	match preset:
		"left_right":
			point.x += extent.x if waypoint % 2 == 0 else -extent.x
		"up_down":
			point.z += extent.y if waypoint % 2 == 0 else -extent.y
		"clockwise", "counterclockwise":
			var corners := [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]
			var index := posmod(waypoint if preset == "clockwise" else -waypoint, 4)
			point += Vector3(corners[index].x*extent.x, 0, corners[index].y*extent.y)
		"random":
			point = position
			if rng.randi_range(0,1) == 0 and extent.x > 0 or extent.y == 0:
				point.x = anchor.x + rng.randf_range(-extent.x,extent.x)
			else:
				point.z = anchor.z + rng.randf_range(-extent.y,extent.y)
	waypoint += 1
	return point
