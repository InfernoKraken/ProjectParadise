extends SceneTree

const Resolver := preload("res://world/terrain_transition_resolver.gd")
const TextureCache := preload("res://world/terrain_transition_texture_cache.gd")

func _init() -> void:
	assert(Resolver.resolve({Vector2i(0,0):"water",Vector2i(1,0):"water"}).is_empty())
	_check_pair("water", "sand", "east")
	_check_pair("sand", "forest_floor", "east")
	_check_pair("forest_floor", "rock", "east")
	_check_pair("water", "rock", "east")
	_check_pair("sand", "mud", "east")
	_check_pair("mud", "forest_floor", "east")
	_check_pair("forest_floor", "stone", "east")
	_check_pair("stone", "rock", "east")
	assert(Resolver.priority("sand")<Resolver.priority("mud") and Resolver.priority("mud")<Resolver.priority("forest_floor") and Resolver.priority("forest_floor")<Resolver.priority("stone"))
	_check_pair("water", "sand", "south")
	var outer := Resolver.resolve({Vector2i(0,0):"water",Vector2i(1,1):"sand"})
	assert(outer.is_empty(), "Diagonal-only point contact must not create a disconnected transition fragment.")
	var connected_corner := Resolver.resolve({Vector2i(0,0):"water",Vector2i(1,0):"sand",Vector2i(0,1):"sand",Vector2i(1,1):"sand"})
	assert(connected_corner.any(func(v):return v.boundary_kind=="corner" and v.piece.mask_type=="corner_a_dominant"))
	var inner := Resolver.resolve({Vector2i(0,0):"water",Vector2i(1,0):"sand",Vector2i(0,1):"sand",Vector2i(1,1):"water"})
	assert(inner.filter(func(v):return v.boundary_kind=="cardinal").size()==4)
	var multi := Resolver.resolve({Vector2i(0,0):"water",Vector2i(0,-1):"sand",Vector2i(0,1):"sand"})
	var multi_pieces := Resolver.operations_affecting_tile(multi,Vector2i.ZERO)
	assert(multi_pieces.size()==2 and multi_pieces.all(func(v):return v.terrain_a=="sand" and v.terrain_b=="water"))
	var shoreline := Resolver.resolve({Vector2i(0,0):"forest_floor",Vector2i(1,0):"sand",Vector2i(2,0):"water"})
	var sand_operations:=Resolver.operations_affecting_tile(shoreline,Vector2i(1,0))
	assert(sand_operations.any(func(v):return v.terrain_a=="forest_floor" and v.terrain_b=="sand"))
	assert(sand_operations.any(func(v):return v.terrain_a=="sand" and v.terrain_b=="water"))
	assert(not shoreline.any(func(v):return (v.lower_terrain=="water" and v.higher_terrain=="forest_floor")))
	var route_file:=FileAccess.open("res://data/maps/eastern_rainforest_route.json",FileAccess.READ)
	var route_data:Dictionary=JSON.parse_string(route_file.get_as_text())
	var bridge_transitions:=Resolver.resolve(Resolver.terrain_grid(route_data),"eastern_rainforest_route")
	var regression:=Resolver.operations_affecting_tile(bridge_transitions,Vector2i(-3,-6))
	assert(regression.any(func(v):return v.terrain_a=="forest_floor" and v.terrain_b=="sand" and v.piece.orientation=="east"))
	assert(regression.any(func(v):return v.terrain_a=="sand" and v.terrain_b=="water" and v.piece.orientation=="east"))
	for map_path in ["canopy_route.json","rainforest_clearing.json","western_rainforest_route.json","eastern_rainforest_route.json"]:
		var map_file:=FileAccess.open("res://data/maps/"+map_path,FileAccess.READ)
		var outdoor_data:Dictionary=JSON.parse_string(map_file.get_as_text())
		assert(String(outdoor_data.get("base_terrain_type",""))=="forest_floor" and not (outdoor_data.get("terrain_tiles",[]) as Array).is_empty(),map_path+" must use canonical terrain data.")
		var outdoor_grid:=Resolver.terrain_grid(outdoor_data)
		assert(outdoor_grid.values().has("sand") and outdoor_grid.values().has("water"),map_path+" must canonically represent both shoreline terrains.")
		assert(not Resolver.resolve(outdoor_grid,map_path).is_empty(),map_path+" must generate transition operations from its canonical boundaries.")
		if map_path in ["canopy_route.json","rainforest_clearing.json"]:
			for position:Vector2i in outdoor_grid:
				if outdoor_grid[position]!="water":continue
				for offset:Vector2i in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
					assert(outdoor_grid.has(position+offset) and outdoor_grid[position+offset]!="forest_floor",map_path+" water must terminate inside a canonical sand cap, not at the map edge or directly against forest.")
	assert(Resolver.resolve({Vector2i(0,0):"water"}).is_empty())
	assert(Resolver.deterministic_variation("seed",Vector2i(4,8),"edge",7)==Resolver.deterministic_variation("seed",Vector2i(4,8),"edge",7))
	assert(Resolver.mask_variant_count("vertical_edge")==5 and Resolver.mask_path("vertical_edge",4).ends_with("mask_vertical_edge_small_04.png"))
	var varied_grid:Dictionary={}
	for y in 20:varied_grid[Vector2i(0,y)]="water";varied_grid[Vector2i(1,y)]="sand"
	var first_variants:=Resolver.resolve(varied_grid,"stable_map_seed").filter(func(value):return value.boundary_kind=="cardinal" and value.piece.mask_type=="vertical_edge").map(func(value):return value.piece.mask_variant)
	var repeated_variants:=Resolver.resolve(varied_grid,"stable_map_seed").filter(func(value):return value.boundary_kind=="cardinal" and value.piece.mask_type=="vertical_edge").map(func(value):return value.piece.mask_variant)
	assert(first_variants==repeated_variants and first_variants.all(func(value):return value>=0 and value<5),"Mask variants must be deterministic and remain within the authored set.")
	var unique_variants:Dictionary={};for value in first_variants:unique_variants[value]=true
	assert(unique_variants.size()>1,"Neighboring boundaries should receive controlled visual variation.")
	assert(Resolver.affected_positions(Vector2i.ZERO).size()==9)
	var bounded := Resolver.terrain_grid({"size":[4,4],"terrain_tiles":[
		{"position":[1,0],"terrain_type":"sand"},{"position":[2,0],"terrain_type":"water"}]})
	assert(bounded.has(Vector2i(1,0)) and not bounded.has(Vector2i(2,0)))
	assert(bounded.keys().all(func(position:Vector2i):return Resolver.tile_fits_map_bounds(position,Vector2(4,4))))
	var legacy_ignored:=Resolver.terrain_grid({"size":[4,4],"water_blocks":[[0,0.15,0,2,0.3,2]],"sand_blocks":[[0,0.05,0,3,0.1,0.5]],"objects":[{"type":"block.rock","position":[0,0,0],"size":[1,1,1]}]})
	assert(legacy_ignored.values().all(func(terrain):return terrain=="forest_floor"),"Legacy visual rectangles must never create canonical topology.")
	var duplicate_issues:=Resolver.canonical_terrain_issues({"size":[4,4],"terrain_tiles":[{"terrain_type":"sand","position":[0,0]},{"terrain_type":"water","positions":[[0,0]]}]})
	assert(duplicate_issues.any(func(issue):return issue.code=="duplicate_coordinate"))
	TextureCache.clear()
	assert(TextureCache.base_texture("sand")!=null and TextureCache.base_texture("water")!=null and TextureCache.base_texture("mud")!=null and TextureCache.base_texture("stone")!=null)
	var first := TextureCache.texture_for("forest_floor","sand","vertical_edge","west")
	var repeated := TextureCache.texture_for("forest_floor","sand","vertical_edge","west")
	var opposite := TextureCache.texture_for("forest_floor","sand","vertical_edge","east")
	assert(first != null and first == repeated and opposite != null and TextureCache.cache_size()==2)
	var alternate_variant:=TextureCache.texture_for("forest_floor","sand","vertical_edge","west",1)
	assert(alternate_variant!=null and alternate_variant!=first and TextureCache.cache_size()==3,"Generated texture caching must distinguish selected mask variants.")
	assert(first.get_image().get_pixel(0, first.get_height()/2) != first.get_image().get_pixel(first.get_width()-1, first.get_height()/2))
	_assert_mask_sides(first, "forest_floor", "sand", true)
	var sand_water := TextureCache.texture_for("sand","water","horizontal_edge","north")
	_assert_mask_sides(sand_water, "sand", "water", false)
	var sand_water_corner := TextureCache.texture_for("sand","water","convex_corner","northwest")
	assert(sand_water_corner != null and sand_water_corner != sand_water)
	for optional_corner in ["corner_a_dominant","corner_b_dominant","corner_even"]:
		assert(TextureCache.texture_for("sand","water",optional_corner,"northwest") != null)
	var ordered_stack := TextureCache.texture_for_stack("water",[
		{"terrain_a":"sand","mask_type":"vertical_edge","orientation":"west"},
		{"terrain_a":"forest_floor","mask_type":"horizontal_edge","orientation":"north"}])
	var reversed_stack := TextureCache.texture_for_stack("water",[
		{"terrain_a":"forest_floor","mask_type":"horizontal_edge","orientation":"north"},
		{"terrain_a":"sand","mask_type":"vertical_edge","orientation":"west"}])
	assert(ordered_stack != null and ordered_stack == reversed_stack)
	var same_pair_tile:=TextureCache.texture_for_tile("water",[
		{"terrain_a":"sand","terrain_b":"water","mask_type":"vertical_edge","orientation":"east","slice":"vertical_negative"},
		{"terrain_a":"sand","terrain_b":"water","mask_type":"vertical_edge","orientation":"west","slice":"vertical_positive"}])
	assert(same_pair_tile!=null,"Opposing masks for one terrain pair must compose into one tile texture.")
	var three_priority_tile:=TextureCache.texture_for_tile("sand",[
		{"terrain_a":"sand","terrain_b":"water","mask_type":"vertical_edge","orientation":"east","slice":"vertical_positive"},
		{"terrain_a":"forest_floor","terrain_b":"sand","mask_type":"vertical_edge","orientation":"east","slice":"vertical_negative"}])
	assert(three_priority_tile!=null,"Different terrain pairs must compose into one canonical tile texture.")
	var prepared := Resolver.prepare_map({"terrain_tiles":[{"position":[0,0],"terrain_type":"water"},{"position":[1,0],"terrain_type":"sand"}]})
	assert(prepared._terrain_transitions.size()>0 and not prepared.has("collision") and not prepared.has("elevation"))
	print("Terrain transition tests passed.")
	quit()

func _check_pair(lower:String,higher:String,orientation:String)->void:
	var neighbor := Vector2i(1,0) if orientation=="east" else Vector2i(0,1)
	var records := Resolver.resolve({Vector2i(0,0):lower,neighbor:higher})
	assert(records.size()==1 and records[0].boundary_kind=="cardinal" and records[0].piece.orientation==orientation and Vector2i.ZERO in records[0].affected_tiles and neighbor in records[0].affected_tiles)

func _assert_mask_sides(generated: Texture2D, terrain_a_type: String, terrain_b_type: String, vertical_split: bool) -> void:
	var actual := generated.get_image()
	var terrain_a := TextureCache._terrain_image(terrain_a_type); terrain_a.resize(actual.get_width(),actual.get_height(),Image.INTERPOLATE_NEAREST)
	var terrain_b := TextureCache._terrain_image(terrain_b_type); terrain_b.resize(actual.get_width(),actual.get_height(),Image.INTERPOLATE_NEAREST)
	if vertical_split:
		var y := actual.get_height()/2
		assert(actual.get_pixel(0,y).is_equal_approx(terrain_a.get_pixel(0,y)))
		assert(actual.get_pixel(actual.get_width()-1,y).is_equal_approx(terrain_b.get_pixel(actual.get_width()-1,y)))
	else:
		var x := actual.get_width()/2
		assert(actual.get_pixel(x,0).is_equal_approx(terrain_a.get_pixel(x,0)))
		assert(actual.get_pixel(x,actual.get_height()-1).is_equal_approx(terrain_b.get_pixel(x,actual.get_height()-1)))
