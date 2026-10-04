extends RefCounted

# Standard NPC sheets use eight columns: one direction per row in down, up,
# left, right order. Citizen sheets have an idle column and four walk columns.
# Authored cell edges preserve poses that cross evenly divided grid boundaries.
const GRID_COLUMNS := 8
const GRID_ROWS := 4
const GRID_DIRECTIONS := {"down": 0, "up": 1, "left": 2, "right": 3}

# Preserve editor/saved-map names as aliases of the same animated sheets.
const ALIASES := {"Young Man":"man", "Young Woman":"woman", "Young Boy":"boy", "Young Girl":"girl"}

static func canonical_id(sprite_id: String) -> String:
	return String(ALIASES.get(sprite_id, sprite_id))

static func source_path(sprite_id: String) -> String:
	return String(SPRITES.get(canonical_id(sprite_id), {}).get("grid_path", ""))

static var SPRITES := {

	"man": {"grid_path":"res://assets/trainers/Male Citizen.png", "columns":5, "walk_sequence":[0,1,0,2,0,3,0,4], "x_edges":[0,215,395,580,760,962], "y_edges":[0,335,630,930,1235]},
	"woman": {"grid_path":"res://assets/trainers/Female Citizen.png", "columns":5, "walk_sequence":[0,1,0,2,0,3,0,4], "x_edges":[0,215,395,580,760,962], "y_edges":[0,335,640,950,1260]},
	"boy": {"grid_path":"res://assets/trainers/Boy.png"},
	"girl": {"grid_path":"res://assets/trainers/Girl.png"},
}

static func walk_frame_count(sprite_id: String) -> int:
	var spec: Dictionary = SPRITES.get(canonical_id(sprite_id), {})
	if spec.has("grid_path"):
		if spec.has("walk_sequence"): return (spec.walk_sequence as Array).size()
		return int(spec.get("walk_count", spec.get("columns", GRID_COLUMNS)))
	return (spec.get("walk", {}).get("down", []) as Array).size()

static var _cache: Dictionary = {}
static var _source_images: Dictionary = {}
static var _warned: Dictionary = {}


static func texture_for(sprite_id:String,direction:String="down",walk_frame:int=-1,game_root:String="")->Texture2D:
	sprite_id = canonical_id(sprite_id)
	var pose:="idle" if walk_frame<0 else "walk"
	var cache_key:="%s:%s:%s:%d:%s"%[sprite_id,pose,direction,walk_frame,game_root]
	if _cache.has(cache_key):return _cache[cache_key]
	var spec:Dictionary=SPRITES.get(sprite_id,{})
	if spec.is_empty():
		_warn_once(sprite_id,"unknown NPC sprite id")
		return null
	if spec.has("grid_path"):
		return _grid_texture(sprite_id, spec, direction, walk_frame, cache_key, game_root)
	var regions:Dictionary=spec.get(pose,{})
	if not regions.has(direction):direction="down"
	var rect:Rect2i
	if pose=="walk":
		var frames:Array=regions[direction]
		rect=frames[posmod(walk_frame,frames.size())]
	else:rect=regions[direction]
	var source_path:=String(spec.get(pose+"_path",""))
	var source:Texture2D
	if game_root.is_empty():
		source=load(source_path) as Texture2D
	else:
		var source_image:=Image.load_from_file(game_root.path_join(source_path.trim_prefix("res://")))
		if source_image!=null and not source_image.is_empty():source=ImageTexture.create_from_image(source_image)
	if source==null:
		_warn_once(sprite_id,"source sheet could not be imported: "+source_path)
		return null
	if not _source_images.has(source_path):
		_source_images[source_path] = source.get_image()
	var image: Image = _source_images[source_path]
	if image==null or not Rect2i(Vector2i.ZERO,image.get_size()).encloses(rect):
		_warn_once(sprite_id,"configured slice is outside the source sheet")
		return null
	var frame:=image.get_region(rect)
	if frame.is_empty():
		_warn_once(sprite_id,"slice contained no usable sprite pixels")
		return null
	var texture:=ImageTexture.create_from_image(frame)
	_cache[cache_key]=texture
	return texture


static func _grid_texture(sprite_id: String, spec: Dictionary, direction: String, walk_frame: int, cache_key: String, game_root: String) -> Texture2D:
	var source_path := String(spec["grid_path"])
	var source_key := source_path if game_root.is_empty() else game_root.path_join(source_path.trim_prefix("res://"))
	if not _source_images.has(source_key):
		var source_image: Image
		if game_root.is_empty():
			var source := load(source_path) as Texture2D
			if source != null: source_image = source.get_image()
		else:
			source_image = Image.load_from_file(source_key)
		if source_image == null or source_image.is_empty():
			_warn_once(sprite_id, "source sheet could not be imported: " + source_path)
			return null
		_source_images[source_key] = source_image
	var image: Image = _source_images[source_key]
	var row: int = GRID_DIRECTIONS.get(direction, 0)
	var columns := int(spec.get("columns", GRID_COLUMNS))
	var walk_count := int(spec.get("walk_count", columns))
	var column: int = 0 if walk_frame < 0 else int(spec.get("walk_start", 0)) + posmod(walk_frame, walk_count)
	var sequence: Array = spec.get("walk_sequence", [])
	if walk_frame >= 0 and not sequence.is_empty():
		column = int(sequence[posmod(walk_frame, sequence.size())])
	var x_edges: Array = spec.get("x_edges", [])
	var y_edges: Array = spec.get("y_edges", [])
	var x0: int = x_edges[column] if not x_edges.is_empty() else column * image.get_width() / columns
	var x1: int = x_edges[column + 1] if not x_edges.is_empty() else (column + 1) * image.get_width() / columns
	var y0: int = y_edges[row] if not y_edges.is_empty() else row * image.get_height() / GRID_ROWS
	var y1: int = y_edges[row + 1] if not y_edges.is_empty() else (row + 1) * image.get_height() / GRID_ROWS
	var frame := image.get_region(Rect2i(x0, y0, x1 - x0, y1 - y0))
	if frame.is_empty():
		_warn_once(sprite_id, "grid cell contained no usable sprite pixels")
		return null
	var texture := ImageTexture.create_from_image(frame)
	_cache[cache_key] = texture
	return texture


static func _warn_once(sprite_id:String,message:String)->void:
	if _warned.has(sprite_id):return
	_warned[sprite_id]=true
	push_warning("NPC art '%s' unavailable (%s); using the colored placeholder."%[sprite_id,message])
