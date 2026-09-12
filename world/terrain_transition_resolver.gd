class_name TerrainTransitionResolver
extends RefCounted

## Pure map-preparation logic. Terrain identity remains authored data; the returned
## transition records are disposable render data and are never written to maps.

const N := 1
const NE := 2
const E := 4
const SE := 8
const S := 16
const SW := 32
const W := 64
const NW := 128

const DIRECTIONS := [
	{"name":"north", "offset":Vector2i(0, -1), "bit":N},
	{"name":"northeast", "offset":Vector2i(1, -1), "bit":NE},
	{"name":"east", "offset":Vector2i(1, 0), "bit":E},
	{"name":"southeast", "offset":Vector2i(1, 1), "bit":SE},
	{"name":"south", "offset":Vector2i(0, 1), "bit":S},
	{"name":"southwest", "offset":Vector2i(-1, 1), "bit":SW},
	{"name":"west", "offset":Vector2i(-1, 0), "bit":W},
	{"name":"northwest", "offset":Vector2i(-1, -1), "bit":NW},
]

const TERRAIN := {
	"water":{"priority":0, "texture":"res://assets/overworld/tile_water_generic.png", "tint":"3188b8"},
	"sand":{"priority":1, "texture":"res://assets/overworld/tile_sand_generic.png", "tint":"ffffff"},
	"mud":{"priority":2, "texture":"res://assets/overworld/tile_dirt_generic.png", "tint":"ffffff"},
	"forest_floor":{"priority":3, "texture":"res://assets/overworld/grass_main.png", "tint":"376b42", "rotate_180":true},
	"stone":{"priority":4, "texture":"res://assets/overworld/stone_main.png", "tint":"ffffff"},
	"rock":{"priority":5, "texture":"res://assets/overworld/stone_main.png", "tint":"777970"},
}

const MASKS := {
	"vertical_edge":{"paths":["res://assets/overworld/terrain_masks/mask_vertical_edge_small_00.png","res://assets/overworld/terrain_masks/mask_vertical_edge_small_01.png","res://assets/overworld/terrain_masks/mask_vertical_edge_small_02.png","res://assets/overworld/terrain_masks/mask_vertical_edge_small_03.png","res://assets/overworld/terrain_masks/mask_vertical_edge_small_04.png"], "rotation_safe":false},
	"horizontal_edge":{"paths":["res://assets/overworld/terrain_masks/mask_horizontal_edge_small_00.png","res://assets/overworld/terrain_masks/mask_horizontal_edge_small_01.png","res://assets/overworld/terrain_masks/mask_horizontal_edge_small_02.png","res://assets/overworld/terrain_masks/mask_horizontal_edge_small_03.png","res://assets/overworld/terrain_masks/mask_horizontal_edge_small_04.png"], "rotation_safe":false},
	"concave_corner":{"paths":["res://assets/overworld/terrain_masks/mask_corner_concave_small_00.png","res://assets/overworld/terrain_masks/mask_corner_concave_small_01.png","res://assets/overworld/terrain_masks/mask_corner_concave_small_02.png","res://assets/overworld/terrain_masks/mask_corner_concave_small_03.png","res://assets/overworld/terrain_masks/mask_corner_concave_small_04.png"], "rotation_safe":true},
	"convex_corner":{"paths":["res://assets/overworld/terrain_masks/mask_corner_convex_large_00.png","res://assets/overworld/terrain_masks/mask_corner_convex_large_01.png","res://assets/overworld/terrain_masks/mask_corner_convex_large_02.png","res://assets/overworld/terrain_masks/mask_corner_convex_large_03.png","res://assets/overworld/terrain_masks/mask_corner_convex_large_04.png"], "rotation_safe":true},
	"corner_a_dominant":{"paths":["res://assets/overworld/terrain_masks/mask_corner_a_dominant_00.png","res://assets/overworld/terrain_masks/mask_corner_a_dominant_01.png","res://assets/overworld/terrain_masks/mask_corner_a_dominant_02.png","res://assets/overworld/terrain_masks/mask_corner_a_dominant_03.png","res://assets/overworld/terrain_masks/mask_corner_a_dominant_04.png"], "rotation_safe":true},
	"corner_b_dominant":{"paths":["res://assets/overworld/terrain_masks/mask_corner_b_dominant_00.png","res://assets/overworld/terrain_masks/mask_corner_b_dominant_01.png","res://assets/overworld/terrain_masks/mask_corner_b_dominant_02.png","res://assets/overworld/terrain_masks/mask_corner_b_dominant_03.png","res://assets/overworld/terrain_masks/mask_corner_b_dominant_04.png"], "rotation_safe":true},
	"corner_even":{"paths":["res://assets/overworld/terrain_masks/mask_corner_even_00.png","res://assets/overworld/terrain_masks/mask_corner_even_01.png","res://assets/overworld/terrain_masks/mask_corner_even_02.png","res://assets/overworld/terrain_masks/mask_corner_even_03.png","res://assets/overworld/terrain_masks/mask_corner_even_04.png"], "rotation_safe":true},
}

# Layers are deliberately arrays: later recipes can append wet ground, foam, moss,
# or animated effect descriptors without changing the resolver or map format.
const RECIPES := {
	"water|sand":{"id":"sandy_shoreline", "layers":[{"kind":"base_edge", "texture":"res://assets/overworld/tile_sand_generic.png"}]},
	"sand|forest_floor":{"id":"forest_fringe", "layers":[{"kind":"base_edge", "texture":"res://assets/overworld/grass_main.png"}]},
	"forest_floor|rock":{"id":"rock_edge", "layers":[{"kind":"base_edge", "texture":"res://assets/overworld/stone_main.png"}]},
	"sand|rock":{"id":"rock_edge", "layers":[{"kind":"base_edge", "texture":"res://assets/overworld/stone_main.png"}]},
	"water|rock":{"id":"rock_bank", "layers":[{"kind":"base_edge", "texture":"res://assets/overworld/stone_main.png"}]},
	"water|forest_floor":{"id":"forest_bank", "layers":[{"kind":"base_edge", "texture":"res://assets/overworld/grass_main.png"}]},
}

static func prepare_map(map_data: Dictionary,map_seed:String="") -> Dictionary:
	var prepared := map_data.duplicate(true)
	var grid := terrain_grid(prepared)
	prepared["_terrain_grid"] = grid
	prepared["_terrain_issues"] = canonical_terrain_issues(prepared)
	var resolved_seed:=map_seed if not map_seed.is_empty() else String(prepared.get("map_metadata", {}).get("id", "map"))
	prepared["_terrain_transitions"] = resolve(grid,resolved_seed)
	return prepared

static func terrain_grid(map_data: Dictionary) -> Dictionary:
	var grid: Dictionary = {}
	var map_size: Variant = map_data.get("size", map_data.get("map_size", []))
	if map_size is Array and map_size.size() == 2:
		var base_terrain := String(map_data.get("base_terrain_type", "forest_floor"))
		if TERRAIN.has(base_terrain):
			var width := maxi(0, int(map_size[0])); var depth := maxi(0, int(map_size[1]))
			var start_x := floori(-float(width) * 0.5); var start_z := floori(-float(depth) * 0.5)
			for x in range(start_x, start_x + width):
				for z in range(start_z, start_z + depth): grid[Vector2i(x, z)] = base_terrain
	# Canonical identity is the sole topology source. Legacy water/sand rectangles
	# and block objects remain render/collision compatibility data and never enter
	# this grid.
	var explicit: Variant = map_data.get("terrain_tiles", [])
	if explicit is Array:
		for value: Variant in explicit:
			if value is Dictionary:
				var terrain_type := String(value.get("terrain_type", value.get("terrain", "")))
				if not TERRAIN.has(terrain_type): continue
				for position: Vector2i in _entry_positions(value): grid[position] = terrain_type
	if map_size is Array and map_size.size() >= 2:
		for position: Vector2i in grid.keys():
			if not tile_fits_map_bounds(position, Vector2(float(map_size[0]), float(map_size[1]))): grid.erase(position)
	return grid

static func canonical_terrain_issues(map_data: Dictionary) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	var claimed: Dictionary = {}
	var map_size_value: Variant = map_data.get("size", map_data.get("map_size", []))
	var has_bounds: bool = map_size_value is Array and map_size_value.size()==2
	var map_size := Vector2(float(map_size_value[0]),float(map_size_value[1])) if has_bounds else Vector2.ZERO
	var entries: Variant = map_data.get("terrain_tiles", [])
	if not entries is Array:
		return [{"code":"invalid_terrain_tiles", "message":"terrain_tiles must be an array."}]
	for index in entries.size():
		var value: Variant = entries[index]
		if not value is Dictionary:
			issues.append({"code":"invalid_entry", "index":index, "message":"Terrain entry must be an object."});continue
		var terrain_type:=String(value.get("terrain_type",value.get("terrain","")))
		if not TERRAIN.has(terrain_type):
			issues.append({"code":"unknown_terrain", "index":index, "terrain_type":terrain_type});continue
		for position:Vector2i in _entry_positions(value):
			if has_bounds and not tile_fits_map_bounds(position,map_size):
				issues.append({"code":"out_of_bounds", "index":index, "position":position});continue
			if claimed.has(position): issues.append({"code":"duplicate_coordinate", "index":index, "position":position, "first_index":claimed[position]})
			else: claimed[position]=index
	return issues

static func _entry_positions(entry: Dictionary) -> Array[Vector2i]:
	var result:Array[Vector2i]=[]
	var values:Variant=entry.get("positions",[])
	if values is Array:
		for position:Variant in values:
			if position is Array and position.size()>=2:result.append(Vector2i(int(position[0]),int(position[1])))
	var single:Variant=entry.get("position",[])
	if single is Array and single.size()>=2:result.append(Vector2i(int(single[0]),int(single[1])))
	return result

static func tile_fits_map_bounds(position: Vector2i, map_size: Vector2) -> bool:
	var half := map_size * 0.5
	return float(position.x) - 0.5 >= -half.x and float(position.x) + 0.5 <= half.x \
		and float(position.y) - 0.5 >= -half.y and float(position.y) + 0.5 <= half.y

static func resolve(grid: Dictionary, map_seed := "map") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var positions: Array = grid.keys()
	positions.sort_custom(func(a: Vector2i, b: Vector2i): return a.y < b.y or (a.y == b.y and a.x < b.x))
	for position: Vector2i in positions:
		# Scan each cardinal boundary once. Priority chooses A/B and draw order, never
		# whether the boundary exists.
		for boundary: Dictionary in [
			{"offset":Vector2i(1,0),"mask_type":"vertical_edge","negative":"west","positive":"east"},
			{"offset":Vector2i(0,1),"mask_type":"horizontal_edge","negative":"north","positive":"south"}]:
			var neighbor:Vector2i=position+boundary.offset
			if not grid.has(neighbor):continue
			var first:=String(grid[position]);var second:=String(grid[neighbor])
			if first==second:continue
			var terrain_a:=first if priority(first)>priority(second) else second
			var terrain_b:=second if terrain_a==first else first
			var key:=pair_key(terrain_a,terrain_b)
			var orientation:=String(boundary.negative) if terrain_a==first else String(boundary.positive)
			var recipe:Dictionary=_recipe_for(key,terrain_a)
			var mask_variant:=deterministic_variation(map_seed,position,recipe.id+":"+String(boundary.mask_type),mask_variant_count(String(boundary.mask_type)))
			result.append({"boundary_kind":"cardinal","region_position":Vector2(position)+Vector2(boundary.offset)*0.5,
				"affected_tiles":[position,neighbor],"terrain_a":terrain_a,"terrain_b":terrain_b,
				"higher_terrain":terrain_a,"lower_terrain":terrain_b,"piece":{"shape":"edge","mask_type":boundary.mask_type,"mask_variant":mask_variant,"orientation":orientation,"supported":true},
				"recipe_id":recipe.id,"layers":recipe.layers.duplicate(true),"variation":mask_variant})
	_add_corner_boundaries(result,grid,map_seed,positions)
	return result

static func operations_affecting_tile(transitions:Array[Dictionary],tile:Vector2i)->Array[Dictionary]:
	return transitions.filter(func(value:Dictionary):return tile in value.get("affected_tiles",[]))

static func _add_corner_boundaries(result:Array[Dictionary],grid:Dictionary,map_seed:String,positions:Array)->void:
	for northwest:Vector2i in positions:
		var northeast:=northwest+Vector2i.RIGHT;var southwest:=northwest+Vector2i.DOWN;var southeast:=northwest+Vector2i(1,1)
		if not grid.has(northeast) or not grid.has(southwest) or not grid.has(southeast):continue
		var tiles:=[northwest,northeast,southwest,southeast];var counts:={}
		for tile:Vector2i in tiles:
			var terrain:=String(grid[tile]);counts[terrain]=int(counts.get(terrain,0))+1
		if counts.size()!=2:continue
		var types:Array=counts.keys();var terrain_a:=String(types[0]) if priority(String(types[0]))>priority(String(types[1])) else String(types[1]);var terrain_b:=String(types[1]) if terrain_a==String(types[0]) else String(types[0])
		var count_a:=int(counts[terrain_a]);var mask_type:="";var orientation:=""
		if count_a==1:
			mask_type="corner_b_dominant";orientation=_corner_name_for_index(grid_values_index(grid,tiles,terrain_a))
		elif count_a==3:
			mask_type="corner_a_dominant";var b_corner:=_corner_name_for_index(grid_values_index(grid,tiles,terrain_b));orientation=_opposite_corner(b_corner)
		else:continue # Adjacent 2/2 splits are already represented by cardinal edges; diagonal checkerboards are ambiguous point contact.
		var key:=pair_key(terrain_a,terrain_b)
		var recipe:Dictionary=_recipe_for(key,terrain_a)
		var mask_variant:=deterministic_variation(map_seed,northwest,recipe.id+":"+mask_type,mask_variant_count(mask_type))
		result.append({"boundary_kind":"corner","region_position":Vector2(northwest)+Vector2(0.5,0.5),"affected_tiles":tiles,
			"terrain_a":terrain_a,"terrain_b":terrain_b,"higher_terrain":terrain_a,"lower_terrain":terrain_b,
			"piece":{"shape":"corner","mask_type":mask_type,"mask_variant":mask_variant,"orientation":orientation,"supported":true},"recipe_id":recipe.id,
			"layers":recipe.layers.duplicate(true),"variation":mask_variant})

static func grid_values_index(grid:Dictionary,tiles:Array,terrain:String)->int:
	for index in tiles.size():
		if String(grid[tiles[index]])==terrain:return index
	return 0

static func _corner_name_for_index(index:int)->String:
	return ["northwest","northeast","southwest","southeast"][index]

static func _opposite_corner(value:String)->String:
	return {"northwest":"southeast","northeast":"southwest","southwest":"northeast","southeast":"northwest"}[value]

static func pieces_for_mask(mask: int) -> Array[Dictionary]:
	var pieces: Array[Dictionary] = []
	var cardinals := [N,E,S,W].filter(func(bit:int):return bool(mask&bit))
	# Two adjacent cardinal edges describe one connected corner. The diagonal only
	# selects whether A dominates that corner or leaves a concave B pocket.
	if cardinals.size()==2:
		for value: Dictionary in [
			{"bit":NE,"a":N,"b":E,"orientation":"northeast"}, {"bit":SE,"a":S,"b":E,"orientation":"southeast"},
			{"bit":SW,"a":S,"b":W,"orientation":"southwest"}, {"bit":NW,"a":N,"b":W,"orientation":"northwest"}]:
			if bool(mask&int(value.a)) and bool(mask&int(value.b)):
				if bool(mask&int(value.bit)):
					return [{"shape":"connected_corner", "mask_type":"corner_a_dominant", "orientation":value.orientation, "supported":true}]
				return [{"shape":"inner_corner", "mask_type":"concave_corner", "orientation":value.orientation, "supported":true}]
	for value: Dictionary in [{"bit":N,"orientation":"north"},{"bit":E,"orientation":"east"},{"bit":S,"orientation":"south"},{"bit":W,"orientation":"west"}]:
		if mask & int(value.bit):
			pieces.append({"shape":"edge", "mask_type":"horizontal_edge" if value.orientation in ["north","south"] else "vertical_edge", "orientation":value.orientation, "supported":true})
	# A diagonal with neither adjacent cardinal is merely point contact. The lower
	# cardinal terrain blocks it, so it must not create a disconnected overlay.
	return pieces

static func priority(terrain_type: String) -> int:
	return int(TERRAIN.get(terrain_type, {"priority":-1}).priority)

static func _recipe_for(key:String,terrain_a:String)->Dictionary:
	if RECIPES.has(key):return RECIPES[key]
	return {"id":"generic_%s"%key.replace("|","_"),"layers":[{"kind":"base_edge","texture":String(TERRAIN[terrain_a].texture)}]}

static func pair_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if priority(a) <= priority(b) else "%s|%s" % [b, a]

static func deterministic_variation(map_seed: String, position: Vector2i, recipe_id: String, count: int) -> int:
	if count <= 1: return 0
	return absi((map_seed + ":%d:%d:" % [position.x, position.y] + recipe_id).hash()) % count

static func mask_variant_count(mask_type:String)->int:
	return Array(MASKS.get(mask_type,{}).get("paths",[])).size()

static func mask_path(mask_type:String,variant:int)->String:
	var paths:Array=MASKS.get(mask_type,{}).get("paths",[])
	return String(paths[posmod(variant,paths.size())]) if not paths.is_empty() else ""


static func affected_positions(changed: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = [changed]
	for direction: Dictionary in DIRECTIONS: result.append(changed + direction.offset)
	return result
