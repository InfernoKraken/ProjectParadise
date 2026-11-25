class_name PlayerSpriteFrames
extends RefCounted

# Shared five-pose layout for all authored appearances. Exclude sheet labels.
const X_EDGES := [144, 320, 518, 716, 918, 1106]
const Y_EDGES := [48, 362, 678, 1008, 1336]
const CARDINAL_ROWS := {"down": 0, "up": 1, "left": 2, "right": 3}
const DIAGONAL_ROWS := {"down_right": 0, "down_left": 1, "up_right": 2, "up_left": 3}
# Seconds per authored pose (frames 1-5), shared by all walking directions.
const WALK_FRAME_DURATIONS := [0.16, 0.16, 0.08, 0.16, 0.08]
const FRAME_SIZE := Vector2i(208, 336)
const APPEARANCES := {
	"medium": "Medium_Brown",
	"light_blonde": "Light_Blonde",
	"light_red": "Light_Red",
	"dark_black": "Dark_Black",
}

static func source_path(gender: String, preset: String, diagonal: bool = false) -> String:
	assert(gender in ["Male", "Female"], "Unknown player gender: " + gender)
	assert(APPEARANCES.has(preset), "Unknown player appearance: " + preset)
	return "res://assets/trainers/player/%s/%s%sPlayer_%s_Base.png" % [
		gender.to_lower(), "Diagonal_" if diagonal else "", gender, APPEARANCES[preset]]

static func create_texture(gender: String, preset: String, diagonal: bool = false) -> Texture2D:
	return load(source_path(gender, preset, diagonal)) as Texture2D

static func is_diagonal(animation: String) -> bool:
	return animation.get_slice_count("_") == 3

static func frames(_gender: String, animation: String, atlas: Texture2D) -> Array[AtlasTexture]:
	var result: Array[AtlasTexture] = []
	var direction := animation.substr(animation.find("_") + 1)
	var rows: Dictionary = DIAGONAL_ROWS if is_diagonal(animation) else CARDINAL_ROWS
	assert(rows.has(direction), "Missing player animation: " + animation)
	var row: int = rows[direction]
	var columns: Array = [0, 1, 2, 3, 4] if animation.begins_with("walk_") else [0]
	for column: int in columns:
		var size := Vector2i(X_EDGES[column + 1] - X_EDGES[column], Y_EDGES[row + 1] - Y_EDGES[row])
		var frame := AtlasTexture.new()
		frame.atlas = atlas
		frame.region = Rect2i(Vector2i(X_EDGES[column], Y_EDGES[row]), size)
		# A common canvas keeps scale fixed across rows; registration is at the feet.
		frame.margin = Rect2i(Vector2i((FRAME_SIZE.x - size.x) / 2, FRAME_SIZE.y - size.y), FRAME_SIZE - size)
		frame.filter_clip = true
		result.append(frame)
	return result
