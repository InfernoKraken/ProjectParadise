extends RefCounted

const DIRECTORY := "data/habitats"
# Initial footprint follows the massive museum pen asset's reference size.
const PEN_TEXTURE := "assets/overworld/habitat_pen_massive.png"
const COLLECTIONS := [
	"objects", "terrain_tiles", "grass_zones", "water_blocks", "sand_blocks",
	"rocks", "floor_blocks", "wall_blocks", "furnishings", "trees", "vines",
	"orchids", "blue_flowers", "flower_beds", "tall_flowers", "rare_torch_ginger",
]
const BLOCK_COLLECTIONS := ["water_blocks", "sand_blocks", "rocks", "floor_blocks", "wall_blocks"]
const SIZE := Vector2(6.666667, 5.0)

static func habitat_types(project_root: String) -> Array:
	var types: Variant = JSON.parse_string(FileAccess.get_file_as_string(project_root.path_join("data/habitat_types.json")))
	return types if types is Array else []

static func create() -> Dictionary:
	var data := {
		"habitat_template_version": 1,
		"id": "",
		"name": "",
		"habitat_type": "tropical_clearing",
		"size": [SIZE.x, SIZE.y],
		"base_terrain_type": "forest_floor",
		"npc_spawn": [0, 0],
		"wander_bounds": [-2, -1.5, 4, 3],
	}

	ensure_collections(data)
	return data

static func ensure_collections(data: Dictionary) -> void:
	for field in COLLECTIONS:
		if not data.has(field):
			data[field] = []

static func footprint() -> Rect2:
	return Rect2(-SIZE * 0.5, SIZE)

static func contains_cell(cell: Vector2) -> bool:
	return footprint().encloses(Rect2(cell - Vector2.ONE * 0.5, Vector2.ONE))

static func valid_id(id: String) -> bool:
	if id.is_empty() or id[0] not in "abcdefghijklmnopqrstuvwxyz":
		return false
	for character in id:
		if character not in "abcdefghijklmnopqrstuvwxyz0123456789_":
			return false
	return id.validate_filename() == id

static func _numbers(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count:
		return false
	for number in value:
		if typeof(number) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(number)):
			return false
	return true

static func problem(data: Dictionary, project_root: String) -> String:
	if data.get("habitat_template_version") != 1:
		return "Unsupported habitat template version."
	if not data.get("id") is String or not valid_id(data.id):
		return "Use a lowercase template ID with letters, digits and underscores, starting with a letter."
	if not data.get("name") is String or data.name.strip_edges().is_empty():
		return "Enter a template name."
	if not habitat_types(project_root).has(data.get("habitat_type")):
		return "Choose a habitat type."
	var size: Variant = data.get("size")
	var bounds: Variant = data.get("wander_bounds")
	var spawn: Variant = data.get("npc_spawn")
	if not _numbers(size, 2) or not _numbers(bounds, 4) or not _numbers(spawn, 2):
		return "Invalid footprint, wander bounds, or NPC spawn."
	var dimensions := Vector2(size[0], size[1])
	if not dimensions.is_equal_approx(SIZE):
		return "The template must use the standard enclosure footprint."
	var wander := Rect2(bounds[0], bounds[1], bounds[2], bounds[3])
	if not wander.has_area() or not footprint().encloses(wander):
		return "The wander rectangle must fit inside the enclosure."
	if not wander.has_point(Vector2(spawn[0], spawn[1])):
		return "Place the NPC spawn inside the wander rectangle."
	for field in COLLECTIONS:
		if not data.get(field, []) is Array:
			return "Invalid habitat collection: " + field
	for field in BLOCK_COLLECTIONS:
		for block in data.get(field, []):
			if not block is Array or block.size() < 6 or not _numbers(block.slice(0, 6), 6):
				return "Invalid habitat block in " + field
			var center := Vector2(block[0], block[2])
			var extent := Vector2(block[3], block[5])
			if extent.x <= 0 or extent.y <= 0 or not footprint().encloses(Rect2(center - extent * 0.5, extent)):
				return "Keep the entire block inside the enclosure: " + field
	for object in data.get("objects", []):
		if not object is Dictionary or not object.get("type") is String:
			return "Invalid habitat object."
		if object.type == "wall.fence":
			if not object.get("points") is Array or object.points.size() < 2:
				return "A habitat fence needs at least two points."
			for point in object.points:
				if not _numbers(point, 2) or not footprint().has_point(Vector2(point[0], point[1])):
					return "Keep fence points inside the enclosure."
			continue
		if not _numbers(object.get("position"), 3):
			return "Invalid habitat object position."
		var local: Array = object.position
		if not footprint().has_point(Vector2(local[0], local[2])):
			return "Keep object anchors inside the enclosure."
		if object.has("size") and not _numbers(object.size, 3):
			return "Invalid habitat object size."
		if not object.has("asset_path"):
			continue
		var asset_path: Variant = object.asset_path
		if not asset_path is String or not asset_path.begins_with("res://assets/overworld/") or asset_path.contains(".."):
			return "Habitat objects must reference overworld sprites."
		if asset_path == "res://" + PEN_TEXTURE:
			continue # Older templates could include a manually placed pen.
		if not FileAccess.file_exists(project_root.path_join(asset_path.trim_prefix("res://"))):
			return "Missing sprite: " + asset_path
	for entry in data.get("terrain_tiles", []):
		if not entry is Dictionary or not entry.get("terrain_type") is String:
			return "Invalid habitat terrain entry."
		var cells: Variant = entry.get("positions", [])
		if not cells is Array:
			return "Invalid habitat terrain cells."
		if entry.has("position"):
			cells = cells + [entry.position]
		for cell in cells:
			if not _numbers(cell, 2) or not contains_cell(Vector2(cell[0], cell[1])):
				return "Keep terrain cells inside the enclosure."
	return ""

static func objects_at(data: Dictionary, origin: Vector3) -> Array:
	var objects: Array = data.get("objects", []).duplicate(true)
	for object in objects:
		if object.type == "wall.fence":
			for point in object.points:
				point[0] += origin.x
				point[1] += origin.z
			continue
		var local: Array = object.position
		object.position = [origin.x + local[0], origin.y + local[1], origin.z + local[2]]
	return objects
