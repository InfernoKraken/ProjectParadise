extends Node

# Entry boundary: named map-local Blocks only; no executable script resources.
func run_map_block(filename: String, block: String) -> bool:
	if script_runner.running: return false
	var data: Dictionary = map_data.get("_map_files", {}).get(filename, {})
	if data.is_empty() or _location_for_map_file(filename) != _current_location(): return false
	var source: Variant = data.get("script_source", "")
	if not source is String: return false
	script_host.map_file = filename
	var path_data := preload("res://world/scripting/script_paths.gd").inspect(data)
	# Only validated paths enter the parser pools; unrelated draft paths stay editable.
	var references := preload("res://world/scripting/script_paths.gd").actor_references(data)
	references["move_path"] = path_data.move_path; references["follow_path"] = path_data.follow_path
	return script_runner.start(source, block, filename, game_flags, script_host.execute, script_host.cleanup, references)

func _run_map_headers(location: String) -> void:
	for filename: String in map_data.get("_map_files", {}):
		if _location_for_map_file(filename) != location: continue
		var data: Dictionary = map_data._map_files[filename]
		if not data.has("map_script_header") and not data.has("map_script_headers"): continue
		var references := preload("res://world/scripting/script_paths.gd").actor_references(data)
		var inspected := preload("res://world/scripting/map_header.gd").inspect(data, references)
		if not inspected.valid:
			push_warning("Map header rejected: " + JSON.stringify(inspected.diagnostics)); continue
		for header: Dictionary in inspected.headers:
			var entry := str(header.true_block if game_flags.has_flag(header.flag) else header.false_block)
			if not run_map_block(filename, entry): break

func _try_script_npc(npc: Node) -> bool:
	if script_host.sprite_hidden(npc): return false
	var filename := str(npc.get_meta("script_map", ""))
	var key := "npc:" + str(npc.get_meta("script_npc_id", ""))
	var data: Dictionary = map_data.get("_map_files", {}).get(filename, {})
	var table: Variant = data.get("script_interactions", {})
	if not table is Dictionary or not table.has(key): return false
	run_map_block(filename, str(table[key]))
	return true

func _interact_placed_npc(npc: Area3D) -> void:
	if npc.get_meta("npc_definition", {}).get("type") == "vehicle": return
	if script_runner.running or script_host.sprite_hidden(npc): return
	_face_npc_toward_player(npc)
	if _try_script_npc(npc): return
	var dialogue_data: Dictionary = npc_dialogues.get(npc.get_instance_id(), {})
	if not dialogue_data.is_empty():
		_start_dialogue(String(dialogue_data["speaker"]), dialogue_data["pages"], dialogue_data.get("after_dialogue", Callable()))

func _try_script_object_click(screen_position: Vector2) -> bool:
	for filename: String in map_data.get("_map_files", {}):
		if _location_for_map_file(filename) != _current_location(): continue
		var table: Variant = map_data._map_files[filename].get("script_interactions", {})
		if not table is Dictionary: continue
		for entries: Array in [object_sort_entries, tree_sort_entries, background_object_sort_entries]:
			for entry: Dictionary in entries:
				var key := "object:" + str(entry.get("instance_id", ""))
				if not table.has(key) or not entry.has("sort_root") or not entry.sort_root.is_visible_in_tree(): continue
				var art := entry.sort_root.get_node_or_null("Visual") as Sprite2D
				if art != null and art.get_rect().has_point(art.to_local(screen_position)):
					run_map_block(filename, str(table[key])); return true
	return false

# Shared outdoor framing keeps zoom consistent across travel and save loading.
const OUTDOOR_CAMERA_SIZE := 14.0
const MAP_DATA_PATH := "res://data/maps/map_index.json"
const PLATFORM_WALL_LAYER := 4
const ACTOR_COLLISION_LAYER := 8
const FENCE_COLLISION_LAYER := 16
const MapDataLoader := preload("res://world/map_data_loader.gd")
const TerrainTransitionResolver := preload("res://world/terrain_transition_resolver.gd")
const PolygonColliders := preload("res://tools/map_editor/core/polygon_colliders.gd")
const MapBounds := preload("res://tools/map_editor/core/map_bounds.gd")
const MapBorderRenderer := preload("res://world/map_border_renderer.gd")
const MapBorderLayout := preload("res://tools/map_editor/core/map_border_layout.gd")
const TerrainTransitionTextureCache := preload("res://world/terrain_transition_texture_cache.gd")
const PlayerPalette := preload("res://world/player_palette.gd")
const PlayerSpriteFrames := preload("res://world/player_sprite_frames.gd")
const SwimSpriteFrames := preload("res://world/swim_sprite_frames.gd")
const NpcMovement := preload("res://world/npc_movement.gd")
const WaterDecoration := preload("res://world/water_decoration.gd")
var npc_movement_states: Dictionary = {}
var npc_script_movement = preload("res://world/npc_script_movement.gd").new(self)
var npc_water_surfaces: Dictionary = {}
var applied_visual_location := ""
var collision_regions:Dictionary={}
var collision_regions_dirty:=true
var collision_diagnostics := false
var last_collision_diagnostic := ""

const NpcVisualResolver := preload("res://world/npc_visual_resolver.gd")
var npc_visual_resolver: RefCounted
# map filename -> map-local integer ID -> mutable live Area3D
var runtime_npcs: Dictionary = {}
var patrols = preload("res://world/vehicle_patrols.gd").new(self)

const NpcSpriteLibrary := preload("res://world/npc_sprite_library.gd")
const DayNightControllerScript := preload("res://world/day_night_controller.gd")
const AUTO_SAVE_PATH := "user://project_paradise_autosave.json"
const SAVE_SLOT_COUNT := 5
const SAVE_VERSION := 3
const MOVE_SPEED := 5.0
const PLAYER_VISUAL_HEIGHT := 1.6
const PLAYER_GROUND_HEIGHT := 0.65
const NPC_ADULT_VISUAL_HEIGHT := 1.65
const NPC_CHILD_VISUAL_HEIGHT := 1.4
const NPC_FOOT_COLLISION_SIZE := NpcMovement.FOOT_SIZE
const NPC_FOOT_COLLISION_OFFSET := Vector3(0.0,-0.33,0.0)
const SWIM_VISUAL_HEIGHT := 0.58
const DIVE_ACTOR_VISUAL_HEIGHT := PLAYER_VISUAL_HEIGHT
const DIVE_NEUTRAL_TIME := 0.58
const DIVE_THROW_TIME := 0.59
const DIVE_BACKPACK_LAND_TIME := 0.57
const DIVE_JUMP_TIME := 0.50
const DIVE_SPLASH_TIME := 0.18
const DEX_VIEW_SCENE := preload("res://dex/dex_view.tscn")
const TEX_FLOWER_BLUE := preload("res://assets/overworld/flower_small_blue_generic.png")
const TEX_FLOWER_RED := preload("res://assets/overworld/flower_tall_redginger.png")
const TEX_FLOWER_ORCHID_POT := preload("res://assets/overworld/flower_indoor_orchidpot.png")
const TEX_FLOWER_TORCH_GINGER := preload("res://assets/overworld/flower_tall_magnificent_torchginger.png")
const TEX_GRASS := preload("res://assets/overworld/grass_main.png")
const TEX_HOUSE := preload("res://assets/overworld/house.png")
const CITY_BACKGROUND_TEXTURES := {
	"background.citybuilding_00": preload("res://assets/overworld/citybuilding_00.png"),
	"background.citybuilding_01": preload("res://assets/overworld/citybuilding_01.png"),
	"background.citybuilding_02": preload("res://assets/overworld/citybuilding_02.png"),
	"background.citybuilding_03": preload("res://assets/overworld/citybuilding_03.png"),
	"background.citybuilding_04": preload("res://assets/overworld/citybuilding_04.png"),
	"background.citybuilding_apartment_00": preload("res://assets/overworld/citybuilding_apartment_00.png"),
	"background.citybuilding_apartment_01": preload("res://assets/overworld/citybuilding_apartment_01.png"),
	"background.citybuilding_apartment_02": preload("res://assets/overworld/citybuilding_apartment_02.png"),
	"background.citybuilding_apartment_03": preload("res://assets/overworld/citybuilding_apartment_03.png"),
	"background.citybuilding_apartment_04": preload("res://assets/overworld/citybuilding_apartment_04.png"),
}
const TEX_MEDICAL_WARD := preload("res://assets/overworld/medical_ward.png")
const TEX_STONE := preload("res://assets/overworld/stone_main.png")
const TEX_DIRT := preload("res://assets/overworld/tile_dirt_generic.png")
const TEX_DIRT_RICH := preload("res://assets/overworld/tile_dirt_rich.png")
const TEX_SAND := preload("res://assets/overworld/tile_sand_generic.png")
const TEX_TALL_GRASS := preload("res://assets/overworld/tile_tallgrass_generic.png")
const TEX_WALL := preload("res://assets/overworld/tile_wall_interior.png")
const TEX_WALL_GENERIC := preload("res://assets/overworld/tile_wall_interior_generic.png")
const TEX_WALL_POST := preload("res://assets/overworld/wall_post_generic.png")
const TEX_WALL_FILLER_HORIZONTAL := preload("res://assets/overworld/wall_horizontal_generic.png")
const TEX_WALL_FILLER_VERTICAL := preload("res://assets/overworld/wall_vertical_generic.png")
const WALL_VISUAL_HEIGHT := 2.0
# Every wall asset uses this same source-pixel-to-world-unit ratio.  It is
# anchored to the existing 166px-tall post at its authored 2.0-unit height.
const WALL_PIXELS_TO_WORLD := 2.0 / 166.0
const WALL_FILLER_INTERVAL := 2.0
const TEX_INTERIOR_FLOOR := preload("res://assets/overworld/tile_interior_floor_tiles.png")
const TEX_WATER := preload("res://assets/overworld/tile_water_generic.png")
const TEX_WOOD := preload("res://assets/overworld/tile_wood.png")
const TEX_BRIDGE_HORIZONTAL_START := preload("res://assets/overworld/tile_bridge_horizontal_l.png")
const TEX_BRIDGE_HORIZONTAL_MIDDLE := preload("res://assets/overworld/tile_bridge_horizontal_edge.png")
const TEX_BRIDGE_HORIZONTAL_END := preload("res://assets/overworld/tile_bridge_horizontal_edge_r.png")
const TEX_BRIDGE_VERTICAL_START := preload("res://assets/overworld/tile_bridge_vertical_edge_north.png")
const TEX_BRIDGE_VERTICAL_MIDDLE := preload("res://assets/overworld/tile_bridge_vertical_section.png")
const TEX_BRIDGE_VERTICAL_END := preload("res://assets/overworld/tile_bridge_vertical_edge_south.png")
const TERRAIN_OBSTACLE_LAYER := 2
const BRIDGE_ASSET_WIDTH_SCALE := 1.3
const TERRAIN_FOOTPRINT_SIZE := Vector3(0.45,0.25,0.45)
const TERRAIN_FOOTPRINT_OFFSET_Y := -0.5
# Building records use their saved position as the front, ground-contact line of
# the artwork.  Their physical mass therefore belongs behind that line; keeping
# the front clear lets the player stand at doors and on visible steps.
const BUILDING_FRONT_EXTENSION := {"medical_ward":0.0,"house":0.0}
const TEX_BED := preload("res://assets/overworld/bed_bedroom_main.png")
const TEX_DRESSER := preload("res://assets/overworld/dresser_bedroom_main.png")
const TEX_HUTCH := preload("res://assets/overworld/hutch_familyroom_main.png")
const TEX_LAMPSTAND := preload("res://assets/overworld/lampstand_bedroom_main.png")
const TEX_TABLE := preload("res://assets/overworld/table_familyroom_main.png")
const TEX_HOUSEPLANT_ONE := preload("res://assets/overworld/houseplant_indoor_1.png")
const TEX_HOUSEPLANT_TWO := preload("res://assets/overworld/houseplant_indoor_2.png")
const TEX_WARD_COUNTER := preload("res://assets/overworld/medical_ward_counter_entry.png")
const TEX_WARD_SHELF := preload("res://assets/overworld/medical_ward_shelf.png")
const TEX_WARD_TABLE := preload("res://assets/overworld/medical_ward_table.png")
const TEX_WARD_CURTAIN := preload("res://assets/overworld/indoor_changing_curtain.png")
const TEX_WARD_WASH := preload("res://assets/overworld/indoor_wash_station.png")
const TEX_TREE_MAIN := preload("res://assets/overworld/tree_main.png")
const TEX_TREE_PALM := preload("res://assets/overworld/tree_palm.png")
const TEX_VINES := preload("res://assets/overworld/vines.png")
const TEX_PASSION_VINE_HORIZONTAL := preload("res://assets/overworld/vines_horizontal_flower_passion.png")
const WarpSpriteCatalog := preload("res://tools/map_editor/core/warp_sprite_catalog.gd")
const TEX_WARP_BUILDING := preload("res://assets/overworld/warp_building_generic.png")
const TEX_WARP_EAST := preload("res://assets/overworld/warp_outdoor_facing_east.png")
const TEX_WARP_GENERIC := preload("res://assets/overworld/warp_outdoor_generic.png")
const TEX_WARP_NORTH := preload("res://assets/overworld/warp_outdoor_facing_north.png")
const TEX_WARP_WEST := preload("res://assets/overworld/warp_outdoor_facing_west.png")
const DYNAMIC_VISUAL_LAYER := 20
const OUTDOOR_BACKGROUND := Color("#17321f")
const PLAYER_CHOICES := [
	{"gender": "Male", "style": "Medium", "preset": "medium"},
	{"gender": "Male", "style": "Light / Blonde", "preset": "light_blonde"},
	{"gender": "Male", "style": "Light / Red", "preset": "light_red"},
	{"gender": "Male", "style": "Dark / Black", "preset": "dark_black"},
	{"gender": "Female", "style": "Medium", "preset": "medium"},
	{"gender": "Female", "style": "Light / Blonde", "preset": "light_blonde"},
	{"gender": "Female", "style": "Light / Red", "preset": "light_red"},
	{"gender": "Female", "style": "Dark / Black", "preset": "dark_black"},
]

@onready var world: Node3D = $World
@onready var battle: Control = $Battle

var map_data: Dictionary
var trainer_catalog: Dictionary = {}
var player: CharacterBody3D
var player_sprite: Sprite3D
var terrain_foot_shape:BoxShape3D
var follower: Node3D
var follower_sprite: Sprite3D
var sort_canvas: CanvasLayer
var day_night_controller: Node
var sort_root: Node2D
var player_sort_root: Node2D
var follower_sort_root: Node2D
var npc_sort_entries: Array[Dictionary] = []
var tree_sort_entries: Array[Dictionary] = []
# Clear this signature after runtime edits to static artwork. Script visibility
# and camera/map changes are detected by the static pass automatically.
var static_art_view_signature:Array=[]
var map_border_renderer: Node3D
var map_border_location := ""
var object_sort_entries: Array[Dictionary] = []
var overlay_sort_entries: Array[Dictionary] = []
var attached_overlay_entries: Array[Dictionary] = []
var background_object_sort_entries: Array[Dictionary] = []
var traversal_surfaces: Array[Dictionary] = []
var bridge_sort_entries: Array[Dictionary] = []
var active_traversal_layer := 0
var active_traversal_surface: Dictionary = {}
var follower_target := Vector3.ZERO
var follower_facing := "Down"
var opponent: Area3D
var camera: Camera3D
var spawn_position: Vector3
var respawn_position: Vector3
var respawn_location := "rainforest"
var respawn_title := "RAINFOREST CLEARING - PLACEHOLDER MAP"
var opponent_fakemon_index := 2
var opponent_fakemon_indices: Array[int] = []
var in_battle := false
var active_battle_is_wild := false
var game_flags = preload('res://world/scripting/game_flags.gd').new()
var script_runner = preload('res://world/scripting/script_runner.gd').new()
var script_host = preload('res://world/scripting/world_script_host.gd').new(self)
var script_input_locked := false
const FakemonStorage = preload("res://world/fakemon_storage.gd")
const CloudDialog = preload("res://world/cloud_dialog.gd")

const HabitatExhibits := preload("res://world/habitat_exhibits.gd")
var exhibits := HabitatExhibits.new(self)
var exhibit_menu: PopupMenu
var exhibit_transition := false
var fakemon_storage := FakemonStorage.new()
var party: Array[Dictionary] = fakemon_storage.party
var cloud: Array[Dictionary] = fakemon_storage.cloud
var cloud_dialog: CloudDialog
var active_party_index := 0
var last_grass_tile := ""
var last_water_tile := ""
var hint_label: Label
var map_ui: CanvasLayer
var party_panel: PanelContainer
var party_list: VBoxContainer
var settings_panel: PanelContainer
var bag_panel: PanelContainer
var dex_panel: Control
var door_warp_ready := true
var inside_medical_ward := false
var inside_house := false
var inside_route := false
var inside_east_route := false
var inside_west_route := false
var inside_east_cave := false
var inside_city := false
var inside_city_ward := false
var inside_orchid_house := false
var inside_family_house := false
var active_authored_map_id := ""
var authored_visual_regions: Array[Dictionary] = []
var medical_origin := Vector3.ZERO
var house_origin := Vector3.ZERO
var route_origin := Vector3.ZERO
var east_route_origin := Vector3.ZERO
var west_route_origin := Vector3.ZERO
var east_cave_origin := Vector3.ZERO
var city_origin := Vector3.ZERO
var city_ward_origin := Vector3.ZERO
var orchid_house_origin := Vector3.ZERO
var family_house_origin := Vector3.ZERO
var adventure_started := false
var poison_step_distance := 0.0
var world_environment: Environment
var map_title: Label
var house_npc: Area3D
var dialog_panel: PanelContainer
var dialog_label: Label
var dialog_speaker: Label
var dialog_button: Button
var dialog_page := 0
var dialog_open := false
var dialogue_complete_action := Callable()
var save_status_label: Label
var startup_panel: PanelContainer
var player_selection_panel: PanelContainer
var player_gender := "Male"
var player_color_name := ""
var player_color := Color("#55e36a")
var player_style := "Medium"
var player_palette_preset := PlayerPalette.DEFAULT_PRESET
var player_atlas: Texture2D
var player_animation := "idle_down"
var player_frame_index := 0
var player_animation_time := 0.0
var swimming := false
var swim_transitioning := false
var swim_direction := "down"
var swim_atlas: Texture2D
var dive_atlas: Texture2D
var swim_transition_effect_root: Node2D
var swim_transition_effect_position := Vector3.ZERO
var swim_transition_effect_height := 0.8
var swim_jump_height := 0.0
var save_slot_selector: OptionButton
var selected_save_slot := 1
var npc_dialogues: Dictionary = {}
var family_children: Array[Dictionary] = []
var dialog_choice_row: HBoxContainer
var dialog_yes_button: Button
var dialog_no_button: Button
var dialogue_choice_action := Callable()
var dialog_choosing := false
var active_dialogue: Array[String] = []
var active_dialogue_speaker := "RAINFOREST RESIDENT"
var pending_move_learning: Array[Dictionary] = []
var move_learning_panel: PanelContainer
var move_learning_list: VBoxContainer
var pending_evolutions: Array[Dictionary] = []
var evolution_layer: CanvasLayer
var evolution_screen: Control
var evolution_old_art: TextureRect
var evolution_new_art: TextureRect
var evolution_title: Label
var evolution_cancel_button: Button
var evolution_cancelled := false
var evolution_in_progress := false
var burn_dialogue := [
	"Burned is a persistent special condition. It remains after battle until the affected Fakemon receives medical care.",
	"After a Burned Fakemon uses a move, it loses 1/8 of its maximum HP. Burn also lowers its physical Attack and Defense by 25%.",
	"The medical ward cures Burn and other persistent conditions. Some Fakemon also know condition-removing moves such as Burn Off or Restore."
]


func _ready() -> void:
	var profile_startup := "--profile-startup" in OS.get_cmdline_user_args()
	var startup_started := Time.get_ticks_usec()
	script_runner.failed.connect(func(details): npc_script_movement.release_player(); push_warning('Script runtime error: ' + JSON.stringify(details)))
	map_data = _load_map_data()
	var data_loaded := Time.get_ticks_usec()
	trainer_catalog=MapDataLoader._load_json_object("res://data/trainers.json").get("trainers",{})
	if map_data.is_empty():
		return
	build_rainforest()
	var world_built := Time.get_ticks_usec()
	battle.battle_finished.connect(_on_battle_finished)
	battle.fakemon_selected.connect(_on_fakemon_selected)
	_build_evolution_screen()
	_set_overworld_visuals_visible(false)
	map_ui.visible = false
	battle.hide()
	var test_map_filename:=_test_map_filename_from_args(OS.get_cmdline_user_args())
	if not test_map_filename.is_empty():
		call_deferred("_start_map_test",test_map_filename)
	else:
		_build_player_selection()
		if FileAccess.file_exists(AUTO_SAVE_PATH):
			player_selection_panel.hide()
			_build_startup_save_prompt()
	if profile_startup:
		print("STARTUP_PROFILE data_ms=%.1f world_ms=%.1f ui_ms=%.1f total_ready_ms=%.1f" % [(data_loaded-startup_started)/1000.0,(world_built-data_loaded)/1000.0,(Time.get_ticks_usec()-world_built)/1000.0,(Time.get_ticks_usec()-startup_started)/1000.0])


static func _test_map_filename_from_args(arguments:PackedStringArray)->String:
	for argument in arguments:
		if argument.begins_with("--test-map="):return argument.trim_prefix("--test-map=").get_file()
	return ""


func _start_map_test(filename:String)->void:
	var target:Variant=map_data.get("_map_files",{}).get(filename,{})
	var location:=_location_for_map_file(filename)
	if not target is Dictionary or target.is_empty() or location.is_empty():
		push_error("Test Map could not load a playable map: %s"%filename)
		return
	if startup_panel!=null:startup_panel.queue_free();startup_panel=null
	if player_selection_panel != null: player_selection_panel.hide()
	player_gender = "Male"
	player_style = "Medium"
	player_palette_preset = PlayerPalette.DEFAULT_PRESET
	player_color_name = player_style
	_apply_player_appearance()
	cloud.clear()
	party.clear()
	var starter:Dictionary=battle.create_fakemon(battle.battle_data["fakemon"][0])
	starter["experience"]=int(pow(float(starter["level"]),3.0));starter["current_hp"]=int(starter["max_hp"]);starter["condition"]="";starter["condition_turns"]=0;party.append(starter);active_party_index=0
	var local_entry:Variant=target.get("entry",target.get("player_spawn",[0,0.65,0]))
	var origin:=_array_to_vector3(target.get("origin",[0,0,0]))
	var title:=String(target.get("map_metadata",{}).get("display_name",filename.get_basename().replace("_"," ").capitalize()))
	_set_route_location(location,origin+_array_to_vector3(local_entry),title,"Testing this map from the map editor.")
	adventure_started=true;in_battle=false;_update_follower_appearance();follower.show();_set_overworld_visuals_visible(true);map_ui.visible=true;_set_active_visual_region(location);_refresh_party_menu()


func _set_overworld_visuals_visible(is_visible: bool) -> void:
	world.visible = is_visible
	if sort_canvas != null:
		sort_canvas.visible = is_visible


func _physics_process(delta: float) -> void:
	patrols.update(delta)
	npc_script_movement.update(delta)
	if script_input_locked and not npc_script_movement.waiters.is_empty(): _update_placed_npcs(delta)
	if (script_input_locked and not npc_script_movement.player_can_yield()) or not adventure_started or in_battle or dialog_open or exhibit_transition or (exhibit_menu != null and exhibit_menu.visible) or swim_transitioning or player == null or (party_panel != null and party_panel.visible) or (settings_panel != null and settings_panel.visible) or (bag_panel != null and bag_panel.visible) or (cloud_dialog != null and cloud_dialog.visible) or (dex_panel != null and dex_panel.visible) or (move_learning_panel != null and move_learning_panel.visible) or (evolution_screen != null and evolution_screen.visible):
		# Script movement and facing still update world state while input is locked.
		# Keep the projected sprites synchronized during locks and dialogue.
		if adventure_started and player != null: _update_sort_canvas()
		return
	_set_active_visual_region(_current_location())
	var guided := npc_script_movement.controls(player)
	var input_vector := Vector2(player.velocity.x,player.velocity.z) / MOVE_SPEED if guided else Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if not swimming:
		_update_traversal_surface(player.position, input_vector)
	else:
		_update_platform_collision_mask()
	if not guided: player.velocity = _swim_constrained_velocity(Vector3(input_vector.x,0.0,input_vector.y)*MOVE_SPEED, delta) if swimming else _terrain_constrained_velocity(Vector3(input_vector.x,0.0,input_vector.y)*MOVE_SPEED,delta)
	var position_before_move := player.position
	if not guided: player.move_and_slide()
	if collision_diagnostics:
		for index in player.get_slide_collision_count():
			_report_collision_blocker(player.get_slide_collision(index).get_collider())
	if not swimming:
		_update_traversal_surface(player.position, input_vector)
	_update_swim_animation(input_vector, delta) if swimming else _update_player_animation(input_vector, delta)
	if player.velocity.length_squared() > 0.01:
		follower_target = player.position - player.velocity.normalized() * 1.25
		_update_follower_facing(player.velocity)
	if follower != null and follower.visible:
		follower.position = follower.position.move_toward(follower_target, MOVE_SPEED * 0.85 * delta)
	_update_family_children(delta)
	_update_placed_npcs(delta)
	if inside_medical_ward:
		_clamp_player_to_region(medical_origin+MapBounds.offset(map_data.medical_ward),map_data.medical_ward.interior_size,0.5)
	elif inside_house:
		_clamp_player_to_region(house_origin+MapBounds.offset(map_data.house),map_data.house.interior_size,0.5)
	elif inside_route:
		_clamp_player_to_region(route_origin+MapBounds.offset(map_data.route),map_data.route.size)
	elif inside_east_route:
		_clamp_player_to_region(east_route_origin+MapBounds.offset(map_data["east_route"]), map_data["east_route"]["size"])
	elif inside_west_route:
		_clamp_player_to_region(west_route_origin+MapBounds.offset(map_data["west_route"]), map_data["west_route"]["size"])
	elif inside_east_cave:
		_clamp_player_to_region(east_cave_origin+MapBounds.offset(map_data["east_cave"]), map_data["east_cave"]["size"])
	elif inside_city:
		_clamp_player_to_region(city_origin+MapBounds.offset(map_data["rainforest_city"]), map_data["rainforest_city"]["size"])
	elif inside_city_ward:
		_clamp_player_to_region(city_ward_origin+MapBounds.offset(map_data["rainforest_city"]["medical_ward"]), map_data["rainforest_city"]["medical_ward"]["interior_size"])
	elif inside_orchid_house:
		_clamp_player_to_region(orchid_house_origin+MapBounds.offset(map_data["rainforest_city"]["orchid_house"]), map_data["rainforest_city"]["orchid_house"]["interior_size"])
	elif inside_family_house:
		_clamp_player_to_region(family_house_origin+MapBounds.offset(map_data["rainforest_city"]["family_house"]), map_data["rainforest_city"]["family_house"]["interior_size"])
	elif not active_authored_map_id.is_empty():
		var authored_region: Dictionary = map_data.get("authored_maps", {}).get(active_authored_map_id, {})
		_clamp_player_to_region(_array_to_vector3(authored_region.get("origin", [0,0,0]))+MapBounds.offset(authored_region), authored_region.get("size", [20,20]),0.5 if _is_authored_indoor_map(authored_region) else 0.6)
	else:
		_clamp_player_to_region(MapBounds.offset(map_data),map_data.map_size)
	_process_poison_steps(position_before_move.distance_to(player.position))
	_process_water_encounter(position_before_move.distance_to(player.position))
	camera.position.x = player.position.x
	var is_inside := inside_medical_ward or inside_house or inside_east_cave or inside_city_ward or inside_orchid_house or inside_family_house
	camera.position.y = 7.0 if is_inside else 18.0
	camera.position.z = player.position.z + (7.0 if is_inside else 18.0)
	_update_sort_canvas()


func _terrain_constrained_velocity(desired:Vector3,delta:float)->Vector3:
	if desired.is_zero_approx() or active_traversal_layer>0:return desired
	var result:=Vector3.ZERO;var intermediate:=player.position
	var x_step:=Vector3(desired.x*delta,0,0)
	if is_zero_approx(desired.x) or not _terrain_foot_blocked(intermediate+x_step):
		result.x=desired.x;intermediate+=x_step
	var z_step:=Vector3(0,0,desired.z*delta)
	if is_zero_approx(desired.z) or not _terrain_foot_blocked(intermediate+z_step):result.z=desired.z
	return result


func _terrain_foot_blocked(candidate:Vector3)->bool:
	if not _platform_at_position(candidate).is_empty():return false
	if terrain_foot_shape==null:terrain_foot_shape=BoxShape3D.new();terrain_foot_shape.size=TERRAIN_FOOTPRINT_SIZE
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=terrain_foot_shape
	# Terrain obstacles describe the authored ground footprint. A recessed floor
	# lowers the actor, but the probe must still intersect these obstacles.
	var probe_position := candidate
	probe_position.y = maxf(candidate.y, PLAYER_GROUND_HEIGHT) + TERRAIN_FOOTPRINT_OFFSET_Y
	query.transform = Transform3D(Basis.IDENTITY, probe_position)
	query.collision_mask=TERRAIN_OBSTACLE_LAYER;query.collide_with_bodies=true;query.collide_with_areas=false;query.exclude=[player.get_rid()]
	var hits := world.get_world_3d().direct_space_state.intersect_shape(query,1)
	if not hits.is_empty() and collision_diagnostics: _report_collision_blocker(hits[0].collider)
	return not hits.is_empty()


func _swim_constrained_velocity(desired: Vector3, delta: float) -> Vector3:
	if desired.is_zero_approx():
		return desired
	var candidate := player.position + desired * delta
	if _terrain_at(candidate) == "water":
		return desired
	var exit_position := _terrain_cell_center(candidate)
	if _terrain_at(exit_position) != "water" and _terrain_at(exit_position) != "":
		var safe_exit := _safe_shore_exit(exit_position, desired.normalized())
		if safe_exit != Vector3.ZERO:
			_finish_swimming(safe_exit)
	return Vector3.ZERO


func _safe_shore_exit(first_land_cell: Vector3, outward: Vector3) -> Vector3:
	# Water-transition aprons intentionally extend onto the shoreline. Center the
	# player on the first genuinely clear land cell before restoring their water
	# collision check, so every facing (especially north) can walk away freely.
	for distance in 3:
		var candidate := _terrain_cell_center(first_land_cell + outward * float(distance))
		if _terrain_at(candidate) != "" and _terrain_at(candidate) != "water" and not _surf_crosses_fence(candidate) and not _terrain_foot_blocked(candidate):
			return candidate
	return Vector3.ZERO


func _surf_crosses_fence(destination: Vector3) -> bool:
	# Surf transitions reposition the player directly, so check the crossing
	# against the same fence bodies that block ordinary movement.
	var from := player.global_position
	var to := from + Vector3(destination.x - player.position.x, 0.0, destination.z - player.position.z)
	if from.is_equal_approx(to):
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to, FENCE_COLLISION_LAYER)
	query.hit_from_inside = true
	return not world.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		collision_diagnostics = not collision_diagnostics;last_collision_diagnostic = ""
		hint_label.text = "Collision diagnostics %s. Walk into a blocker to show its name and position." % ("on" if collision_diagnostics else "off")
		get_viewport().set_input_as_handled();return
	if script_runner.running or in_battle or dialog_open or exhibit_transition or not event is InputEventMouseButton:
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	# A failed map load leaves no world camera. Do not turn that primary loading
	# error into a follow-up null-camera input error.
	if camera == null or not is_instance_valid(camera) or world == null:
		return
	if _try_script_object_click(event.position) or _try_display_text_click(event.position) or _try_platform_sign_click(event.position):
		get_viewport().set_input_as_handled()
		return
	var from := camera.project_ray_origin(event.position)
	var to := from + camera.project_ray_normal(event.position) * 100.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	if hit["collider"] == opponent:
		_face_npc_toward_player(opponent)
		_start_battle()
	elif hit["collider"] == house_npc:
		_face_npc_toward_player(house_npc)
		_start_burn_dialogue()
	elif npc_dialogues.has(hit["collider"].get_instance_id()):
		_interact_placed_npc(hit["collider"] as Area3D)


func build_rainforest() -> void:
	var environment := WorldEnvironment.new()
	world_environment = Environment.new()
	world_environment.background_mode = Environment.BG_COLOR
	world_environment.background_color = OUTDOOR_BACKGROUND
	world_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_environment.ambient_light_color = Color.WHITE
	world_environment.ambient_light_energy = 1.0
	environment.environment = world_environment
	world.add_child(environment)

	var ground := MeshInstance3D.new()
	var ground_mesh := BoxMesh.new()
	var configured_size: Array = map_data["map_size"]
	ground_mesh.size = Vector3(float(configured_size[0]), 0.2, float(configured_size[1]))
	ground.mesh = ground_mesh
	ground.position = MapBounds.offset(map_data)+Vector3(0,-0.1,0)
	ground.material_override = _textured_material(TEX_GRASS, Color("#39734b"), Vector3(float(configured_size[0]), float(configured_size[1]), 1.0))
	world.add_child(ground)

	spawn_position = _array_to_vector3(map_data["player_spawn"])
	respawn_position = spawn_position
	player = CharacterBody3D.new()
	player.collision_layer = 1 | ACTOR_COLLISION_LAYER
	player.name = "Player"
	player.position = spawn_position
	player_atlas = PlayerPalette.create_texture(PlayerPalette.DEFAULT_PRESET)
	player_sprite = _billboard_sprite(PlayerSpriteFrames.frames("Male", "idle_down", player_atlas)[0], PLAYER_VISUAL_HEIGHT, "PlayerSprite")
	player_sprite.offset = Vector2(0.0, float(player_sprite.texture.get_height()) * 0.5)
	player.add_child(player_sprite)
	player.add_child(_box_shape(Vector3(0.8, 1.2, 0.8)))
	# Structures use the full body; terrain is evaluated by the foot-level query.
	player.collision_mask = 1 | PLATFORM_WALL_LAYER
	world.add_child(player)
	follower = Node3D.new()
	follower.name = "LeadingFakemonFollowerPlaceholder"
	follower.position = spawn_position + Vector3(0, 0, 1.25)
	follower_target = follower.position
	follower_sprite = _square_sprite(Color("#c4b9a8"), "FOLLOWER", Vector2(0.75, 0.9))
	follower.add_child(follower_sprite)
	follower.hide()
	world.add_child(follower)

	var opponent_data: Dictionary = map_data["opponent"]
	opponent_fakemon_index = int(opponent_data["fakemon_index"])
	opponent_fakemon_indices.clear()
	for enemy_index: Variant in opponent_data.get("fakemon_indices", [opponent_fakemon_index]):
		opponent_fakemon_indices.append(int(enemy_index))
	opponent = Area3D.new()
	opponent.name = "RainforestTrainerPlaceholder"
	opponent.position = _array_to_vector3(opponent_data["position"])
	var opponent_texture:=NpcSpriteLibrary.texture_for(String(opponent_data.get("sprite","man")))
	var opponent_visual:=_billboard_sprite(opponent_texture,NPC_ADULT_VISUAL_HEIGHT,"BATTLESprite") if opponent_texture!=null else _square_sprite(Color("#df6d5f"),"BATTLE",Vector2(1.0,1.25))
	if opponent_texture!=null:opponent_visual.offset=Vector2(0.0,float(opponent_texture.get_height())*0.5)
	opponent.add_child(opponent_visual)
	opponent.set_meta("sprite_id",String(opponent_data.get("sprite","man")))
	opponent.set_meta("facing","down")
	opponent.set_meta("visual_height",NPC_ADULT_VISUAL_HEIGHT)
	opponent.add_child(_box_shape(Vector3(1.0, 1.3, 1.0)))
	opponent.add_child(_npc_foot_body())
	world.add_child(opponent)

	# The clearing references the same complete ward-instance schema as Mossvale.
	# The legacy clearing `building` record remains compatible with old maps.
	var building_data: Dictionary = map_data.get(String(map_data.get("medical_ward_instance", "")), map_data["building"])
	var building_size := _array_to_vector3(building_data["size"])
	var building_position := _array_to_vector3(building_data["position"])
	var medical_art := _add_world_billboard("MedicalWardExteriorArt", building_position, TEX_MEDICAL_WARD, 5.4, 0.0)
	_register_sortable_object(medical_art, "MedicalWardExteriorSortRoot", building_position, medical_art.global_position, float(medical_art.texture.get_height()) * medical_art.pixel_size, float(building_data.get("sort_offset_y", 0.0)))
	_add_building_collision("BuildingCollision",building_position,building_size,"medical_ward")
	_build_building_door_warp(medical_art, "MedicalWardExteriorDoor", _array_to_vector3(building_data["door"]), _on_exterior_door_entered, Vector3(1.5, 0.3, 1.0))
	_build_medical_ward(map_data["medical_ward"])
	_build_house(map_data["house"])
	_build_route(map_data["route"])
	_build_side_route(map_data["east_route"], "East", true)
	_build_side_route(map_data["west_route"], "West", false)
	_build_east_cave(map_data["east_cave"])
	_build_rainforest_city(map_data["rainforest_city"])
	_build_authored_maps()
	_build_editor_authored_warps()
	_build_trainers(map_data.get("trainers", []), Vector3.ZERO, "Clearing")

	# Clearing terrain uses the same data-driven asset fields as every outdoor route.
	_build_outdoor_terrain_assets(map_data, Vector3.ZERO, "Clearing")
	_build_forest_warp("ClearingNorthExit", _array_to_vector3(map_data["north_warp"]), _on_route_entrance_entered, "generic")

	for tree_data: Array in map_data["trees"]:
		var tree_anchor := Vector3(float(tree_data[0]), float(tree_data[1]), float(tree_data[2]))
		_add_tree(tree_anchor, int(tree_data[3]), "Clearing")

	camera = Camera3D.new()
	camera.name = "RainforestCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = OUTDOOR_CAMERA_SIZE
	camera.position = Vector3(0, 18, 18)
	camera.rotation_degrees = Vector3(-45, 0, 0)
	camera.current = true
	world.add_child(camera)
	_build_sort_canvas()
	day_night_controller = DayNightControllerScript.new()
	day_night_controller.name = "DayNightController"
	sort_canvas.add_child(day_night_controller)
	day_night_controller.setup(get_node("/root/WorldClock"), world_environment)
	_configure_visual_regions()
	_set_active_visual_region("clearing")

	map_ui = CanvasLayer.new()
	add_child(map_ui)
	map_title = Label.new()
	map_title.text = "RAINFOREST CLEARING - PLACEHOLDER MAP"
	map_title.position = Vector2(24, 18)
	map_title.add_theme_font_size_override("font_size", 22)
	map_ui.add_child(map_title)
	hint_label = Label.new()
	hint_label.text = "Move: WASD / Arrow Keys (including left/right)    Grass: 20% encounters    Water: 5% encounters"
	hint_label.position = Vector2(24, 50)
	hint_label.add_theme_color_override("font_color", Color("#f1ffe9"))
	map_ui.add_child(hint_label)
	_build_party_menu()
	_build_dialog_ui()


func _start_battle() -> void:
	active_battle_is_wild = false
	_open_battle(opponent_fakemon_index, opponent_fakemon_indices)


func _open_battle(enemy_index: int, enemy_party_indices: Array = [], enemy_team: Array[Dictionary] = []) -> void:
	if party.is_empty():
		hint_label.text = "Choose your starter at the Institute before battling."
		return
	if int(party[active_party_index].get("current_hp", party[active_party_index]["max_hp"])) <= 0:
		var conscious_index := -1
		for index in party.size():
			if int(party[index].get("current_hp", party[index]["max_hp"])) > 0:
				conscious_index = index
				break
		if conscious_index == -1:
			hint_label.text = "Every party member has fainted. Visit the cyan building entrance to heal."
			return
		active_party_index = conscious_index
		_update_follower_appearance()
		_refresh_party_menu()
	in_battle = true
	_set_overworld_visuals_visible(false)
	map_ui.visible = false
	battle.set_battle_background(_map_type_for_location(_current_location()), active_battle_is_wild and swimming)
	if active_battle_is_wild:
		if not enemy_team.is_empty(): battle.begin_battle_with_enemy_party(party,active_party_index,enemy_team,true)
		else: battle.begin_battle_with_party(party, active_party_index, enemy_index, true)
	elif not enemy_team.is_empty():
		battle.begin_battle_with_enemy_party(party, active_party_index, enemy_team, false)
	else:
		var trainer_party := enemy_party_indices if not enemy_party_indices.is_empty() else [enemy_index]
		battle.begin_battle_with_opponent_party(party, active_party_index, trainer_party, false)


func _begin_unpartnered_adventure() -> void:
	script_runner.stop(); npc_script_movement.clear(); script_host.hidden_objects.clear(); script_host.reset_sprites(); game_flags.restore({})
	cloud.clear()
	party.clear(); active_party_index = 0
	exhibits.restore([], {})
	adventure_started = true; in_battle = false
	battle.hide(); follower.hide()
	_set_overworld_visuals_visible(true); map_ui.visible = true
	hint_label.text = "Visit the Institute to choose your starter. Move with WASD / Arrow Keys."
	_refresh_party_menu(); _set_active_visual_region(_current_location()); _run_map_headers(_current_location()); _auto_save()


func _on_fakemon_selected(index: int) -> void:
	game_flags.restore({}); script_runner.stop(); npc_script_movement.clear(); script_host.hidden_objects.clear(); script_host.reset_sprites()
	var starter: Dictionary = battle.create_fakemon(battle.battle_data["fakemon"][index])
	starter["experience"] = int(pow(float(starter["level"]), 3.0))
	starter["current_hp"] = int(starter["max_hp"])
	starter["condition"] = ""
	starter["condition_turns"] = 0
	party.append(starter)
	exhibits.record(starter)
	game_flags.set_flag("Starter",true)
	active_party_index = 0
	adventure_started = true
	_update_follower_appearance()
	follower.show()
	in_battle = false
	_set_overworld_visuals_visible(true)
	map_ui.visible = true
	hint_label.text = "Fakemon chosen! Move with WASD / Arrow Keys. Grass: 20% encounters. Water: 5% encounters."
	_refresh_party_menu()
	_set_active_visual_region(_current_location())
	_run_map_headers(_current_location())
	_auto_save()


func _on_grass_tile_entered(body: Node3D, tile_id: String, encounter_chance: float, encounter_species: Array) -> void:
	if body != player or in_battle:
		return
	if tile_id == last_grass_tile:
		return
	last_grass_tile = tile_id
	if randf() < encounter_chance:
		var encounter := _random_tall_grass_encounter(encounter_species)
		if encounter.is_empty():
			hint_label.text = "This tall grass has no encounter species assigned yet."
			return
		active_battle_is_wild = true
		var enemies := _build_trainer_team([encounter])
		if not enemies.is_empty(): _open_battle(0, [], enemies)
	else:
		hint_label.text = "No encounter on this grass tile. Each newly stepped-on tile rolls 20%."


func _random_tall_grass_species_index(encounter_species: Array) -> int:
	var encounter := _random_tall_grass_encounter(encounter_species)
	if encounter.is_empty(): return -1
	var species_name:=String(encounter.get("fakemon",""))
	for index in battle.battle_data["fakemon"].size():
		if String(battle.battle_data["fakemon"][index].get("name",""))==species_name:return index
	return -1

func _random_tall_grass_encounter(encounter_species:Array)->Dictionary:
	var eligible:Array[Dictionary]=[]
	for value:Variant in encounter_species:
		var species_name:=String(value.get("fakemon","")) if value is Dictionary else String(value)
		for index in battle.battle_data["fakemon"].size():
			if String(battle.battle_data["fakemon"][index].get("name", "")) == String(species_name):
				eligible.append({"fakemon":species_name,"level":clampi(int(value.get("level",battle.battle_data["fakemon"][index].get("level",5))) if value is Dictionary else int(battle.battle_data["fakemon"][index].get("level",5)),1,100)})
				break
	return {} if eligible.is_empty() else eligible.pick_random()


func _process_water_encounter(distance_traveled: float) -> void:
	if not swimming or distance_traveled <= 0.0:
		last_water_tile = ""
		return
	var context := _terrain_context()
	if context.is_empty() or _terrain_at(player.position) != "water":
		last_water_tile = ""
		return
	var origin: Vector3 = context["origin"]
	var cell := Vector2i(roundi(player.position.x - origin.x), roundi(player.position.z - origin.z))
	var tile_id := "%s:%d,%d" % [_current_location(), cell.x, cell.y]
	if tile_id == last_water_tile:
		return
	last_water_tile = tile_id
	var map_region: Dictionary = context["data"]
	var encounter_chance := float(map_region.get("water_encounter_chance", 0.0))
	if randf() >= encounter_chance:
		hint_label.text = "No encounter in this water tile. Each newly entered tile rolls %d%%." % roundi(encounter_chance * 100.0)
		return
	var encounter := _random_tall_grass_encounter(map_region.get("water_species", []))
	if encounter.is_empty():
		hint_label.text = "This water has no encounter species assigned yet."
		return
	active_battle_is_wild = true
	var enemies := _build_trainer_team([encounter])
	if not enemies.is_empty():
		_open_battle(0, [], enemies)


func _on_exterior_door_entered(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready or (script_runner.running and npc_script_movement.controls(player)):
		return
	_warp_to_medical_ward()


func _on_interior_door_entered(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	inside_medical_ward = false
	player.position = _array_to_vector3(map_data["medical_ward"].get("exterior_return",[-7.0,0.65,-1.1]))
	_place_follower_behind_player()
	camera.size = OUTDOOR_CAMERA_SIZE
	camera.position = Vector3(player.position.x, 18.0, player.position.z + 18.0)
	world_environment.background_color = OUTDOOR_BACKGROUND
	map_title.text = "RAINFOREST CLEARING - PLACEHOLDER MAP"
	hint_label.text = "Exited the medical ward."
	_start_door_cooldown()
	_auto_save()


func _on_house_exterior_door_entered(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	var house_data: Dictionary = map_data["house"]
	house_origin = _array_to_vector3(house_data["origin"])
	inside_medical_ward = false
	inside_house = true
	player.position = house_origin + _array_to_vector3(house_data["entry"])
	_place_follower_behind_player()
	camera.size = 8.0
	camera.position = Vector3(player.position.x, 7.0, player.position.z + 7.0)
	world_environment.background_color = Color("#55483d")
	map_title.text = "RAINFOREST HOUSE - PLACEHOLDER INTERIOR"
	hint_label.text = "Click the orange resident to talk. Walk onto the door tile to leave."
	_start_door_cooldown()
	_auto_save()


func _on_house_interior_door_entered(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	inside_house = false
	player.position = _array_to_vector3(map_data["house"].get("exterior_return",[8.0,0.65,-3.25]))
	_place_follower_behind_player()
	camera.size = OUTDOOR_CAMERA_SIZE
	camera.position = Vector3(player.position.x, 18.0, player.position.z + 18.0)
	world_environment.background_color = OUTDOOR_BACKGROUND
	map_title.text = "RAINFOREST CLEARING - PLACEHOLDER MAP"
	hint_label.text = "Exited the rainforest house."
	_start_door_cooldown()
	_auto_save()


func _on_route_entrance_entered(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	var route_data: Dictionary = map_data["route"]
	inside_medical_ward = false
	inside_house = false
	inside_route = true
	player.position = route_origin + _array_to_vector3(MapDataLoader.arrival_position(map_data, "north_warp", route_data, "entry"))
	_place_follower_behind_player()
	camera.size = OUTDOOR_CAMERA_SIZE
	world_environment.background_color = OUTDOOR_BACKGROUND
	map_title.text = "CANOPY ROUTE - PLACEHOLDER MAP"
	hint_label.text = "Dense forest route: water is uncrossable. The trainer waits at the far end."
	_start_door_cooldown()
	_auto_save()


func _on_route_exit_entered(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	inside_route = false
	player.position = _array_to_vector3(MapDataLoader.arrival_position(map_data["route"], "exit_warp", map_data, "north_return"))
	_place_follower_behind_player()
	camera.size = OUTDOOR_CAMERA_SIZE
	world_environment.background_color = OUTDOOR_BACKGROUND
	map_title.text = "RAINFOREST CLEARING - PLACEHOLDER MAP"
	hint_label.text = "Returned through the dense forest passage."
	_start_door_cooldown()
	_auto_save()


func _on_east_route_entered(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	_set_route_location("east_route", east_route_origin + _array_to_vector3(MapDataLoader.arrival_position(map_data["route"], "east_warp", map_data["east_route"], "entry")), "EASTERN RAINFOREST ROUTE", "The cave entrance lies deeper along the eastern route.")


func _on_east_route_exited(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	_set_route_location("route", route_origin + _array_to_vector3(MapDataLoader.arrival_position(map_data["east_route"], "return_warp", map_data["route"], "east_return")), "CANOPY ROUTE - PLACEHOLDER MAP", "Returned from the eastern rainforest route.")


func _on_west_route_entered(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	_set_route_location("west_route", west_route_origin + _array_to_vector3(MapDataLoader.arrival_position(map_data["route"], "west_warp", map_data["west_route"], "entry")), "WESTERN RAINFOREST ROUTE", "A humid rainforest path stretches westward.")


func _on_west_route_exited(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	_set_route_location("route", route_origin + _array_to_vector3(MapDataLoader.arrival_position(map_data["west_route"], "return_warp", map_data["route"], "west_return")), "CANOPY ROUTE - PLACEHOLDER MAP", "Returned from the western rainforest route.")


func _on_east_cave_entered(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	_set_route_location("east_cave", east_cave_origin + _array_to_vector3(MapDataLoader.arrival_position(map_data["east_route"], "cave_warp", map_data["east_cave"], "entry")), "VINESTONE CAVE - PLACEHOLDER MAP", "A small rocky cave dotted with blue flowers and vines.")
	camera.size = 12.0


func _on_east_cave_exited(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	_set_route_location("east_route", east_route_origin + _array_to_vector3(MapDataLoader.arrival_position(map_data["east_cave"], "exit_warp", map_data["east_route"], "cave_return")), "EASTERN RAINFOREST ROUTE", "Exited Vinestone Cave.")


func _on_city_entered(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	_set_route_location("city", city_origin + _array_to_vector3(MapDataLoader.arrival_position(map_data["route"], "north_warp", map_data["rainforest_city"], "entry")), "MOSSVALE RAINFOREST CITY", "Medical care and two family homes line the rainforest plaza.")


func _on_city_exited(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	_set_route_location("route", route_origin + _array_to_vector3(MapDataLoader.arrival_position(map_data["rainforest_city"], "return_warp", map_data["route"], "north_return")), "CANOPY ROUTE - PLACEHOLDER MAP", "Returned from Mossvale City.")


func _on_city_ward_entered(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	var ward: Dictionary = map_data["rainforest_city"]["medical_ward"]
	_set_respawn_checkpoint("city", city_origin + _array_to_vector3(ward["exterior_return"]), "MOSSVALE RAINFOREST CITY")
	_set_route_location("city_ward", city_ward_origin + _array_to_vector3(ward["entry"]), "MOSSVALE MEDICAL WARD", "Your party was fully restored. Walk onto the door tile to leave.")
	camera.size = 9.0


func _on_city_ward_exited(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	_return_to_city(map_data["rainforest_city"]["medical_ward"]["exterior_return"], "Exited the Mossvale medical ward.")


func _on_orchid_house_entered(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	var house: Dictionary = map_data["rainforest_city"]["orchid_house"]
	_set_route_location("orchid_house", orchid_house_origin + _array_to_vector3(house["entry"]), "GROUND ORCHID HOUSE", "Click the purple resident to learn about ground orchids.")
	camera.size = 9.0


func _on_orchid_house_exited(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	_return_to_city(map_data["rainforest_city"]["orchid_house"]["exterior_return"], "Exited the ground orchid home.")


func _on_family_house_entered(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	var house: Dictionary = map_data["rainforest_city"]["family_house"]
	_set_route_location("family_house", family_house_origin + _array_to_vector3(house["entry"]), "MOSSVALE FAMILY HOME", "Click the adults to talk. The three children wander around the house.")
	camera.size = 11.0


func _on_family_house_exited(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	_return_to_city(map_data["rainforest_city"]["family_house"]["exterior_return"], "Exited the family home.")


func _return_to_city(exterior_return: Array, hint: String) -> void:
	_set_route_location("city", city_origin + _array_to_vector3(exterior_return), "MOSSVALE RAINFOREST CITY", hint)


func _set_route_location(location: String, destination: Vector3, title: String, hint: String) -> void:
	if location != _current_location(): npc_script_movement.clear()
	if script_runner.running:
		script_runner.stop(); dialog_open = false; dialogue_complete_action = Callable(); dialog_panel.hide()
	inside_medical_ward = location=="medical_ward"
	inside_house = location=="house"
	inside_route = location == "route"
	inside_east_route = location == "east_route"
	inside_west_route = location == "west_route"
	inside_east_cave = location == "east_cave"
	inside_city = location == "city"
	inside_city_ward = location == "city_ward"
	inside_orchid_house = location == "orchid_house"
	inside_family_house = location == "family_house"
	active_authored_map_id = location.trim_prefix("authored:") if location.begins_with("authored:") else ""
	player.position = destination
	_place_follower_behind_player()
	camera.size = 9.0 if inside_medical_ward else (8.0 if inside_house else OUTDOOR_CAMERA_SIZE)
	var indoors := inside_medical_ward or inside_house or inside_east_cave or inside_city_ward or inside_orchid_house or inside_family_house or _is_authored_indoor_map(map_data.get("authored_maps",{}).get(active_authored_map_id,{}))
	world_environment.background_color = Color("#3d453d") if indoors else OUTDOOR_BACKGROUND
	map_title.text = title
	hint_label.text = hint
	_set_active_visual_region(location)
	_run_map_headers(location)
	_start_door_cooldown()
	_auto_save()


func _set_respawn_checkpoint(location: String, position: Vector3, title: String) -> void:
	respawn_location = location
	respawn_position = position
	respawn_title = title


func _restore_respawn_checkpoint() -> void:
	_set_route_location(respawn_location, respawn_position, respawn_title, "Defeat! Returned to the most recently visited medical ward.")
	player.velocity = Vector3.ZERO


func _warp_to_medical_ward() -> void:
	var ward_data: Dictionary = map_data["medical_ward"]
	_set_respawn_checkpoint("rainforest", _array_to_vector3(ward_data.get("exterior_return", [-7.0, 0.65, -1.1])), "RAINFOREST CLEARING - PLACEHOLDER MAP")
	medical_origin = _array_to_vector3(ward_data["origin"])
	inside_medical_ward = true
	inside_house = false
	player.position = medical_origin + _array_to_vector3(ward_data["entry"])
	_place_follower_behind_player()
	camera.size = 9.0
	camera.position = Vector3(player.position.x, 7.0, player.position.z + 7.0)
	world_environment.background_color = Color("#354b5e")
	map_title.text = "MEDICAL WARD - PLACEHOLDER INTERIOR"
	hint_label.text = "Medical ward: speak to the attendant at the counter for care."
	_start_door_cooldown()
	_auto_save()


func _start_door_cooldown() -> void:
	door_warp_ready = false
	await get_tree().create_timer(0.5).timeout
	door_warp_ready = true


func _on_battle_finished(player_won: bool, escaped: bool, captured_mon: Dictionary, experience_earned: int, experience_recipients: Array[int], _final_active_index: int, final_party_hp: Array[int], final_party_conditions: Array[Dictionary]) -> void:
	var sent_to_cloud := false
	if experience_earned > 0 and not experience_recipients.is_empty():
		var valid_recipients: Array[int] = []
		for recipient in experience_recipients:
			if recipient >= 0 and recipient < party.size() and not valid_recipients.has(recipient):
				valid_recipients.append(recipient)
		if not valid_recipients.is_empty():
			var base_share := experience_earned / valid_recipients.size()
			var remainder := experience_earned % valid_recipients.size()
			for index in valid_recipients.size():
				_award_experience(party[valid_recipients[index]], base_share + (1 if index < remainder else 0))
	if player_won or escaped:
		for index in mini(party.size(), final_party_hp.size()):
			party[index]["current_hp"] = final_party_hp[index]
	for index in mini(party.size(), final_party_conditions.size()):
		party[index]["condition"] = final_party_conditions[index]["condition"]
		party[index]["condition_turns"] = final_party_conditions[index]["condition_turns"]
	if not captured_mon.is_empty():
		captured_mon["condition"] = String(captured_mon.get("condition", ""))
		captured_mon["condition_turns"] = int(captured_mon.get("condition_turns", 0))
		sent_to_cloud = fakemon_storage.add_capture(captured_mon)
		exhibits.record(captured_mon)
	in_battle = false
	if not player_won and not escaped:
		_restore_respawn_checkpoint()
	_set_overworld_visuals_visible(true)
	map_ui.visible = true
	var battle_kind := "wild encounter" if active_battle_is_wild else "trainer battle"
	if escaped:
		hint_label.text = "Escaped from the wild encounter."
	else:
		hint_label.text = ("Victory in the %s! You remain where the battle began." % battle_kind if player_won else "Defeat! Returned to the most recently visited medical ward.")
	if not captured_mon.is_empty():
		hint_label.text += " Captured %s." % captured_mon["name"]
		if sent_to_cloud:
			hint_label.text += " Party full. Sent to the Cloud."
	_refresh_party_menu()
	_auto_save()
	if not pending_evolutions.is_empty():
		_show_next_evolution.call_deferred()
	elif not pending_move_learning.is_empty():
		_show_next_move_learning_choice.call_deferred()


func _process_poison_steps(distance_traveled: float) -> void:
	poison_step_distance += distance_traveled
	var took_damage := false
	while poison_step_distance >= 1.0:
		poison_step_distance -= 1.0
		for mon: Dictionary in party:
			var condition_data: Dictionary = battle.battle_data["conditions"].get(String(mon.get("condition", "")), {})
			if condition_data.has("overworld_damage_per_step") and int(mon.get("current_hp", mon["max_hp"])) > 0:
				var poison_damage := int(condition_data["overworld_damage_per_step"])
				mon["current_hp"] = maxi(0, int(mon.get("current_hp", mon["max_hp"])) - poison_damage)
				took_damage = true
	if took_damage:
		hint_label.text = "A condition damaged affected party members while walking. Visit the medical ward to cure them."
		_refresh_party_menu()


func _award_experience(mon: Dictionary, amount: int) -> void:
	mon["experience"] = int(mon.get("experience", int(pow(float(mon["level"]), 3.0)))) + amount
	while int(mon["experience"]) >= int(pow(float(int(mon["level"]) + 1), 3.0)):
		var old_level := int(mon["level"])
		mon["level"] = int(mon["level"]) + 1
		mon["max_hp"] = int(mon["max_hp"]) + 3
		mon["attack"] = int(mon["attack"]) + 2
		mon["defense"] = int(mon["defense"]) + 2
		mon["special_attack"] = int(mon["special_attack"]) + 2
		mon["special_defense"] = int(mon["special_defense"]) + 2
		mon["speed"] = int(mon["speed"]) + 2
		_process_newly_available_moves(mon, old_level, int(mon["level"]))
		_queue_evolution_if_eligible(mon)


func _find_species(name: String) -> Dictionary:
	for species: Dictionary in battle.battle_data.get("fakemon", []):
		if String(species.get("name", "")) == name:
			return species
	return {}


func _eligible_evolution(mon: Dictionary) -> Dictionary:
	var current_name := String(mon.get("name", ""))
	var current_level := int(mon.get("level", 0))
	for species: Dictionary in battle.battle_data.get("fakemon", []):
		if String(species.get("evolves_from", "")) == current_name and current_level >= int(species.get("evolution_level", 0)):
			return species
	return {}


func _queue_evolution_if_eligible(mon: Dictionary) -> void:
	var target := _eligible_evolution(mon)
	if target.is_empty():
		return
	for request: Dictionary in pending_evolutions:
		if request.get("mon") == mon:
			return
	pending_evolutions.append({"mon": mon, "target": target})


func _build_evolution_screen() -> void:
	evolution_layer = CanvasLayer.new()
	evolution_layer.layer = 10
	add_child(evolution_layer)
	evolution_screen = Control.new()
	evolution_screen.name = "EvolutionScreen"
	evolution_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	evolution_layer.add_child(evolution_screen)
	var background := ColorRect.new()
	background.color = Color.BLACK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	evolution_screen.add_child(background)
	evolution_title = Label.new()
	evolution_title.position = Vector2(120, 42)
	evolution_title.size = Vector2(720, 72)
	evolution_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	evolution_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	evolution_title.add_theme_font_size_override("font_size", 28)
	evolution_title.add_theme_color_override("font_color", Color.WHITE)
	evolution_screen.add_child(evolution_title)
	evolution_old_art = _create_evolution_art()
	evolution_screen.add_child(evolution_old_art)
	evolution_new_art = _create_evolution_art()
	evolution_screen.add_child(evolution_new_art)
	evolution_cancel_button = Button.new()
	evolution_cancel_button.text = "Cancel Evolution"
	evolution_cancel_button.position = Vector2(380, 455)
	evolution_cancel_button.size = Vector2(200, 48)
	evolution_cancel_button.pressed.connect(_cancel_current_evolution)
	evolution_screen.add_child(evolution_cancel_button)
	evolution_screen.hide()


func _create_evolution_art() -> TextureRect:
	var art := TextureRect.new()
	art.position = Vector2(330, 140)
	art.size = Vector2(300, 300)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return art


func _show_next_evolution() -> void:
	if evolution_in_progress or pending_evolutions.is_empty():
		return
	evolution_in_progress = true
	while not pending_evolutions.is_empty():
		var request: Dictionary = pending_evolutions.pop_front()
		var mon: Dictionary = request["mon"]
		var target: Dictionary = request["target"]
		if _eligible_evolution(mon).is_empty():
			continue
		await _run_evolution(mon, target)
	evolution_in_progress = false
	_refresh_party_menu()
	_update_follower_appearance()
	_auto_save()
	if not pending_move_learning.is_empty():
		_show_next_move_learning_choice()


func _run_evolution(mon: Dictionary, target: Dictionary) -> void:
	evolution_cancelled = false
	evolution_title.text = "%s is evolving into %s!" % [mon["name"], target["name"]]
	evolution_old_art.texture = _battle_art_texture(mon, "Player")
	evolution_new_art.texture = _battle_art_texture(target, "Player")
	evolution_old_art.modulate.a = 1.0
	evolution_new_art.modulate.a = 0.0
	evolution_screen.show()
	var tween := create_tween()
	tween.tween_property(evolution_old_art, "modulate:a", 0.0, 1.0)
	tween.parallel().tween_property(evolution_new_art, "modulate:a", 1.0, 1.0)
	await tween.finished
	await get_tree().create_timer(0.65).timeout
	if evolution_cancelled:
		return
	_apply_evolution(mon, target)
	evolution_title.text = "Congratulations! %s evolved into %s!" % [String(mon["evolves_from"]), mon["name"]]
	await get_tree().create_timer(0.9).timeout
	evolution_screen.hide()


func _battle_art_texture(mon: Dictionary, role: String) -> Texture2D:
	var path := "res://assets/fakemon/battle/%s_%s.png" % [String(mon.get("art_id", "")), role]
	if ResourceLoader.exists(path):
		return load(path)
	return battle._color_texture(Color(mon.get("color", "777777")))


func _cancel_current_evolution() -> void:
	evolution_cancelled = true
	evolution_screen.hide()
	hint_label.text = "Evolution cancelled. It will be offered again after the next level gain."


func _apply_evolution(mon: Dictionary, target: Dictionary) -> void:
	var previous_name := String(mon["name"])
	var current_hp := int(mon.get("current_hp", mon["max_hp"]))
	var previous_max_hp := int(mon["max_hp"])
	var hp_ratio := float(current_hp) / float(maxi(1, previous_max_hp))
	var level := int(mon["level"])
	var evolved := target.duplicate(true)
	var target_level := int(evolved.get("level", 5))
	var levels_gained := maxi(0, level - target_level)
	evolved["level"] = level
	evolved["experience"] = int(mon.get("experience", int(pow(float(level), 3.0))))
	evolved["gender"] = String(mon.get("gender", "Genderless"))
	evolved["moves"] = mon.get("moves", []).duplicate(true)
	evolved["condition"] = String(mon.get("condition", ""))
	evolved["condition_turns"] = int(mon.get("condition_turns", 0))
	for stat_name: String in ["max_hp", "attack", "defense", "special_attack", "special_defense", "speed"]:
		var increase := 3 if stat_name == "max_hp" else 2
		evolved[stat_name] = int(evolved[stat_name]) + levels_gained * increase
	evolved["current_hp"] = clampi(roundi(float(evolved["max_hp"]) * hp_ratio), 0, int(evolved["max_hp"]))
	mon.clear()
	exhibits.record(mon)
	mon.merge(evolved, true)
	exhibits.record(mon)
	hint_label.text = "%s evolved into %s!" % [previous_name, mon["name"]]


func _process_newly_available_moves(mon: Dictionary, old_level: int, new_level: int) -> void:
	for learn_entry: Dictionary in _species_learnset(mon):
		var required_level := int(learn_entry.get("level", 0))
		var move_id := String(learn_entry.get("move", ""))
		if required_level <= old_level or required_level > new_level or move_id.is_empty() or mon["moves"].has(move_id):
			continue
		if mon["moves"].size() < 6:
			mon["moves"].append(move_id)
			hint_label.text = "%s learned %s!" % [mon["name"], battle.battle_data["moves"][move_id]["name"]]
		else:
			pending_move_learning.append({"mon": mon, "move_id": move_id})


func _species_learnset(mon: Dictionary) -> Array:
	if mon.has("learnset"):
		return mon["learnset"]
	for species: Dictionary in battle.battle_data["fakemon"]:
		if String(species["name"]) == String(mon["name"]):
			mon["learnset"] = species.get("learnset", []).duplicate(true)
			return mon["learnset"]
	return []


func _show_next_move_learning_choice() -> void:
	if pending_move_learning.is_empty():
		if move_learning_panel != null:
			move_learning_panel.hide()
		return
	if move_learning_panel == null:
		_build_move_learning_panel()
	for child in move_learning_list.get_children():
		child.queue_free()
	var request: Dictionary = pending_move_learning[0]
	var mon: Dictionary = request["mon"]
	var move_id := String(request["move_id"])
	var title := Label.new()
	title.text = "%s wants to learn %s, but already knows six moves.\nChoose a move to replace, or decline." % [mon["name"], battle.battle_data["moves"][move_id]["name"]]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	move_learning_list.add_child(title)
	for index in mon["moves"].size():
		var known_move_id := String(mon["moves"][index])
		var replace_button := Button.new()
		replace_button.text = "Replace %s" % battle.battle_data["moves"][known_move_id]["name"]
		replace_button.pressed.connect(_replace_move_for_pending.bind(index))
		move_learning_list.add_child(replace_button)
	var decline_button := Button.new()
	decline_button.text = "Decline %s" % battle.battle_data["moves"][move_id]["name"]
	decline_button.pressed.connect(_decline_pending_move)
	move_learning_list.add_child(decline_button)
	move_learning_panel.show()


func _build_move_learning_panel() -> void:
	move_learning_panel = PanelContainer.new()
	move_learning_panel.name = "MoveLearningPanel"
	move_learning_panel.position = Vector2(245, 75)
	move_learning_panel.size = Vector2(470, 430)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	move_learning_panel.add_child(margin)
	move_learning_list = VBoxContainer.new()
	move_learning_list.add_theme_constant_override("separation", 8)
	margin.add_child(move_learning_list)
	map_ui.add_child(move_learning_panel)


func _replace_move_for_pending(index: int) -> void:
	if pending_move_learning.is_empty():
		return
	var request: Dictionary = pending_move_learning.pop_front()
	var mon: Dictionary = request["mon"]
	var move_id := String(request["move_id"])
	if index >= 0 and index < mon["moves"].size():
		mon["moves"][index] = move_id
		hint_label.text = "%s learned %s!" % [mon["name"], battle.battle_data["moves"][move_id]["name"]]
	_refresh_party_menu()
	_auto_save()
	_show_next_move_learning_choice()


func _decline_pending_move() -> void:
	if pending_move_learning.is_empty():
		return
	var request: Dictionary = pending_move_learning.pop_front()
	var mon: Dictionary = request["mon"]
	var move_id := String(request["move_id"])
	hint_label.text = "%s did not learn %s." % [mon["name"], battle.battle_data["moves"][move_id]["name"]]
	_auto_save()
	_show_next_move_learning_choice()


func _build_grass_tiles(wild_data: Dictionary) -> void:
	var center := _array_to_vector3(wild_data["position"])
	var zone_size := _array_to_vector3(wild_data["size"])
	var columns := int(floor(zone_size.x))
	var rows := int(floor(zone_size.z))
	for x in columns:
		for z in rows:
			var tile_id := "%s:%d:%d" % [str(center), x, z]
			var tile := Area3D.new()
			tile.name = "GrassTile_" + tile_id.replace(":", "_")
			tile.position = center + Vector3(x - (columns - 1) * 0.5, 0.0, z - (rows - 1) * 0.5)
			var tile_size := Vector3(0.92, zone_size.y, 0.92)
			tile.add_child(_box_shape(tile_size))
			var visual := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = tile_size
			visual.mesh = mesh
			visual.material_override = _textured_material(TEX_GRASS, Color("#67a844"))
			tile.add_child(visual)
			var grass_sprite := _billboard_sprite(TEX_TALL_GRASS, 0.9, "TallGrassArt")
			grass_sprite.position = Vector3(0, 0.55, -0.08)
			tile.add_child(grass_sprite)
			tile.body_entered.connect(_on_grass_tile_entered.bind(tile_id, float(wild_data["encounter_chance"]), wild_data.get("species", map_data.get("tall_grass_species", []))))
			tile.body_exited.connect(_on_grass_tile_exited.bind(tile_id))
			world.add_child(tile)


func _build_outdoor_terrain_assets(region_data: Dictionary, origin: Vector3, prefix: String) -> void:
	_build_universal_terrain_layers(region_data,origin,prefix)
	for flower_data: Variant in region_data.get("tall_flowers", []):
		if flower_data is Array and flower_data.size() >= 3:
			_add_prop_billboard("TallFlowerBlock" if prefix == "CanopyRoute" else prefix + "TallFlower", origin + _array_to_vector3(flower_data), TEX_FLOWER_RED, 0.9)
	for flower_data: Variant in region_data.get("rare_torch_ginger", []):
		if flower_data is Array and flower_data.size() >= 3:
			_add_prop_billboard("MagnificentTorchGinger" if prefix == "CanopyRoute" else prefix + "TorchGinger", origin + _array_to_vector3(flower_data), TEX_FLOWER_TORCH_GINGER, 1.15)
	for flower_data: Variant in region_data.get("blue_flowers", region_data.get("flower_beds", [])):
		if flower_data is Array and flower_data.size() >= 3:
			_add_prop_billboard(prefix + "BlueFlower", origin + _array_to_vector3(flower_data), TEX_FLOWER_BLUE, 0.45)
	if bool(ProjectSettings.get_setting("debug/terrain/show_canonical_grid",false)):
		_build_canonical_terrain_debug(region_data,origin,prefix)
	else:
		_build_terrain_transition_overlays(region_data, origin, prefix)
	_build_universal_objects(region_data, origin, prefix, true)


func _build_universal_terrain_layers(region_data: Dictionary, origin: Vector3, prefix: String) -> void:
	var grass_zones: Array = region_data.get("grass_zones", [])
	# Supports legacy data while all current outdoor maps use grass_zones.
	if grass_zones.is_empty() and region_data.get("wild_zone") is Dictionary:
		grass_zones = [region_data["wild_zone"]]
	for grass_data: Variant in grass_zones:
		if not grass_data is Dictionary:
			continue
		var placed_grass: Dictionary = (grass_data as Dictionary).duplicate(true)
		var local_position := _array_to_vector3(placed_grass.get("position", [0, 0.12, 0]))
		placed_grass["position"] = [origin.x + local_position.x, origin.y + local_position.y, origin.z + local_position.z]
		placed_grass["species"] = region_data.get("tall_grass_species", [])
		_build_grass_tiles(placed_grass)
	_build_canonical_terrain_bases(region_data,origin,prefix)
	# Legacy sand rectangles are migration hints only. Canonical terrain tiles now
	# provide all visible ground topology, so drawing these would restore rigid edges.
	_build_canonical_water_collision(region_data,origin,prefix)


func _build_canonical_terrain_bases(region_data:Dictionary,origin:Vector3,prefix:String)->void:
	var grid:Dictionary=region_data.get("_terrain_grid",{})
	var base_terrain:=String(region_data.get("base_terrain_type","forest_floor"))
	var batches:Dictionary=preload("res://world/terrain_mesh_batcher.gd").build(grid,base_terrain,region_data.get("objects",[]),region_data.get("_habitat_floor_clip", PackedVector2Array()), region_data.has("habitat_type"))
	for key in batches:
		var batch:Dictionary=batches[key]
		var terrain_type:=String(batch.terrain_type)
		var texture:=TerrainTransitionTextureCache.base_texture(terrain_type)
		if texture==null:continue
		var tile:=MeshInstance3D.new()
		tile.name="%sCanonicalBase_%s"%[prefix,key]
		tile.mesh=batch.mesh
		var material:=_textured_material(texture)
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		tile.material_override=material
		tile.position=origin+Vector3(0,0.401,0)
		tile.add_to_group("day_night_terrain")
		tile.set_meta("canonical_terrain_type",terrain_type)
		tile.set_meta("affects_collision",false);tile.set_meta("affects_elevation",false)
		world.add_child(tile)
		OverworldTextureAnimation.register_terrain(texture,tile)


func _build_canonical_water_collision(region_data:Dictionary,origin:Vector3,prefix:String)->void:
	var grid:Dictionary=region_data.get("_terrain_grid",{})
	var water_tiles:Array=grid.keys().filter(func(position:Vector2i):return String(grid[position])=="water")
	water_tiles.sort_custom(func(a:Vector2i,b:Vector2i):return a.y<b.y or (a.y==b.y and a.x<b.x))
	for index in water_tiles.size():
		var position:Vector2i=water_tiles[index]
		# Water is an impassable terrain wall, not a low step. A shallow box can be
		# classified as floor by CharacterBody3D, letting the actor stand on its top.
		_add_static_collision("%sCanonicalWaterCollision%d"%[prefix,index],origin+Vector3(position.x,1.0,position.y),Vector3(1.0,2.0,1.0),TERRAIN_OBSTACLE_LAYER)
	_build_water_transition_collision_aprons(region_data,origin,prefix)
	# Compatibility fallback for maps not yet migrated to canonical water.
	if not water_tiles.is_empty():return
	for water_index in region_data.get("water_blocks",[]).size():
		var water_data:Variant=region_data.water_blocks[water_index]
		if not water_data is Array or water_data.size()!=6:continue
		var clipped:=_clip_terrain_block(_array_to_vector3(water_data),Vector3(float(water_data[3]),float(water_data[4]),float(water_data[5])),region_data)
		if not clipped.is_empty():_add_static_collision("%sLegacyWaterCollision%d"%[prefix,water_index],origin+clipped.position,clipped.size,TERRAIN_OBSTACLE_LAYER)


func _build_water_transition_collision_aprons(region_data:Dictionary,origin:Vector3,prefix:String)->void:
	var apron_index:=0
	for value:Variant in region_data.get("_terrain_transitions",[]):
		if not value is Dictionary or String(value.get("boundary_kind",""))!="cardinal" or String(value.get("terrain_b",""))!="water":continue
		var orientation:=String(value.get("piece",{}).get("orientation",""));var offset:=Vector3.ZERO;var size:=Vector3.ONE
		match orientation:
			"north":offset.z=-0.25;size=Vector3(1.0,2.0,0.5)
			"south":offset.z=0.05;size=Vector3(1.0,2.0,0.5)
			"west":offset.x=-0.05;size=Vector3(0.5,2.0,1.0)
			"east":offset.x=0.05;size=Vector3(0.5,2.0,1.0)
			_:continue
		var boundary:Vector2=value.region_position
		_add_static_collision("%sWaterTransitionCollision%d"%[prefix,apron_index],origin+Vector3(boundary.x,1.0,boundary.y)+offset,size,TERRAIN_OBSTACLE_LAYER)
		apron_index+=1


func _build_canonical_terrain_debug(region_data:Dictionary,origin:Vector3,prefix:String)->void:
	var colors:={"water":Color("3188b8"),"sand":Color("f4d990"),"mud":Color("8a603f"),"forest_floor":Color("376b42"),"stone":Color("a6a79f"),"rock":Color("777970")}
	var grid:Dictionary=region_data.get("_terrain_grid",{})
	for position:Vector2i in grid:
		var terrain_type:=String(grid[position]);var tile:=MeshInstance3D.new();tile.name="%sCanonicalTerrain_%d_%d_%s"%[prefix,position.x,position.y,terrain_type]
		var mesh:=PlaneMesh.new();mesh.size=Vector2(0.94,0.94);tile.mesh=mesh;tile.material_override=_material(colors.get(terrain_type,Color.MAGENTA))
		tile.position=origin+Vector3(position.x,0.405,position.y);tile.set_meta("canonical_terrain_type",terrain_type);tile.set_meta("affects_collision",false);world.add_child(tile)


func _build_terrain_transition_overlays(region_data: Dictionary, origin: Vector3, prefix: String) -> void:
	# These are visual-only chunk meshes. They intentionally create no body,
	# collision shape, traversal surface, or elevation entry.
	var tile_patches:Dictionary={}
	for value: Variant in region_data.get("_terrain_transitions", []):
		if not value is Dictionary: continue
		if not bool(value.get("piece",{}).get("supported",false)):continue
		var affected:Array=value.affected_tiles
		for tile_index in affected.size():
			var tile:Vector2i=affected[tile_index]
			if not tile_patches.has(tile):tile_patches[tile]=[]
			tile_patches[tile].append({"terrain_a":String(value.terrain_a),"terrain_b":String(value.terrain_b),"mask_type":String(value.piece.mask_type),"mask_variant":int(value.piece.get("mask_variant",0)),"orientation":String(value.piece.orientation),"slice":_transition_slice(value,tile_index)})
	var positions:Array=tile_patches.keys();positions.sort_custom(func(a:Vector2i,b:Vector2i):return a.y<b.y or (a.y==b.y and a.x<b.x));var grid:Dictionary=region_data.get("_terrain_grid",{})
	var cells:Array[Dictionary]=[]
	for transition_index in positions.size():
		var tile:Vector2i=positions[transition_index];var patches:Array=tile_patches[tile]
		var hard_boundary:=preload("res://tools/map_editor/core/wall_water_clip.gd").near_wall(tile,region_data.get("objects",[]))
		if TerrainTransitionResolver.solid_sand_fill(String(grid.get(tile,"forest_floor")),patches,hard_boundary):continue
		if hard_boundary:
			patches=patches.filter(func(patch:Dictionary)->bool:return String(patch.terrain_a)!="water" and String(patch.terrain_b)!="water")
			if patches.is_empty():continue
		var texture := TerrainTransitionTextureCache.texture_for_tile(String(grid.get(tile,"forest_floor")),patches)
		if texture == null: continue
		var highest_priority:=0
		for patch:Dictionary in patches:highest_priority=maxi(highest_priority,TerrainTransitionResolver.priority(String(patch.terrain_a)))
		var rect:=Rect2(Vector2(tile)-Vector2.ONE*0.5,Vector2.ONE)
		if String(grid.get(tile,""))=="water":rect=preload("res://tools/map_editor/core/wall_water_clip.gd").bounds(tile,grid,region_data.get("objects",[]))
		cells.append({"tile":tile,"rect":rect,"texture":texture,"priority":highest_priority,"patches":patches})
	var batches:Array[Dictionary]=preload("res://world/terrain_mesh_batcher.gd").build_transitions(cells, region_data.get("_habitat_floor_clip", PackedVector2Array()))
	for batch_index in batches.size():
		var batch:Dictionary=batches[batch_index]
		var overlay:=MeshInstance3D.new()
		overlay.name="%sTerrainOverlayBatch_%d_%d_%d"%[prefix,batch.chunk.x,batch.chunk.y,batch_index]
		overlay.mesh=batch.mesh;overlay.position=origin
		var texture:Texture2D=batch.texture
		var material:=_textured_material(texture)
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		overlay.material_override=material
		overlay.add_to_group("day_night_terrain")
		overlay.set_meta("terrain_transition",true)
		overlay.set_meta("transition_cells",batch.cells)
		overlay.set_meta("transition_operation_count",batch.operation_count)
		overlay.set_meta("affects_collision",false);overlay.set_meta("affects_elevation",false)
		world.add_child(overlay)
		OverworldTextureAnimation.register_terrain(texture,overlay)


func _build_canal_lock(record:Dictionary,position:Vector3,node_name:String,instance_id:String)->void:
	var gate=preload("res://world/canal_lock.tscn").instantiate()
	gate.name=node_name
	gate.position=position
	gate.rotation.y=deg_to_rad(float(record.get("rotation_degrees",0.0)))
	gate.gate_scale=float(record.get("gate_scale",1.0))
	gate.animation_time=float(record.get("animation_time",1.0))
	gate.visual_height=float(record.get("height",4.0))
	gate.collider_size=_array_to_vector3(record.get("size",[6.0,2.0,0.4]))
	gate.autoplay=bool(record.get("autoplay",true))
	gate.loop=bool(record.get("loop",true))
	world.add_child(gate)
	var source:Sprite3D=gate.get_node("Visual")
	_register_sortable_object(source,node_name+"SortRoot",position,source.global_position,gate.visual_height*gate.gate_scale,float(record.get("sort_offset_y",0.0)),Rect2(),instance_id)
	var entry:Dictionary=object_sort_entries[-1]
	entry["gate"]=gate
	gate.frame_changed.connect(func(_frame:int):
		entry["texture"]=source.texture
		if is_instance_valid(entry.get("sort_root")):
			(entry.sort_root.get_node("Visual") as Sprite2D).texture=source.texture
		# Animated bounds must refresh even with a stationary camera.
		static_art_view_signature=[])

func _transition_slice(transition:Dictionary,tile_index:int)->String:
	if String(transition.boundary_kind)=="corner":return ["corner_northwest","corner_northeast","corner_southwest","corner_southeast"][tile_index]
	var affected:Array=transition.affected_tiles;var delta:Vector2i=affected[1]-affected[0]
	return ("vertical_" if delta.x!=0 else "horizontal_")+("negative" if tile_index==0 else "positive")


func _build_universal_objects(region_data: Dictionary, origin: Vector3, prefix: String, terrain_layers_built:bool=false) -> void:
	_build_placed_npcs(region_data, origin)
	if not terrain_layers_built and (region_data.get("terrain_tiles") is Array or region_data.get("grass_zones") is Array):
		_build_universal_terrain_layers(region_data,origin,prefix)
	for index in region_data.get("objects", []).size():
		var value: Variant = region_data.get("objects", [])[index]
		if not value is Dictionary: continue
		var object: Dictionary = value
		var type_id := String(object.get("type", ""))
		var instance_id:=prefix+"|"+String(object.get("instance_id","")) if not String(object.get("instance_id","")).is_empty() else ""
		var node_name := "%sUniversalObject%d" % [prefix, index]
		# Geometry-based walls are anchored by their polyline points, not a single
		# object position. Every other universal object keeps the position guard.
		if type_id == "wall.fence":
			_build_wall_fence(object,origin,node_name)
			continue
		var position_data: Variant = object.get("position", [])
		if not position_data is Array or position_data.size() < 3: continue
		var position := origin + _array_to_vector3(position_data)
		if type_id in ["tree.main", "tree.palm"]:
			_add_tree(position, 1 if type_id == "tree.palm" else 0, node_name, float(object.get("sort_offset_y", 0.0)), float(object.get("height",3.8 if type_id=="tree.palm" else 4.2)),instance_id)
		elif type_id in ["block.water", "block.sand", "block.rock"]:
			var size_data: Variant = object.get("size", [2.0, 0.3, 2.0])
			if not size_data is Array or size_data.size() < 3: continue
			var size := _array_to_vector3(size_data)
			var clipped := _clip_terrain_block(_array_to_vector3(position_data), size, region_data)
			if clipped.is_empty(): continue
			position = origin + clipped.position
			size = clipped.size
			var texture := TerrainTransitionTextureCache.base_texture("water") if type_id == "block.water" else (TEX_SAND if type_id == "block.sand" else TEX_STONE)
			var color := Color.WHITE if type_id == "block.water" else (Color.WHITE if type_id == "block.sand" else Color("#777970"))
			_add_textured_block(node_name, position, size, texture, color, type_id != "block.sand", TERRAIN_OBSTACLE_LAYER if type_id == "block.water" else 1)
		elif type_id.begins_with("decal."):
			var texture:=load(String(object.get("asset_path",""))) as Texture2D
			if texture==null:continue
			var dimensions:Variant=object.get("size",[2.0,0.02,2.0])
			var visual:=MeshInstance3D.new();visual.name=node_name
			var plane:=PlaneMesh.new();plane.size=Vector2(float(dimensions[0]),float(dimensions[2]));visual.mesh=plane
			visual.position=Vector3(position.x,maxf(position.y,origin.y+0.43),position.z)
			visual.rotation.y=deg_to_rad(float(object.get("rotation_degrees",0.0)))
			visual.material_override=_textured_material(texture)
			visual.add_to_group("day_night_terrain");visual.set_meta("ground_decal",true);world.add_child(visual)
		elif type_id.begins_with("tile."):
			var asset_texture:=load(String(object.get("asset_path",""))) as Texture2D
			var size_data:Variant=object.get("size",[1.0,0.2,1.0])
			if asset_texture==null or not size_data is Array or size_data.size()<3:continue
			_add_water_shape_tile(node_name,position,_array_to_vector3(size_data),asset_texture,float(object.get("rotation_degrees",0.0)),String(object.get("asset_path","")))
		elif type_id == "structure.bridge":
			_build_traversal_bridge(object, origin, node_name)
		elif type_id == "structure.canal_lock":
			_build_canal_lock(object,position,node_name,instance_id)
		elif CITY_BACKGROUND_TEXTURES.has(type_id):
			var size_data: Variant = object.get("size", [10.0, 6.0, 4.0])
			if not size_data is Array or size_data.size() < 3: continue
			var size := _array_to_vector3(size_data)
			var texture: Texture2D = CITY_BACKGROUND_TEXTURES[type_id]
			var art := _add_world_billboard(node_name, position, texture, size.x, 0.0)
			_register_background_object(art, node_name + "BackgroundRoot", position, art.global_position, float(art.texture.get_height()) * art.pixel_size,instance_id)
			# The serialized position is the façade's bottom contact. Keep the
			# structural footprint behind that line so foreground remains walkable.
			_add_static_collision(node_name + "Collision", position-Vector3(0,0,size.z*0.5), size)
		elif type_id.begins_with("building."):
			var size_data: Variant = object.get("size", [5.0, 3.0, 4.0])
			if not size_data is Array or size_data.size() < 3: continue
			var size := _array_to_vector3(size_data)
			var texture:Texture2D = load(String(object.get("asset_path",""))) as Texture2D if object.has("asset_path") else (TEX_MEDICAL_WARD if type_id == "building.medical_ward" else TEX_HOUSE)
			if texture==null:continue
			var art := _add_world_billboard(node_name, position, texture, size.x * (1.08 if type_id == "building.medical_ward" else 1.15), 0.0)
			_register_sortable_object(art, node_name + "SortRoot", position, art.global_position, float(art.texture.get_height()) * art.pixel_size, float(object.get("sort_offset_y", 0.0)),Rect2(),instance_id)
			# Authored polygons replace the default footprint, including entrance cutouts.
			var asset_path:=String(object.get("asset_path",""))
			if not _add_asset_polygon_collision(node_name+"AssetPolygon",position,size,float(object.get("rotation_degrees",0.0)),asset_path):
				_add_building_collision(node_name+"Collision",position,size,"medical_ward" if type_id=="building.medical_ward" else "house")
				_add_asset_collision_boxes(node_name,position,asset_path,size,float(object.get("rotation_degrees",0.0)))
		elif type_id in ["npc.generic", "npc.opponent"]:
			var character:=_resolved_trainer(object) if type_id=="npc.opponent" else object
			var speaker := String(character.get("name" if type_id == "npc.opponent" else "speaker", "TRAINER" if type_id == "npc.opponent" else "NPC"))
			var pages: Array = character.get("dialogue", ["Let's battle!"] if type_id == "npc.opponent" else ["Hello, traveler!"])
			var after_dialogue := _begin_trainer_battle.bind(character.get("team", character.get("party",[]))) if type_id == "npc.opponent" else Callable()
			var npc := _add_talking_npc(node_name, position, Color(String(character.get("color", "df6d5f" if type_id == "npc.opponent" else "e9c35b"))), speaker.to_upper(), pages, after_dialogue, String(character.get("sprite","")))
		elif type_id.begins_with("asset.") and not WaterDecoration.kind(String(object.get("asset_path",""))).is_empty():
			var asset_path := String(object.asset_path)
			var texture := load(asset_path) as Texture2D
			if texture == null: continue
			var water_kind := WaterDecoration.kind(asset_path)
			var height := float(object.get("height",1.0))
			var metadata := _overworld_asset_metadata(asset_path)
			if bool(metadata.get("standardize_scale",false)): height = float(metadata.get("visual_height",height))
			height = maxf(height,0.05)
			var art := _add_world_billboard(node_name,position,texture,height*float(texture.get_width())/float(texture.get_height()),0.0)
			_register_overlay_object(art,node_name+"WaterDecorationRoot",position,art.global_position,height,float(object.get("rotation_degrees",0.0)),WaterDecoration.render_band(water_kind))
			# Pure art never builds collision or navigation from copied sidecars.
			if water_kind == "submerged": _ensure_water_surface(region_data,origin,prefix)
		elif type_id.begins_with("overlay."):
			var asset_path:=String(object.get("asset_path",""))
			var asset_texture:=load(asset_path) as Texture2D
			if asset_texture==null:continue
			var dimensions:Variant=object.get("size",[])
			var height:=float(object.get("height",0.0))
			if height<=0.0:
				var width:=float(dimensions[0]) if dimensions is Array and dimensions.size()>=1 else 1.0
				height=width*float(asset_texture.get_height())/maxf(float(asset_texture.get_width()),1.0)
			if bool(object.get("is_attached",false)) and not String(object.get("host_id","")).is_empty() and object.get("local_position") is Array and object.local_position.size()>=2:
				attached_overlay_entries.append({"name":node_name+"AttachedOverlay","host_id":prefix+"|"+String(object.host_id),"texture":asset_texture,"height":height,"local_position":Vector2(float(object.local_position[0]),float(object.local_position[1])),"rotation_degrees":float(object.get("rotation_degrees",0.0)),"attachment_order":int(object.get("attachment_order",0)),"fallback_position":position})
			else:
				var art:=_add_world_billboard(node_name,position,asset_texture,height*float(asset_texture.get_width())/maxf(float(asset_texture.get_height()),1.0),0.0)
				_register_overlay_object(art,node_name+"OverlayRoot",position,art.global_position,height,float(object.get("rotation_degrees",0.0)))
		else:
			# The map editor can serialize any imported overworld sprite as an
			# asset.* object.  Resolve that data-driven path at runtime too, so a
			# newly imported palette asset does not need a main.gd code entry.
			if type_id.begins_with("asset."):
				var asset_path := String(object.get("asset_path", ""))
				var asset_texture := load(asset_path) as Texture2D
				if asset_texture != null:
					var dimensions:Variant=object.get("size",[])
					var height:=float(object.get("height",0.0))
					var metadata_path:=asset_path.trim_suffix(".png")+".json"
					var metadata_file := FileAccess.open(metadata_path, FileAccess.READ)
					var metadata: Variant = JSON.parse_string(metadata_file.get_as_text()) if metadata_file != null else null
					if metadata is Dictionary and bool(metadata.get("standardize_scale", false)):
						height = float(metadata.get("visual_height", height))
					if height<=0.0:
						var width:=float(dimensions[0]) if dimensions is Array and dimensions.size()>=1 else 1.0
						height=width*float(asset_texture.get_height())/float(asset_texture.get_width())
					_add_prop_billboard(node_name, position, asset_texture, height,instance_id)
					if object.get("habitat_exhibit") is Dictionary:
						object_sort_entries[-1]["habitat_exhibit"] = object.habitat_exhibit
					object_sort_entries[-1]["sort_offset_y"]+=float(object.get("sort_offset_y",0.0))
					if prefix == "AuthoredMap_ChallengerCenterJalvoeaCity" and asset_path == "res://assets/overworld/habitat_pen_massive.png":
						_split_habitat_pen_art(object_sort_entries[-1])
					var is_signpost: bool = metadata is Dictionary and bool(metadata.get("signpost", false))
					if is_signpost or type_id in ["asset.indoor_display", "asset.indoor_billboard_tropical_research"]:
						object_sort_entries[-1]["interaction_text"] = String(object.get("interaction_text", ""))
					if is_signpost and metadata.has("active_texture"):
						var active_path := String(metadata.active_texture).replace("\\", "/")
						if ResourceLoader.exists(active_path):
							object_sort_entries[-1]["active_texture"] = load(active_path) as Texture2D
					_add_asset_collision_boxes(node_name,position,asset_path,_array_to_vector3(dimensions) if dimensions is Array and dimensions.size()>=3 else Vector3.ONE,float(object.get("rotation_degrees",0.0)))
					_add_asset_navigation(node_name,position,asset_path,height)
				continue
			var texture: Texture2D = TEX_FLOWER_RED
			var height := 0.9
			match type_id:
				"flower.torch_ginger": texture = TEX_FLOWER_TORCH_GINGER; height = 1.15
				"flower.blue": texture = TEX_FLOWER_BLUE; height = 0.45
				"flower.orchid": texture = TEX_FLOWER_ORCHID_POT; height = 0.72
				"cave.vine": texture = TEX_VINES; height = 1.25
				"flower.passion_vine_horizontal": texture = TEX_PASSION_VINE_HORIZONTAL; height = 0.62
				"flower.red_ginger": pass
				_: continue
			_add_prop_billboard(node_name, position, texture, float(object.get("height", height)))

func _build_wall_fence(object:Dictionary,origin:Vector3,node_name:String)->void:
	# The authored polyline owns visual geometry.  Baked strips remain the existing
	# editor-generated collision representation and are not recalculated at runtime.
	var points:Variant=object.get("points",[])
	if not points is Array:return
	var disabled:Dictionary={};var disabled_source:Variant=object.get("disabled_segments",[])
	if disabled_source is Array:
		for value:Variant in disabled_source:
			if (value is int or value is float) and is_equal_approx(float(value),floorf(float(value))):disabled[int(value)]=true
	for index in range(1,points.size()):
		if disabled.has(index-1):continue
		var from:Variant=points[index-1];var to:Variant=points[index]
		if not from is Array or not to is Array or from.size()<2 or to.size()<2:continue
		var start:=Vector2(float(from[0]),float(from[1]));var finish:=Vector2(float(to[0]),float(to[1]))
		_add_wall_filler_run("%sFiller_%d"%[node_name,index-1],origin,start,finish,String(object.get("wall_set","generic_wall")))
	# Fillers are created first.  Each unique coordinate receives one post after
	# them, so the post artwork conceals endpoints and junction seams.
	var posted:Dictionary={}
	for anchor:Variant in points:
		if not anchor is Array or anchor.size()<2:continue
		var anchor_position:=Vector2(float(anchor[0]),float(anchor[1]));var anchor_key:="%.6f,%.6f"%[anchor_position.x,anchor_position.y]
		if posted.has(anchor_key):continue
		posted[anchor_key]=true
		_add_prop_billboard("%sPost_%d"%[node_name,posted.size()-1],origin+Vector3(anchor_position.x,0.0,anchor_position.y),TEX_WALL_POST,WALL_VISUAL_HEIGHT)
	var segments:Variant=object.get("baked_segments",[])
	var collision:Variant=object.get("baked_collision",[])
	if not segments is Array or not collision is Array:return
	for index in segments.size():
		var segment:Variant=segments[index];if not segment is Dictionary:continue
		var a:Variant=segment.get("from",[]);var b:Variant=segment.get("to",[])
		if not a is Array or not b is Array or a.size()<2 or b.size()<2:continue
		var start:=Vector2(float(a[0]),float(a[1]));var finish:=Vector2(float(b[0]),float(b[1]));var delta:=finish-start;var length:=delta.length()
		if length<=0.001:continue
		# Legacy diagonal records remain loadable data, but diagonal wall geometry is
		# unsupported and therefore creates neither artwork nor collision.
		if _wall_direction_for_delta(delta).is_empty():continue
		var offset:=float(collision[index].get("offset",0.0)) if index<collision.size() and collision[index] is Dictionary else 0.0
		var normal:=Vector2(-delta.y,delta.x).normalized()*offset
		var center:=origin+Vector3((start.x+finish.x)*0.5+normal.x,0.5,(start.y+finish.y)*0.5+normal.y)
		var thickness:=float(collision[index].get("thickness",0.22)) if index<collision.size() and collision[index] is Dictionary else 0.22
		_add_wall_collision_segment("%s_%d"%[node_name,index],center,length,thickness,atan2(delta.x,delta.y),1 | FENCE_COLLISION_LAYER)


func _add_wall_filler_run(name:String,origin:Vector3,start:Vector2,finish:Vector2,wall_set:String="generic_wall")->void:
	var delta:=finish-start
	var direction:=_wall_direction_for_delta(delta)
	if direction.is_empty():return
	var run_length:=delta.length()
	if run_length<=0.001:return
	var texture:=_wall_filler_texture(direction)
	if wall_set=="canal_wall":texture=load("res://assets/overworld/canal_wall_vertical.png" if direction=="vertical" else "res://assets/overworld/canal_wall_close.png")
	var filler_interval:=WALL_FILLER_INTERVAL
	# Wall geometry owns repetition spacing. Texture dimensions affect only the
	# artwork's appearance, never the number or placement of filler intervals.
	var run_direction:=delta/run_length
	var bounded_repeat_count:=floori((run_length+0.0001)/filler_interval)
	for repeat_index in bounded_repeat_count:
		var midpoint:=start+run_direction*(filler_interval*(float(repeat_index)+0.5))
		_add_wall_filler_piece("%s_%d"%[name,repeat_index],origin+Vector3(midpoint.x,0.0,midpoint.y),texture,wall_set=="canal_wall",direction)


func _wall_direction_for_delta(delta:Vector2)->String:
	if is_zero_approx(delta.y):return "horizontal"
	if is_zero_approx(delta.x):return "vertical"
	return ""


func _wall_filler_texture(direction:String)->Texture2D:
	return TEX_WALL_FILLER_VERTICAL if direction=="vertical" else TEX_WALL_FILLER_HORIZONTAL


func _add_wall_filler_piece(name:String,ground_position:Vector3,texture:Texture2D,canal:bool=false,direction:String="horizontal")->void:
	# Fillers retain their full native aspect ratio at the same pixel scale as
	# posts.  Their dimensions never come from a map-unit or segment length.
	var visual_height:=float(texture.get_height())*WALL_PIXELS_TO_WORLD
	if canal:visual_height=2.0*float(texture.get_height())/float(texture.get_width()) if direction=="horizontal" else 2.0*sqrt(0.5)
	# Raise canal panels to the existing posts without stretching their run span.
	if canal and direction=="horizontal":visual_height=1.6
	var sprite:=_billboard_sprite(texture,visual_height,name)
	if canal and direction=="horizontal":sprite.scale.x=2.0/(visual_height*float(texture.get_width())/float(texture.get_height()))
	sprite.position=Vector3(ground_position.x,visual_height*0.5,ground_position.z)
	if canal and direction=="vertical":sprite.position.y=0.0
	# Vertical artwork represents a run on the ground plane. Its lower end is
	# half a run south of the midpoint, raised to the horizontal rail's screen
	# height. Sorting/collision continue to use the authored midpoint.
	if canal and direction=="vertical":sprite.position.z+=1.0-1.2/sqrt(0.5)
	world.add_child(sprite)
	_register_sortable_object(sprite,name+"SortRoot",ground_position,sprite.global_position,visual_height)
	if canal:object_sort_entries[-1]["wall_scale_x"]=sprite.scale.x


func _add_wall_collision_segment(name:String,center:Vector3,length:float,thickness:float,angle:float,physics_layer:int=1)->void:
	# The authored line is the fence's ground-contact/blocking line. The box
	# begins at ground level and is independent of filler/post pixels.
	var collision_height:=1.0
	var body:=StaticBody3D.new();body.name=name+"Collision";body.position=center;body.rotation.y=angle;body.collision_layer=physics_layer;body.collision_mask=1;body.add_child(_box_shape(Vector3(thickness,collision_height,length)));world.add_child(body)


func _clip_terrain_block(local_position: Vector3, block_size: Vector3, region_data: Dictionary) -> Dictionary:
	var size_data: Variant = region_data.get("size", region_data.get("map_size", []))
	if not size_data is Array or size_data.size() < 2: return {"position":local_position, "size":block_size}
	var half_x := float(size_data[0]) * 0.5; var half_z := float(size_data[1]) * 0.5
	var center:=MapBounds.center(region_data)
	var min_x := maxf(local_position.x - block_size.x * 0.5, center.x-half_x)
	var max_x := minf(local_position.x + block_size.x * 0.5, center.x+half_x)
	var min_z := maxf(local_position.z - block_size.z * 0.5, center.y-half_z)
	var max_z := minf(local_position.z + block_size.z * 0.5, center.y+half_z)
	if max_x - min_x <= 0.0001 or max_z - min_z <= 0.0001: return {}
	return {"position":Vector3((min_x+max_x)*0.5,local_position.y,(min_z+max_z)*0.5), "size":Vector3(max_x-min_x,block_size.y,max_z-min_z)}


# Elevated traversal is shared world architecture. A bridge is only one data-driven
# participant: its deck changes the actor's world Y and terrain collision mask.
func _build_traversal_bridge(data: Dictionary, origin: Vector3, node_name: String) -> void:
	var center := origin + _array_to_vector3(data.get("position", [0, 0, 0]))
	var orientation := String(data.get("orientation", "horizontal"))
	var length := maxi(3, int(data.get("length", 3)))
	# Width is an asset-level scale shared by every horizontal and vertical bridge.
	var width := maxf(1.0, float(data.get("width", 1.0))) * BRIDGE_ASSET_WIDTH_SCALE
	var elevation := maxf(0.5, float(data.get("elevation", 1.0)))
	var entrance_length := maxf(0.5, float(data.get("entrance_length", 1.0)))
	var axis := Vector3.RIGHT if orientation == "horizontal" else Vector3.FORWARD
	var side_axis := Vector3.FORWARD if orientation == "horizontal" else Vector3.RIGHT
	# Transparent padding in the bridge art is asymmetric. Match containment to
	# the visible rail span rather than the full texture rectangle.
	var middle_texture: Texture2D = TEX_BRIDGE_HORIZONTAL_MIDDLE if orientation == "horizontal" else TEX_BRIDGE_VERTICAL_MIDDLE
	var image := middle_texture.get_image()
	var extent := image.get_height() if orientation == "horizontal" else image.get_width()
	var first := extent
	var last := 0
	for pixel in extent:
		var color := image.get_pixel(image.get_width() / 2, pixel) if orientation == "horizontal" else image.get_pixel(pixel, image.get_height() / 2)
		if color.a > 0.5:
			first = mini(first, pixel)
			last = maxi(last, pixel)
	var visible_min := (float(first) / extent - 0.5) * width
	var visible_max := (float(last + 1) / extent - 0.5) * width
	# Vector3.FORWARD points toward negative Z, opposite the texture's V axis.
	if orientation == "horizontal":
		var previous_min := visible_min
		visible_min = -visible_max
		visible_max = -previous_min
	var surface := {
		"lateral_min": visible_min, "lateral_max": visible_max,
		"name": node_name, "center": center, "axis": axis, "side_axis": side_axis,
		"visual_layer": _visual_layer_for_position(center),
		"length": float(length), "width": width, "elevation": elevation,
		"entrance_length": entrance_length, "traversal_layer": int(data.get("traversal_layer", 1))
	}
	traversal_surfaces.append(surface)
	var textures: Array = [TEX_BRIDGE_HORIZONTAL_START, TEX_BRIDGE_HORIZONTAL_MIDDLE, TEX_BRIDGE_HORIZONTAL_END] if orientation == "horizontal" else [TEX_BRIDGE_VERTICAL_START, TEX_BRIDGE_VERTICAL_MIDDLE, TEX_BRIDGE_VERTICAL_END]
	for tile_index in length:
		var offset := float(tile_index) - float(length - 1) * 0.5
		var tile_center: Vector3 = center + axis * offset
		tile_center.y = elevation + 0.015
		var tile := MeshInstance3D.new()
		tile.name = "%sDeckTile%d" % [node_name, tile_index]
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(1.0 if orientation == "horizontal" else width, width if orientation == "horizontal" else 1.0)
		tile.mesh = mesh
		var texture_index := 0 if tile_index == 0 else (2 if tile_index == length - 1 else 1)
		var deck_material := _textured_material(textures[texture_index])
		deck_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		deck_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tile.material_override = deck_material
		tile.position = tile_center
		world.add_child(tile)
		bridge_sort_entries.append({"name":"%sOcclusion%d" % [node_name, tile_index], "position":tile_center, "texture":textures[texture_index], "size":mesh.size, "surface":surface})
	# Railings are permanent structure collision, but are high enough that actors
	# beneath the bridge can pass below them. Their X/Z placement is orientation-free.
	for side in [-1.0, 1.0]:
		var rail_position := center + side_axis * (width * 0.5)
		rail_position.y = elevation + 1.0
		var rail_size := Vector3(float(length), 0.6, 0.18) if orientation == "horizontal" else Vector3(0.18, 0.6, float(length))
		_add_static_collision("%sRailing%s" % [node_name, "A" if side < 0 else "B"], rail_position, rail_size)


func _surface_coordinates(surface: Dictionary, world_position: Vector3) -> Vector2:
	var delta: Vector3 = world_position - (surface["center"] as Vector3)
	return Vector2(delta.dot(surface["axis"]), delta.dot(surface["side_axis"]))


func _update_traversal_surface(world_position: Vector3, input_vector: Vector2 = Vector2.ZERO) -> void:
	if not active_traversal_surface.is_empty() and int(active_traversal_surface.get("visual_layer",_visual_layer_for_position(active_traversal_surface.center))) != _active_visual_layer():
		active_traversal_layer = 0; active_traversal_surface = {}
	# Once an actor is on a traversal surface, its lateral footprint is contained
	# by that surface. It may leave only past either authored end/ramp.
	if active_traversal_layer > 0 and not active_traversal_surface.is_empty():
		var active_coordinate := _surface_coordinates(active_traversal_surface, world_position)
		var player_half_width := 0.4
		var half_width := float(active_traversal_surface["width"]) * 0.5
		var lower := float(active_traversal_surface.get("lateral_min", -half_width)) + player_half_width
		var upper := float(active_traversal_surface.get("lateral_max", half_width)) - player_half_width
		var constrained_lateral := clampf(active_coordinate.y, lower, upper) if lower <= upper else (lower + upper) * 0.5
		player.position += (active_traversal_surface["side_axis"] as Vector3) * (constrained_lateral - active_coordinate.y)
		world_position = player.position
	var chosen: Dictionary = {}
	var chosen_height := 0.0
	for surface: Dictionary in traversal_surfaces:
		if int(surface.get("visual_layer",_visual_layer_for_position(surface.center))) != _active_visual_layer(): continue
		if surface.has("recessed_outline"):
			if not Geometry2D.is_point_in_polygon(Vector2(world_position.x, world_position.z), surface.recessed_outline):
				continue
			var north_progress := inverse_lerp(float(surface.north_entry), float(surface.north_landing), world_position.z)
			var south_progress := inverse_lerp(float(surface.south_entry), float(surface.south_landing), world_position.z)
			chosen = surface
			chosen_height = -float(surface.depth) * clampf(minf(north_progress, south_progress), 0.0, 1.0)
			break
		var coordinate := _surface_coordinates(surface, world_position)
		var half_length := float(surface["length"]) * 0.5
		var half_width := float(surface["width"]) * 0.5
		var ramp := float(surface["entrance_length"])
		if absf(coordinate.y) > half_width:
			continue # Side approaches cannot change elevation.
		var longitudinal := absf(coordinate.x)
		if longitudinal <= half_length:
			chosen = surface
			chosen_height = float(surface["elevation"])
			break
		if longitudinal <= half_length + ramp:
			chosen = surface
			chosen_height = float(surface["elevation"]) * (1.0 - (longitudinal - half_length) / ramp)
			break
	if not chosen.is_empty() and (active_traversal_layer > 0 or chosen_height < 0.35 or _is_entering_surface_end(chosen, world_position, input_vector)):
		active_traversal_layer = int(chosen["traversal_layer"]) if chosen_height > 0.35 else 0
		active_traversal_surface = chosen if active_traversal_layer > 0 else {}
		player.position.y = PLAYER_GROUND_HEIGHT + chosen_height
	else:
		active_traversal_layer = 0
		active_traversal_surface = {}
		player.position.y = PLAYER_GROUND_HEIGHT
	_update_platform_collision_mask()
	_update_bridge_occlusion_priority()


func _is_entering_surface_end(surface: Dictionary, world_position: Vector3, input_vector: Vector2) -> bool:
	var coordinate := _surface_coordinates(surface, world_position)
	var world_input := Vector3(input_vector.x, 0.0, input_vector.y)
	return absf(coordinate.x) >= float(surface["length"]) * 0.5 - 0.25 and coordinate.x * world_input.dot(surface["axis"]) < 0.0


func _update_bridge_occlusion_priority() -> void:
	var actor_priority := 10 if active_traversal_layer > 0 else 0
	if player_sort_root != null:
		player_sort_root.z_index = actor_priority
	# The companion follows the player's traversal state while retaining its
	# trailing X/Z position and normal depth sorting relative to the player.
	if follower != null:
		follower.position.y = player.position.y
		follower_target.y = player.position.y
	if follower_sort_root != null:
		follower_sort_root.z_index = actor_priority
	for entry: Dictionary in bridge_sort_entries:
		if entry.has("sort_root"):
			(entry["sort_root"] as CanvasItem).z_index = 5


func _build_route(route_data: Dictionary) -> void:
	route_origin = _array_to_vector3(route_data["origin"])
	var route_size: Array = route_data["size"]
	_add_textured_block("CanopyRouteGround", route_origin + MapBounds.offset(route_data) + Vector3(0, -0.1, 0), Vector3(float(route_size[0]), 0.2, float(route_size[1])), TEX_GRASS, Color("#315f3b"), false)
	_build_forest_warp("CanopyRouteExit", route_origin + _array_to_vector3(route_data["exit_warp"]), _on_route_exit_entered, "north")
	_build_forest_warp("CanopyRouteEastConnection", route_origin + _array_to_vector3(route_data["east_warp"]), _on_east_route_entered, "east")
	_build_forest_warp("CanopyRouteWestConnection", route_origin + _array_to_vector3(route_data["west_warp"]), _on_west_route_entered, "west")
	_build_forest_warp("CanopyRouteNorthConnection", route_origin + _array_to_vector3(route_data["north_warp"]), _on_city_entered, "generic")
	_build_outdoor_terrain_assets(route_data, route_origin, "CanopyRoute")
	for tree_data: Array in route_data["trees"]:
		_add_tree(route_origin + Vector3(float(tree_data[0]), float(tree_data[1]), float(tree_data[2])), int(tree_data[3]), "Route")
	_build_trainers(route_data.get("trainers", []), route_origin, "CanopyRoute")


func _build_side_route(route_data: Dictionary, prefix: String, is_east: bool) -> void:
	var origin := _array_to_vector3(route_data["origin"])
	if is_east:
		east_route_origin = origin
	else:
		west_route_origin = origin
	var route_size: Array = route_data["size"]
	_add_textured_block(prefix + "RainforestRouteGround", origin + MapBounds.offset(route_data) + Vector3(0, -0.1, 0), Vector3(float(route_size[0]), 0.2, float(route_size[1])), TEX_GRASS, Color("#376b42"), false)
	_build_forest_warp(prefix + "RouteReturnWarp", origin + _array_to_vector3(route_data["return_warp"]), _on_east_route_exited if is_east else _on_west_route_exited, "west" if is_east else "east")
	_build_outdoor_terrain_assets(route_data, origin, prefix + "Route")
	for tree_data: Array in route_data["trees"]:
		_add_tree(origin + Vector3(float(tree_data[0]), float(tree_data[1]), float(tree_data[2])), int(tree_data[3]), prefix + "Route")
	_build_trainers(route_data.get("trainers", []), origin, prefix + "Route")
	if is_east:
		_build_forest_warp("EasternRouteCaveEntrance", origin + _array_to_vector3(route_data["cave_warp"]), _on_east_cave_entered, "east")


func _build_east_cave(cave_data: Dictionary) -> void:
	east_cave_origin = _array_to_vector3(cave_data["origin"])
	var cave_size: Array = cave_data["size"]
	var cave_floor_blocks: Array = cave_data.get("floor_blocks", [[0, -0.1, 0, cave_size[0], 0.2, cave_size[1]]])
	_add_map_blocks(east_cave_origin, cave_floor_blocks, "VinestoneCaveRockyGround", TEX_STONE, Color("#595b55"), false)
	_build_forest_warp("VinestoneCaveExit", east_cave_origin + _array_to_vector3(cave_data["exit_warp"]), _on_east_cave_exited, "north")
	for rock_data: Array in cave_data["rocks"]:
		_add_textured_block("CaveRockBlock", east_cave_origin + Vector3(float(rock_data[0]), float(rock_data[1]), float(rock_data[2])), Vector3(float(rock_data[3]), float(rock_data[4]), float(rock_data[5])), TEX_STONE, Color("#777970"), true)
	for flower_data: Array in cave_data["blue_flowers"]:
		_add_prop_billboard("SmallBlueFlower", east_cave_origin + Vector3(float(flower_data[0]), float(flower_data[1]), float(flower_data[2])), TEX_FLOWER_BLUE, 0.45)
	for vine_data: Array in cave_data["vines"]:
		_add_prop_billboard("CaveVine", east_cave_origin + Vector3(float(vine_data[0]), float(vine_data[1]), float(vine_data[2])), TEX_VINES, 1.25)
	_build_universal_objects(cave_data, east_cave_origin, "VinestoneCave")
	_build_trainers(cave_data.get("trainers", []), east_cave_origin, "VinestoneCave")


func _build_rainforest_city(city_data: Dictionary) -> void:
	city_origin = _array_to_vector3(city_data["origin"])
	var city_size: Array = city_data["size"]
	_add_textured_block("MossvaleCityGround", city_origin + MapBounds.offset(city_data) + Vector3(0, -0.1, 0), Vector3(float(city_size[0]), 0.2, float(city_size[1])), TEX_GRASS, Color("#47784d"), false)
	_add_textured_block("MossvalePlazaPath", city_origin + Vector3(0, 0.02, 2), Vector3(5, 0.08, 16), TEX_STONE, Color("#a7956f"), false)
	_build_forest_warp("MossvaleCitySouthExit", city_origin + _array_to_vector3(city_data["return_warp"]), _on_city_exited, "north")
	for tree_data: Array in city_data["trees"]:
		_add_tree(city_origin + Vector3(float(tree_data[0]), float(tree_data[1]), float(tree_data[2])), int(tree_data[3]), "Mossvale")
	for flower_data: Array in city_data["flower_beds"]:
		_add_prop_billboard("MossvaleFlowerBed", city_origin + Vector3(float(flower_data[0]), float(flower_data[1]), float(flower_data[2])), TEX_FLOWER_BLUE, 0.45)
	_build_universal_objects(city_data, city_origin, "Mossvale")
	_build_city_exterior(city_data["medical_ward"], "MossvaleMedicalWard", Color("#91cdd0"), _on_city_ward_entered)
	_build_city_exterior(city_data["orchid_house"], "GroundOrchidHouse", Color("#9b7359"), _on_orchid_house_entered)
	_build_city_exterior(city_data["family_house"], "MossvaleFamilyHouse", Color("#b08359"), _on_family_house_entered)
	_build_medical_ward_instance(city_data["medical_ward"], "MossvaleWard", _on_city_ward_exited)
	_build_city_room(city_data["orchid_house"], "OrchidHome", Color("#dac9aa"), Color("#e0b45b"), _on_orchid_house_exited)
	_build_city_room(city_data["family_house"], "FamilyHome", Color("#d7c29c"), Color("#e0b45b"), _on_family_house_exited)
	city_ward_origin = _array_to_vector3(city_data["medical_ward"]["origin"])
	orchid_house_origin = _array_to_vector3(city_data["orchid_house"]["origin"])
	family_house_origin = _array_to_vector3(city_data["family_house"]["origin"])
	for orchid_data: Array in city_data["orchid_house"]["orchids"]:
		_add_small_orchid(orchid_house_origin + _array_to_vector3(orchid_data))
	var orchid_npc := _add_talking_npc("GroundOrchidExpert", orchid_house_origin + _array_to_vector3(city_data["orchid_house"]["npc"]), Color("#b36bc9"), "ORCHID KEEPER", ["Ground orchids grow from the forest floor instead of clinging to trees. Their roots shelter in the rich leaf litter below the canopy."], Callable(), "woman")
	var adult_data: Array = city_data["family_house"]["adults"]
	_add_talking_npc("EvolutionParent", family_house_origin + _array_to_vector3(adult_data[0]), Color("#d98b57"), "PARENT", ["Some Fakemon may evolve after earning enough experience. Training and exploring together can help them reach that turning point."], Callable(), "woman")
	_add_talking_npc("DespairParent", family_house_origin + _array_to_vector3(adult_data[1]), Color("#5c8ecb"), "PARENT", ["Try not to let your Fakemon fall into Despair. A despairing partner struggles to give its best, so care and recovery matter as much as winning."], Callable(), "man")
	for index in city_data["family_house"].get("children", []).size():
		var child_data: Dictionary = city_data["family_house"]["children"][index]
		var child := _add_talking_npc("FamilyChild%d" % (index + 1), family_house_origin + _array_to_vector3(child_data["position"]), Color("#e9c35b"), "CHILD", [String(child_data.get("dialogue", "We like playing together inside when the rainforest rain gets heavy!"))], Callable(), String(child_data["sprite"]))
		family_children.append({"node": child, "target": child.position, "timer": randf_range(0.5, 2.0), "animation_time": 0.0, "frame": 0})
	_build_trainers(city_data.get("trainers", []), city_origin, "Mossvale")


func _build_city_exterior(building_data: Dictionary, building_name: String, color: Color, callback: Callable) -> void:
	var position := city_origin + _array_to_vector3(building_data["position"])
	var size := _array_to_vector3(building_data["size"])
	var texture := TEX_MEDICAL_WARD if building_name.contains("Medical") else TEX_HOUSE
	var width := size.x * (1.08 if building_name.contains("Medical") else 1.15)
	var building_art := _add_world_billboard(building_name, position, texture, width, 0.0)
	_register_sortable_object(building_art, building_name + "SortRoot", position, building_art.global_position, float(building_art.texture.get_height()) * building_art.pixel_size, float(building_data.get("sort_offset_y", 0.0)))
	_add_building_collision(building_name+"Collision",position,size,"medical_ward" if building_name.contains("Medical") else "house")
	_build_building_door_warp(building_art, building_name + "Door", city_origin + _array_to_vector3(building_data["door"]), callback, Vector3(1.5, 0.3, 0.9))


func _build_city_room(room_data: Dictionary, prefix: String, floor_color: Color, door_color: Color, callback: Callable) -> void:
	var origin := _array_to_vector3(room_data["origin"])
	var size: Array = room_data["interior_size"]
	_add_map_blocks(origin, room_data.get("floor_blocks", [[0, -0.1, 0, size[0], 0.2, size[1]]]), prefix + "Floor", TEX_INTERIOR_FLOOR, floor_color, false)
	_add_map_blocks(origin, room_data.get("wall_blocks", _room_wall_blocks(size)), prefix + "Wall", TEX_WALL_GENERIC, floor_color.darkened(0.18), true)
	_build_colored_warp(prefix + "ExitDoor", origin + _array_to_vector3(room_data["exit_door"]), callback, door_color)
	_add_room_furnishings(origin, size, prefix, room_data.get("furnishings", []))
	_build_universal_objects(room_data, origin, prefix)


func _add_room_furnishings(origin: Vector3, room_size: Array, prefix: String, serialized:Array=[]) -> void:
	if not serialized.is_empty():
		_add_serialized_furnishings(origin,serialized,prefix);return
	var half_width := float(room_size[0]) * 0.5
	var half_depth := float(room_size[1]) * 0.5
	if prefix == "OrchidHome":
		_add_serialized_furnishings(origin, [{"type":"hutch","position":[-half_width+0.9,0,-half_depth+0.9],"height":2.0},{"type":"table","position":[1.3,0,0.5],"height":1.3},{"type":"houseplant_1","position":[half_width-0.8,0,-half_depth+0.8],"height":1.05}], prefix)
	elif prefix == "FamilyHome":
		_add_serialized_furnishings(origin, [{"type":"bed","position":[-half_width+1.0,0,-half_depth+1.2],"height":2.4},{"type":"dresser","position":[half_width-0.9,0,-half_depth+0.9],"height":2.2},{"type":"lampstand","position":[half_width-0.8,0,1.5],"height":1.0},{"type":"table","position":[0,0,0.4],"height":1.35}], prefix)

func _furnishing_texture(type:String)->Texture2D:
	match type:
		"bed":return TEX_BED
		"dresser":return TEX_DRESSER
		"hutch":return TEX_HUTCH
		"lampstand":return TEX_LAMPSTAND
		"table":return TEX_TABLE
		"houseplant_1":return TEX_HOUSEPLANT_ONE
		"houseplant_2":return TEX_HOUSEPLANT_TWO
		"ward_counter":return TEX_WARD_COUNTER
		"ward_shelf":return TEX_WARD_SHELF
		"ward_table":return TEX_WARD_TABLE
		"ward_curtain":return TEX_WARD_CURTAIN
		"ward_wash":return TEX_WARD_WASH
	return null

func _add_serialized_furnishings(origin:Vector3, furnishings:Array, prefix:String)->void:
	for index in furnishings.size():
		var item:Variant=furnishings[index];if not item is Dictionary:continue
		var furnishing_type := String(item.get("type", ""))
		var texture:=_furnishing_texture(furnishing_type);var position:Variant=item.get("position",[])
		if texture==null or not position is Array or position.size()<3:continue
		var furnishing_name := "%sFurnishing%d" % [prefix, index]
		var furnishing_position := origin + _array_to_vector3(position)
		_add_prop_billboard(furnishing_name, furnishing_position, texture, float(item.get("height", 1.0)))
		object_sort_entries[-1]["furnishing_type"] = furnishing_type
		var footprint := _furnishing_footprint(furnishing_type)
		var serialized_footprint: Variant = item.get("footprint", [])
		if serialized_footprint is Array and serialized_footprint.size() >= 2:
			footprint = Vector2(float(serialized_footprint[0]), float(serialized_footprint[1]))
		if footprint != Vector2.ZERO:
			_add_static_collision(furnishing_name + "Collision", furnishing_position + Vector3(0.0, 0.45, 0.0), Vector3(footprint.x, 0.9, footprint.y))


func _furnishing_footprint(furnishing_type: String) -> Vector2:
	match furnishing_type:
		"bed": return Vector2(1.1, 1.75)
		"dresser": return Vector2(1.0, 0.75)
		"hutch": return Vector2(0.9, 0.7)
		"lampstand": return Vector2(0.45, 0.45)
		"table": return Vector2(1.45, 0.95)
		"houseplant_1", "houseplant_2": return Vector2(0.55, 0.55)
		"ward_counter": return Vector2(2.0, 0.75)
		"ward_shelf": return Vector2(0.8, 0.65)
		"ward_table": return Vector2(1.05, 0.8)
		"ward_curtain": return Vector2(0.8, 0.7)
		"ward_wash": return Vector2(0.75, 0.65)
	return Vector2.ZERO


func _build_colored_warp(warp_name: String, position: Vector3, callback: Callable, color: Color, show_sprite: Variant = null, sprite: String = "") -> void:
	var warp := Area3D.new()
	warp.name = warp_name
	warp.position = position
	var size := Vector3(1.5, 0.3, 0.9)
	warp.add_child(_box_shape(size))
	if show_sprite == null: show_sprite = _warp_sprite_visible_at(position)
	if show_sprite: _add_warp_rug_visual(warp, size.x, sprite if not sprite.is_empty() else _warp_sprite_at(position))
	warp.body_entered.connect(callback)
	world.add_child(warp)


func _add_talking_npc(npc_name: String, position: Vector3, color: Color, speaker: String, pages: Array, after_dialogue := Callable(), sprite_id:String="", patrol_spawn: bool = false) -> Area3D:
	var npc := Area3D.new()
	npc.name = npc_name
	npc.position = position
	var texture:=NpcSpriteLibrary.texture_for(sprite_id) if not sprite_id.is_empty() else null
	var visual_height:=NPC_CHILD_VISUAL_HEIGHT if sprite_id in ["boy", "girl"] else NPC_ADULT_VISUAL_HEIGHT
	var visual:=_billboard_sprite(texture,visual_height,speaker+"Sprite") if texture!=null else _square_sprite(color,speaker,Vector2(0.8,1.05))
	visual.offset=Vector2(0.0,float(texture.get_height())*0.5) if texture!=null else visual.offset
	npc.add_child(visual)
	npc.set_meta("sprite_id",sprite_id)
	npc.set_meta("facing","down")
	npc.set_meta("visual_height",visual_height)
	npc.add_child(_box_shape(Vector3(0.8, 1.1, 0.8)))
	npc.add_child(_npc_foot_body())
	if patrol_spawn: npc.set_meta("patrol_spawn", true)
	world.add_child(npc)
	npc_sort_entries.append({"node": npc, "visual": visual, "height": visual_height, "name": npc_name + "SortRoot"})
	npc_dialogues[npc.get_instance_id()] = {"speaker": speaker, "pages": pages, "after_dialogue": after_dialogue}
	return npc


func _build_trainers(trainers: Array, map_origin: Vector3, prefix: String) -> void:
	for index in trainers.size():
		var placement:Dictionary=trainers[index]
		var trainer: Dictionary = _resolved_trainer(placement)
		var party_indices: Array = trainer.get("team",trainer.get("party", [int(trainer.get("fakemon_index", 0))]))
		var trainer_name := String(trainer.get("name", "RAIN FOREST TRAINER"))
		var dialogue: Array = trainer.get("dialogue", ["My Fakemon and I are ready for a friendly battle!"])
		var npc := _add_talking_npc("%sTrainer%d" % [prefix, index + 1], map_origin + _array_to_vector3(placement["position"]), Color(String(trainer.get("color", "df6d5f"))), trainer_name.to_upper(), dialogue, _begin_trainer_battle.bind(party_indices), String(trainer.get("sprite","")))

func _resolved_trainer(placement:Dictionary)->Dictionary:
	var trainer_id:=String(placement.get("trainer_id",""))
	if not trainer_id.is_empty() and trainer_catalog.get(trainer_id) is Dictionary:
		# Editor placements own their map-only fields (such as position), while the
		# catalog remains authoritative for the reusable trainer definition.  This
		# also keeps pre-catalog, inline trainer records working unchanged below.
		var resolved:Dictionary=placement.duplicate(true)
		resolved.merge((trainer_catalog[trainer_id] as Dictionary).duplicate(true),true)
		resolved["trainer_id"]=trainer_id
		return resolved
	return placement


func _begin_trainer_battle(team: Array) -> void:
	if team.is_empty() or in_battle:
		return
	active_battle_is_wild = false
	if team[0] is Dictionary:
		var enemies := _build_trainer_team(team)
		if not enemies.is_empty():_open_battle(0, [], enemies)
	else:
		_open_battle(int(team[0]), team)

func _build_trainer_team(team:Array)->Array[Dictionary]:
	var enemies:Array[Dictionary]=[]
	for member:Variant in team:
		if not member is Dictionary:continue
		var reference:Variant=member.get("fakemon",0);var species_index:=int(reference) if reference is int or reference is float or String(reference).is_valid_int() else -1
		if species_index<0:
			for index in battle.battle_data["fakemon"].size():
				if String(battle.battle_data["fakemon"][index].get("name","")).to_lower()==String(reference).to_lower():species_index=index;break
		if species_index<0 or species_index>=battle.battle_data["fakemon"].size():continue
		var species: Dictionary = battle.battle_data["fakemon"][species_index]
		var enemy_level := clampi(int(member.get("level", species.get("level", 5))), 1, 100)
		var enemy: Dictionary = battle.create_fakemon(species, enemy_level)
		enemy["experience"] = int(pow(float(enemy_level), 3.0))
		enemy["current_hp"] = int(enemy["max_hp"])
		enemies.append(enemy)
	return enemies


func _heal_party_at_ward() -> void:
	for mon: Dictionary in party:
		mon["current_hp"] = int(mon["max_hp"])
		mon["condition"] = ""
		mon["condition_turns"] = 0
	_refresh_party_menu()
	hint_label.text = "Your party was restored to full health."
	_auto_save()


func _add_small_orchid(position: Vector3) -> void:
	_add_prop_billboard("GroundOrchidBloom", position, TEX_FLOWER_ORCHID_POT, 0.72)


func _build_forest_warp(warp_name: String, warp_position: Vector3, callback: Callable, facing: String, show_sprite: Variant = null) -> void:
	var warp := Area3D.new()
	warp.name = warp_name
	warp.position = warp_position
	var warp_size := Vector3(2.2, 0.4, 1.2)
	warp.add_child(_box_shape(warp_size))
	warp.body_entered.connect(callback)
	world.add_child(warp)
	if show_sprite == null: show_sprite = _warp_sprite_visible_at(warp_position)
	if show_sprite:
		var texture := TEX_WARP_EAST if facing == "east" else (TEX_WARP_WEST if facing == "west" else (TEX_WARP_GENERIC if facing == "generic" else TEX_WARP_NORTH))
		var visual_height := 1.75 if facing == "north" else 2.1
		var visual := _billboard_sprite(texture, visual_height, "OutdoorWarpArt_%s" % facing.capitalize())
		visual.position = Vector3(0, visual_height * 0.5, -0.08)
		warp.add_child(visual)
		_register_sortable_object(visual, warp_name + "SortRoot", warp_position, visual.global_position, visual_height, 0.0)


func _warp_sprite_at(position: Vector3) -> String:
	for data: Dictionary in Dictionary(map_data.get("_map_files", {})).values():
		var origin := _array_to_vector3(data.get("origin", [0, 0, 0]))
		for field: String in Dictionary(data.get("warp_metadata", {})):
			var point: Variant = data.get(field, [])
			if point is Array and point.size() >= 3 and (origin + _array_to_vector3(point)).is_equal_approx(position):
				return String(data.warp_metadata[field].get("sprite", WarpSpriteCatalog.DEFAULT))
	return WarpSpriteCatalog.DEFAULT


func _warp_sprite_visible_at(position: Vector3) -> bool:
	for data: Dictionary in Dictionary(map_data.get("_map_files", {})).values():
		var origin := _array_to_vector3(data.get("origin", [0, 0, 0]))
		for field: String in Dictionary(data.get("warp_metadata", {})):
			var point: Variant = data.get(field, [])
			if point is Array and point.size() >= 3 and (origin + _array_to_vector3(point)).is_equal_approx(position):
				return bool(data.warp_metadata[field].get("show_sprite", false))
	return false


func _build_editor_authored_warps() -> void:
	var map_files: Variant = map_data.get("_map_files", {})
	if not map_files is Dictionary:
		return
	for filename: Variant in map_files:
		var authored_map: Variant = map_files[filename]
		if not authored_map is Dictionary:
			continue
		var metadata: Variant = authored_map.get("warp_metadata", {})
		if not metadata is Dictionary:
			continue
		var origin := _array_to_vector3(authored_map.get("origin", [0, 0, 0]))
		for field: Variant in metadata:
			var field_name := String(field)
			# Legacy named warps are already built by their established gameplay code.
			var is_authored_file:bool=Dictionary(map_data.get("_authored_file_ids",{})).has(String(filename))
			if not is_authored_file and not field_name.begins_with("warp_"):
				continue
			var position: Variant = authored_map.get(field_name, [])
			if not position is Array or position.size() < 3:
				continue
			var record: Variant = metadata[field]
			if not record is Dictionary:
				continue
			var node_name := "EditorWarp_%s_%s" % [String(filename).get_basename().validate_node_name(), field_name.validate_node_name()]
			var first_world_child := world.get_child_count()
			var first_sort_entry:=object_sort_entries.size()
			var callback := _on_editor_authored_warp_entered.bind(String(filename), field_name, record)
			var is_indoor:=_is_authored_indoor_map(authored_map) or _location_for_map_file(String(filename)) in ["medical_ward","house","city_ward","orchid_house","family_house"]
			if is_indoor:_build_colored_warp(node_name,origin+_array_to_vector3(position),callback,Color.WHITE, bool(record.get("show_sprite", false)), String(record.get("sprite", WarpSpriteCatalog.DEFAULT)))
			else:_build_forest_warp(node_name, origin + _array_to_vector3(position), callback, String(record.get("facing", "generic")), bool(record.get("show_sprite", false)))
			var authored_id := String(Dictionary(map_data.get("_authored_file_ids", {})).get(String(filename), ""))
			if not authored_id.is_empty():
				var layer := _active_visual_layer("authored:" + authored_id)
				for index in range(first_world_child, world.get_child_count()): _assign_visual_region(world.get_child(index), layer)
				for index in range(first_sort_entry, object_sort_entries.size()): object_sort_entries[index]["visual_layer"] = layer


func _is_authored_indoor_map(data:Dictionary)->bool:
	return String(data.get("map_metadata",{}).get("layout_type","outdoor")) in ["indoor","interior"]


func _build_authored_maps() -> void:
	authored_visual_regions.clear()
	var next_layer := 12
	for map_id: Variant in map_data.get("authored_maps", {}):
		var authored: Variant = map_data.authored_maps[map_id]
		if not authored is Dictionary:
			continue
		var indoors:=_is_authored_indoor_map(authored)
		if not indoors and String(authored.get("map_metadata",{}).get("layout_type","outdoor"))!="outdoor":continue
		var origin:=_array_to_vector3(authored.get("origin",[0,0,0]));var size:Variant=authored.get("size",authored.get("interior_size",[20,20]));var map_layer:=next_layer
		var first_world_child:=world.get_child_count()
		var first_surface := traversal_surfaces.size()
		var first_tree:=tree_sort_entries.size();var first_object:=object_sort_entries.size();var first_overlay:=overlay_sort_entries.size();var first_background:=background_object_sort_entries.size();var first_npc:=npc_sort_entries.size();var first_bridge:=bridge_sort_entries.size()
		if size is Array and size.size()>=2:
			authored_visual_regions.append({"id":String(map_id),"origin":origin+MapBounds.offset(authored),"size":Vector2(float(size[0]),float(size[1])),"layer":next_layer})
			next_layer += 1
		if size is Array and size.size()>=2:
			var ground_texture:=TerrainTransitionTextureCache.base_texture(String(authored.get("base_terrain_type","indoor_floor_tile" if indoors else "forest_floor")))
			if indoors:
				var ground:=MeshInstance3D.new()
				ground.name="AuthoredMap_%s_Ground"%String(map_id).validate_node_name()
				var plane:=PlaneMesh.new();plane.size=Vector2(float(size[0]),float(size[1]));ground.mesh=plane
				ground.position=origin+MapBounds.offset(authored)+Vector3(0,0.4,0)
				var material:=_textured_material(ground_texture if ground_texture!=null else TEX_GRASS,Color.WHITE,Vector3(plane.size.x,plane.size.y,1))
				# Canonical cells are centered on integer coordinates, not the map edge.
				var phase:=MapBounds.rect(authored).position+Vector2.ONE*0.5
				material.uv1_offset=Vector3(phase.x,phase.y,0)
				ground.material_override=material;ground.add_to_group("day_night_terrain");world.add_child(ground)
			else:
				_add_textured_block("AuthoredMap_%s_Ground"%String(map_id).validate_node_name(),origin+MapBounds.offset(authored)+Vector3(0,-0.1,0),Vector3(float(size[0]),0.2,float(size[1])),ground_texture if ground_texture!=null else TEX_GRASS,Color.WHITE,false)
		if indoors:
			var room_prefix:="AuthoredMap_"+String(map_id).to_pascal_case()
			_add_map_blocks(origin,authored.get("floor_blocks",[]),room_prefix+"Floor",TEX_INTERIOR_FLOOR,Color.WHITE,false)
			_add_map_blocks(origin,authored.get("wall_blocks",[]),room_prefix+"Wall",TEX_WALL_GENERIC,Color.WHITE,true)
			_add_serialized_furnishings(origin,authored.get("furnishings",[]),room_prefix)
		_build_outdoor_terrain_assets(authored,origin,"AuthoredMap_"+String(map_id).to_pascal_case())
		# _build_outdoor_terrain_assets already builds universal objects, including
		# their art and collision. A second call hides platform actors under a copy.
		_build_trainers(authored.get("trainers",[]),origin,"AuthoredMap_"+String(map_id).to_pascal_case())
		for index in range(first_tree,tree_sort_entries.size()):tree_sort_entries[index]["visual_layer"]=map_layer
		for index in range(first_object,object_sort_entries.size()):
			var entry := object_sort_entries[index]
			entry["visual_layer"] = map_layer
			if String(map_id) == "challenger_center_jalvoea_city" and entry.has("habitat_exhibit"):
				exhibits.register(entry, authored, map_layer)
		for index in range(first_overlay,overlay_sort_entries.size()):overlay_sort_entries[index]["visual_layer"]=map_layer
		for index in range(first_background,background_object_sort_entries.size()):background_object_sort_entries[index]["visual_layer"]=map_layer
		for index in range(first_npc,npc_sort_entries.size()):npc_sort_entries[index]["visual_layer"]=map_layer
		var npc_map_file := _water_surface_key(authored,"AuthoredMap_"+String(map_id).to_pascal_case())
		if npc_water_surfaces.has(npc_map_file): npc_water_surfaces[npc_map_file]["visual_layer"] = map_layer
		for index in range(first_bridge,bridge_sort_entries.size()):bridge_sort_entries[index]["visual_layer"]=map_layer
		for index in range(first_surface,traversal_surfaces.size()):traversal_surfaces[index]["visual_layer"]=map_layer
		for index in range(first_world_child,world.get_child_count()):_assign_visual_region(world.get_child(index),map_layer)


func _on_editor_authored_warp_entered(body: Node3D, _source_file: String, _source_field: String, record: Dictionary) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	if _current_location() != _location_for_map_file(_source_file):
		return
	# Reserve the transition now; change Area3D monitoring after physics signals finish.
	door_warp_ready = false
	_complete_editor_authored_warp.call_deferred(record)


func _complete_editor_authored_warp(record: Dictionary) -> void:
	door_warp_ready = true
	var target_file := String(record.get("entrance_map", "")); var target_id := int(record.get("entrance_map_warp_id", 0))
	target_file = MapDataLoader.instance_file(target_file, String(record.get("entrance_instance_id", "")))
	var map_files: Dictionary = map_data.get("_map_files", {})
	var target: Variant = map_files.get(target_file, {})
	if not target is Dictionary or target_id < 1:
		return
	var target_field := MapDataLoader.warp_field_for_id(target, target_id)
	var target_position: Variant = target.get(target_field, [])
	if target_field.is_empty() or not target_position is Array or target_position.size() < 3:
		return
	var location := _location_for_map_file(target_file)
	if location.is_empty():
		push_warning("Editor warp destination is not a playable map: %s" % target_file)
		return
	var title := String(target.get("map_metadata", target.get("index_metadata", {})).get("display_name", target_file.get_basename().replace("_", " ").to_upper()))
	_set_route_location(location, _array_to_vector3(target.get("origin", [0, 0, 0])) + _array_to_vector3(target_position), title, "Travelled through warp %d." % target_id)


func _location_for_map_file(filename: String) -> String:
	var authored_ids: Dictionary = map_data.get("_authored_file_ids", {})
	if authored_ids.has(filename): return "authored:" + String(authored_ids[filename])
	match filename:
		"rainforest_clearing.json": return "rainforest"
		"canopy_route.json": return "route"
		"eastern_rainforest_route.json": return "east_route"
		"western_rainforest_route.json": return "west_route"
		"vinestone_cave.json": return "east_cave"
		"mossvale_city.json": return "city"
		"rainforest_medical_ward.json": return "medical_ward"
		"rainforest_house.json": return "house"
		"mossvale_medical_ward.json": return "city_ward"
		"mossvale_orchid_house.json": return "orchid_house"
		"mossvale_family_house.json": return "family_house"
	return ""


func _add_tree(tree_anchor: Vector3, variant: int, prefix: String, sort_offset_y: float = 0.0, authored_height:float=-1.0,instance_id:String="") -> void:
	var texture := TEX_TREE_MAIN if variant == 0 else TEX_TREE_PALM
	var tree_height := authored_height if authored_height>0 else (4.2 if variant == 0 else 3.8)
	var tree := _add_tree_billboard("%sCanopyArt" % prefix, tree_anchor, texture, texture.get_width() * tree_height / texture.get_height())
	tree.visible = false
	tree_sort_entries.append({"name": "%sTreeSortRoot_%d" % [prefix, tree.get_instance_id()], "placement": tree_anchor, "texture": texture, "height": tree_height, "sort_offset_y": sort_offset_y,"instance_id":instance_id})
	var tree_index := tree.get_instance_id()
	_add_static_collision("%sTreeTrunkCollision_%d" % [prefix, tree_index], Vector3(tree_anchor.x, 0.75, tree_anchor.z), Vector3(0.9, 1.5, 0.9))


func _add_colored_block(block_name: String, block_position: Vector3, block_size: Vector3, color: Color, solid: bool) -> void:
	var visual := MeshInstance3D.new()
	visual.name = block_name
	var mesh := BoxMesh.new()
	mesh.size = block_size
	visual.mesh = mesh
	visual.position = block_position
	visual.material_override = _material(color)
	world.add_child(visual)
	if solid:
		_add_static_collision(block_name + "Collision", block_position, block_size)


func _add_textured_block(block_name: String, block_position: Vector3, block_size: Vector3, texture: Texture2D, color: Color, solid: bool, collision_layer: int = 1) -> void:
	var visual := MeshInstance3D.new()
	visual.name = block_name
	var mesh := BoxMesh.new()
	mesh.size = block_size
	visual.mesh = mesh
	visual.position = block_position
	visual.material_override = _textured_material(texture, color, Vector3(maxf(block_size.x, 1.0), maxf(block_size.z, 1.0), 1.0))
	visual.add_to_group("day_night_terrain")
	world.add_child(visual)
	if solid:
		_add_static_collision(block_name + "Collision", block_position, block_size, collision_layer)

func _add_water_shape_tile(tile_name:String,ground_position:Vector3,tile_size:Vector3,texture:Texture2D,rotation_degrees:float,asset_path:String="")->void:
	var visual:=Sprite3D.new();visual.add_to_group("day_night_world_sprites");visual.name=tile_name;visual.texture=texture;visual.billboard=BaseMaterial3D.BILLBOARD_DISABLED;visual.alpha_cut=SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS;visual.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
	visual.pixel_size=tile_size.z/maxf(float(texture.get_height()),1.0);visual.scale.x=tile_size.x/(maxf(float(texture.get_width()),1.0)*visual.pixel_size);visual.rotation_degrees=Vector3(-90.0,rotation_degrees,0.0);visual.position=ground_position+Vector3(0,maxf(tile_size.y*0.5,0.02),0);visual.set_meta("water_terrain_tile",true);world.add_child(visual)
	if not _add_asset_polygon_collision(tile_name,ground_position,tile_size,rotation_degrees,asset_path):
		var body:=StaticBody3D.new();body.name=tile_name+"Collision";body.position=Vector3(ground_position.x,1.0,ground_position.z);body.rotation.y=deg_to_rad(rotation_degrees);body.collision_layer=TERRAIN_OBSTACLE_LAYER;body.collision_mask=1;body.add_child(_box_shape(Vector3(tile_size.x,2.0,tile_size.z)));world.add_child(body)


func _add_map_blocks(origin: Vector3, blocks: Array, block_name: String, texture: Texture2D, color: Color, solid: bool) -> void:
	for index in blocks.size():
		var block: Array = blocks[index]
		if block.size() < 6:
			continue
		var name := block_name if blocks.size() == 1 else "%s_%d" % [block_name, index]
		var wall:=texture==TEX_WALL_GENERIC and solid
		_add_textured_block(name, origin + Vector3(float(block[0]), float(block[1]), float(block[2])), Vector3(float(block[3]), float(block[4]), float(block[5])), texture, color, solid and not wall)
		if wall:
			var collider:Dictionary=block[6] if block.size()>6 and block[6] is Dictionary else {}
			if bool(collider.get("enabled",true)):
				var offset:=_array_to_vector3(collider.get("offset",[0,0,0]))
				var collision_size:=_array_to_vector3(collider.get("size",[block[3],block[4],block[5]]))
				_add_static_collision(name+"Collision",origin+Vector3(float(block[0]),float(block[1]),float(block[2]))+offset,collision_size)
		if texture==TEX_WALL_GENERIC and solid:
			# Wall art uses the editor's ground footprint; Y remains collision data.
			var visual:=world.get_node(NodePath(name)) as MeshInstance3D
			visual.hide()
			var placement:=origin+Vector3(float(block[0]),0,float(block[2]))
			object_sort_entries.append({"name":name+"SortRoot","placement":placement,"visual_center":placement,"texture":texture,"height":float(block[5]),"wall_size":Vector2(float(block[3]),float(block[5]))})


func _room_wall_blocks(room_size: Array) -> Array:
	var width := float(room_size[0])
	var depth := float(room_size[1])
	return [[0, 1.2, -depth * 0.5 + 0.15, width, 2.4, 0.3], [-width * 0.5 + 0.15, 1.2, 0, 0.3, 2.4, depth], [width * 0.5 - 0.15, 1.2, 0, 0.3, 2.4, depth]]


func _add_prop_billboard(prop_name: String, ground_position: Vector3, texture: Texture2D, height: float,instance_id:String="") -> Sprite3D:
	var sprite := _billboard_sprite(texture, height, prop_name)
	sprite.position = Vector3(ground_position.x, height * 0.5, ground_position.z)
	world.add_child(sprite)
	# Props share the player's generated Y-sort tree.  Their placement and collision
	# remain unchanged; the visual root is placed at ground level so furniture can
	# properly cover a player behind it and uncover one standing in front.
	_register_sortable_object(sprite, prop_name + "SortRoot", ground_position, sprite.global_position, height,0.0,Rect2(),instance_id)
	return sprite


func _add_world_billboard(sprite_name: String, anchor: Vector3, texture: Texture2D, width: float, z_offset: float) -> Sprite3D:
	var height := width * float(texture.get_height()) / float(texture.get_width())
	var sprite := _billboard_sprite(texture, height, sprite_name)
	sprite.position = Vector3(anchor.x, height * 0.5, anchor.z + z_offset)
	world.add_child(sprite)
	return sprite


func _add_tree_billboard(sprite_name: String, trunk_contact: Vector3, texture: Texture2D, width: float) -> Sprite3D:
	var height := width * float(texture.get_height()) / float(texture.get_width())
	var sprite := _billboard_sprite(texture, height, sprite_name)
	sprite.position = Vector3(trunk_contact.x, height * 0.5, trunk_contact.z)
	world.add_child(sprite)
	return sprite


func _register_sortable_object(source: Sprite3D, node_name: String, placement: Vector3, visual_center: Vector3, visual_height: float, sort_offset_y: float = 0.0, source_crop: Rect2 = Rect2(),instance_id:String="") -> void:
	source.visible = false
	object_sort_entries.append({"name": node_name, "placement": placement, "visual_center": visual_center, "texture": source.texture, "height": visual_height, "sort_offset_y": sort_offset_y, "source_crop": source_crop,"instance_id":instance_id})
	var metadata := _overworld_asset_metadata(source.texture.resource_path)
	object_sort_entries[-1]["render_band"]=int(metadata.get("render_band",0))
	object_sort_entries[-1]["sort_offset_y"]+=preload("res://world/building_sorting.gd").offset(source.texture.resource_path,metadata) if is_zero_approx(sort_offset_y) else float(metadata.get("sort_offset_y",0.0))
	object_sort_entries[-1]["wall_overlay"]=bool(metadata.get("wall_overlay",false))
	object_sort_entries[-1]["light_source"] = bool(metadata.get("light_source", false))
	object_sort_entries[-1]["light_strength"] = float(metadata.get("light_strength", 0.5))


func _register_overlay_object(source:Sprite3D,node_name:String,placement:Vector3,visual_center:Vector3,visual_height:float,rotation_degrees:float,render_band:int=0)->void:
	source.visible=false
	overlay_sort_entries.append({"name":node_name,"placement":placement,"visual_center":visual_center,"texture":source.texture,"height":visual_height,"rotation_degrees":rotation_degrees,"render_band":render_band})


func _register_background_object(source: Sprite3D, node_name: String, placement: Vector3, visual_center: Vector3, visual_height: float,instance_id:String="") -> void:
	source.visible = false
	background_object_sort_entries.append({"name":node_name, "placement":placement, "visual_center":visual_center, "texture":source.texture, "height":visual_height,"instance_id":instance_id})


func _build_sort_canvas() -> void:
	static_art_view_signature=[]
	sort_canvas = CanvasLayer.new()
	sort_canvas.name = "WorldSortCanvas"
	sort_canvas.layer = 0
	add_child(sort_canvas)
	sort_root = Node2D.new()
	sort_root.name = "WorldYSortRoot"
	sort_root.y_sort_enabled = true
	sort_canvas.add_child(sort_root)
	_attach_sorted_world_entries()
	_warn_platform_overlaps()
	_update_sort_canvas()


func _attach_sorted_world_entries() -> void:
	for entry: Dictionary in tree_sort_entries:
		if entry.has("sort_root"): continue
		entry["sort_root"] = _create_sorted_sprite(String(entry["name"]), entry["texture"])
	for entry: Dictionary in object_sort_entries:
		if entry.has("sort_root"): continue
		entry["sort_root"] = _create_sorted_sprite(String(entry["name"]), entry["texture"])
		(entry.sort_root as CanvasItem).z_index=int(entry.get("render_band",0))
		if entry.has("wall_size"):
			var art:Sprite2D=entry.sort_root.get_node("Visual")
			art.texture_repeat=CanvasItem.TEXTURE_REPEAT_ENABLED
			art.region_enabled=true
			art.region_rect=Rect2(Vector2.ZERO,entry.texture.get_size()*entry.wall_size)
		_configure_sorted_region(entry["sort_root"] as Node2D, entry.get("source_crop", Rect2()))
		if entry.has("foreground_masks"):
			entry["platform_layers"] = preload("res://world/platform_art_layers.gd").build(entry.sort_root,entry.texture,entry.foreground_masks,entry.get("foreground_depth_lines",[]))
	for entry:Dictionary in overlay_sort_entries:
		if entry.has("sort_root"): continue
		entry["sort_root"]=_create_sorted_sprite(String(entry.name),entry.texture)
		(entry.sort_root as Node2D).rotation_degrees=float(entry.get("rotation_degrees",0.0))
		(entry.sort_root as CanvasItem).z_index=int(entry.get("render_band",0))
	if player_sort_root == null:
		player_sort_root = _create_sorted_sprite("PlayerSortRoot", player_sprite.texture)
		follower_sort_root = _create_sorted_sprite("FollowerSortRoot", follower_sprite.texture)
		player_sprite.visible = false
		follower_sprite.visible = false
	for entry: Dictionary in background_object_sort_entries:
		if entry.has("sort_root"): continue
		entry["sort_root"] = _create_sorted_sprite(String(entry["name"]), entry["texture"])
		(entry["sort_root"] as CanvasItem).z_index = -10
	var hosts:Dictionary={}
	for collection:Array in [tree_sort_entries,object_sort_entries,background_object_sort_entries]:
		for entry:Dictionary in collection:
			if not String(entry.get("instance_id","")).is_empty():hosts[String(entry.instance_id)]=entry
	attached_overlay_entries.sort_custom(func(a,b):return int(a.get("attachment_order",0))<int(b.get("attachment_order",0)) if String(a.get("host_id",""))==String(b.get("host_id","")) else String(a.get("host_id",""))<String(b.get("host_id","")))
	for entry:Dictionary in attached_overlay_entries:
		if entry.has("pivot") or entry.get("fallback_built", false): continue
		var host:Dictionary=hosts.get(String(entry.get("host_id","")),{})
		if host.is_empty():
			entry["fallback_built"] = true
			var fallback_root:=_create_sorted_sprite(String(entry.name)+"Fallback",entry.texture);fallback_root.rotation_degrees=float(entry.get("rotation_degrees",0.0));overlay_sort_entries.append({"name":String(entry.name)+"Fallback","placement":entry.fallback_position,"visual_center":entry.fallback_position+Vector3(0,float(entry.height)*0.5,0),"texture":entry.texture,"height":entry.height,"rotation_degrees":entry.rotation_degrees,"sort_root":fallback_root,"visual_layer":entry.get("visual_layer",_visual_layer_for_position(entry.fallback_position))});entry["fallback_entry"] = overlay_sort_entries[-1];continue
		var overhang:float=(entry.local_position as Vector2).length()+float(entry.height)*(1.0+float(entry.texture.get_width())/maxf(float(entry.texture.get_height()),1))
		host["static_overhang"]=maxf(float(host.get("static_overhang",0)),overhang)
		var pivot:=Node2D.new();pivot.name=String(entry.name);pivot.rotation_degrees=float(entry.get("rotation_degrees",0.0))
		var art:=Sprite2D.new();art.name="Visual";art.texture=entry.texture;art.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;pivot.add_child(art);(host.sort_root as Node2D).add_child(pivot);entry["host_entry"]=host;entry["pivot"]=pivot;entry["visual"]=art
	for entry: Dictionary in npc_sort_entries:
		if entry.has("sort_root"): continue
		var npc_visual := entry["visual"] as Sprite3D
		if not entry.has("visual_layer"):entry["visual_layer"] = _visual_layer_for_position((entry["node"] as Area3D).global_position)
		entry["sort_root"] = _create_sorted_sprite(String(entry["name"]), npc_visual.texture)
		npc_visual.hide()
	for entry: Dictionary in bridge_sort_entries:
		if entry.has("sort_root"): continue
		entry["sort_root"] = _create_sorted_sprite(String(entry["name"]), entry["texture"])
		(entry["sort_root"] as CanvasItem).z_index = 5

func _create_sorted_sprite(node_name: String, texture: Texture2D) -> Node2D:
	var sort_point := Node2D.new()
	sort_point.name = node_name
	var art := Sprite2D.new()
	art.name = "Visual"
	art.texture = texture
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sort_point.add_child(art)
	sort_root.add_child(sort_point)
	return sort_point


func _configure_sorted_region(sort_point: Node2D, source_crop: Rect2) -> void:
	if source_crop.size.is_zero_approx():
		return
	var visual := sort_point.get_node("Visual") as Sprite2D
	visual.region_enabled = true
	visual.region_rect = source_crop

func _update_sort_canvas() -> void:
	if camera == null or sort_root == null:
		return
	var pixels_per_world_unit := get_viewport().get_visible_rect().size.y / camera.size
	var projection_signature:Array=preload("res://world/terrain_camera_view.gd").signature(camera)
	if camera.projection==Camera3D.PROJECTION_ORTHOGONAL:projection_signature[1]=camera.global_basis
	var projection_origin:=camera.unproject_position(Vector3.ZERO)
	var static_cache:=preload("res://world/static_art_projection_cache.gd")
	var active_visual_layer := _active_visual_layer()
	_update_map_borders(active_visual_layer)
	OverworldTextureAnimation.update_visibility(camera,active_visual_layer)
	var player_feet := Vector3(player.global_position.x, 0.0, player.global_position.z)
	var contact_elevation := minf(0.0, player.global_position.y - PLAYER_GROUND_HEIGHT) if not swimming and not swim_transitioning else 0.0
	_update_sorted_art(player_sort_root, player_feet, player.global_position, SWIM_VISUAL_HEIGHT if swimming else PLAYER_VISUAL_HEIGHT, pixels_per_world_unit, contact_elevation)
	if not swimming and not swim_transitioning:
		_apply_player_frame_adjustment(pixels_per_world_unit)
	if swim_transitioning:
		(player_sort_root.get_node("Visual") as Sprite2D).position.y -= swim_jump_height * pixels_per_world_unit
	if swim_transition_effect_root != null and swim_transition_effect_root.visible:
		_update_sorted_art(swim_transition_effect_root, swim_transition_effect_position, swim_transition_effect_position, swim_transition_effect_height, pixels_per_world_unit)
	var follower_feet:=Vector3(follower.global_position.x,0.0,follower.global_position.z)
	follower_sort_root.visible=follower.visible
	if follower.visible:
		_update_sorted_art(follower_sort_root, follower_feet, follower.global_position, 0.9 * follower_sprite.scale.y, pixels_per_world_unit, contact_elevation)
	for entry: Dictionary in npc_sort_entries:
		var npc := entry["node"] as Area3D
		var npc_visual := entry["visual"] as Sprite3D
		var npc_sort := entry["sort_root"] as Node2D
		npc_sort.visible = int(entry["visual_layer"]) == active_visual_layer and not script_host.sprite_hidden(npc)
		if not npc_sort.visible:
			continue
		var art := npc_sort.get_node("Visual") as Sprite2D
		if art.texture != npc_visual.texture:
			art.texture = npc_visual.texture
		var feet := Vector3(npc.global_position.x, 0.0, npc.global_position.z)
		feet = _npc_bed_sort_position(npc, feet)
		var center := npc.global_position + Vector3(0.0, float(entry["height"]) * 0.5, 0.0)
		_update_sorted_art(npc_sort, feet, center, float(entry["height"]), pixels_per_world_unit)
		if npc.has_meta("movement_mode"):
			art.position = camera.unproject_position(npc.global_position) - npc_sort.position - Vector2(0,float(entry["height"])*pixels_per_world_unit*0.5)
			if npc.has_meta("habitat_flight_frame"):
				_bound_habitat_flight_art(npc, art)
			_set_npc_water_draw_order(npc, npc_sort)
	_update_npc_water_surfaces(active_visual_layer)
	var view_signature:Array=preload("res://world/terrain_camera_view.gd").signature(camera)+[active_visual_layer,script_host.hidden_objects.hash(),tree_sort_entries.size(),object_sort_entries.size(),overlay_sort_entries.size(),attached_overlay_entries.size(),background_object_sort_entries.size(),bridge_sort_entries.size()]
	if view_signature!=static_art_view_signature:
		static_art_view_signature=view_signature
		for entry:Dictionary in tree_sort_entries:
			var enabled:=_sort_entry_layer(entry,entry.placement)==active_visual_layer and not script_host.object_hidden(entry)
			static_cache.update(entry,camera,enabled,projection_signature,projection_origin,pixels_per_world_unit,func():
				var placement:Vector3=entry.placement
				_update_sorted_art(entry.sort_root,Vector3(placement.x,0,placement.z+float(entry.get("sort_offset_y",0))),Vector3(placement.x,float(entry.height)*0.5,placement.z),float(entry.height),pixels_per_world_unit))
		for entry:Dictionary in object_sort_entries:
			var enabled:=_sort_entry_layer(entry,entry.placement)==active_visual_layer and not script_host.object_hidden(entry)
			static_cache.update(entry,camera,enabled,projection_signature,projection_origin,pixels_per_world_unit,func():
				if entry.has("wall_size"):_update_sorted_wall(entry);return
				var placement:Vector3=entry.placement
				var effective:=Vector3(placement.x,0,placement.z+float(entry.get("sort_offset_y",0)))
				if bool(entry.get("wall_overlay",false)):
					for wall:Dictionary in object_sort_entries:
						if not wall.has("wall_size") or _sort_entry_layer(wall,wall.placement)!=active_visual_layer:continue
						var bounds:=Rect2(Vector2(wall.placement.x,wall.placement.z)-wall.wall_size*0.5,wall.wall_size)
						if bounds.has_point(Vector2(placement.x,placement.z)):effective.z=maxf(effective.z,wall.placement.z+wall.wall_size.y*0.5+0.001)
				_update_sorted_art(entry.sort_root,effective,entry.visual_center,float(entry.height),pixels_per_world_unit)
				if entry.has("wall_scale_x"):(entry.sort_root.get_node("Visual") as Sprite2D).scale.x*=float(entry.wall_scale_x))
		for entry:Dictionary in overlay_sort_entries:
			static_cache.update(entry,camera,_sort_entry_layer(entry,entry.placement)==active_visual_layer,projection_signature,projection_origin,pixels_per_world_unit,func():
				var placement:Vector3=entry.placement
				_update_sorted_art(entry.sort_root,Vector3(placement.x,0,placement.z),entry.visual_center,float(entry.height),pixels_per_world_unit))
		for entry:Dictionary in attached_overlay_entries:
			if not entry.has("pivot"):continue
			var host:Dictionary=entry.host_entry;var host_root:=host.get("sort_root") as Node2D;var pivot:=entry.pivot as Node2D;var visual:=entry.visual as Sprite2D
			pivot.visible=host_root.visible
			if not pivot.visible:continue
			var attachment_key:Array=[host.get("projection_key",[]),entry.local_position,entry.height,visual.texture,pivot.rotation]
			if entry.get("attachment_projection_key",[])==attachment_key:continue
			entry["attachment_projection_key"]=attachment_key
			var placement:Vector3=host.placement;var local:Vector2=entry.local_position
			# Attachments are offsets on the host's billboard, as displayed in the
			# editor. Project only the ground anchor; projecting the art offset
			# compresses it with camera pitch and using placement.y raises it again.
			var contact_screen:=camera.unproject_position(Vector3(placement.x,0,placement.z))
			var local_screen:=local*pixels_per_world_unit
			pivot.position=contact_screen-host_root.position+local_screen
			visual.position=Vector2(0,-float(entry.height)*pixels_per_world_unit*0.5)
			visual.scale=Vector2.ONE*(float(entry.height)*pixels_per_world_unit/maxf(float(visual.texture.get_height()),1.0))
		for entry:Dictionary in background_object_sort_entries:
			var enabled:=_sort_entry_layer(entry,entry.placement)==active_visual_layer and not script_host.object_hidden(entry)
			static_cache.update(entry,camera,enabled,projection_signature,projection_origin,pixels_per_world_unit,func():_update_sorted_art(entry.sort_root,entry.placement,entry.visual_center,float(entry.height),pixels_per_world_unit))
		for entry:Dictionary in bridge_sort_entries:
			static_cache.update(entry,camera,_sort_entry_layer(entry,entry.position)==active_visual_layer,projection_signature,projection_origin,pixels_per_world_unit,func():
				var visual:Sprite2D=entry.sort_root.get_node("Visual")
				entry.sort_root.position=camera.unproject_position(entry.position)
				visual.position=Vector2.ZERO
				visual.scale=Vector2(entry.size.x,entry.size.y*0.72)*pixels_per_world_unit/Vector2(visual.texture.get_size()))
	_update_bridge_occlusion_priority()
	_update_platform_art_layers()


	_update_fakemon_lights()


func _update_platform_art_layers()->void:
	var actors:Array = [{"node":player,"visual":player_sort_root.get_node("Visual")}]
	for npc_entry:Dictionary in npc_sort_entries:
		var visual:Sprite2D = npc_entry.sort_root.get_node("Visual")
		visual.visible = true
		if npc_entry.sort_root.visible:actors.append({"node":npc_entry.node,"visual":visual})
	(player_sort_root.get_node("Visual") as Sprite2D).visible = true
	if follower != null and follower.visible and follower_sort_root != null:
		actors.append({"node": follower, "visual": follower_sort_root.get_node("Visual"), "render_only": true})
	var claimed:Dictionary = {}
	for entry:Dictionary in object_sort_entries:
		if not entry.has("platform_layers") or not (entry.sort_root as CanvasItem).visible:continue
		var occupants:Array = []
		for actor:Dictionary in actors:
			var id:int = actor.node.get_instance_id()
			if claimed.has(id) or not (entry.sort_root as CanvasItem).visible:continue
			if entry.has("actor_render_polygon"):
				var position: Vector3 = actor.node.position
				var feet := Vector2(position.x, position.z)
				if not Geometry2D.is_point_in_polygon(feet, entry.actor_render_polygon):
					if not _is_in_front_of_arena_rail(entry, feet):
						continue
					occupants.append({"node": actor.node, "visual": actor.visual, "show_foreground": false})
					claimed[id] = true
					continue
			elif actor.get("render_only", false) or _platform_at_position(actor.node.position, actor.node) != entry:
				continue
			occupants.append(actor)
			claimed[id] = true
		preload("res://world/platform_art_layers.gd").update_actors(entry,occupants,player_sort_root.get_node("Visual"))
	for actor:Dictionary in actors:actor.visual.visible = not claimed.has(actor.node.get_instance_id())


func _is_in_front_of_arena_rail(entry: Dictionary, feet: Vector2) -> bool:
	# Past the sprite anchor, normal Y-sort already draws the actor in front.
	if feet.y >= float(entry.placement.z) + float(entry.get("sort_offset_y", 0.0)):
		return false
	var front_edge := -INF
	for polygon: PackedVector2Array in entry.get("render_rail_polygons", []):
		for index in polygon.size():
			var a := polygon[index]
			var b := polygon[(index + 1) % polygon.size()]
			if feet.x < minf(a.x, b.x) or feet.x > maxf(a.x, b.x):
				continue
			var edge_z := maxf(a.y, b.y) if is_equal_approx(a.x, b.x) else lerpf(a.y, b.y, inverse_lerp(a.x, b.x, feet.x))
			front_edge = maxf(front_edge, edge_z)
	return is_finite(front_edge) and feet.y >= front_edge


func _platform_at_position(position:Vector3, actor:Node3D = null, margin:float = 0.0)->Dictionary:
	if actor == null or actor == player:
		if swimming or active_traversal_layer > 0:return {}
	elif actor.get_meta("movement_mode","ground") != "ground":return {}
	var layer := _active_visual_layer() if actor == null or actor == player else int(actor.get_meta("visual_layer",_visual_layer_for_position(position)))
	for entry:Dictionary in object_sort_entries:
		if not entry.has("navigation_polygon") or not entry.has("foreground_masks"):continue
		if int(entry.get("visual_layer",_visual_layer_for_position(entry.placement))) != layer:continue
		var point := Vector2(position.x,position.z)
		var polygon:PackedVector2Array = entry.navigation_polygon
		if Geometry2D.is_point_in_polygon(point,polygon):return entry
		if margin > 0.0:
			for index in polygon.size():
				if point.distance_to(Geometry2D.get_closest_point_to_segment(point,polygon[index],polygon[(index+1)%polygon.size()])) <= margin:return entry
	return {}


func _update_sorted_wall(entry:Dictionary)->void:
	var center:Vector3=entry.placement
	var size:Vector2=entry.wall_size
	var a:=camera.unproject_position(center-Vector3(size.x*0.5,0,size.y*0.5))
	var b:=camera.unproject_position(center+Vector3(size.x*0.5,0,size.y*0.5))
	var root_node:Node2D=entry.sort_root
	root_node.position=camera.unproject_position(center+Vector3(0,0,size.y*0.5))
	var art:Sprite2D=root_node.get_node("Visual")
	art.position=(a+b)*0.5-root_node.position
	art.scale=(b-a).abs()/art.get_rect().size


func _try_display_text_click(screen_position:Vector2)->bool:
	for entry:Dictionary in object_sort_entries:
		var text:=String(entry.get("interaction_text",""))
		var slot := String(entry.get("exhibit_slot", ""))
		if (slot.is_empty() and text.strip_edges().is_empty()) or not (entry.sort_root as CanvasItem).is_visible_in_tree():continue
		var art:Sprite2D=entry.sort_root.get_node("Visual")
		if art.get_rect().has_point(art.to_local(screen_position)):
			if not slot.is_empty() and adventure_started and _active_visual_layer() == int(entry.visual_layer):
				_open_habitat_exhibit(slot)
				return true
			_start_dialogue("DISPLAY", [text])
			var active_texture: Texture2D = entry.get("active_texture")
			if active_texture != null:
				var idle_texture := art.texture
				art.texture = active_texture
				var restore_idle := func():
					if is_instance_valid(art): art.texture = idle_texture
				dialog_panel.visibility_changed.connect(restore_idle, CONNECT_ONE_SHOT)
			return true
	return false


func _try_platform_sign_click(screen_position:Vector2)->bool:
	if not adventure_started or in_battle or dialog_open or not sort_canvas.visible:return false
	for entry:Dictionary in object_sort_entries:
		if not entry.has("platform_sign") or not (entry.sort_root as CanvasItem).is_visible_in_tree():continue
		var sign:Dictionary = entry.platform_sign
		var visual:Sprite2D = entry.sort_root.get_node("Visual")
		var pixel := visual.to_local(screen_position)+Vector2(visual.texture.get_size())*0.5
		var polygon := PackedVector2Array()
		for point:Array in sign.get("polygon",[]):polygon.append(Vector2(point[0],point[1]))
		if not Geometry2D.is_point_in_polygon(pixel,polygon):continue
		for species:Dictionary in battle.battle_data.get("fakemon",[]):
			if String(species.get("name","")).nocasecmp_to(String(sign.get("species","")))!=0:continue
			var description := String(species.get("description","")).strip_edges()
			if description.is_empty():return false
			var pages:Array[String] = []
			var page := ""
			for sentence:String in description.split(". "):
				var text := sentence if sentence.ends_with(".") else sentence+"."
				if not page.is_empty() and page.length()+text.length()>230:pages.append(page);page=""
				page += (" " if not page.is_empty() else "")+text
			if not page.is_empty():pages.append(page)
			_start_dialogue(String(species.name).to_upper()+" — HABITAT SIGN",pages)
			return true
	return false


func _warn_platform_overlaps()->void:
	var platforms:Array = object_sort_entries.filter(func(entry):return entry.has("navigation_polygon") and entry.has("foreground_masks"))
	for index in platforms.size():
		for other_index in range(index+1,platforms.size()):
			var a:Dictionary = platforms[index]
			var b:Dictionary = platforms[other_index]
			if int(a.get("visual_layer",_visual_layer_for_position(a.placement))) != int(b.get("visual_layer",_visual_layer_for_position(b.placement))):continue
			if not Geometry2D.intersect_polygons(a.navigation_polygon,b.navigation_polygon).is_empty():
				push_warning("Platform walk areas overlap: %s and %s. Increase their spacing or reduce their heights; overlapping art and rails may obstruct traversal."%[a.name,b.name])


func _update_platform_collision_mask()->void:
	# A platform occupies the same projected X/Z space as ground props. Its own
	# rails remain solid while the actor passes over ground-level obstructions.
	player.collision_mask = _floor_collision_mask(player,player.position,false)


func _floor_collision_mask(actor:Node3D, position:Vector3, terrain:bool = true)->int:
	if not _platform_at_position(position,actor).is_empty():
		return PLATFORM_WALL_LAYER | ACTOR_COLLISION_LAYER
	return 1 | PLATFORM_WALL_LAYER | (TERRAIN_OBSTACLE_LAYER if terrain else 0)


func _update_sorted_art(sort_point: Node2D, effective_sort_world: Vector3, visual_center_world: Vector3, visual_height: float, pixels_per_world_unit: float, contact_elevation: float = 0.0) -> void:
	if sort_point == null:
		return
	var visual := sort_point.get_node("Visual") as Sprite2D
	var sort_screen := camera.unproject_position(effective_sort_world)
	# Sprite2D height is camera-facing screen space, so projecting a world-Y
	# midpoint through the tilted camera introduces a height-dependent drift.
	# Anchor the bottom of the full texture directly to its saved X/Z contact.
	var contact_screen := camera.unproject_position(Vector3(visual_center_world.x, contact_elevation, visual_center_world.z))
	sort_point.position = sort_screen
	var scale := visual_height * pixels_per_world_unit / float(visual.texture.get_height())
	visual.scale = Vector2(scale, scale)
	visual.position = contact_screen - sort_screen - Vector2(0.0, visual_height * pixels_per_world_unit * 0.5)


func _build_building_door_warp(building_art: Node3D, warp_name: String, global_position: Vector3, callback: Callable, size: Vector3) -> Area3D:
	var warp := Area3D.new()
	warp.name = warp_name
	warp.position = building_art.to_local(global_position)
	warp.add_child(_box_shape(size))
	warp.body_entered.connect(callback)
	building_art.add_child(warp)
	return warp


func _add_warp_rug_visual(parent: Node3D, width: float, sprite: String = "") -> MeshInstance3D:
	if sprite.is_empty(): sprite = _warp_sprite_at(parent.position)
	var texture: Texture2D = load("res://" + WarpSpriteCatalog.texture_path(sprite))
	var visual := MeshInstance3D.new()
	visual.name = "WarpRugArt"
	var mesh := PlaneMesh.new()
	var aspect := float(texture.get_width()) / float(texture.get_height())
	mesh.size = Vector2(width, width / aspect)
	visual.mesh = mesh
	# Canonical floor tiles are rendered at world Y=0.4; keep the rug above them.
	visual.position.y = maxf(0.17, 0.43 - parent.position.y)
	var material:=_textured_material(texture, Color.WHITE)
	# Ground decals stay above canonical terrain and decorative border art.
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test=true
	material.depth_draw_mode=BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.render_priority=2
	visual.material_override=material
	parent.add_child(visual)
	return visual


func _build_medical_ward(ward_data: Dictionary) -> void:
	medical_origin = _array_to_vector3(ward_data["origin"])
	_build_medical_ward_instance(ward_data, "MedicalWard", _on_interior_door_entered)


func _build_medical_ward_instance(ward_data: Dictionary, prefix: String, exit_callback: Callable) -> void:
	var ward_origin := _array_to_vector3(ward_data["origin"])
	var ward_size: Array = ward_data["interior_size"]
	_add_map_blocks(ward_origin, ward_data.get("floor_blocks", [[0, -0.1, 0, ward_size[0], 0.2, ward_size[1]]]), prefix + "Floor", TEX_INTERIOR_FLOOR, Color("#d7f0ec"), false)
	var center_tile := MeshInstance3D.new()
	center_tile.name = prefix + "CenterFloorTile"
	var center_mesh := BoxMesh.new()
	center_mesh.size = Vector3(4.5, 0.06, 3.2)
	center_tile.mesh = center_mesh
	center_tile.position = ward_origin + Vector3(0, 0.04, 0.3)
	center_tile.material_override = _textured_material(TEX_INTERIOR_FLOOR, Color("#b8ddd9"), Vector3(4.5, 3.2, 1.0))
	world.add_child(center_tile)
	_add_map_blocks(ward_origin, ward_data.get("wall_blocks", _room_wall_blocks(ward_size)), prefix + "Wall", TEX_WALL_GENERIC, Color("#d6e8e8"), true)
	_add_serialized_furnishings(ward_origin,ward_data.get("furnishings",[{"type":"ward_counter","position":[0,0,-2.2],"height":1.75},{"type":"ward_shelf","position":[-3,0,-1.7],"height":2.05},{"type":"ward_table","position":[2,0,0.8],"height":0.95},{"type":"ward_curtain","position":[2.95,0,-1],"height":1.85},{"type":"ward_wash","position":[-2.9,0,1.5],"height":1.85}]),prefix)
	_build_universal_objects(ward_data, ward_origin, prefix)

	#var reception := MeshInstance3D.new()
	#reception.name = "MedicalWardCounterPlaceholder"
	#var counter_mesh := BoxMesh.new()
	#counter_mesh.size = Vector3(4.5, 1.0, 0.8)
	#reception.mesh = counter_mesh
	#reception.position = medical_origin + Vector3(0, 0.5, -2.2)
	#reception.material_override = _material(Color("#e89aae"))
	#world.add_child(reception)
	#_add_static_collision("MedicalWardCounterCollision", reception.position, counter_mesh.size)
	var exit_door := Area3D.new()
	exit_door.name = prefix + "InteriorDoor"
	exit_door.position = ward_origin + _array_to_vector3(ward_data["exit_door"])
	var door_size := Vector3(1.5, 0.3, 0.9)
	exit_door.add_child(_box_shape(door_size))
	_add_warp_rug_visual(exit_door, door_size.x)
	exit_door.body_entered.connect(exit_callback)
	world.add_child(exit_door)


func _build_house(house_data: Dictionary) -> void:
	var exterior_position := _array_to_vector3(house_data["position"])
	var exterior_size := _array_to_vector3(house_data["size"])
	var house_art := _add_world_billboard("HouseExteriorArt", exterior_position, TEX_HOUSE, 4.6, 0.0)
	_register_sortable_object(house_art, "HouseExteriorSortRoot", exterior_position, house_art.global_position, float(house_art.texture.get_height()) * house_art.pixel_size, float(house_data.get("sort_offset_y", 0.0)))
	_add_building_collision("HouseExteriorCollision",exterior_position,exterior_size,"house")
	var door_size := Vector3(1.3, 0.3, 0.9)
	_build_building_door_warp(house_art, "HouseExteriorDoor", _array_to_vector3(house_data["door"]), _on_house_exterior_door_entered, door_size)

	house_origin = _array_to_vector3(house_data["origin"])
	var room_size: Array = house_data["interior_size"]
	_add_map_blocks(house_origin, house_data.get("floor_blocks", [[0, -0.1, 0, room_size[0], 0.2, room_size[1]]]), "HouseInteriorFloor", TEX_INTERIOR_FLOOR, Color("#d8c6a5"), false)
	_add_map_blocks(house_origin, house_data.get("wall_blocks", _room_wall_blocks(room_size)), "HouseInteriorWall", TEX_WALL_GENERIC, Color("#d8c6a5").darkened(0.18), true)
	_add_serialized_furnishings(house_origin,house_data.get("furnishings",[{"type":"bed","position":[-2.3,0,-1.6],"height":2.35},{"type":"dresser","position":[2.5,0,-1.6],"height":2.05},{"type":"table","position":[0,0,0.4],"height":1.3},{"type":"houseplant_2","position":[2.6,0,1.6],"height":1.0}]),"RainforestHouse")
	_build_universal_objects(house_data, house_origin, "RainforestHouse")
	house_npc = Area3D.new()
	house_npc.name = "BurnTutorNPC"
	house_npc.position = house_origin + _array_to_vector3(house_data["npc"])
	var tutor_texture:=NpcSpriteLibrary.texture_for("man")
	var tutor_visual:=_billboard_sprite(tutor_texture,NPC_ADULT_VISUAL_HEIGHT,"BURN_TUTORSprite") if tutor_texture!=null else _square_sprite(Color("#f0a34a"),"BURN_TUTOR",Vector2(0.9,1.15))
	if tutor_texture!=null:tutor_visual.offset=Vector2(0.0,float(tutor_texture.get_height())*0.5)
	house_npc.add_child(tutor_visual)
	house_npc.set_meta("sprite_id","man")
	house_npc.set_meta("facing","down")
	house_npc.set_meta("visual_height",NPC_ADULT_VISUAL_HEIGHT)
	house_npc.add_child(_box_shape(Vector3(0.9, 1.2, 0.9)))
	house_npc.add_child(_npc_foot_body())
	world.add_child(house_npc)

	var interior_door := Area3D.new()
	interior_door.name = "HouseInteriorDoor"
	interior_door.position = house_origin + _array_to_vector3(house_data["exit_door"])
	interior_door.add_child(_box_shape(door_size))
	_add_warp_rug_visual(interior_door, door_size.x)
	interior_door.body_entered.connect(_on_house_interior_door_entered)
	world.add_child(interior_door)


func _add_ward_block(block_name: String, block_position: Vector3, block_size: Vector3, color: Color) -> void:
	var visual := MeshInstance3D.new()
	visual.name = block_name
	var mesh := BoxMesh.new()
	mesh.size = block_size
	visual.mesh = mesh
	visual.position = block_position
	visual.material_override = _textured_material(TEX_WALL if block_name.contains("BackWall") else TEX_WALL_GENERIC, color, Vector3(maxf(block_size.x, 1.0), maxf(block_size.y, 1.0), 1.0))
	world.add_child(visual)
	var body := StaticBody3D.new()
	body.name = block_name + "Collision"
	body.position = block_position
	body.add_child(_box_shape(block_size))
	world.add_child(body)


func _add_static_collision(collision_name: String, collision_position: Vector3, collision_size: Vector3, physics_layer: int = 1) -> void:
	var body := StaticBody3D.new()
	body.name = collision_name
	body.position = collision_position
	body.collision_layer = physics_layer
	body.collision_mask = 1
	body.set_meta("elevation_span",Vector2(collision_position.y-collision_size.y*0.5,collision_position.y+collision_size.y*0.5))
	body.add_child(_box_shape(collision_size))
	world.add_child(body)


func _npc_foot_body()->StaticBody3D:
	var body:=StaticBody3D.new()
	body.name="FootCollision"
	body.position=NPC_FOOT_COLLISION_OFFSET
	body.collision_layer=1 | ACTOR_COLLISION_LAYER
	body.collision_mask=1
	body.add_child(_box_shape(NPC_FOOT_COLLISION_SIZE))
	return body


func _add_building_collision(collision_name:String,position:Vector3,size:Vector3,building_type:String)->void:
	var front_extension:=float(BUILDING_FRONT_EXTENSION.get(building_type,0.0))
	var collision_size:=size+Vector3(0,0,front_extension)
	# Unlike an ordinary block, a façade is anchored at its visible front edge.
	# Center the collider behind that edge, never across the entry approach.
	_add_static_collision(collision_name,position-Vector3(0,0,collision_size.z*0.5),collision_size)

# Project authored texture coordinates onto the X/Z navigation plane. Sorted art
# uses a bottom-center anchor and the world camera views this plane at 45 degrees.
func _asset_navigation_point(point:Array,position:Vector3,height:float,image_size:Array)->Vector3:
	var scale := height / float(image_size[1])
	return position + Vector3((float(point[0])-float(image_size[0])*0.5)*scale,0.0,(float(point[1])-float(image_size[1]))*scale*sqrt(2.0))


func _add_recessed_floor(node_name: String, position: Vector3, height: float, profile: Dictionary) -> void:
	var image_size: Variant = profile.get("image_size")
	var outline: Variant = profile.get("outline")
	if not _valid_navigation_point(image_size) or float(image_size[0]) <= 0.0 or float(image_size[1]) <= 0.0:
		return
	if not outline is Array or outline.size() < 3:
		return
	var polygon := PackedVector2Array()
	var north_entry := INF
	var south_entry := -INF
	for point in outline:
		if not _valid_navigation_point(point):
			return
		var mapped := _asset_navigation_point(point, position, height, image_size)
		polygon.append(Vector2(mapped.x, mapped.z))
		north_entry = minf(north_entry, mapped.z)
		south_entry = maxf(south_entry, mapped.z)
	var north_landing := _asset_navigation_point([0, profile.get("north_landing", 0.0)], position, height, image_size).z
	var south_landing := _asset_navigation_point([0, profile.get("south_landing", 0.0)], position, height, image_size).z
	var depth := float(profile.get("depth", 0.0))
	if depth <= 0.0 or not (north_entry < north_landing and north_landing <= south_landing and south_landing < south_entry):
		return
	traversal_surfaces.append({
		"name": node_name,
		"center": position,
		"visual_layer": _visual_layer_for_position(position),
		"recessed_outline": polygon,
		"north_entry": north_entry,
		"north_landing": north_landing,
		"south_landing": south_landing,
		"south_entry": south_entry,
		"depth": depth,
	})
	var masks: Array = profile.get("foreground_masks", [])
	if masks.is_empty():
		return
	var render_polygon := polygon.duplicate()
	var approach_row: Variant = profile.get("south_render_entry")
	if approach_row is float or approach_row is int:
		var approach_z := _asset_navigation_point([0, approach_row], position, height, image_size).z
		if approach_z > south_entry:
			# The player can overlap the stair art before reaching the physical ramp.
			for index in render_polygon.size():
				if is_equal_approx(render_polygon[index].y, south_entry):
					render_polygon[index].y = approach_z
	for entry in object_sort_entries:
		if entry.name == node_name + "SortRoot":
			entry["actor_render_polygon"] = render_polygon
			var rail := world.get_node_or_null(NodePath(node_name + "AssetPolygonCollision")) as StaticBody3D
			if rail != null:
				entry["render_rail_polygons"] = rail.get_meta("ground_polygons", [])
			entry["foreground_masks"] = masks
			break


func _add_asset_navigation(node_name:String,position:Vector3,asset_path:String,height:float)->void:
	var file := FileAccess.open(asset_path.trim_suffix(".png")+".json",FileAccess.READ)
	if file == null:return
	var metadata:Variant = JSON.parse_string(file.get_as_text())
	if not metadata is Dictionary:return
	if metadata.get("recessed_floor") is Dictionary:
		_add_recessed_floor(node_name, position, height, metadata.recessed_floor)
	var navigation_data:Variant = metadata.get("navigation",{})
	if not navigation_data is Dictionary:return
	var navigation:Dictionary = navigation_data
	if navigation.is_empty():return
	var image_size:Variant = navigation.get("image_size",[])
	if not _valid_navigation_point(image_size) or float(image_size[0])<=0.0 or float(image_size[1])<=0.0:
		push_warning("Invalid navigation image size for "+asset_path);return
	var walls:Variant = navigation.get("walls",[])
	var ground_walls:Variant = navigation.get("ground_walls",[])
	var walk:Variant = navigation.get("walk_polygon",[])
	var masks:Variant = navigation.get("foreground_masks",[])
	var depth_lines:Variant = navigation.get("foreground_depth_lines",[])
	if not depth_lines is Array:push_warning("Invalid railing depth data for "+asset_path);return
	for line:Variant in depth_lines:
		if not line is Array or (line.size()!=0 and (line.size()!=2 or not _valid_navigation_point(line[0]) or not _valid_navigation_point(line[1]))):
			push_warning("Invalid railing depth line for "+asset_path);return
	var sign:Variant = navigation.get("sign",{})
	if not sign is Dictionary:push_warning("Invalid platform sign for "+asset_path);return
	if not sign.is_empty():
		if not sign.get("polygon") is Array:push_warning("Invalid sign polygon for "+asset_path);return
		for point:Variant in sign.polygon:
			if not _valid_navigation_point(point):push_warning("Invalid sign point for "+asset_path);return
	if not walls is Array or not ground_walls is Array or not walk is Array or walk.size()<3 or not masks is Array:
		push_warning("Invalid navigation geometry for "+asset_path);return
	for point:Variant in walk:
		if not _valid_navigation_point(point):push_warning("Invalid navigation point for "+asset_path);return
	for line:Variant in walls+ground_walls+masks:
		if not line is Array or line.size()<2:push_warning("Invalid navigation line for "+asset_path);return
		for point:Variant in line:
			if not _valid_navigation_point(point):push_warning("Invalid navigation point for "+asset_path);return
	for mask:Array in masks:
		var vertices := PackedVector2Array()
		for point:Array in mask:vertices.append(Vector2(point[0],point[1]))
		if Geometry2D.triangulate_polygon(vertices).is_empty():push_warning("Invalid foreground polygon for "+asset_path);return
	if height < float(navigation.get("minimum_height",0.0)):
		push_warning("%s height %.2f is below the tested navigation minimum; stairs may be too narrow."%[asset_path,height])
	var polygon := PackedVector2Array()
	for point:Array in walk:
		var mapped := _asset_navigation_point(point,position,height,image_size)
		polygon.append(Vector2(mapped.x,mapped.z))
	for entry:Dictionary in object_sort_entries:
		if entry.name == node_name+"SortRoot":
			entry["navigation_polygon"] = polygon
			entry["foreground_depth_lines"] = depth_lines
			if not sign.is_empty():entry["platform_sign"] = sign
			if not masks.is_empty():entry["foreground_masks"] = masks
	var index := 0
	var all_lines:Array = walls+ground_walls
	for line_index in all_lines.size():
		var line:Array = all_lines[line_index]
		var physics_layer := PLATFORM_WALL_LAYER if line_index < walls.size() else 1
		for segment in range(line.size()-1):
			var a := _asset_navigation_point(line[segment],position,height,image_size)
			var b := _asset_navigation_point(line[segment+1],position,height,image_size)
			var delta := b-a
			if delta.length()<0.001:continue
			_add_wall_collision_segment("%sNavigationWall%d"%[node_name,index],(a+b)*0.5+Vector3(0,0.65,0),delta.length(),float(navigation.get("wall_thickness",0.08)),atan2(delta.x,delta.z),physics_layer)
			index += 1


func _valid_navigation_point(point:Variant)->bool:
	return point is Array and point.size()==2 and (point[0] is float or point[0] is int) and (point[1] is float or point[1] is int) and is_finite(float(point[0])) and is_finite(float(point[1]))


func _add_asset_collision_boxes(node_name:String,position:Vector3,asset_path:String,instance_size:Vector3=Vector3.ONE,rotation_degrees:float=0.0)->void:
	if asset_path.is_empty():return
	if _add_asset_polygon_collision(node_name+"AssetPolygon",position,instance_size,rotation_degrees,asset_path):return
	var metadata_path:=asset_path.trim_suffix(".png")+".json"
	var file:=FileAccess.open(metadata_path,FileAccess.READ)
	if file==null:return
	var json:=JSON.new()
	if json.parse(file.get_as_text())!=OK or not json.data is Dictionary:return
	for index in (json.data as Dictionary).get("collision_boxes",[]).size():
		var box:Variant=(json.data as Dictionary).get("collision_boxes",[])[index]
		if not box is Dictionary:continue
		var offset:Variant=box.get("offset",[0.0,0.0]);var size_data:Variant=box.get("size",[1.0,1.0,1.0])
		if not offset is Array or offset.size()<2 or not size_data is Array or size_data.size()<3:continue
		_add_static_collision("%sAssetCollision%d"%[node_name,index],position+Vector3(float(offset[0]),float(size_data[1])*0.5,float(offset[1])),_array_to_vector3(size_data))

func _add_asset_polygon_collision(node_name:String,position:Vector3,size:Vector3,rotation_degrees:float,asset_path:String)->bool:
	if asset_path.is_empty():return false
	var file:=FileAccess.open(asset_path.trim_suffix(".png")+".json",FileAccess.READ)
	if file==null:return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return false
	var polygons := PolygonColliders.read(parsed.get("collision"))
	if polygons.is_empty():
		return false

	var body := StaticBody3D.new()
	body.name = node_name + "Collision"
	body.position = Vector3(position.x, 1.0, position.z)
	body.rotation.y = deg_to_rad(rotation_degrees)
	body.collision_layer = TERRAIN_OBSTACLE_LAYER
	body.collision_mask = 1
	var ground_polygons: Array[PackedVector2Array] = []
	for polygon: Dictionary in polygons:
		var outline := _asset_polygon_outline(polygon, size)
		var shape := _asset_polygon_shape(outline)
		if shape == null:
			push_warning("Invalid or unclosed polygon collision for " + asset_path)
			continue
		var collision_shape := CollisionShape3D.new()
		collision_shape.shape = shape
		body.add_child(collision_shape)
		var ground_polygon := PackedVector2Array()
		for point in outline:
			var mapped := body.transform * Vector3(point.x, 0.0, point.y)
			ground_polygon.append(Vector2(mapped.x, mapped.z))
		ground_polygons.append(ground_polygon)
	if body.get_child_count() > 0:
		body.set_meta("ground_polygons", ground_polygons)
		world.add_child(body)
	else:
		body.free()
	# Authored polygons override box collision, including while a draft is open.
	return true

func _asset_polygon_outline(collision: Dictionary, size: Vector3) -> PackedVector2Array:
	var raw: Variant = collision.get("points", [])
	if not bool(collision.get("closed", false)) or not raw is Array or raw.size() < 3:
		return PackedVector2Array()
	var reference := PolygonColliders.reference_size(collision, Vector2(size.x, size.z))
	var outline := PackedVector2Array()
	for point in raw:
		if not _valid_navigation_point(point):
			return PackedVector2Array()
		outline.append((Vector2(float(point[0]), float(point[1])) - Vector2(0.5, 0.5)) * reference)
	return outline


func _asset_polygon_shape(local: PackedVector2Array) -> ConcavePolygonShape3D:
	if local.size() < 3:
		return null
	var triangles := Geometry2D.triangulate_polygon(local)
	if triangles.is_empty():
		return null
	var faces:=PackedVector3Array();var half_height:=1.0
	for index in range(0,triangles.size(),3):
		var a:=local[triangles[index]];var b:=local[triangles[index+1]];var c:=local[triangles[index+2]]
		faces.append_array(PackedVector3Array([Vector3(a.x,half_height,a.y),Vector3(b.x,half_height,b.y),Vector3(c.x,half_height,c.y),Vector3(c.x,-half_height,c.y),Vector3(b.x,-half_height,b.y),Vector3(a.x,-half_height,a.y)]))
	for index in local.size():
		var a:=local[index];var b:=local[(index+1)%local.size()]
		faces.append_array(PackedVector3Array([Vector3(a.x,-half_height,a.y),Vector3(b.x,-half_height,b.y),Vector3(b.x,half_height,b.y),Vector3(a.x,-half_height,a.y),Vector3(b.x,half_height,b.y),Vector3(a.x,half_height,a.y)]))
	# Editor polygons can be authored in either winding direction.
	var shape:=ConcavePolygonShape3D.new();shape.backface_collision=true;shape.set_faces(faces)
	return shape


func _on_grass_tile_exited(body: Node3D, tile_id: String) -> void:
	if body == player and last_grass_tile == tile_id:
		last_grass_tile = ""


func _build_party_menu() -> void:
	var menu_button := Button.new()
	menu_button.name = "PartyButton"
	menu_button.text = "Party (P)"
	menu_button.pressed.connect(_toggle_party_menu)
	map_ui.add_child(menu_button)
	_set_bottom_right_rect(menu_button, Vector2(-139, -60), Vector2(115, 36))
	var bag_button := Button.new()
	bag_button.name = "BagButton"
	bag_button.text = "Bag"
	bag_button.pressed.connect(_toggle_bag_menu)
	map_ui.add_child(bag_button)
	_set_bottom_right_rect(bag_button, Vector2(-266, -60), Vector2(115, 36))
	var settings_button := Button.new()
	settings_button.name = "SettingsButton"
	settings_button.text = "Settings"
	settings_button.pressed.connect(_toggle_settings_menu)
	map_ui.add_child(settings_button)
	settings_button.anchor_top = 1.0
	settings_button.anchor_bottom = 1.0
	settings_button.offset_left = 24.0
	settings_button.offset_top = -60.0
	settings_button.offset_right = 164.0
	settings_button.offset_bottom = -24.0

	settings_panel = PanelContainer.new()
	settings_panel.name = "SettingsPanel"
	var settings_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		settings_margin.add_theme_constant_override("margin_" + side, 12)
	settings_panel.add_child(settings_margin)
	var settings_list := VBoxContainer.new()
	settings_list.add_theme_constant_override("separation", 8)
	settings_margin.add_child(settings_list)
	var settings_title := Label.new()
	settings_title.text = "SETTINGS"
	settings_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_list.add_child(settings_title)
	save_slot_selector = OptionButton.new()
	save_slot_selector.name = "SaveSlotSelector"
	for slot in SAVE_SLOT_COUNT:
		save_slot_selector.add_item("Slot %d" % (slot + 1), slot + 1)
	save_slot_selector.item_selected.connect(_on_save_slot_selected)
	settings_list.add_child(save_slot_selector)
	var save_button := Button.new()
	save_button.name = "SaveSlotButton"
	save_button.text = "Save Slot (F5)"
	save_button.pressed.connect(_save_game)
	settings_list.add_child(save_button)
	var load_button := Button.new()
	load_button.name = "LoadSlotButton"
	load_button.text = "Load Slot (F9)"
	load_button.pressed.connect(_load_game)
	settings_list.add_child(load_button)
	var reset_button := Button.new()
	reset_button.name = "ResetAdventureButton"
	reset_button.text = "Reset Adventure"
	reset_button.pressed.connect(_reset_to_start)
	settings_list.add_child(reset_button)
	save_status_label = Label.new()
	save_status_label.name = "SaveStatusLabel"
	save_status_label.add_theme_font_size_override("font_size", 12)
	save_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_list.add_child(save_status_label)
	settings_panel.hide()
	map_ui.add_child(settings_panel)
	settings_panel.anchor_top = 1.0
	settings_panel.anchor_bottom = 1.0
	settings_panel.offset_left = 24.0
	settings_panel.offset_top = -284.0
	settings_panel.offset_right = 244.0
	settings_panel.offset_bottom = -72.0

	bag_panel = PanelContainer.new()
	bag_panel.name = "BagPanel"
	var bag_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		bag_margin.add_theme_constant_override("margin_" + side, 12)
	bag_panel.add_child(bag_margin)
	var bag_list := VBoxContainer.new()
	bag_list.add_theme_constant_override("separation", 8)
	bag_margin.add_child(bag_list)
	var bag_title := Label.new()
	bag_title.text = "BAG"
	bag_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bag_list.add_child(bag_title)
	var items_label := Label.new()
	items_label.name = "ItemsCategory"
	items_label.text = "Items\n  Nothing here yet."
	bag_list.add_child(items_label)
	var key_items_list := VBoxContainer.new()
	key_items_list.name = "KeyItemsSection"
	key_items_list.add_theme_constant_override("separation", 4)
	bag_list.add_child(key_items_list)
	var key_items_label := Label.new()
	key_items_label.name = "KeyItemsCategory"
	key_items_label.text = "Key Items"
	key_items_list.add_child(key_items_label)
	var swimgear_button := Button.new()
	swimgear_button.name = "SwimgearButton"
	swimgear_button.text = "Swimgear"
	swimgear_button.tooltip_text = "Use beside water to go for a swim."
	swimgear_button.pressed.connect(_use_swimgear)
	key_items_list.add_child(swimgear_button)
	var watch_button := Button.new()
	watch_button.name = "WatchButton"
	watch_button.text = "Watch"
	watch_button.tooltip_text = "Check the shared world clock."
	watch_button.pressed.connect(_use_watch)
	key_items_list.add_child(watch_button)
	var cloud_button := Button.new()
	cloud_button.name = "CloudButton"
	cloud_button.text = "Cloud"
	cloud_button.pressed.connect(_use_cloud)
	key_items_list.add_child(cloud_button)
	cloud_dialog = CloudDialog.new()
	cloud_dialog.storage = fakemon_storage
	map_ui.add_child(cloud_dialog)
	fakemon_storage.transferred.connect(_on_fakemon_transferred)
	var outfits_label := Label.new()
	outfits_label.name = "OutfitsCategory"
	outfits_label.text = "Outfits\n  Nothing here yet."
	bag_list.add_child(outfits_label)
	bag_panel.hide()
	map_ui.add_child(bag_panel)
	_set_bottom_right_rect(bag_panel, Vector2(-326, -344), Vector2(302, 272))
	party_panel = PanelContainer.new()
	var party_margin := MarginContainer.new()
	party_margin.add_theme_constant_override("margin_left", 12)
	party_margin.add_theme_constant_override("margin_right", 12)
	party_margin.add_theme_constant_override("margin_top", 10)
	party_margin.add_theme_constant_override("margin_bottom", 10)
	party_panel.add_child(party_margin)
	party_list = VBoxContainer.new()
	party_list.add_theme_constant_override("separation", 7)
	party_margin.add_child(party_list)
	party_panel.hide()
	map_ui.add_child(party_panel)
	_set_bottom_right_rect(party_panel, Vector2(-489, -527), Vector2(465, 455))
	dex_panel = DEX_VIEW_SCENE.instantiate()
	dex_panel.return_requested.connect(_return_from_dex)
	map_ui.add_child(dex_panel)


func _set_bottom_right_rect(control: Control, offset: Vector2, control_size: Vector2) -> void:
	control.anchor_left = 1.0
	control.anchor_top = 1.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = offset.x
	control.offset_top = offset.y
	control.offset_right = offset.x + control_size.x
	control.offset_bottom = offset.y + control_size.y


func _reset_to_start() -> void:
	# Reloading reconstructs all transient world/battle/UI state and returns to
	# the existing startup prompt without deleting any saved adventures.
	get_tree().reload_current_scene()


func _build_dialog_ui() -> void:
	dialog_panel = PanelContainer.new()
	dialog_panel.z_index = 110
	dialog_panel.position = Vector2(80, 345)
	dialog_panel.size = Vector2(800, 165)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	dialog_panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)
	dialog_speaker = Label.new()
	dialog_speaker.text = "RAINFOREST RESIDENT"
	dialog_speaker.add_theme_font_size_override("font_size", 16)
	content.add_child(dialog_speaker)
	dialog_label = Label.new()
	dialog_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialog_label.add_theme_font_size_override("font_size", 17)
	content.add_child(dialog_label)
	dialog_button = Button.new()
	dialog_button.pressed.connect(_advance_dialogue)
	content.add_child(dialog_button)
	dialog_choice_row = HBoxContainer.new()
	dialog_choice_row.add_theme_constant_override("separation", 16)
	for yes: bool in [true,false]:
		var button := Button.new()
		button.text = "Yes" if yes else "No"
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_answer_dialogue_choice.bind(yes))
		dialog_choice_row.add_child(button)
		if yes: dialog_yes_button = button
		else: dialog_no_button = button
	content.add_child(dialog_choice_row); dialog_choice_row.hide()
	dialog_panel.hide()
	map_ui.add_child(dialog_panel)


func _start_burn_dialogue() -> void:
	_start_dialogue("RAINFOREST RESIDENT", burn_dialogue)


func _clear_dialogue_choice() -> void:
	dialog_choosing = false; dialogue_choice_action = Callable()
	if dialog_choice_row != null: dialog_choice_row.hide()
	if dialog_button != null: dialog_button.show()


func _start_yes_no_dialogue(text: String, answer: Callable) -> void:
	_start_dialogue("",[text])
	dialog_choosing = true; dialogue_choice_action = answer
	dialog_button.hide(); dialog_choice_row.show(); dialog_no_button.grab_focus()


func _answer_dialogue_choice(yes: bool) -> void:
	if not dialog_open or not dialog_choosing: return
	var answer := dialogue_choice_action
	_clear_dialogue_choice()
	dialog_open = false; dialog_panel.hide(); dialogue_complete_action = Callable()
	if answer.is_valid(): answer.call(yes)


func _start_dialogue(speaker: String, pages: Array, after_dialogue := Callable()) -> void:
	_clear_dialogue_choice()
	active_dialogue.clear()
	for page: Variant in pages:
		active_dialogue.append(String(page))
	active_dialogue_speaker = speaker
	dialogue_complete_action = after_dialogue
	dialog_page = 0
	dialog_open = true
	dialog_panel.show()
	_update_dialogue()


func _advance_dialogue() -> void:
	if dialog_choosing: return
	dialog_page += 1
	if dialog_page >= active_dialogue.size():
		dialog_open = false
		dialog_panel.hide()
		var action := dialogue_complete_action
		dialogue_complete_action = Callable()
		if action.is_valid():
			action.call()
		return
	_update_dialogue()


func _update_dialogue() -> void:
	dialog_speaker.text = active_dialogue_speaker
	dialog_label.text = active_dialogue[dialog_page]
	dialog_button.text = "Close" if dialog_page == active_dialogue.size() - 1 else "Next"


func _update_family_children(delta: float) -> void:
	if not inside_family_house:
		return
	var room_size: Array = map_data["rainforest_city"]["family_house"]["interior_size"]
	for child_data: Dictionary in family_children:
		var child: Area3D = child_data["node"]
		child_data["timer"] = float(child_data["timer"]) - delta
		if float(child_data["timer"]) <= 0.0 or child.position.distance_to(child_data["target"]) < 0.1:
			child_data["target"] = family_house_origin + Vector3(randf_range(-float(room_size[0]) * 0.5 + 1.2, float(room_size[0]) * 0.5 - 1.2), 0.65, randf_range(-float(room_size[1]) * 0.5 + 1.2, float(room_size[1]) * 0.5 - 1.2))
			child_data["timer"] = randf_range(1.5, 4.0)
		var motion: Vector3 = child_data["target"] - child.position
		if motion.length() > 0.1:
			var direction := _cardinal_direction(motion)
			child_data["animation_time"] = float(child_data["animation_time"]) + delta
			if float(child_data["animation_time"]) >= 0.16:
				child_data["animation_time"] = 0.0
				child_data["frame"] = (int(child_data["frame"]) + 1) % NpcSpriteLibrary.walk_frame_count(String(child.get_meta("sprite_id")))
			_set_npc_pose(child, direction, int(child_data["frame"]))
			child.position = child.position.move_toward(child_data["target"], 1.2 * delta)
		else:
			_set_npc_pose(child, String(child.get_meta("facing", "down")))


func _face_npc_toward_player(npc:Area3D)->void:
	if npc==null or player==null:return
	_set_npc_pose(npc,_cardinal_direction(player.position-npc.position))


func _cardinal_direction(vector:Vector3)->String:
	if absf(vector.x)>absf(vector.z):return "left" if vector.x<0.0 else "right"
	return "up" if vector.z<0.0 else "down"


func _set_npc_pose(npc:Area3D,direction:String,walk_frame:int=-1)->void:
	var sprite_id:=String(npc.get_meta("sprite_id",""))
	if sprite_id.is_empty() or npc.get_child_count()==0:return
	var texture:Texture2D
	if npc.has_meta("npc_definition"):
		var definition:Dictionary=npc.get_meta("npc_definition")
		texture=npc_visual_resolver.texture_for(String(definition.type),String(definition.sprite),direction,walk_frame)
	else:
		texture=NpcSpriteLibrary.texture_for(sprite_id,direction,walk_frame)
	if texture==null:return
	var visual:=npc.get_child(0) as Sprite3D
	if visual==null:return
	visual.texture=texture
	if npc.get_meta("npc_definition", {}).get("type") == "vehicle":
		_configure_vehicle_hull(npc, direction)
		npc.set_meta("visual_height", npc_visual_resolver.display_height("vehicle", sprite_id, direction))
		for entry: Dictionary in npc_sort_entries:
			if entry.get("node") == npc: entry["height"] = npc.get_meta("visual_height")
	visual.pixel_size=float(npc.get_meta("visual_height",NPC_ADULT_VISUAL_HEIGHT))/float(texture.get_height())
	visual.offset=Vector2(0.0,float(texture.get_height())*0.5)
	npc.set_meta("facing",direction)


func _toggle_party_menu() -> void:
	if script_runner.running: return
	if dex_panel.visible:
		dex_panel.hide()
	settings_panel.hide()
	bag_panel.hide()
	party_panel.visible = not party_panel.visible
	if party_panel.visible:
		_refresh_party_menu()


func _toggle_settings_menu() -> void:
	if script_runner.running: return
	party_panel.hide()
	bag_panel.hide()
	if dex_panel.visible:
		dex_panel.hide()
	settings_panel.visible = not settings_panel.visible


func _toggle_bag_menu() -> void:
	if script_runner.running: return
	party_panel.hide()
	settings_panel.hide()
	if dex_panel.visible:
		dex_panel.hide()
	bag_panel.visible = not bag_panel.visible


func _use_swimgear() -> void:
	if swimming or swim_transitioning:
		return
	var direction := _player_facing_direction()
	var direction_vector := _direction_vector(direction)
	var water_position := _terrain_cell_center(player.position + direction_vector)
	if _terrain_at(water_position) != "water":
		return
	_start_swimming(water_position, direction)


func _use_cloud() -> void:
	if in_battle or dialog_open or script_runner.running or swimming or swim_transitioning:
		hint_label.text = "Open the Cloud while exploring on dry land."
		return
	bag_panel.hide()
	cloud_dialog.open()


func _on_fakemon_transferred(removed_index: int) -> void:
	if removed_index == active_party_index:
		active_party_index = 0
	elif removed_index >= 0 and removed_index < active_party_index:
		active_party_index -= 1
	_refresh_party_menu()
	_update_follower_appearance()
	_auto_save()


func _use_watch() -> void:
	var world_clock := get_node_or_null("/root/WorldClock")
	bag_panel.hide()
	if world_clock == null:
		hint_label.text = "The Watch cannot reach the world clock right now."
		return
	hint_label.text = "Watch — Day %d, %s" % [int(world_clock.day) + 1, String(world_clock.formatted_time())]


func _start_swimming(water_position: Vector3, direction: String) -> void:
	if swimming or swim_transitioning or _terrain_at(water_position) != "water" or _surf_crosses_fence(water_position):
		return
	bag_panel.hide()
	water_position.y = 0.65
	swim_transitioning = true
	active_traversal_layer = 0
	active_traversal_surface = {}
	player.position.y = 0.65
	_update_bridge_occlusion_priority()
	player.velocity = Vector3.ZERO
	follower.hide()
	dive_atlas = PlayerPalette.create_texture(player_palette_preset, "dive")
	var flip_left := direction == "left"
	_set_dive_player_visual(SwimSpriteFrames.dive_actor_frame(player_gender, direction, 0, dive_atlas), flip_left)
	await get_tree().create_timer(DIVE_NEUTRAL_TIME).timeout
	_set_dive_player_visual(SwimSpriteFrames.dive_actor_frame(player_gender, direction, 1, dive_atlas), flip_left)
	await get_tree().create_timer(DIVE_THROW_TIME).timeout
	_set_dive_player_visual(SwimSpriteFrames.dive_actor_frame(player_gender, direction, 2, dive_atlas), flip_left)
	_set_swim_transition_effect(SwimSpriteFrames.dive_effect_frame(player_gender, direction, false, dive_atlas), water_position, 0.7, flip_left)
	await get_tree().create_timer(DIVE_BACKPACK_LAND_TIME).timeout
	var water_context := _terrain_context()
	var water_origin: Vector3 = water_context.get("origin", Vector3.ZERO)
	last_water_tile = "%s:%d,%d" % [_current_location(), roundi(water_position.x - water_origin.x), roundi(water_position.z - water_origin.z)]
	_set_dive_player_visual(SwimSpriteFrames.dive_actor_frame(player_gender, direction, 3, dive_atlas), flip_left)
	var jump_origin := player.position
	var jump := create_tween()
	jump.tween_method(func(progress: float) -> void:
		var previous_position := player.position
		player.position = jump_origin.lerp(water_position, progress)
		# Normal camera following is paused with movement during this transition.
		camera.position += player.position - previous_position
		swim_jump_height = sin(progress * PI) * 0.6
		_update_sort_canvas()
	, 0.0, 1.0, DIVE_JUMP_TIME)
	await jump.finished
	swim_jump_height = 0.0
	# Platform sorting refreshes child visibility every frame; hide the group
	# until the splash finishes so it cannot restore the last jump frame.
	player_sort_root.hide()
	_set_swim_transition_effect(SwimSpriteFrames.dive_effect_frame(player_gender, direction, true, dive_atlas), water_position, 1.35, flip_left)
	await get_tree().create_timer(DIVE_SPLASH_TIME).timeout
	_hide_swim_transition_effect()
	swimming = true
	swim_transitioning = false
	swim_direction = direction
	swim_atlas = PlayerPalette.create_texture(player_palette_preset, "swim")
	player_frame_index = 0
	player_animation_time = 0.0
	_set_player_visual(SwimSpriteFrames.frames(player_gender, swim_direction, swim_atlas)[0], false)
	player_sort_root.show()
	hint_label.text = "Swimming! Each new water tile has a 5% Moach encounter chance; swim onto shore to leave."
	_update_sort_canvas()


func _set_swim_transition_effect(texture: Texture2D, world_position: Vector3, visual_height: float, flip_h: bool) -> void:
	if swim_transition_effect_root == null:
		swim_transition_effect_root = _create_sorted_sprite("SwimTransitionEffect", texture)
	var visual := swim_transition_effect_root.get_node("Visual") as Sprite2D
	visual.texture = texture
	visual.flip_h = flip_h
	swim_transition_effect_position = world_position
	swim_transition_effect_height = visual_height
	swim_transition_effect_root.show()
	var pixels_per_world_unit := get_viewport().get_visible_rect().size.y / camera.size
	_update_sorted_art(swim_transition_effect_root, world_position, world_position, visual_height, pixels_per_world_unit)


func _hide_swim_transition_effect() -> void:
	if swim_transition_effect_root != null:
		swim_transition_effect_root.hide()


func _finish_swimming(exit_position: Vector3) -> void:
	swimming = false
	last_water_tile = ""
	player.position = exit_position
	player.velocity = Vector3.ZERO
	_apply_player_appearance()
	if adventure_started and not party.is_empty():
		follower.show()
		_place_follower_behind_player()
	hint_label.text = "Back on dry land."
	_update_sort_canvas()


func _update_swim_animation(input_vector: Vector2, delta: float) -> void:
	if input_vector.length_squared() > 0.01:
		if absf(input_vector.x) > absf(input_vector.y):
			swim_direction = "left" if input_vector.x < 0.0 else "right"
		else:
			swim_direction = "up" if input_vector.y < 0.0 else "down"
	player_animation_time += delta
	var frames := SwimSpriteFrames.frames(player_gender, swim_direction, swim_atlas)
	if input_vector.length_squared() > 0.01 and player_animation_time >= 0.16:
		player_animation_time = 0.0
		player_frame_index = (player_frame_index + 1) % frames.size()
	elif input_vector.length_squared() <= 0.01:
		player_frame_index = 0
	_set_player_visual(frames[player_frame_index], false)


func _set_player_visual(texture: Texture2D, flip_h: bool) -> void:
	player_sprite.texture = texture
	if player_sort_root != null:
		var visual := player_sort_root.get_node("Visual") as Sprite2D
		visual.texture = texture
		visual.flip_h = flip_h
		visual.show()


func _set_dive_player_visual(texture: Texture2D, flip_h: bool) -> void:
	_set_player_visual(texture, flip_h)
	var pixels_per_world_unit := get_viewport().get_visible_rect().size.y / camera.size
	_update_sorted_art(player_sort_root, player.position, player.position, DIVE_ACTOR_VISUAL_HEIGHT, pixels_per_world_unit)


func _player_facing_direction() -> String:
	for direction in ["left", "right", "up", "down"]:
		if player_animation.ends_with(direction):
			return direction
	return "down"


func _direction_vector(direction: String) -> Vector3:
	match direction:
		"left": return Vector3.LEFT
		"right": return Vector3.RIGHT
		"up": return Vector3.FORWARD
		_: return Vector3.BACK


func _update_map_borders(layer: int) -> void:
	var location := _current_location()
	if map_border_location != location:
		map_border_location = location
		var context := _terrain_context()
		match location:
			"medical_ward": context = {"data": map_data.medical_ward, "origin": medical_origin}
			"house": context = {"data": map_data.house, "origin": house_origin}
			"city_ward": context = {"data": map_data.rainforest_city.medical_ward, "origin": city_ward_origin}
			"orchid_house": context = {"data": map_data.rainforest_city.orchid_house, "origin": orchid_house_origin}
			"family_house": context = {"data": map_data.rainforest_city.family_house, "origin": family_house_origin}
		var region: Dictionary = context.get("data", {})
		if MapBorderLayout.has_enabled_border(region) and map_border_renderer == null:
			map_border_renderer = MapBorderRenderer.new()
			map_border_renderer.name = "MapBorders"
			world.add_child(map_border_renderer)
		if map_border_renderer != null:
			map_border_renderer.configure(region, context.get("origin", Vector3.ZERO), layer, sort_canvas)
	if map_border_renderer != null:
		map_border_renderer.update_view(camera, day_night_controller)

func _terrain_context() -> Dictionary:
	var location:=_current_location()
	if location.begins_with("authored:"):
		var map_id:=location.trim_prefix("authored:")
		var authored:Variant=map_data.get("authored_maps",{}).get(map_id,{})
		if authored is Dictionary:
			return {"data":authored,"origin":_array_to_vector3(authored.get("origin",[0,0,0]))}
	match _current_location():
		"rainforest": return {"data":map_data, "origin":Vector3.ZERO}
		"route": return {"data":map_data["route"], "origin":route_origin}
		"east_route": return {"data":map_data["east_route"], "origin":east_route_origin}
		"west_route": return {"data":map_data["west_route"], "origin":west_route_origin}
		"east_cave": return {"data":map_data["east_cave"], "origin":east_cave_origin}
		"city": return {"data":map_data["rainforest_city"], "origin":city_origin}
		_: return {}


func _terrain_at(world_position: Vector3) -> String:
	var context := _terrain_context()
	if context.is_empty():
		return ""
	var origin: Vector3 = context["origin"]
	var local := world_position - origin
	var cell := Vector2i(roundi(local.x), roundi(local.z))
	var grid: Dictionary = context["data"].get("_terrain_grid", {})
	return String(grid.get(cell, ""))


func _terrain_cell_center(world_position: Vector3) -> Vector3:
	var context := _terrain_context()
	if context.is_empty():
		return world_position
	var origin: Vector3 = context["origin"]
	return Vector3(origin.x + roundf(world_position.x - origin.x), player.position.y, origin.z + roundf(world_position.z - origin.z))


func _refresh_party_menu() -> void:
	if party_list == null:
		return
	for child in party_list.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = "PARTY (%d / %d) - click a mon to make active" % [party.size(), FakemonStorage.PARTY_CAPACITY]
	party_list.add_child(title)
	for index in party.size():
		var mon: Dictionary = party[index]
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(0, 50)
		var card_margin := MarginContainer.new()
		card_margin.add_theme_constant_override("margin_left", 7)
		card_margin.add_theme_constant_override("margin_right", 7)
		card_margin.add_theme_constant_override("margin_top", 5)
		card_margin.add_theme_constant_override("margin_bottom", 5)
		card.add_child(card_margin)
		var card_content := VBoxContainer.new()
		card_content.add_theme_constant_override("separation", 2)
		card_margin.add_child(card_content)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		card_content.add_child(row)
		var select := Button.new()
		select.text = "%s%s  Lv.%d" % ["> " if index == active_party_index else "", mon["name"], mon["level"]]
		select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select.disabled = int(mon.get("current_hp", mon["max_hp"])) <= 0
		select.pressed.connect(_select_party_mon.bind(index))
		row.add_child(select)
		var dex_button := Button.new()
		dex_button.text = "Dex"
		dex_button.custom_minimum_size.x = 48
		dex_button.pressed.connect(_show_dex_entry.bind(index))
		row.add_child(dex_button)
		var up := Button.new()
		up.text = "Up"
		up.custom_minimum_size.x = 42
		up.disabled = index == 0
		up.pressed.connect(_move_party_mon.bind(index, -1))
		row.add_child(up)
		var down := Button.new()
		down.text = "Down"
		down.custom_minimum_size.x = 52
		down.disabled = index == party.size() - 1
		down.pressed.connect(_move_party_mon.bind(index, 1))
		row.add_child(down)
		var experience := int(mon.get("experience", int(pow(float(mon["level"]), 3.0))))
		var next_level_exp := int(pow(float(int(mon["level"]) + 1), 3.0))
		var details := Label.new()
		details.text = "HP %d/%d    EXP %d/%d" % [mon.get("current_hp", mon["max_hp"]), mon["max_hp"], experience, next_level_exp]
		details.add_theme_font_size_override("font_size", 12)
		card_content.add_child(details)
		party_list.add_child(card)


func _select_party_mon(index: int) -> void:
	active_party_index = index
	_refresh_party_menu()
	_update_follower_appearance()
	_auto_save()


func _show_dex_entry(index: int) -> void:
	if index < 0 or index >= party.size():
		return
	party_panel.hide()
	dex_panel.show_entry(party[index], battle.battle_data["moves"])


func _return_from_dex() -> void:
	dex_panel.hide()
	party_panel.show()
	_refresh_party_menu()


func _move_party_mon(index: int, direction: int) -> void:
	var destination := index + direction
	if destination < 0 or destination >= party.size():
		return
	var active_mon: Dictionary = party[active_party_index]
	var moved: Dictionary = party[index]
	party[index] = party[destination]
	party[destination] = moved
	active_party_index = party.find(active_mon)
	_refresh_party_menu()
	_update_follower_appearance()
	_auto_save()


func _update_follower_appearance() -> void:
	if follower_sprite == null or party.is_empty():
		return
	var leading_mon: Dictionary = party[active_party_index]
	var art_id := String(leading_mon.get("art_id", ""))
	var path := "res://assets/fakemon/overworld/%s_Follow_%s.png" % [art_id, follower_facing]
	if not art_id.is_empty() and ResourceLoader.exists(path):
		follower_sprite.texture = load(path)
		follower_sprite.pixel_size = 0.9 / float(follower_sprite.texture.get_height())
		follower_sprite.scale = Vector3.ONE
		follower.name = "%sFollower" % leading_mon["name"].replace(" ", "")
	else:
		follower_sprite.texture = _solid_texture(Color(leading_mon["color"]))
		follower_sprite.pixel_size = 0.015
		follower_sprite.scale = Vector3(0.75, 0.9, 1.0)
		follower.name = "%sFollowerPlaceholder" % leading_mon["name"].replace(" ", "")
	if follower_sort_root!=null:
		(follower_sort_root.get_node("Visual") as Sprite2D).texture=follower_sprite.texture


func _update_follower_facing(velocity: Vector3) -> void:
	var next_facing := follower_facing
	if absf(velocity.x) > absf(velocity.z):
		next_facing = "Right" if velocity.x > 0.0 else "Left"
	else:
		next_facing = "Down" if velocity.z > 0.0 else "Up"
	if next_facing != follower_facing:
		follower_facing = next_facing
		_update_follower_appearance()


func _place_follower_behind_player() -> void:
	if follower == null:
		return
	follower.position = player.position + Vector3(0, 0, 1.25)
	follower_target = follower.position


func _input(event: InputEvent) -> void:
	if exhibit_transition or (exhibit_menu != null and exhibit_menu.visible): return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE: npc_script_movement.release_player()
	if dialog_open and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			if dialog_choosing:
				_answer_dialogue_choice(dialog_yes_button.has_focus())
				get_viewport().set_input_as_handled()
			else: _advance_dialogue()
		elif event.keycode == KEY_ESCAPE:
			script_runner.stop(); dialogue_complete_action = Callable()
			dialog_open = false
			dialog_panel.hide(); _clear_dialogue_choice()
		return
	if script_runner.running: return
	if event.is_action_pressed("party_menu") and not in_battle and map_ui.visible:
		_toggle_party_menu()
	if event is InputEventKey and event.pressed and not event.echo and adventure_started and not in_battle:
		if event.keycode == KEY_F5:
			_save_game()
		elif event.keycode == KEY_F9:
			_load_game()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_5:
			selected_save_slot = int(event.keycode - KEY_1) + 1
			save_slot_selector.select(selected_save_slot - 1)
			save_status_label.text = "Manual save slot %d selected." % selected_save_slot


func _build_player_selection() -> void:
	player_selection_panel = PanelContainer.new()
	player_selection_panel.name = "PlayerSelectionPanel"
	player_selection_panel.position = Vector2(50, 45)
	player_selection_panel.size = Vector2(860, 450)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	player_selection_panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)
	var title := Label.new()
	title.text = "CHOOSE YOUR PLAYER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 27)
	content.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Choose your player style. Appearance is saved with your adventure."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(subtitle)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	content.add_child(grid)
	for index in PLAYER_CHOICES.size():
		var choice: Dictionary = PLAYER_CHOICES[index]
		var button := Button.new()
		button.name = "PlayerChoice%d" % index
		button.text = ""
		button.custom_minimum_size = Vector2(195, 145)
		button.clip_contents = true
		button.pressed.connect(_on_player_choice_selected.bind(index))
		grid.add_child(button)
		var preview := TextureRect.new()
		preview.name = "Preview"
		var preview_atlas := PlayerPalette.create_texture(String(choice["preset"]))
		preview.texture = PlayerSpriteFrames.frames(String(choice["gender"]), "idle_down", preview_atlas)[0]
		# TextureRect retains an AtlasTexture's native frame dimensions. Scale it
		# uniformly into a shared box instead of distorting or overflowing it.
		var preview_bounds := Vector2(88, 132)
		var native_size := Vector2(preview.texture.get_size())
		var preview_scale := minf(preview_bounds.x / native_size.x, preview_bounds.y / native_size.y)
		preview.scale = Vector2.ONE * preview_scale
		preview.position = Vector2((195.0 - native_size.x * preview_scale) * 0.5, (145.0 - native_size.y * preview_scale) * 0.5)
		preview.expand_mode = TextureRect.EXPAND_KEEP_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP
		preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(preview)
	add_child(player_selection_panel)


func _on_player_choice_selected(index: int) -> void:
	if index < 0 or index >= PLAYER_CHOICES.size():
		return
	var choice: Dictionary = PLAYER_CHOICES[index]
	player_gender = String(choice["gender"])
	player_style = String(choice["style"])
	player_palette_preset = String(choice["preset"])
	player_color_name = player_style
	_apply_player_appearance()
	player_selection_panel.hide()
	_begin_unpartnered_adventure()


func _apply_player_appearance() -> void:
	if player_sprite == null:
		return
	player_atlas = PlayerPalette.create_texture(player_palette_preset)
	player_animation = "idle_down"
	player_frame_index = 0
	player_animation_time = 0.0
	player_sprite.texture = PlayerSpriteFrames.frames(player_gender, player_animation, player_atlas)[0]
	player_sprite.pixel_size = PLAYER_VISUAL_HEIGHT / float(player_sprite.texture.get_height())
	player_sprite.offset = Vector2(0.0, float(player_sprite.texture.get_height()) * 0.5)
	if player_sort_root != null:
		var visual := player_sort_root.get_node("Visual") as Sprite2D
		visual.texture = player_sprite.texture
		visual.flip_h = false
	player.name = "%s%sPlayer" % [player_style, player_gender]


func _face_script_player(facing: String) -> void:
	player.velocity = Vector3.ZERO
	player_animation = "idle_" + facing
	player_frame_index = 0
	player_animation_time = 0.0
	_update_player_animation(Vector2.ZERO, 0.0)


func _update_player_animation(input_vector: Vector2, delta: float) -> void:
	var facing := player_animation.substr(player_animation.find("_") + 1)
	var next_animation := "idle_" + facing
	if input_vector.length_squared() > 0.01:
		if absf(input_vector.x) > 0.1 and absf(input_vector.y) > 0.1:
			next_animation = "walk_" + ("up_" if input_vector.y < 0.0 else "down_") + ("left" if input_vector.x < 0.0 else "right")
		elif absf(input_vector.x) > absf(input_vector.y):
			next_animation = "walk_left" if input_vector.x < 0.0 else "walk_right"
		elif input_vector.y < 0.0:
			next_animation = "walk_up"
		else:
			next_animation = "walk_down"
	if next_animation != player_animation:
		player_animation = next_animation
		player_frame_index = 0
		player_animation_time = 0.0
	player_animation_time += delta
	var animation_frames := _player_animation_frames(player_animation)
	if player_animation.begins_with("walk_") and player_animation_time >= 0.16:
		player_animation_time = 0.0
		player_frame_index = (player_frame_index + 1) % animation_frames.size()
	var frame: Texture2D = animation_frames[player_frame_index]
	player_sprite.texture = frame
	if player_sort_root != null:
		var visual := player_sort_root.get_node("Visual") as Sprite2D
		visual.texture = frame
		visual.flip_h = player_gender == "Male" and player_animation.ends_with("left")


func _apply_player_frame_adjustment(pixels_per_world_unit: float) -> void:
	var adjustment := PlayerSpriteFrames.frame_adjustment(player_gender, player_animation, player_frame_index)
	var frame_scale: Vector2 = adjustment["scale"]
	var frame_offset: Vector2 = adjustment["offset"]
	var visual := player_sort_root.get_node("Visual") as Sprite2D
	var height_pixels := PLAYER_VISUAL_HEIGHT * pixels_per_world_unit
	visual.scale *= frame_scale
	# Scale around the feet rather than the Sprite2D center. Sorting and the
	# collision body retain their original world-space contact position.
	visual.position += Vector2(0.0, height_pixels * (1.0 - frame_scale.y) * 0.5) + frame_offset * height_pixels


func _player_animation_frames(animation: String) -> Array[AtlasTexture]:
	var gender := player_gender if not player_gender.is_empty() else "Male"
	var atlas: Texture2D = PlayerPalette.create_texture(player_palette_preset, "diagonal") if PlayerSpriteFrames.is_diagonal(animation) else player_atlas
	var authored := PlayerSpriteFrames.frames(gender, animation, atlas)
	if not animation.begins_with("walk_") or authored.size() < 2:
		return authored
	var direction := animation.trim_prefix("walk_")
	var neutral := PlayerSpriteFrames.frames(gender, "idle_" + direction, atlas)[0]
	# Each leg pose returns through the matching directional neutral pose.
	return [authored[0], neutral, authored[1], neutral]


func _build_startup_save_prompt() -> void:
	startup_panel = PanelContainer.new()
	startup_panel.position = Vector2(300, 190)
	startup_panel.size = Vector2(360, 170)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	startup_panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)
	var title := Label.new()
	title.text = "PROJECT PARADISE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	content.add_child(title)
	var continue_button := Button.new()
	continue_button.text = "Continue Saved Adventure"
	continue_button.pressed.connect(_continue_saved_adventure)
	content.add_child(continue_button)
	var new_button := Button.new()
	new_button.text = "New Adventure"
	new_button.pressed.connect(_start_new_adventure)
	content.add_child(new_button)
	add_child(startup_panel)


func _continue_saved_adventure() -> void:
	startup_panel.queue_free()
	startup_panel = null
	_load_game(0)


func _start_new_adventure() -> void:
	startup_panel.queue_free()
	startup_panel = null
	player_selection_panel.show()


func _on_save_slot_selected(index: int) -> void:
	selected_save_slot = save_slot_selector.get_item_id(index)
	save_status_label.text = "Manual save slot %d selected." % selected_save_slot


func _manual_save_path(slot: int) -> String:
	return "user://project_paradise_state_%d.json" % clampi(slot, 1, SAVE_SLOT_COUNT)


func _save_game() -> bool:
	return _write_save(_manual_save_path(selected_save_slot), true, "State %d saved." % selected_save_slot)


func _auto_save() -> bool:
	return _write_save(AUTO_SAVE_PATH, false, "")


func _write_save(path: String, show_feedback: bool, success_message: String) -> bool:
	if not adventure_started or in_battle or swimming or swim_transitioning:
		if show_feedback and save_status_label != null:
			save_status_label.text = "Return to dry land before saving." if swimming or swim_transitioning else "Saving is available while exploring."
		return false
	var location := _current_location()
	exhibits.record_owned()
	var save_data := {
		"exhibit_species": exhibits.discovered.keys(),
		"habitat_exhibits": exhibits.assignments,
		"version": SAVE_VERSION,
		"game_flags": game_flags.values,
		"player_gender": player_gender,
		"player_color_name": player_color_name,
		"player_color": player_color.to_html(false),
		"player_style": player_style,
		"player_palette_preset": player_palette_preset,
		"party": party,
		"cloud": cloud,
		"active_party_index": active_party_index,
		"location": location,
		"player_position": [player.position.x, player.position.y, player.position.z],
		"respawn_location": respawn_location,
		"respawn_position": [respawn_position.x, respawn_position.y, respawn_position.z],
		"respawn_title": respawn_title,
		"poison_step_distance": poison_step_distance
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		if save_status_label != null:
			save_status_label.text = "Save failed: storage could not be opened."
		return false
	file.store_string(JSON.stringify(save_data, "  "))
	if show_feedback and save_status_label != null:
		save_status_label.text = success_message
	return true


func _load_game(slot: int = -1) -> bool:
	var loading_auto_save := slot == 0
	var effective_slot := selected_save_slot if slot < 0 else slot
	var path := AUTO_SAVE_PATH if loading_auto_save else _manual_save_path(effective_slot)
	if in_battle or not FileAccess.file_exists(path):
		if save_status_label != null:
			save_status_label.text = "No autosave is available." if loading_auto_save else "Manual state %d is empty." % effective_slot
		return false
	return _restore_save(path)


func _restore_save(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if not parsed is Dictionary:
		if save_status_label != null:
			save_status_label.text = "Save file is invalid. Start a new adventure."
		return false
	var data := parsed as Dictionary
	if not fakemon_storage.restore(data.get("party"), data.get("cloud", [])):
		if save_status_label != null:
			save_status_label.text = "Save party or Cloud data is invalid."
		return false
	player_gender = String(data.get("player_gender", "Male"))
	player_style = String(data.get("player_style", "Medium"))
	player_palette_preset = String(data.get("player_palette_preset", PlayerPalette.DEFAULT_PRESET))
	player_color_name = player_style
	player_color = Color(String(data.get("player_color", "173f73")))
	_apply_player_appearance()
	game_flags.restore(data.get("game_flags", {}))
	# Before v2 every adventure began with a selected starter.
	if int(data.get("version",1)) < 2 and not party.is_empty(): game_flags.set_flag("Starter",true)
	script_runner.stop(); npc_script_movement.clear(); script_host.hidden_objects.clear(); script_host.reset_sprites()
	active_party_index = clampi(int(data.get("active_party_index", 0)), 0, maxi(0,party.size() - 1))
	poison_step_distance = clampf(float(data.get("poison_step_distance", 0.0)), 0.0, 0.999)
	var saved_position: Variant = data.get("player_position", map_data["player_spawn"])
	player.position = _array_to_vector3(saved_position as Array) if saved_position is Array and saved_position.size() >= 3 else spawn_position
	var saved_respawn_position: Variant = data.get("respawn_position", map_data["player_spawn"])
	respawn_position = _array_to_vector3(saved_respawn_position as Array) if saved_respawn_position is Array and saved_respawn_position.size() >= 3 else spawn_position
	respawn_location = String(data.get("respawn_location", "rainforest"))
	if not ["rainforest", "city"].has(respawn_location):
		respawn_location = "rainforest"
		respawn_position = spawn_position
	respawn_title = String(data.get("respawn_title", "MOSSVALE RAINFOREST CITY" if respawn_location == "city" else "RAINFOREST CLEARING - PLACEHOLDER MAP"))
	var location := String(data.get("location", "rainforest"))
	inside_medical_ward = location == "medical_ward"
	inside_house = location == "house"
	inside_route = location == "route"
	inside_east_route = location == "east_route"
	inside_west_route = location == "west_route"
	inside_east_cave = location == "east_cave"
	inside_city = location == "city"
	inside_city_ward = location == "city_ward"
	inside_orchid_house = location == "orchid_house"
	inside_family_house = location == "family_house"
	active_authored_map_id = location.trim_prefix("authored:") if location.begins_with("authored:") else ""
	dialog_open = false
	dialog_panel.hide()
	if player_selection_panel != null: player_selection_panel.hide()
	party_panel.hide()
	settings_panel.hide()
	bag_panel.hide()
	dex_panel.hide()
	last_grass_tile = ""
	last_water_tile = ""
	exhibits.restore(data.get("exhibit_species", []), data.get("habitat_exhibits", {}))
	_apply_loaded_location(location)
	player.velocity = Vector3.ZERO
	adventure_started = true
	in_battle = false
	battle.hide()
	_set_overworld_visuals_visible(true)
	map_ui.visible = true
	_update_follower_appearance()
	follower.visible = not party.is_empty()
	_place_follower_behind_player()
	_refresh_party_menu()
	if save_status_label != null:
		save_status_label.text = ""
	return true


func _apply_loaded_location(location: String) -> void:
	if location.begins_with("authored:"):
		active_authored_map_id = location.trim_prefix("authored:")
		var authored: Dictionary = map_data.get("authored_maps", {}).get(active_authored_map_id, {})
		camera.size = OUTDOOR_CAMERA_SIZE
		# Editor relocation preserves local coordinates, but older saves contain
		# absolute positions. Recover at the entry if that room has moved.
		if _is_authored_indoor_map(authored):
			var origin := _array_to_vector3(authored.get("origin", [0, 0, 0]))
			var dimensions: Array = authored.get("size", authored.get("interior_size", [20, 20]))
			var local := player.position - origin
			var center:=MapBounds.center(authored)
			if absf(local.x-center.x) > float(dimensions[0]) * 0.5 or absf(local.z-center.y) > float(dimensions[1]) * 0.5:
				player.position = origin + _array_to_vector3(authored.get("entry", [0, 0.65, 0]))
		world_environment.background_color = Color("#3d453d") if _is_authored_indoor_map(authored) else OUTDOOR_BACKGROUND
		map_title.text = String(authored.get("map_metadata", {}).get("display_name", active_authored_map_id.replace("_", " ").to_upper()))
		hint_label.text = "Loaded in %s." % map_title.text
	elif location == "medical_ward":
		camera.size = 9.0
		world_environment.background_color = Color("#354b5e")
		map_title.text = "MEDICAL WARD - PLACEHOLDER INTERIOR"
		hint_label.text = "Loaded inside the medical ward. Walk onto the door tile to leave."
	elif location == "house":
		camera.size = 8.0
		world_environment.background_color = Color("#55483d")
		map_title.text = "RAINFOREST HOUSE - PLACEHOLDER INTERIOR"
		hint_label.text = "Loaded inside the house. Click the orange resident to talk."
	elif location == "route":
		camera.size = OUTDOOR_CAMERA_SIZE
		world_environment.background_color = OUTDOOR_BACKGROUND
		map_title.text = "CANOPY ROUTE - PLACEHOLDER MAP"
		hint_label.text = "Loaded on Canopy Route. Water is uncrossable; the trainer waits at the far end."
	elif location == "east_route":
		camera.size = OUTDOOR_CAMERA_SIZE
		world_environment.background_color = OUTDOOR_BACKGROUND
		map_title.text = "EASTERN RAINFOREST ROUTE"
		hint_label.text = "Loaded on the eastern route. The cave lies deeper in the rainforest."
	elif location == "west_route":
		camera.size = OUTDOOR_CAMERA_SIZE
		world_environment.background_color = OUTDOOR_BACKGROUND
		map_title.text = "WESTERN RAINFOREST ROUTE"
		hint_label.text = "Loaded on the western rainforest route."
	elif location == "east_cave":
		camera.size = 12.0
		world_environment.background_color = Color("#3d453d")
		map_title.text = "VINESTONE CAVE - PLACEHOLDER MAP"
		hint_label.text = "Loaded in Vinestone Cave. Blue flowers and vines grow among the rocks."
	elif location == "city":
		camera.size = OUTDOOR_CAMERA_SIZE
		world_environment.background_color = OUTDOOR_BACKGROUND
		map_title.text = "MOSSVALE RAINFOREST CITY"
		hint_label.text = "Loaded in Mossvale City. Visit the ward or either home."
	elif location == "city_ward":
		camera.size = 9.0
		world_environment.background_color = Color("#354b5e")
		map_title.text = "MOSSVALE MEDICAL WARD"
		hint_label.text = "Loaded inside the Mossvale medical ward."
	elif location == "orchid_house":
		camera.size = 9.0
		world_environment.background_color = Color("#55483d")
		map_title.text = "GROUND ORCHID HOUSE"
		hint_label.text = "Loaded inside the ground orchid home."
	elif location == "family_house":
		camera.size = 11.0
		world_environment.background_color = Color("#55483d")
		map_title.text = "MOSSVALE FAMILY HOME"
		hint_label.text = "Loaded inside the family home."
	else:
		inside_medical_ward = false
		inside_house = false
		inside_route = false
		inside_east_route = false
		inside_west_route = false
		inside_east_cave = false
		inside_city = false
		inside_city_ward = false
		inside_orchid_house = false
		inside_family_house = false
		camera.size = OUTDOOR_CAMERA_SIZE
		world_environment.background_color = OUTDOOR_BACKGROUND
		map_title.text = "RAINFOREST CLEARING - PLACEHOLDER MAP"
		hint_label.text = "Adventure loaded. Move with WASD / Arrow Keys."
	var is_inside := inside_medical_ward or inside_house or inside_east_cave or inside_city_ward or inside_orchid_house or inside_family_house
	camera.position = Vector3(player.position.x, 7.0 if is_inside else 18.0, player.position.z + (7.0 if is_inside else 18.0))
	_set_active_visual_region(location)
	_run_map_headers(location)


func _current_location() -> String:
	if not active_authored_map_id.is_empty():
		return "authored:" + active_authored_map_id
	if inside_medical_ward:
		return "medical_ward"
	if inside_house:
		return "house"
	if inside_city_ward:
		return "city_ward"
	if inside_orchid_house:
		return "orchid_house"
	if inside_family_house:
		return "family_house"
	if inside_city:
		return "city"
	if inside_east_cave:
		return "east_cave"
	if inside_east_route:
		return "east_route"
	if inside_west_route:
		return "west_route"
	if inside_route:
		return "route"
	return "rainforest"


func _configure_visual_regions() -> void:
	applied_visual_location = ""
	collision_regions_dirty=true
	if not world.child_entered_tree.is_connected(_on_world_collision_changed):
		world.child_entered_tree.connect(_on_world_collision_changed)
		world.child_exiting_tree.connect(_on_world_collision_changed)
	var dynamic_mask := 1 << (DYNAMIC_VISUAL_LAYER - 1)
	for node: Node in world.find_children("*", "GeometryInstance3D", true, false):
		var visual := node as GeometryInstance3D
		if visual.get_meta("border_foreground_source", false): continue
		if visual == player_sprite or visual == follower_sprite:
			visual.layers = dynamic_mask
			continue
		var layer := int(visual.get_meta("visual_layer", _visual_layer_for_position(visual.global_position)))
		visual.layers = 1 << (mini(layer, DYNAMIC_VISUAL_LAYER - 1) - 1)
	for node: Node in world.find_children("*", "CollisionObject3D", true, false):
		var collision := node as CollisionObject3D
		if collision == player: continue
		if not collision.has_meta("visual_layer"):
			collision.set_meta("visual_layer", _visual_layer_for_position(collision.global_position))
		collision.set_meta("base_collision_layer", collision.collision_layer)

func _assign_visual_region(node: Node, layer: int) -> void:
	node.set_meta("visual_layer", layer)
	if node is GeometryInstance3D:
		# Keep logical collision/sorting regions independent beyond Godot's render
		# layer budget. Distant shared-layout instances can reuse the last map bit.
		(node as GeometryInstance3D).layers = 1 << (mini(layer, DYNAMIC_VISUAL_LAYER - 1) - 1)
	for child: Node in node.get_children(): _assign_visual_region(child, layer)


func _visual_layer_for_position(position: Vector3) -> int:
	var region_centers := {
		1: Vector3.ZERO,
		2: medical_origin,
		3: house_origin,
		4: route_origin,
		5: east_route_origin,
		6: west_route_origin,
		7: east_cave_origin,
		8: city_origin,
		9: city_ward_origin,
		10: orchid_house_origin,
		11: family_house_origin,
	}
	var closest_layer := 1
	var closest_distance := INF
	for layer: int in region_centers:
		var distance := position.distance_squared_to(region_centers[layer])
		if distance < closest_distance:
			closest_distance = distance
			closest_layer = layer
	return closest_layer


func _on_world_collision_changed(node:Node)->void:
	if node is CollisionObject3D and not node.get_meta("patrol_spawn", false): collision_regions_dirty = true


# Traffic actors enter the current region and already have their authored masks.
func _track_patrol_collision(npc: Area3D, added: bool) -> void:
	var layer := int(npc.get_meta("visual_layer"))
	if not collision_regions.has(layer): collision_regions[layer] = []
	var colliders: Array = [npc]
	colliders.append_array(npc.find_children("*", "CollisionObject3D", true, false))
	for collider in colliders:
		if added: collision_regions[layer].append(collider)
		else: collision_regions[layer].erase(collider)


func _set_collision_region_active(layer:int,enabled:bool)->void:
	for collision:CollisionObject3D in collision_regions.get(layer,[]):
		if not is_instance_valid(collision):continue
		var npc_enabled := enabled and not bool(collision.get_meta("script_hidden", false))
		if collision.has_meta("gate_open"): collision.set_meta("region_collision_enabled", npc_enabled)
		collision.collision_layer = int(collision.get_meta("base_collision_layer", 1)) if npc_enabled and not collision.get_meta("gate_open", false) else 0
		if collision is Area3D:
			var authored: Dictionary = collision.get_meta("npc_authored_collision", {"monitoring":true,"monitorable":true})
			collision.set_deferred("monitoring", npc_enabled and authored.monitoring)
			collision.set_deferred("monitorable", npc_enabled and authored.monitorable)


func _set_active_visual_region(location: String) -> void:
	if camera == null or (applied_visual_location == location and not collision_regions_dirty):
		return
	var previous_layer:=_active_visual_layer(applied_visual_location) if not applied_visual_location.is_empty() else -1
	applied_visual_location = location
	var active_layer := _active_visual_layer(location)
	camera.cull_mask = (1 << (mini(active_layer, DYNAMIC_VISUAL_LAYER - 1) - 1)) | (1 << (DYNAMIC_VISUAL_LAYER - 1))
	if collision_regions_dirty:
		collision_regions.clear()
		for node:Node in world.find_children("*","CollisionObject3D",true,false):
			var collision:=node as CollisionObject3D
			if collision==player or not collision.has_meta("visual_layer"):continue
			var layer:=int(collision.get_meta("visual_layer"))
			if not collision.has_meta("base_collision_layer"):collision.set_meta("base_collision_layer",collision.collision_layer)
			if not collision_regions.has(layer):collision_regions[layer]=[]
			collision_regions[layer].append(collision)
		for layer:int in collision_regions:_set_collision_region_active(layer,layer==active_layer)
		collision_regions_dirty=false
	else:
		_set_collision_region_active(previous_layer,false)
		_set_collision_region_active(active_layer,true)
	if day_night_controller != null:
		day_night_controller.set_map_type(_map_type_for_location(location))

func _map_type_for_location(location: String) -> String:
	var region: Variant = map_data
	if location.begins_with("authored:"):
		region = map_data.get("authored_maps", {}).get(location.trim_prefix("authored:"), {})
		if _is_authored_indoor_map(region):return "Indoor"
		return String(region.get("map_type", "Rainforest")) if region is Dictionary else "Rainforest"
	match location:
		"medical_ward": region = map_data.get("medical_ward", {})
		"house": region = map_data.get("house", {})
		"route": region = map_data.get("route", {})
		"east_route": region = map_data.get("east_route", {})
		"west_route": region = map_data.get("west_route", {})
		"east_cave": region = map_data.get("east_cave", {})
		"city": region = map_data.get("rainforest_city", {})
		"city_ward": region = map_data.get("rainforest_city", {}).get("medical_ward", {})
		"orchid_house": region = map_data.get("rainforest_city", {}).get("orchid_house", {})
		"family_house": region = map_data.get("rainforest_city", {}).get("family_house", {})
	return String(region.get("map_type", "Rainforest")) if region is Dictionary else "Rainforest"


func _active_visual_layer(location: String = "") -> int:
	var resolved_location := _current_location() if location.is_empty() else location
	if resolved_location.begins_with("authored:"):
		var map_id := resolved_location.trim_prefix("authored:")
		for region: Dictionary in authored_visual_regions:
			if String(region.id) == map_id: return int(region.layer)
	var location_layers := {
		"rainforest": 1,
		"medical_ward": 2,
		"house": 3,
		"route": 4,
		"east_route": 5,
		"west_route": 6,
		"east_cave": 7,
		"city": 8,
		"city_ward": 9,
		"orchid_house": 10,
		"family_house": 11,
	}
	return int(location_layers.get(resolved_location, 1))


func _clamp_player_to_region(origin: Vector3, region_size: Array,margin:float=0.6) -> void:
	player.position.x = clampf(player.position.x, origin.x - float(region_size[0]) * 0.5 + margin, origin.x + float(region_size[0]) * 0.5 - margin)
	player.position.z = clampf(player.position.z, origin.z - float(region_size[1]) * 0.5 + margin, origin.z + float(region_size[1]) * 0.5 - margin)


func _load_map_data() -> Dictionary:
	return MapDataLoader.load_world(MAP_DATA_PATH)


func _array_to_vector3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


func _solid_texture(color: Color) -> ImageTexture:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _billboard_sprite(texture: Texture2D, height: float, sprite_name: String) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.add_to_group("day_night_world_sprites")
	sprite.name = sprite_name
	sprite.texture = texture
	sprite.pixel_size = height / float(texture.get_height())
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	return sprite


func _square_sprite(color: Color, label_text: String, size: Vector2) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.add_to_group("day_night_world_sprites")
	sprite.texture = _solid_texture(color)
	sprite.pixel_size = 0.015
	sprite.scale = Vector3(size.x, size.y, 1.0)
	# Actors sort from their feet, while their artwork extends upward from that point.
	# Positive local Y keeps the pixels above the ground plane.
	sprite.offset = Vector2(0.0, 32.0)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	# Names provide readable placeholder identification in the remote scene tree.
	sprite.name = label_text + "SpritePlaceholder"
	return sprite


func _box_shape(size: Vector3) -> CollisionShape3D:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	return collision


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material


func _textured_material(texture: Texture2D, color: Color = Color.WHITE, uv_scale: Vector3 = Vector3.ONE) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.albedo_color = color
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if texture == TEX_GRASS:
		# Visual-only 180-degree correction for the authored forest-floor texture.
		material.uv1_scale = Vector3(-uv_scale.x, -uv_scale.y, uv_scale.z)
		material.uv1_offset = Vector3(uv_scale.x, uv_scale.y, 0.0)
	else:
		material.uv1_scale = uv_scale
	return material


func _build_placed_npcs(region_data: Dictionary, origin: Vector3) -> void:
	var map_file := String(region_data.get("_npc_map_file", ""))
	if map_file.is_empty() or runtime_npcs.has(map_file): return
	if npc_visual_resolver == null: npc_visual_resolver = NpcVisualResolver.new(ProjectSettings.globalize_path("res://"))
	var instances := {}
	runtime_npcs[map_file] = instances
	for record: Dictionary in region_data.get("_resolved_npcs", []):
		_spawn_placed_npc(region_data, origin, record)
	patrols.register(region_data, origin)

func _spawn_placed_npc(region_data: Dictionary, origin: Vector3, record: Dictionary, patrol_spawn: bool = false) -> Area3D:
	var map_file := String(region_data.get("_npc_map_file", ""))
	var texture:Texture2D = npc_visual_resolver.texture_for(String(record.type), String(record.sprite), String(record.facing))
	if texture == null:
		push_warning("NPC %s/%d could not resolve art." % [map_file, int(record.id)])
		return null
	var npc := _add_talking_npc("PlacedNPC_%s_%d" % [map_file.get_basename(), int(record.id)], origin + _array_to_vector3(record.position) + Vector3(0,NpcMovement.elevation(record),0), Color("#67c46a"), String(record.sprite), [String(record.get("interaction_text", ""))], Callable(), "", patrol_spawn)
	npc.set_meta('script_map', map_file); npc.set_meta('script_npc_id', str(int(record.id)))
	var height: float = npc_visual_resolver.display_height(String(record.type), String(record.sprite), String(record.facing)) if record.type == "vehicle" else NPC_ADULT_VISUAL_HEIGHT if record.type == "human" else 0.9
	var visual := npc.get_child(0) as Sprite3D
	visual.texture = texture
	visual.pixel_size = height / float(texture.get_height())
	visual.offset = Vector2(0, float(texture.get_height()) * 0.5)
	if record.type == "vehicle":
		npc_dialogues.erase(npc.get_instance_id())
		npc.input_ray_pickable = false
	npc.set_meta("authored_hidden", bool(record.get("hidden", false)))
	npc.set_meta("sprite_id", String(record.sprite))
	npc.set_meta("npc_definition", {"type":record.type,"sprite":record.sprite,"interaction_text":record.get("interaction_text", "")})
	npc.set_meta("movement_mode", "swimming" if record.type == "vehicle" else String(record.get("movement_mode","ground")))
	npc.set_meta("base_elevation", origin.y + float(record.position[1]))
	npc.set_meta("water_grid", region_data.get("_terrain_grid",{}))
	npc.set_meta("map_origin", origin)
	var map_size: Array = region_data.get("size", region_data.get("interior_size", []))
	if map_size.size() >= 2:
		npc.set_meta("wander_bounds", Rect2(Vector2(origin.x, origin.z)+MapBounds.center(region_data) - Vector2(float(map_size[0]), float(map_size[1])) * 0.5, Vector2(float(map_size[0]), float(map_size[1]))))
	if MapBorderLayout.has_enabled_border(region_data):
		var bounds := MapBounds.rect(region_data)
		bounds.position += Vector2(origin.x, origin.z)
		npc.set_meta("border_playable_bounds", bounds)
	if npc.get_meta("movement_mode") == "swimming":
		if not _npc_in_water(npc,npc.position): push_warning("Swimming NPC %d is outside canonical water; movement is paused." % int(record.id))
		_ensure_water_surface(region_data,origin,map_file)
	npc.set_meta("script_movement_owned", preload("res://world/scripting/script_paths.gd").movement_actors(region_data).has(int(record.id)))
	npc.set_meta("npc_id", int(record.id))
	npc.set_meta("facing", String(record.facing))
	npc.set_meta("visual_height", height)
	npc_sort_entries[-1]["height"] = height
	# Placed NPC coordinates are ground anchors, unlike legacy character centers.
	(npc.get_node("FootCollision") as StaticBody3D).position.y = NPC_FOOT_COLLISION_SIZE.y * 0.5
	if record.type == "vehicle": _configure_vehicle_hull(npc, String(record.facing))
	script_host.remember_sprite_collision(npc)
	runtime_npcs[map_file][int(record.id)] = npc
	if npc.get_meta("authored_hidden"): script_host.set_sprite_hidden(npc, true, false)
	npc_movement_states[npc.get_instance_id()] = NpcMovement.new(npc.position, NpcMovement.settings(record), hash(map_file+str(int(record.id))))

	return npc


func _update_placed_npcs(delta: float) -> void:
	if not adventure_started or in_battle or dialog_open or swim_transitioning: return
	var active_layer := _active_visual_layer()
	for instances: Dictionary in runtime_npcs.values():
		for npc: Area3D in instances.values():
			if script_input_locked and not npc_script_movement.waiters.has(npc.get_instance_id()): continue
			if script_host.sprite_hidden(npc) or npc.get_meta("script_movement_owned", false) or npc_script_movement.controls(npc): continue
			if int(npc.get_meta("visual_layer", _visual_layer_for_position(npc.global_position))) != active_layer: continue
			var state: RefCounted = npc_movement_states.get(npc.get_instance_id())
			if state == null: continue
			var planned: Dictionary = state.step(npc.position, String(npc.get_meta("facing","down")), delta)
			if npc.has_meta("wander_bounds"):
				var bounds: Rect2 = npc.get_meta("wander_bounds")
				bounds = bounds.grow_individual(-NPC_FOOT_COLLISION_SIZE.x * 0.5, -NPC_FOOT_COLLISION_SIZE.z * 0.5, -NPC_FOOT_COLLISION_SIZE.x * 0.5, -NPC_FOOT_COLLISION_SIZE.z * 0.5)
				var bounded: Vector3 = planned.position
				# A scripted placement outside the floor may walk back in without
				# teleporting, but autonomous movement cannot take it farther out.
				bounded.x = clampf(bounded.x, minf(npc.position.x, bounds.position.x), maxf(npc.position.x, bounds.end.x))
				bounded.z = clampf(bounded.z, minf(npc.position.z, bounds.position.y), maxf(npc.position.z, bounds.end.y))
				if not bounded.is_equal_approx(planned.position): state.blocked(bounded)
				planned.position = bounded
			var previous_position := npc.position
			var requested: Vector3 = planned.position - npc.position
			if requested.length_squared() > 0.000001:
				var fraction := _move_vehicle_fraction(npc, requested)
				npc.position += requested * fraction
				if fraction < 0.999: state.blocked(npc.position)
			_animate_placed_npc(npc, previous_position, String(planned.facing), delta)

func _npc_bed_sort_position(npc: Area3D, feet: Vector3) -> Vector3:
	if npc.get_meta("npc_definition", {}).get("type", "") != "fakemon" or npc.get_meta("movement_mode", "ground") == "swimming": return feet
	var layer := int(npc.get_meta("visual_layer", _visual_layer_for_position(npc.global_position)))
	for entry: Dictionary in object_sort_entries:
		if entry.get("furnishing_type", "") != "bed" or _sort_entry_layer(entry, entry.placement) != layer or script_host.object_hidden(entry): continue
		var placement: Vector3 = entry.placement
		var height := float(entry.height)
		var texture: Texture2D = entry.texture
		var width := height * float(texture.get_width()) / float(texture.get_height())
		# Beds extend north from their foot anchor. Keep occupants above the bed
		# while retaining ordinary Y sorting against the rest of the room.
		if absf(feet.x - placement.x) <= width * 0.5 and feet.z >= placement.z - height and feet.z <= placement.z:
			feet.z = maxf(feet.z, placement.z + float(entry.get("sort_offset_y", 0.0)) + 0.001)
	return feet


func _move_script_player(motion: Vector3, delta: float) -> void:
	if delta <= 0 or player == null: return
	player.velocity = _swim_constrained_velocity(motion / delta, delta) if swimming else _terrain_constrained_velocity(motion / delta, delta)
	player.move_and_slide()
	if script_input_locked: _update_player_animation(Vector2(player.velocity.x,player.velocity.z).normalized(), delta)
	if follower != null:
		follower_target = player.position - motion.normalized()*1.25

func _animate_placed_npc(npc: Area3D, previous_position: Vector3, facing: String, delta: float) -> void:
	var walk_frame := -1
	var definition: Dictionary = npc.get_meta("npc_definition", {})
	if definition.get("type") == "vehicle":
		walk_frame = 0 if npc.position.distance_squared_to(previous_position) > 0.000001 else -1
	elif definition.get("type", "") == "human" and npc.position.distance_squared_to(previous_position) > 0.000001:
		var frame_count := NpcSpriteLibrary.walk_frame_count(String(definition.sprite))
		if frame_count > 0:
			var animation_time := float(npc.get_meta("walk_animation_time", 0.0)) + delta
			npc.set_meta("walk_animation_time", fmod(animation_time, 0.16 * frame_count))
			walk_frame = int(animation_time / 0.16) % frame_count
	else: npc.set_meta("walk_animation_time", 0.0)
	_set_npc_pose(npc, facing, walk_frame)

func _npc_motion_fraction(npc: Area3D, motion: Vector3, from_position: Variant = null, ignore: Array[RID] = []) -> float:
	var start:Vector3 = npc.position if from_position == null else from_position
	var limit := _npc_playable_motion_fraction(npc, start, motion)
	if limit <= 0.0: return 0.0
	motion *= limit
	var steps := maxi(1,ceili(motion.length()/0.05))
	for index in steps:
		var fraction := _npc_floor_motion_fraction(npc,motion/steps,start+motion*float(index)/steps,ignore)
		if fraction < 0.999:return limit * (float(index)+fraction)/steps
	return limit

func _npc_playable_motion_fraction(npc: Area3D, start: Vector3, motion: Vector3) -> float:
	if not npc.has_meta("border_playable_bounds"): return 1.0
	var bounds: Rect2 = npc.get_meta("border_playable_bounds")
	var half := Vector2(NPC_FOOT_COLLISION_SIZE.x, NPC_FOOT_COLLISION_SIZE.z) * 0.5
	var point := Vector2(start.x, start.z)
	var travel := Vector2(motion.x, motion.z)
	# An NPC placed outside the bounds can return without walking farther out.
	var lower := (bounds.position + half).min(point)
	var upper := (bounds.end - half).max(point)
	var fraction := 1.0
	for axis in 2:
		if travel[axis] > 0: fraction = minf(fraction, (upper[axis] - point[axis]) / travel[axis])
		if travel[axis] < 0: fraction = minf(fraction, (lower[axis] - point[axis]) / travel[axis])
	return fraction

func _npc_floor_motion_fraction(npc: Area3D, motion: Vector3, from_position: Variant = null, ignore: Array[RID] = []) -> float:
	var foot: StaticBody3D
	for child in npc.get_children():
		if child is StaticBody3D: foot = child; break
	if foot == null or foot.get_child_count() == 0: return 0.0
	var shape := foot.get_child(0) as CollisionShape3D
	if shape == null: return 0.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape.shape
	query.transform = shape.global_transform
	var start: Vector3 = npc.position if from_position == null else from_position
	query.transform.origin += start - npc.position
	query.motion = motion
	query.margin = 0.001
	query.collision_mask = _floor_collision_mask(npc,start)
	if npc.get_meta("movement_mode","ground") == "swimming":
		var steps := maxi(1,ceili(motion.length()/0.1))
		for index in range(steps+1):
			if not _npc_in_water(npc,start+motion*float(index)/float(steps)): return 0.0
		query.collision_mask = 1 | PLATFORM_WALL_LAYER
		if npc.get_meta("npc_definition", {}).get("type") != "vehicle":
			query.transform.origin.y = float(npc.get_meta("base_elevation",0.0)) + NPC_FOOT_COLLISION_SIZE.y*0.5
	# Water walls are ground-traversal barriers, not physical two-unit walls.
	if npc.get_meta("movement_mode","ground") == "flying": query.collision_mask = 1 | PLATFORM_WALL_LAYER
	query.exclude = [npc.get_rid(),foot.get_rid()]
	query.exclude += ignore
	var space := npc.get_world_3d().direct_space_state
	# Sweeps alone ignore colliders already overlapping the starting shape.
	query.motion = Vector3.ZERO
	if not space.intersect_shape(query,1).is_empty(): return 0.0
	# Leave room between queued hulls. At exact contact the overlap check
	# can otherwise pin both boats, even when the lead boat moves away.
	var clearance := 0.0
	if npc.get_meta("patrol_spawn", false) and not motion.is_zero_approx():
		clearance = 0.05
		query.motion = motion + motion.normalized() * clearance
	else:
		query.motion = motion
	var fraction := space.cast_motion(query)
	if fraction.size() != 2: return 0.0
	if clearance == 0.0 or fraction[0] >= 1.0: return float(fraction[0])
	return clampf((float(fraction[0]) * query.motion.length() - clearance) / motion.length(), 0.0, 1.0)


func _npc_in_water(npc: Area3D, candidate: Vector3) -> bool:
	var grid: Dictionary = npc.get_meta("water_grid",{})
	var origin: Vector3 = npc.get_meta("map_origin",Vector3.ZERO)
	var footprint: Rect2 = npc.get_meta("hull_footprint",Rect2(Vector2(-NPC_FOOT_COLLISION_SIZE.x,-NPC_FOOT_COLLISION_SIZE.z)*0.5,Vector2(NPC_FOOT_COLLISION_SIZE.x,NPC_FOOT_COLLISION_SIZE.z)))
	return _water_covers_footprint(grid, candidate - origin, footprint)

func _water_covers_footprint(grid: Dictionary, local: Vector3, footprint: Rect2) -> bool:
	# Check every covered cell, including land holes inside a long hull.
	var first := Vector2i(floori(local.x+footprint.position.x+0.5),floori(local.z+footprint.position.y+0.5))
	var last := Vector2i(floori(local.x+footprint.end.x+0.5),floori(local.z+footprint.end.y+0.5))
	for x in range(first.x,last.x+1):
		for z in range(first.y,last.y+1):
			if grid.get(Vector2i(x,z),"") != "water": return false
	return true

func _vehicle_spawn_clear(anchor: Vector3, footprint: Rect2) -> bool:
	var center := footprint.get_center()
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _vehicle_hull_shape(footprint)
	query.transform.origin = anchor + Vector3(center.x, 0.3, center.y)
	query.margin = 0.001
	query.collision_mask = 1 | PLATFORM_WALL_LAYER
	return world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _vehicle_hull_shape(footprint: Rect2) -> BoxShape3D:
	var box := BoxShape3D.new()
	box.size = Vector3(footprint.size.x, 0.6, footprint.size.y)
	return box


func _overworld_asset_metadata(asset_path: String) -> Dictionary:
	var path := asset_path.get_basename()+".json"
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _water_surface_key(region_data: Dictionary, prefix: String) -> String:
	var map_file := String(region_data.get("_npc_map_file",""))
	return map_file if not map_file.is_empty() else prefix


func _ensure_water_surface(region_data: Dictionary, origin: Vector3, prefix: String) -> void:
	var key := _water_surface_key(region_data,prefix)
	if not npc_water_surfaces.has(key):
		npc_water_surfaces[key] = {"grid":region_data.get("_terrain_grid",{}),"origin":origin,"node":null,"walls":region_data.get("objects",[]),"floor_clip":region_data.get("_habitat_floor_clip",PackedVector2Array()),"visual_layer":_visual_layer_for_position(origin)}


func _update_npc_water_surfaces(active_layer: int) -> void:
	var view_cache:=preload("res://world/terrain_camera_view.gd")
	var signature:Array=view_cache.signature(camera)
	# Camera translation only moves the common parent. Local polygon vertices
	# depend on projection/basis/viewport, so moving never retriangulates water.
	var geometry_signature:Array=signature.duplicate()
	geometry_signature[1]=camera.global_basis
	var view:Rect2=view_cache.ground_rect(camera)
	for surface: Dictionary in npc_water_surfaces.values():
		var container:Node2D = surface.node if is_instance_valid(surface.node) else null
		if container == null:
			container = Node2D.new();container.name = "NpcWaterSurface";container.z_index = -1 if surface.floor_clip.is_empty() else 1;sort_root.add_child(container);surface.node = container
			for cell: Vector2i in surface.grid:
				if surface.grid[cell] != "water": continue
				for region:Rect2 in preload("res://tools/map_editor/core/wall_water_clip.gd").regions(cell,surface.grid,surface.get("walls",[])):
					for polygon in HabitatExhibits.water_tint_polygons(cell, region, surface.grid, surface.floor_clip):
						var patch := Polygon2D.new();patch.color = Color(0.12,0.52,0.72,0.32);patch.set_meta("cell",cell);patch.set_meta("region_polygon",polygon);container.add_child(patch)
		container.visible = int(surface.visual_layer) == active_layer
		if not container.visible: continue
		var anchor:Vector3=surface.origin+Vector3(0,0.401,0)
		var projected_origin:=camera.unproject_position(anchor)
		container.position=projected_origin
		# Perspective projection changes shape with translation; orthographic is
		# the game's normal camera and uses the cheaper translation-only path.
		var geometry_key:Array=geometry_signature if camera.projection==Camera3D.PROJECTION_ORTHOGONAL else signature
		var rebuild:bool=surface.get("geometry_signature",[])!=geometry_key
		var recull:bool=rebuild or surface.get("view_signature",[])!=signature
		if not recull:continue
		for patch: Polygon2D in container.get_children():
			var cell: Vector2i = patch.get_meta("cell")
			if rebuild:
				var corners := PackedVector2Array()
				for corner:Vector2 in patch.get_meta("region_polygon"):
					corners.append(camera.unproject_position(anchor+Vector3(corner.x,0,corner.y))-projected_origin)
				patch.polygon=corners
			var cell_rect:=Rect2(Vector2(surface.origin.x+cell.x-0.5,surface.origin.z+cell.y-0.5),Vector2.ONE)
			patch.visible=view.intersects(cell_rect,true)
		surface.geometry_signature=geometry_key
		surface.view_signature=signature

func _overworld_light_species(species_name: String) -> Dictionary:
	for species: Dictionary in battle.battle_data.get("fakemon", []):
		if String(species.get("name", "")) == species_name:
			return species
	return {}

func _update_fakemon_lights() -> void:
	if day_night_controller == null:
		return
	var sources: Array = []
	if follower_sort_root != null:
		var species := _overworld_light_species(String(party[active_party_index].get("name", ""))) if not party.is_empty() else {}
		var emits := bool(species.get("light_source", false))
		var follower_art := follower_sort_root.get_node("Visual") as Sprite2D
		follower_art.set_meta("overworld_light_source", emits)
		follower_art.material = day_night_controller.emissive_material if emits else day_night_controller.canvas_light_material
		if emits and follower_sort_root.is_visible_in_tree():
			sources.append({"position": follower.global_position, "radius": float(species.get("light_strength", 0.5))})
	for entry: Dictionary in npc_sort_entries:
		var npc: Area3D = entry.node
		var definition: Dictionary = npc.get_meta("npc_definition", {})
		var species := _overworld_light_species(String(definition.get("sprite", ""))) if definition.get("type", "") == "fakemon" else {}
		var emits := bool(species.get("light_source", false))
		var art: Sprite2D = entry.sort_root.get_node("Visual")
		art.set_meta("overworld_light_source", emits)
		art.material = day_night_controller.emissive_material if emits else day_night_controller.canvas_light_material
		if emits and art.is_visible_in_tree():
			sources.append({"position": npc.global_position + Vector3(0, float(entry.height) * 0.5, 0), "radius": float(species.get("light_strength", 0.5))})
	for entry: Dictionary in object_sort_entries:
		if not bool(entry.get("light_source", false)):
			continue
		var art: Sprite2D = entry.sort_root.get_node("Visual")
		art.set_meta("overworld_light_source", true)
		art.material = day_night_controller.emissive_material
		if art.is_visible_in_tree():
			sources.append({"position": entry.visual_center, "radius": float(entry.get("light_strength", 0.5))})
	day_night_controller.update_overworld_lights(camera, sort_root, sources)


func _report_collision_blocker(collider: Object) -> void:
	if not collider is CollisionObject3D: return
	var body := collider as CollisionObject3D
	var description := "%s | map layer %d | position %s" % [body.get_path(),int(body.get_meta("visual_layer",0)),str(body.global_position)]
	if description == last_collision_diagnostic: return
	last_collision_diagnostic = description
	print("COLLISION_BLOCKER ",description)
	if hint_label != null: hint_label.text = "Blocked by " + description


func _sort_entry_layer(entry: Dictionary, position: Vector3) -> int:
	if not entry.has("visual_layer"): entry["visual_layer"] = _visual_layer_for_position(position)
	return int(entry.visual_layer)

# Used by both autonomous and scripted movers; planning queries stay side-effect free.
func _move_vehicle_fraction(npc: Area3D, motion: Vector3) -> float:
	if npc.get_meta("npc_definition", {}).get("type") == "vehicle" and not motion.is_zero_approx():
		_configure_vehicle_hull(npc, npc_script_movement.direction(motion, str(npc.get_meta("facing", "down"))))
	var fraction := _npc_motion_fraction(npc, motion)
	if npc.get_meta("npc_definition", {}).get("type") != "vehicle" or player == null or fraction >= 0.999: return fraction
	var ignored: Array[RID] = [player.get_rid()]
	var clear_fraction := _npc_motion_fraction(npc, motion, null, ignored)
	if clear_fraction <= fraction: return fraction
	# A boat may push only as far as the player's own physics permits.
	var foot := npc.get_node("FootCollision") as StaticBody3D
	player.add_collision_exception_with(foot)
	var before := player.position
	var push := motion * clear_fraction
	# Starting overlaps (including collision margins) can be on the broadside.
	# Resolve those outward, rather than dragging the swimmer along the route.
	var side_push := _vehicle_side_separation(npc, motion)
	if not side_push.is_zero_approx(): push = side_push
	player.move_and_collide(push)
	player.remove_collision_exception_with(foot)
	var moved := player.position - before
	if not side_push.is_zero_approx():
		# The hull can pass only if the lateral separation actually succeeded.
		return _npc_motion_fraction(npc,motion)
	var pushed_fraction := clampf(moved.dot(motion)/motion.length_squared(),0.0,clear_fraction)
	return minf(clear_fraction, pushed_fraction)


func _configure_vehicle_hull(npc: Area3D, facing: String) -> void:
	var footprint: Rect2 = npc_visual_resolver.hull_footprint(String(npc.get_meta("sprite_id")),facing)
	if npc.get_meta("hull_footprint", Rect2()) == footprint: return
	npc.set_meta("hull_footprint",footprint)
	var foot := npc.get_node("FootCollision") as StaticBody3D
	var center := footprint.get_center()
	foot.position = Vector3(center.x,float(npc.get_meta("base_elevation",0.0))-npc.position.y+0.3,center.y)
	var shape := foot.get_child(0) as CollisionShape3D
	shape.shape = _vehicle_hull_shape(footprint)

func _set_npc_water_draw_order(npc: Area3D, npc_sort: Node2D) -> void:
	# Water traversal does not imply submersion: boats float above the surface
	# at z=-1 and keep ordinary Y sorting with other above-water sprites.
	var submerged: bool = npc.get_meta("movement_mode", "ground") == "swimming" and npc.get_meta("npc_definition", {}).get("type") != "vehicle"
	npc_sort.z_index = -2 if submerged and not npc.has_meta("habitat_occupant") else 0

func _vehicle_side_separation(npc: Area3D, motion: Vector3) -> Vector3:
	var half_size := Vector2.ZERO
	for child in player.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			half_size = Vector2(child.shape.size.x,child.shape.size.z)*0.5
			break
	if half_size.is_zero_approx(): return Vector3.ZERO
	var hull: Rect2 = npc.get_meta("hull_footprint")
	var expanded := Rect2(hull.position-half_size,hull.size+half_size*2.0).grow(player.safe_margin+0.002)
	var relative := Vector2(player.position.x-npc.position.x,player.position.z-npc.position.z)
	if not expanded.has_point(relative): return Vector3.ZERO
	var distances := [relative.x-expanded.position.x,expanded.end.x-relative.x,relative.y-expanded.position.y,expanded.end.y-relative.y]
	var normals := [Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK]
	var nearest := 0
	for i in range(1,4):
		if distances[i] < distances[nearest]: nearest = i
	var normal: Vector3 = normals[nearest]
	if motion.normalized().dot(normal) > 0.5: return Vector3.ZERO
	return normal * (float(distances[nearest])+0.002)


func _open_habitat_exhibit(slot: String) -> void:
	if exhibit_menu != null:
		exhibit_menu.queue_free()
	exhibit_menu = PopupMenu.new()
	exhibit_menu.name = "HabitatExhibitMenu"
	add_child(exhibit_menu)
	var occupant := String(exhibits.assignments.get(slot, ""))
	exhibit_menu.add_separator("Current exhibit: " + ("Empty" if occupant.is_empty() else occupant))
	var species := exhibits.available(slot)
	for index in species.size():
		exhibit_menu.add_item(species[index], index)
	if species.is_empty():
		exhibit_menu.add_separator("No eligible species")
	if not occupant.is_empty():
		exhibit_menu.add_item("Clear exhibit", species.size())
	exhibit_menu.add_item("Cancel", species.size() + 1)
	exhibit_menu.id_pressed.connect(func(id: int):
		if id == species.size() and not occupant.is_empty():
			_change_habitat_exhibit(slot, "")
		elif id >= 0 and id < species.size():
			_change_habitat_exhibit(slot, species[id])
	)
	exhibit_menu.popup_centered(Vector2i(280, 0))


func _change_habitat_exhibit(slot: String, species: String) -> void:
	if exhibit_transition or exhibits.assignments.get(slot, "") == species:
		return
	var prepared := exhibits.prepare(slot, species)
	if prepared.has("error"):
		_start_dialogue("EXHIBIT", [prepared.error])
		return
	exhibit_transition = true
	var fade := ColorRect.new()
	fade.color = Color.BLACK
	fade.z_index = 100
	fade.mouse_filter = Control.MOUSE_FILTER_STOP
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.modulate.a = 0
	map_ui.add_child(fade)
	var tween := create_tween()
	tween.tween_property(fade, "modulate:a", 1.0, 0.25)
	await tween.finished
	var installed := exhibits.install(slot, species, prepared)
	tween = create_tween()
	tween.tween_property(fade, "modulate:a", 0.0, 0.25)
	await tween.finished
	fade.queue_free()
	exhibit_transition = false
	if installed:
		_auto_save()
	else:
		_start_dialogue("EXHIBIT", ["This species could not be displayed."])


func _build_habitat_layout(layout: Dictionary, origin: Vector3, prefix: String) -> void:
	if layout.has("habitat_type"):
		_add_map_blocks(origin, layout.get("floor_blocks", []), prefix + "Floor", TEX_INTERIOR_FLOOR, Color.WHITE, false)
		_add_map_blocks(origin, layout.get("wall_blocks", []), prefix + "Wall", TEX_WALL_GENERIC, Color.WHITE, true)
		_add_map_blocks(origin, layout.get("water_blocks", []), prefix + "Water", TerrainTransitionTextureCache.base_texture("water"), Color.WHITE, true)
		_add_map_blocks(origin, layout.get("sand_blocks", []), prefix + "Sand", TEX_SAND, Color.WHITE, false)
		_add_map_blocks(origin, layout.get("rocks", []), prefix + "Rock", TEX_STONE, Color.WHITE, true)
		_add_serialized_furnishings(origin, layout.get("furnishings", []), prefix)
		for tree: Array in layout.get("trees", []):
			if tree.size() >= 4:
				_add_tree(origin + _array_to_vector3(tree), int(tree[3]), prefix + "Tree")
		for vine: Array in layout.get("vines", []):
			if vine.size() >= 3:
				_add_prop_billboard(prefix + "Vine", origin + _array_to_vector3(vine), TEX_VINES, 1.25)
		for orchid: Array in layout.get("orchids", []):
			if orchid.size() >= 3:
				_add_small_orchid(origin + _array_to_vector3(orchid))
	_build_outdoor_terrain_assets(layout, origin, prefix)


func _split_habitat_pen_art(front: Dictionary) -> void:
	var texture: Texture2D = front.texture
	var dimensions := texture.get_size()
	var split := floorf(dimensions.y * 0.5)
	var back := front.duplicate()
	back["name"] = String(front.name) + "Rear"
	back["instance_id"] = ""
	# The rear rim sits behind the full interior. The front retains its
	# original depth so it still occludes actors standing south of the pen.
	back["sort_offset_y"] = -4.95
	back["texture"] = _habitat_pen_texture_band(texture, 0, split)
	front["texture"] = _habitat_pen_texture_band(texture, split, dimensions.y - split)
	object_sort_entries.insert(object_sort_entries.size() - 1, back)


func _habitat_pen_texture_band(texture: Texture2D, top: float, height: float) -> AtlasTexture:
	var band := AtlasTexture.new()
	band.atlas = texture
	band.region = Rect2(0, top, texture.get_width(), height)
	band.margin = Rect2(0, top, 0, texture.get_height() - height)
	band.filter_clip = true
	return band


func _bound_habitat_flight_art(npc: Area3D, art: Sprite2D) -> void:
	# Keep the flight elevation for collision. In the tilted view, projecting
	# that elevation directly can put the entire sprite above the rear wall.
	var frame: Rect2 = npc.get_meta("habitat_flight_frame")
	var floor_y := float(npc.get_meta("base_elevation"))
	var a := camera.unproject_position(Vector3(frame.position.x, floor_y, frame.position.y))
	var b := camera.unproject_position(Vector3(frame.end.x, floor_y, frame.end.y))
	var low := a.min(b)
	var high := a.max(b)
	var half_art := (art.get_rect().size * art.scale.abs() * 0.5).min((high - low) * 0.5)
	art.global_position = art.global_position.clamp(low + half_art, high - half_art)
