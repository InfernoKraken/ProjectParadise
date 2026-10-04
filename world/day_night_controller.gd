class_name DayNightController
extends Node

const INDOOR_MAP_TYPE := "Indoor"

const CANVAS_LIGHT_SHADER := preload("res://world/overworld_light_canvas.gdshader")
const TERRAIN_LIGHT_SHADER := preload("res://world/overworld_light_terrain.gdshader")

var canvas_light_material := ShaderMaterial.new()
var emissive_material := ShaderMaterial.new()
var light_texture: ImageTexture
var light_data_image: Image
var light_count := 0
var terrain_material_cache: Dictionary = {}
var material_update_generation := 0
var clock: Node
var world_environment: Environment
var canvas_modulate: CanvasModulate
var color_curve := Gradient.new()
var current_map_type := "Rainforest"
var registered_light_materials: Array[ShaderMaterial] = []
var registered_world_sprites: Array[Sprite3D] = []
var lighting_registered := false
var canvas_lighting_root: Node
var canvas_lighting_dirty := true
var last_lighting_state: Array = []
var sprite_textures: Dictionary = {}

func _on_lighting_node_added(node: Node) -> void:
	if node is MeshInstance3D or node is Sprite3D:
		lighting_registered = false;last_lighting_state = []
	if node is CanvasItem and is_instance_valid(canvas_lighting_root) and canvas_lighting_root.is_ancestor_of(node):
		canvas_lighting_dirty = true


func _ready() -> void:
	get_tree().node_added.connect(_on_lighting_node_added)
	canvas_light_material.shader = CANVAS_LIGHT_SHADER
	emissive_material.shader = CANVAS_LIGHT_SHADER
	emissive_material.set_shader_parameter("light_source", true)
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
	var quantized := Color(snappedf(tint.r,1.0/255.0),snappedf(tint.g,1.0/255.0),snappedf(tint.b,1.0/255.0),tint.a)
	var state := [quantized,enabled,light_count,light_texture,get_viewport().get_visible_rect().size]
	for sprite in registered_world_sprites:
		if not is_instance_valid(sprite) or not sprite.visible: continue
		if sprite_textures.get(sprite.get_instance_id()) != sprite.texture:
			sprite.material_override.set_shader_parameter("albedo_texture",sprite.texture)
			sprite_textures[sprite.get_instance_id()] = sprite.texture
	if lighting_registered and state == last_lighting_state: return
	last_lighting_state = state
	material_update_generation += 1
	canvas_modulate.color = quantized
	# 3D visuals bypass CanvasModulate; use the same tint as the sorted 2D art.
	if is_inside_tree() and not lighting_registered:
		lighting_registered = true
		registered_world_sprites.clear()
		for terrain in get_tree().get_nodes_in_group("day_night_terrain"):
			if terrain is MeshInstance3D and terrain.material_override is StandardMaterial3D:
				var original: StandardMaterial3D = terrain.material_override
				var key := [original.albedo_texture, original.albedo_color, original.uv1_scale, original.uv1_offset]
				var material: ShaderMaterial = terrain_material_cache.get(key)
				if material == null:
					material = ShaderMaterial.new()
					material.shader = TERRAIN_LIGHT_SHADER
					material.set_shader_parameter("albedo_texture", original.albedo_texture)
					material.set_shader_parameter("base_color", original.albedo_color)
					material.set_shader_parameter("uv_scale", Vector2(original.uv1_scale.x, original.uv1_scale.y))
					material.set_shader_parameter("uv_offset", Vector2(original.uv1_offset.x, original.uv1_offset.y))
					terrain_material_cache[key] = material
				terrain.material_override = material
			if terrain is MeshInstance3D and terrain.material_override is ShaderMaterial:
				if terrain.material_override not in registered_light_materials: registered_light_materials.append(terrain.material_override)
		for sprite in get_tree().get_nodes_in_group("day_night_world_sprites"):
			if sprite is Sprite3D:
				if not sprite.get_meta("overworld_light_material", false):
					var material := ShaderMaterial.new()
					material.shader = TERRAIN_LIGHT_SHADER
					material.set_shader_parameter("base_color", sprite.modulate)
					material.set_shader_parameter("billboard_enabled", sprite.billboard == BaseMaterial3D.BILLBOARD_ENABLED)
					sprite.material_override = material
					sprite.set_meta("overworld_light_material", true)
				var material: ShaderMaterial = sprite.material_override
				material.set_shader_parameter("albedo_texture", sprite.texture)
				registered_world_sprites.append(sprite)
				if material not in registered_light_materials: registered_light_materials.append(material)
	for material in registered_light_materials: _update_light_material(material,tint)
	_update_light_material(canvas_light_material, tint)
	_update_light_material(emissive_material, tint)
	if world_environment != null:
		world_environment.ambient_light_color = tint
		world_environment.background_color = tint * Color("#17321f") if enabled else Color("#17321f")

# Called after the world projects its sorted art, so camera movement and NPC poses
# are reflected in this frame's light field. No persistent terrain state is changed.
func update_overworld_lights(camera: Camera3D, art_root: Node2D, sources: Array) -> void:
	var width := maxi(1, sources.size())
	var image := light_data_image
	var image_changed := image == null or image.get_width() != width
	if image == null or image.get_width() != width:
		image = Image.create(width, 1, false, Image.FORMAT_RGBAF)
	var pixels_per_unit := get_viewport().get_visible_rect().size.y / camera.size
	light_count = sources.size() if is_day_night_enabled() else 0
	for index in sources.size():
		var source: Dictionary = sources[index]
		var center := camera.unproject_position(source.position)
		var radius := maxf(0.001, float(source.radius)) * pixels_per_unit
		var value := Color(center.x, center.y, radius, radius * 0.72)
		if image.get_pixel(index, 0) != value:
			image.set_pixel(index, 0, value)
			image_changed = true
	light_data_image = image
	if light_texture == null or light_texture.get_width() != image.get_width():
		light_texture = ImageTexture.create_from_image(image)
	elif image_changed:
		light_texture.update(image)
	_apply_visuals()
	if canvas_lighting_root != art_root:
		canvas_lighting_root = art_root;canvas_lighting_dirty = true
	if canvas_lighting_dirty:
		_install_canvas_lighting(art_root);canvas_lighting_dirty = false

func _install_canvas_lighting(node: Node) -> void:
	if node is CanvasItem:
		if node.get_meta("overworld_light_source", false):
			node.material = emissive_material
		elif node.material is ShaderMaterial and node.material.shader.resource_path == "res://world/platform_rail_occlusion.gdshader":
			if node.material not in registered_light_materials: registered_light_materials.append(node.material)
			_update_light_material(node.material, canvas_modulate.color)
		elif node.material == null or node.material == emissive_material:
			node.material = canvas_light_material
	for child in node.get_children():
		_install_canvas_lighting(child)

func _update_light_material(material: ShaderMaterial, tint: Color) -> void:
	if int(material.get_meta("light_update_generation", -1)) == material_update_generation:
		return
	material.set_meta("light_update_generation", material_update_generation)
	# Texture contents update in place. Rebind uniforms only when their values
	# change, rather than submitting thousands of redundant commands per frame.
	var quantized := Color(snappedf(tint.r, 1.0 / 255.0), snappedf(tint.g, 1.0 / 255.0), snappedf(tint.b, 1.0 / 255.0), tint.a)
	var values := {"night_tint": quantized, "light_count": light_count}
	if light_texture != null:
		values["light_data"] = light_texture
	if is_inside_tree():
		values["viewport_size"] = get_viewport().get_visible_rect().size
	var previous: Dictionary = material.get_meta("light_uniform_values", {})
	for key: String in values:
		if not previous.has(key) or previous[key] != values[key]:
			material.set_shader_parameter(key, values[key])
	material.set_meta("light_uniform_values", values)
