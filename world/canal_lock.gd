@tool
extends Node3D
## Reusable lock. Local X spans the canal; local Z follows boat travel.
signal frame_changed(frame: int)

const FRAMES: Array[Texture2D] = [
	preload("res://assets/animations/canal_locks_main_frame_0.png"),
	preload("res://assets/animations/canal_locks_main_frame_1.png"),
	preload("res://assets/animations/canal_locks_main_frame_2.png"),
]
const SEQUENCE: Array[int] = [0, 1, 2, 1, 0]

@export_range(0.01, 20.0, 0.01) var gate_scale: float = 1.0:
	set(value):
		gate_scale = maxf(value, 0.01)
		if is_node_ready(): _refresh_geometry()
## Seconds each sequence entry remains visible, including both closed endpoints.
@export_range(0.01, 60.0, 0.01) var animation_time: float = 1.0
@export var autoplay: bool = true
@export var loop: bool = true
## Base sprite height in map units, before gate_scale.
@export_range(0.01, 50.0, 0.01) var visual_height: float = 4.0:
	set(value):
		visual_height = maxf(value, 0.01)
		if is_node_ready(): _refresh_geometry()
## Placeholder solid gate bounds; tune to the canal's navigable opening.
@export var collider_size: Vector3 = Vector3(6.0, 2.0, 0.4):
	set(value):
		collider_size = value.max(Vector3.ONE * 0.01)
		if is_node_ready(): _refresh_geometry()

var current_frame: int = 0
var playing: bool = false
var _step: int = 0
var _elapsed: float = 0.0

func _ready() -> void:
	_refresh_geometry()
	_show_frame(0)
	playing = autoplay and not Engine.is_editor_hint()

func _physics_process(delta: float) -> void:
	if not playing or Engine.is_editor_hint(): return
	_elapsed += delta
	var duration := maxf(animation_time, 0.01)
	while _elapsed >= duration and playing:
		_elapsed -= duration
		_step += 1
		if _step == SEQUENCE.size():
			if not loop:
				playing = false
				return
			_step = 0
		_show_frame(SEQUENCE[_step])

func play_cycle() -> void:
	_step = 0
	_elapsed = 0.0
	_show_frame(0)
	playing = true

## Hold the gate open or closed until play_cycle() is called again.
func set_open(opened: bool) -> void:
	playing = false
	_elapsed = 0.0
	_show_frame(2 if opened else 0)

func _show_frame(frame: int) -> void:
	current_frame = frame
	($Visual as Sprite3D).texture = FRAMES[frame]
	# Layer 1 is shared by solid world objects and boat hull queries.
	var body := $Body as StaticBody3D
	body.set_meta("gate_open", frame == 2)
	body.collision_layer = 1 if frame != 2 and body.get_meta("region_collision_enabled", true) else 0
	frame_changed.emit(frame)

func _refresh_geometry() -> void:
	var visual := $Visual as Sprite3D
	# One pixels-to-world ratio preserves differently sized source artwork.
	visual.pixel_size = visual_height * gate_scale / float(FRAMES[0].get_height())
	visual.position.y = visual_height * gate_scale * 0.5
	var mesh := BoxMesh.new()
	mesh.size = collider_size * gate_scale
	($Body/CollisionShape3D as CollisionShape3D).shape = mesh.create_convex_shape()
	($Body as StaticBody3D).position.y = mesh.size.y * 0.5
