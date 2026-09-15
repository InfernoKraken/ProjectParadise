class_name DayNightController
extends Node

const INDOOR_MAP_TYPE := "Indoor"

var clock: Node
var world_environment: Environment
var canvas_modulate: CanvasModulate
var color_curve := Gradient.new()
var current_map_type := "Rainforest"

func _ready() -> void:
	color_curve.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
	color_curve.offsets = PackedFloat32Array([0.0, 5.0/24.0, 6.0/24.0, 8.0/24.0, 12.0/24.0, 17.0/24.0, 19.0/24.0, 20.0/24.0, 1.0])
	color_curve.colors = PackedColorArray([
		Color("#58618f"), Color("#778bb1"), Color("#e6a594"),
		Color("#fffdf4"), Color("#fff4df"), Color("#ffd49b"),
		Color("#b47f9f"), Color("#7382a5"), Color("#58618f")
	])
	canvas_modulate = CanvasModulate.new()
	canvas_modulate.name = "DayNightCanvasModulate"
	add_child(canvas_modulate)
	_apply_visuals()

func setup(world_clock: Node, environment: Environment) -> void:
	clock = world_clock
	world_environment = environment
	_apply_visuals()

func _process(_delta: float) -> void:
	_apply_visuals()

func set_map_type(map_type: String) -> void:
	current_map_type = map_type
	_apply_visuals()

func is_day_night_enabled() -> bool:
	return current_map_type != INDOOR_MAP_TYPE

func sampled_color(day_progress: float) -> Color:
	return color_curve.sample(fposmod(day_progress, 1.0))

func _apply_visuals() -> void:
	if canvas_modulate == null:
		return
	var enabled := is_day_night_enabled()
	var tint := sampled_color(float(clock.get_day_progress())) if enabled and clock != null else Color.WHITE
	canvas_modulate.color = tint
	if world_environment != null:
		world_environment.ambient_light_color = tint
		world_environment.background_color = tint * Color("#17321f") if enabled else Color("#17321f")
