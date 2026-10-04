extends RefCounted

# Explicit human catalog. The existing library owns the authored frame regions.
const HUMANS := ["Young Man", "Young Woman", "Young Boy", "Young Girl"]
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
	if type == "human": return HUMANS.duplicate()
	var names := species.keys()
	names.sort()
	return names if type == "fakemon" else []

func available(type: String, sprite: String) -> bool:
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
	return _human_path(sprite) if type == "human" else _follow_path(String(species[sprite]), facing)

func texture_for(type: String, sprite: String, facing: String, walk_frame: int = -1) -> Texture2D:
	var path := source_path(type, sprite, facing)
	if path.is_empty(): return null
	if type == "human": return library.texture_for(sprite, facing, walk_frame, "" if in_game_project else root)
	if textures.has(path): return textures[path]
	if in_game_project:
		var imported := load(path) as Texture2D
		textures[path] = imported
		return imported
	var image := Image.load_from_file(path)
	var texture:Texture2D = ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null
	textures[path] = texture
	return texture
