class_name MapSchema
extends RefCounted

const POSITION3_FIELDS := ["player_spawn", "position", "door", "origin", "entry", "exit_door", "clearing_warp", "clearing_return", "exit_warp", "east_warp", "east_return", "west_warp", "west_return", "north_warp", "north_return", "return_warp", "cave_warp", "cave_return", "exterior_return", "npc"]
const POINT_ARRAY_FIELDS := ["tall_flowers", "rare_torch_ginger", "blue_flowers", "vines", "flower_beds", "orchids", "adults", "children"]
const TREE_FIELDS := ["trees"]
const BLOCK_FIELDS := ["water_blocks", "sand_blocks", "rocks"]
const SIZE2_FIELDS := ["map_size", "interior_size"]
const REGION_FILES := {
	"rainforest_clearing.json": "clearing",
	"rainforest_medical_ward.json": "clearing_ward",
	"rainforest_house.json": "clearing_house",
	"canopy_route.json": "route",
	"eastern_rainforest_route.json": "east_route",
	"western_rainforest_route.json": "west_route",
	"vinestone_cave.json": "cave",
	"mossvale_city.json": "city",
	"mossvale_medical_ward.json": "city_ward",
	"mossvale_orchid_house.json": "orchid_house",
	"mossvale_family_house.json": "family_house"
}

static func kind_for_file(path: String) -> String:
	return String(REGION_FILES.get(path.get_file(), "unknown"))

static func expected_fields(kind: String) -> Dictionary:
	match kind:
		"clearing": return {"map_size":"size2", "player_spawn":"position3", "opponent":"object", "building":"object", "medical_ward_instance":"string", "north_warp":"position3", "north_return":"position3", "tall_grass_species":"strings", "trainers":"trainers", "grass_zones":"zones", "water_blocks":"blocks", "sand_blocks":"blocks", "tall_flowers":"points", "rare_torch_ginger":"points", "blue_flowers":"points", "trees":"trees"}
		"clearing_ward": return {"position":"position3", "size":"size3", "door":"position3", "exterior_return":"position3", "origin":"position3", "interior_size":"size2", "entry":"position3", "exit_door":"position3", "staff":"position3", "floor_blocks":"blocks", "wall_blocks":"blocks", "furnishings":"furnishings", "tall_grass_species":"strings"}
		"clearing_house": return {"position":"position3", "size":"size3", "door":"position3", "exterior_return":"position3", "origin":"position3", "interior_size":"size2", "entry":"position3", "exit_door":"position3", "npc":"position3", "floor_blocks":"blocks", "wall_blocks":"blocks", "furnishings":"furnishings", "tall_grass_species":"strings"}
		"route": return {"origin":"position3", "size":"size2", "entry":"position3", "exit_warp":"position3", "east_warp":"position3", "east_return":"position3", "west_warp":"position3", "west_return":"position3", "north_warp":"position3", "north_return":"position3", "tall_grass_species":"strings", "trainers":"trainers", "grass_zones":"zones", "water_blocks":"blocks", "sand_blocks":"blocks", "tall_flowers":"points", "trees":"trees"}
		"east_route": return {"origin":"position3", "size":"size2", "entry":"position3", "return_warp":"position3", "cave_warp":"position3", "cave_return":"position3", "tall_grass_species":"strings", "trainers":"trainers", "grass_zones":"zones", "water_blocks":"blocks", "sand_blocks":"blocks", "tall_flowers":"points", "trees":"trees"}
		"west_route": return {"origin":"position3", "size":"size2", "entry":"position3", "return_warp":"position3", "tall_grass_species":"strings", "trainers":"trainers", "grass_zones":"zones", "water_blocks":"blocks", "sand_blocks":"blocks", "tall_flowers":"points", "trees":"trees"}
		"cave": return {"origin":"position3", "size":"size2", "entry":"position3", "exit_warp":"position3", "floor_blocks":"blocks", "tall_grass_species":"strings", "rocks":"blocks", "blue_flowers":"points", "vines":"points"}
		"city": return {"origin":"position3", "size":"size2", "entry":"position3", "return_warp":"position3", "tall_grass_species":"strings", "trainers":"trainers", "trees":"trees", "flower_beds":"points"}
		"city_ward": return {"position":"position3", "size":"size3", "door":"position3", "exterior_return":"position3", "origin":"position3", "interior_size":"size2", "entry":"position3", "exit_door":"position3", "staff":"position3", "floor_blocks":"blocks", "wall_blocks":"blocks", "furnishings":"furnishings", "tall_grass_species":"strings"}
		"orchid_house": return {"position":"position3", "size":"size3", "door":"position3", "exterior_return":"position3", "origin":"position3", "interior_size":"size2", "entry":"position3", "exit_door":"position3", "npc":"position3", "orchids":"points", "floor_blocks":"blocks", "wall_blocks":"blocks", "furnishings":"furnishings", "tall_grass_species":"strings"}
		"family_house": return {"position":"position3", "size":"size3", "door":"position3", "exterior_return":"position3", "origin":"position3", "interior_size":"size2", "entry":"position3", "exit_door":"position3", "adults":"points", "children":"points", "floor_blocks":"blocks", "wall_blocks":"blocks", "furnishings":"furnishings", "tall_grass_species":"strings"}
	return {}

static func is_marker_field(field: String) -> bool:
	return field in ["player_spawn", "entry", "door", "exit_door", "clearing_warp", "clearing_return", "exit_warp", "east_warp", "east_return", "west_warp", "west_return", "north_warp", "north_return", "return_warp", "cave_warp", "cave_return", "exterior_return"]

static func coordinate_space(kind: String, field: String) -> String:
	if kind == "clearing": return "global"
	if kind == "route" and field in ["clearing_warp", "clearing_return"]: return "global"
	if field == "origin": return "global_origin"
	if kind == "clearing_house" and field in ["position", "size", "door"]: return "global"
	if kind in ["city_ward", "orchid_house", "family_house"] and field in ["position", "size", "door", "exterior_return"]: return "city_local"
	return "map_local"
