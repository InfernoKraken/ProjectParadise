extends RefCounted

# Explicit human catalog. The existing library owns the authored frame regions.
const BOATS := {"Cargo":"container", "Luxury":"luxury", "Tug":"tug"}
# Cargo and Luxury source art points left. Tug source art points right.
const BOAT_SIDE_FACING := {"Cargo":"left", "Luxury":"left", "Tug":"right"}
const BOAT_LENGTHS := {"Cargo":4.0, "Luxury":3.0, "Tug":2.5}

const HUMANS := ["Young Man", "Young Woman", "Young Boy", "Young Girl", "Professor", "Scientist"]
const FACINGS := ["down", "up", "left", "right"]
var root: String
var in_game_project := false
var library: Script
var species: Dictionary = {}
var textures: Dictionary = {}

func _init(game_root: String) -> void:
	root = game_root
	in_game_project = root.simplify_path().trim_suffix("/") == ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/")
	library = load(_path("world/npc_sprite_library.gd"))
	var file := FileAccess.open(_path("data/battle_data.json"), FileAccess.READ)
	if file == null: return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary: return
	var catalog: Array = data.get("fakemon", []).duplicate(true)
	var evolved_file := FileAccess.open(_path("data/evolved_fakemon.json"), FileAccess.READ)
	if evolved_file != null:
		var evolved: Variant = JSON.parse_string(evolved_file.get_as_text())
		if evolved is Array: catalog.append_array(evolved)
	for mon: Variant in catalog:
		if not mon is Dictionary: continue
		var id := String(mon.get("art_id", mon.get("name", "")))
		var complete := not id.is_empty()
		for facing in FACINGS:
			complete = complete and _texture_exists(_follow_path(id, facing))
		if complete: species[String(mon.name)] = id

func sprites(type: String) -> Array:
	if type == "vehicle": return BOATS.keys()
	if type == "human": return HUMANS.duplicate()
	var names := species.keys()
	names.sort()
	return names if type == "fakemon" else []

func available(type: String, sprite: String) -> bool:
	if type == "vehicle": return BOATS.has(sprite)
	return sprite in HUMANS and _texture_exists(_human_path(sprite)) if type == "human" else species.has(sprite) if type == "fakemon" else false

func _path(relative: String) -> String:
	return "res://" + relative if in_game_project else root.path_join(relative)

func _texture_exists(path: String) -> bool:
	return ResourceLoader.exists(path) if in_game_project else FileAccess.file_exists(path)

func _follow_path(art_id: String, facing: String) -> String:
	return _path("assets/fakemon/overworld/%s_Follow_%s.png" % [art_id, facing.capitalize()])

func _human_path(sprite: String) -> String:
	return _path(String(library.source_path(sprite)).trim_prefix("res://"))

func source_path(type: String, sprite: String, facing: String) -> String:
	if not available(type, sprite) or facing not in FACINGS: return ""
	if type == "vehicle": return _path("assets/vehicles/boat_%s_%s_stopped.png" % [BOATS[sprite], "side" if facing in ["left","right"] else facing])
	return _human_path(sprite) if type == "human" else _follow_path(String(species[sprite]), facing)

func texture_for(type: String, sprite: String, facing: String, walk_frame: int = -1) -> Texture2D:
	var path := source_path(type, sprite, facing)
	if type == "vehicle" and walk_frame >= 0: path = path.replace("_stopped.png", ".png")
	if path.is_empty(): return null
	if type == "human": return library.texture_for(sprite, facing, walk_frame, "" if in_game_project else root)
	var cache_key := path + ":" + facing if type == "vehicle" else path
	if textures.has(cache_key): return textures[cache_key]
	if in_game_project:
		var imported := load(path) as Texture2D
		if type == "vehicle": imported = _boat_texture(imported.get_image(), facing, BOAT_SIDE_FACING[sprite])
		textures[cache_key] = imported
		return imported
	var image := Image.load_from_file(path)
	var texture:Texture2D = ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null
	if type == "vehicle" and texture != null: texture = _boat_texture(image, facing, BOAT_SIDE_FACING[sprite])
	textures[cache_key] = texture
	return texture

# Preserve the authored canvas and registration across animation states.
# Trimming each state separately makes wakes change the apparent hull scale.
func _boat_texture(image: Image, facing: String, source_side_facing: String = "right") -> Texture2D:
	var cropped := image.duplicate() as Image
	var canvas_size := Vector2i(512, 280) if facing in ["left", "right"] else Vector2i(220, 512)
	var scale_factor := minf(float(canvas_size.x)/cropped.get_width(), float(canvas_size.y)/cropped.get_height())
	cropped.resize(maxi(1,roundi(cropped.get_width()*scale_factor)), maxi(1,roundi(cropped.get_height()*scale_factor)), Image.INTERPOLATE_LANCZOS)
	if facing in ["left", "right"] and facing != source_side_facing: cropped.flip_x()
	var canvas := Image.create_empty(canvas_size.x, canvas_size.y, false, Image.FORMAT_RGBA8)
	canvas.blit_rect(cropped, Rect2i(Vector2i.ZERO,cropped.get_size()), (canvas_size-cropped.get_size())/2)
	return ImageTexture.create_from_image(canvas)

func display_height(type: String, sprite: String, facing: String) -> float:
	if type != "vehicle": return 1.25 if type == "human" else 0.9
	return float(BOAT_LENGTHS.get(sprite,3.0)) * (280.0/512.0 if facing in ["left","right"] else 1.0)

# Hull bounds on the normalized sprite canvas (exclude superstructure and wake).
# Bottom-center sprite anchors project screen Y into world Z at 45 degrees.
const BOAT_HULLS := {
	"Cargo": {"side":Rect2(0.08,0.52,0.86,0.35), "up":Rect2(0.14,0.10,0.72,0.82), "down":Rect2(0.14,0.10,0.72,0.82)},
	"Luxury": {"side":Rect2(0.08,0.53,0.86,0.34), "up":Rect2(0.18,0.10,0.64,0.82), "down":Rect2(0.18,0.10,0.64,0.82)},
	"Tug": {"side":Rect2(0.25,0.53,0.70,0.34), "up":Rect2(0.14,0.12,0.72,0.80), "down":Rect2(0.14,0.12,0.72,0.80)},
}

func hull_footprint(sprite: String, facing: String) -> Rect2:
	var side := facing in ["left","right"]
	var bounds: Rect2 = BOAT_HULLS[sprite]["side" if side else facing]
	if side and facing != BOAT_SIDE_FACING[sprite]: bounds.position.x = 1.0-bounds.end.x
	var height := display_height("vehicle",sprite,facing)
	var width := height * (512.0/280.0 if side else 220.0/512.0)
	return Rect2(Vector2((bounds.position.x-0.5)*width,(bounds.position.y-1.0)*height*sqrt(2.0)), Vector2(bounds.size.x*width,bounds.size.y*height*sqrt(2.0)))
