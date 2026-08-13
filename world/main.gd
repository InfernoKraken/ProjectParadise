extends Node

const MAP_DATA_PATH := "res://data/rainforest_map.json"
const AUTO_SAVE_PATH := "user://project_paradise_autosave.json"
const SAVE_SLOT_COUNT := 5
const SAVE_VERSION := 1
const MOVE_SPEED := 5.0
const DEX_VIEW_SCENE := preload("res://dex/dex_view.tscn")
const TEX_FLOWER_BLUE := preload("res://assets/overworld/flower_small_blue_generic.png")
const TEX_FLOWER_RED := preload("res://assets/overworld/flower_tall_redginger.png")
const TEX_FLOWER_ORCHID_POT := preload("res://assets/overworld/flower_indoor_orchidpot.png")
const TEX_FLOWER_TORCH_GINGER := preload("res://assets/overworld/flower_tall_magnificent_torchginger.png")
const TEX_GRASS := preload("res://assets/overworld/grass_main.png")
const TEX_HOUSE := preload("res://assets/overworld/house.png")
const TEX_MEDICAL_WARD := preload("res://assets/overworld/medical_ward.png")
const TEX_STONE := preload("res://assets/overworld/stone_main.png")
const TEX_DIRT := preload("res://assets/overworld/tile_dirt_generic.png")
const TEX_DIRT_RICH := preload("res://assets/overworld/tile_dirt_rich.png")
const TEX_SAND := preload("res://assets/overworld/tile_sand_generic.png")
const TEX_TALL_GRASS := preload("res://assets/overworld/tile_tallgrass_generic.png")
const TEX_WALL := preload("res://assets/overworld/tile_wall_interior.png")
const TEX_WALL_GENERIC := preload("res://assets/overworld/tile_wall_interior_generic.png")
const TEX_WATER := preload("res://assets/overworld/tile_water_generic.png")
const TEX_WOOD := preload("res://assets/overworld/tile_wood.png")
const TEX_TREE_MAIN := preload("res://assets/overworld/tree_main.png")
const TEX_TREE_PALM := preload("res://assets/overworld/tree_palm.png")
const TEX_VINES := preload("res://assets/overworld/vines.png")
const TEX_WARP_BUILDING := preload("res://assets/overworld/warp_building_generic.png")
const TEX_WARP_EAST := preload("res://assets/overworld/warp_outdoor_facing_east.png")
const TEX_WARP_GENERIC := preload("res://assets/overworld/warp_outdoor_generic.png")
const TEX_WARP_NORTH := preload("res://assets/overworld/warp_outdoor_facing_north.png")
const TEX_WARP_WEST := preload("res://assets/overworld/warp_outdoor_facing_west.png")
const DYNAMIC_VISUAL_LAYER := 20
const PLAYER_CHOICES := [
	{"gender": "Male", "color_name": "Dark Blue", "color": "#173f73"},
	{"gender": "Male", "color_name": "Red", "color": "#b73535"},
	{"gender": "Male", "color_name": "Green", "color": "#33834b"},
	{"gender": "Male", "color_name": "Black", "color": "#20242a"},
	{"gender": "Female", "color_name": "Cyan", "color": "#45c9d4"},
	{"gender": "Female", "color_name": "Pink", "color": "#dc75a8"},
	{"gender": "Female", "color_name": "Teal", "color": "#24877f"},
	{"gender": "Female", "color_name": "White", "color": "#eeeeea"}
]

@onready var world: Node3D = $World
@onready var battle: Control = $Battle

var map_data: Dictionary
var player: CharacterBody3D
var player_sprite: Sprite3D
var follower: Node3D
var follower_sprite: Sprite3D
var follower_target := Vector3.ZERO
var follower_facing := "Down"
var opponent: Area3D
var camera: Camera3D
var spawn_position: Vector3
var opponent_fakemon_index := 2
var opponent_fakemon_indices: Array[int] = []
var in_battle := false
var active_battle_is_wild := false
var party: Array[Dictionary] = []
var active_party_index := 0
var last_grass_tile := ""
var hint_label: Label
var map_ui: CanvasLayer
var party_panel: PanelContainer
var party_list: VBoxContainer
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
var save_status_label: Label
var startup_panel: PanelContainer
var player_selection_panel: PanelContainer
var player_gender := ""
var player_color_name := ""
var player_color := Color("#55e36a")
var save_slot_selector: OptionButton
var selected_save_slot := 1
var npc_dialogues: Dictionary = {}
var family_children: Array[Dictionary] = []
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
	map_data = _load_map_data()
	if map_data.is_empty():
		return
	build_rainforest()
	battle.battle_finished.connect(_on_battle_finished)
	battle.fakemon_selected.connect(_on_fakemon_selected)
	_build_evolution_screen()
	world.hide()
	map_ui.visible = false
	battle.hide()
	_build_player_selection()
	if FileAccess.file_exists(AUTO_SAVE_PATH):
		player_selection_panel.hide()
		_build_startup_save_prompt()


func _physics_process(delta: float) -> void:
	if not adventure_started or in_battle or dialog_open or player == null or (party_panel != null and party_panel.visible) or (dex_panel != null and dex_panel.visible) or (move_learning_panel != null and move_learning_panel.visible) or (evolution_screen != null and evolution_screen.visible):
		return
	_set_active_visual_region(_current_location())
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	player.velocity = Vector3(input_vector.x, 0.0, input_vector.y) * MOVE_SPEED
	var position_before_move := player.position
	player.move_and_slide()
	if player.velocity.length_squared() > 0.01:
		follower_target = player.position - player.velocity.normalized() * 1.25
		_update_follower_facing(player.velocity)
	if follower != null and follower.visible:
		follower.position = follower.position.move_toward(follower_target, MOVE_SPEED * 0.85 * delta)
	_update_family_children(delta)
	if inside_medical_ward:
		var ward_size: Array = map_data["medical_ward"]["size"]
		player.position.x = clampf(player.position.x, medical_origin.x - float(ward_size[0]) * 0.5 + 0.5, medical_origin.x + float(ward_size[0]) * 0.5 - 0.5)
		player.position.z = clampf(player.position.z, medical_origin.z - float(ward_size[1]) * 0.5 + 0.5, medical_origin.z + float(ward_size[1]) * 0.5 - 0.5)
	elif inside_house:
		var house_size: Array = map_data["house"]["interior_size"]
		player.position.x = clampf(player.position.x, house_origin.x - float(house_size[0]) * 0.5 + 0.5, house_origin.x + float(house_size[0]) * 0.5 - 0.5)
		player.position.z = clampf(player.position.z, house_origin.z - float(house_size[1]) * 0.5 + 0.5, house_origin.z + float(house_size[1]) * 0.5 - 0.5)
	elif inside_route:
		var route_size: Array = map_data["route"]["size"]
		player.position.x = clampf(player.position.x, route_origin.x - float(route_size[0]) * 0.5 + 0.6, route_origin.x + float(route_size[0]) * 0.5 - 0.6)
		player.position.z = clampf(player.position.z, route_origin.z - float(route_size[1]) * 0.5 + 0.6, route_origin.z + float(route_size[1]) * 0.5 - 0.6)
	elif inside_east_route:
		_clamp_player_to_region(east_route_origin, map_data["east_route"]["size"])
	elif inside_west_route:
		_clamp_player_to_region(west_route_origin, map_data["west_route"]["size"])
	elif inside_east_cave:
		_clamp_player_to_region(east_cave_origin, map_data["east_cave"]["size"])
	elif inside_city:
		_clamp_player_to_region(city_origin, map_data["rainforest_city"]["size"])
	elif inside_city_ward:
		_clamp_player_to_region(city_ward_origin, map_data["rainforest_city"]["medical_ward"]["interior_size"])
	elif inside_orchid_house:
		_clamp_player_to_region(orchid_house_origin, map_data["rainforest_city"]["orchid_house"]["interior_size"])
	elif inside_family_house:
		_clamp_player_to_region(family_house_origin, map_data["rainforest_city"]["family_house"]["interior_size"])
	else:
		var map_size: Array = map_data["map_size"]
		player.position.x = clampf(player.position.x, -float(map_size[0]) * 0.5 + 0.6, float(map_size[0]) * 0.5 - 0.6)
		player.position.z = clampf(player.position.z, -float(map_size[1]) * 0.5 + 0.6, float(map_size[1]) * 0.5 - 0.6)
	_process_poison_steps(position_before_move.distance_to(player.position))
	camera.position.x = player.position.x
	var is_inside := inside_medical_ward or inside_house or inside_east_cave or inside_city_ward or inside_orchid_house or inside_family_house
	camera.position.y = 7.0 if is_inside else 18.0
	camera.position.z = player.position.z + (7.0 if is_inside else 18.0)


func _unhandled_input(event: InputEvent) -> void:
	if in_battle or dialog_open or not event is InputEventMouseButton:
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
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
		_start_battle()
	elif hit["collider"] == house_npc:
		_start_burn_dialogue()
	elif npc_dialogues.has(hit["collider"].get_instance_id()):
		var dialogue_data: Dictionary = npc_dialogues[hit["collider"].get_instance_id()]
		_start_dialogue(String(dialogue_data["speaker"]), dialogue_data["pages"])


func build_rainforest() -> void:
	var environment := WorldEnvironment.new()
	world_environment = Environment.new()
	world_environment.background_mode = Environment.BG_COLOR
	world_environment.background_color = Color("#93c47d")
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
	ground.position.y = -0.1
	ground.material_override = _textured_material(TEX_GRASS, Color("#39734b"), Vector3(float(configured_size[0]), float(configured_size[1]), 1.0))
	world.add_child(ground)

	spawn_position = _array_to_vector3(map_data["player_spawn"])
	player = CharacterBody3D.new()
	player.name = "PlayerPlaceholder"
	player.position = spawn_position
	player_sprite = _square_sprite(player_color, "PLAYER", Vector2(1.0, 1.25))
	player.add_child(player_sprite)
	player.add_child(_box_shape(Vector3(0.8, 1.2, 0.8)))
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
	opponent.add_child(_square_sprite(Color("#df6d5f"), "BATTLE", Vector2(1.0, 1.25)))
	opponent.add_child(_box_shape(Vector3(1.0, 1.3, 1.0)))
	world.add_child(opponent)

	var building_data: Dictionary = map_data["building"]
	var building_size := _array_to_vector3(building_data["size"])
	var building_position := _array_to_vector3(building_data["position"])
	var medical_art := _add_world_billboard("MedicalWardExteriorArt", building_position, TEX_MEDICAL_WARD, 5.4, 0.0)
	var building_body := StaticBody3D.new()
	building_body.name = "BuildingCollision"
	building_body.position = building_position
	building_body.add_child(_box_shape(building_size))
	world.add_child(building_body)
	_build_building_door_warp(medical_art, "MedicalWardExteriorDoor", _array_to_vector3(building_data["door"]), _on_exterior_door_entered, Vector3(1.5, 0.3, 1.0))
	_build_medical_ward(map_data["medical_ward"])
	_build_house(map_data["house"])
	_build_route(map_data["route"])
	_build_side_route(map_data["east_route"], "East", true)
	_build_side_route(map_data["west_route"], "West", false)
	_build_east_cave(map_data["east_cave"])
	_build_rainforest_city(map_data["rainforest_city"])

	_build_grass_tiles(map_data["wild_zone"])

	for tree_data: Array in map_data["trees"]:
		var tree_anchor := Vector3(float(tree_data[0]), float(tree_data[1]), float(tree_data[2]))
		_add_tree(tree_anchor, int(tree_data[3]), "Clearing")

	camera = Camera3D.new()
	camera.name = "RainforestCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 24.0
	camera.position = Vector3(0, 18, 18)
	camera.rotation_degrees = Vector3(-45, 0, 0)
	camera.current = true
	world.add_child(camera)
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
	hint_label.text = "Move: WASD / Arrow Keys (including left/right)    Red: trainer    Green grass: 20% wild encounters"
	hint_label.position = Vector2(24, 50)
	hint_label.add_theme_color_override("font_color", Color("#f1ffe9"))
	map_ui.add_child(hint_label)
	_build_party_menu()
	_build_dialog_ui()


func _start_battle() -> void:
	active_battle_is_wild = false
	_open_battle(opponent_fakemon_index, opponent_fakemon_indices)


func _open_battle(enemy_index: int, enemy_party_indices: Array = []) -> void:
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
	world.hide()
	map_ui.visible = false
	if active_battle_is_wild:
		battle.begin_battle_with_party(party, active_party_index, enemy_index, true)
	else:
		var trainer_party := enemy_party_indices if not enemy_party_indices.is_empty() else [enemy_index]
		battle.begin_battle_with_opponent_party(party, active_party_index, trainer_party, false)


func _on_fakemon_selected(index: int) -> void:
	var starter: Dictionary = battle.create_fakemon(battle.battle_data["fakemon"][index])
	starter["experience"] = int(pow(float(starter["level"]), 3.0))
	starter["current_hp"] = int(starter["max_hp"])
	starter["condition"] = ""
	starter["condition_turns"] = 0
	party.append(starter)
	active_party_index = 0
	adventure_started = true
	_update_follower_appearance()
	follower.show()
	in_battle = false
	world.show()
	map_ui.visible = true
	hint_label.text = "Fakemon chosen! Move with WASD / Arrow Keys. Red: trainer. Green grass: 20% wild encounters."
	_refresh_party_menu()
	_auto_save()


func _on_grass_tile_entered(body: Node3D, tile_id: String, encounter_chance: float, encounter_species: Array) -> void:
	if body != player or in_battle:
		return
	if tile_id == last_grass_tile:
		return
	last_grass_tile = tile_id
	if randf() < encounter_chance:
		var encounter_index := _random_tall_grass_species_index(encounter_species)
		if encounter_index < 0:
			hint_label.text = "This tall grass has no encounter species assigned yet."
			return
		active_battle_is_wild = true
		_open_battle(encounter_index)
	else:
		hint_label.text = "No encounter on this grass tile. Each newly stepped-on tile rolls 20%."


func _random_tall_grass_species_index(encounter_species: Array) -> int:
	var eligible_indices: Array[int] = []
	for species_name: Variant in encounter_species:
		for index in battle.battle_data["fakemon"].size():
			if String(battle.battle_data["fakemon"][index].get("name", "")) == String(species_name):
				eligible_indices.append(index)
				break
	return -1 if eligible_indices.is_empty() else eligible_indices.pick_random()


func _on_exterior_door_entered(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	_warp_to_medical_ward()


func _on_interior_door_entered(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	inside_medical_ward = false
	player.position = Vector3(-7.0, 0.65, -1.1)
	_place_follower_behind_player()
	camera.size = 24.0
	camera.position = Vector3(player.position.x, 18.0, player.position.z + 18.0)
	world_environment.background_color = Color("#93c47d")
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
	player.position = Vector3(8.0, 0.65, -3.25)
	_place_follower_behind_player()
	camera.size = 24.0
	camera.position = Vector3(player.position.x, 18.0, player.position.z + 18.0)
	world_environment.background_color = Color("#93c47d")
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
	player.position = route_origin + _array_to_vector3(route_data["entry"])
	_place_follower_behind_player()
	camera.size = 24.0
	world_environment.background_color = Color("#587a43")
	map_title.text = "CANOPY ROUTE - PLACEHOLDER MAP"
	hint_label.text = "Dense forest route: water is uncrossable. The trainer waits at the far end."
	_start_door_cooldown()
	_auto_save()


func _on_route_exit_entered(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	inside_route = false
	player.position = _array_to_vector3(map_data["route"]["clearing_return"])
	_place_follower_behind_player()
	camera.size = 24.0
	world_environment.background_color = Color("#93c47d")
	map_title.text = "RAINFOREST CLEARING - PLACEHOLDER MAP"
	hint_label.text = "Returned through the dense forest passage."
	_start_door_cooldown()
	_auto_save()


func _on_east_route_entered(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	_set_route_location("east_route", east_route_origin + _array_to_vector3(map_data["east_route"]["entry"]), "EASTERN RAINFOREST ROUTE", "The cave entrance lies deeper along the eastern route.")


func _on_east_route_exited(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	_set_route_location("route", route_origin + _array_to_vector3(map_data["route"]["east_return"]), "CANOPY ROUTE - PLACEHOLDER MAP", "Returned from the eastern rainforest route.")


func _on_west_route_entered(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	_set_route_location("west_route", west_route_origin + _array_to_vector3(map_data["west_route"]["entry"]), "WESTERN RAINFOREST ROUTE", "A humid rainforest path stretches westward.")


func _on_west_route_exited(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	_set_route_location("route", route_origin + _array_to_vector3(map_data["route"]["west_return"]), "CANOPY ROUTE - PLACEHOLDER MAP", "Returned from the western rainforest route.")


func _on_east_cave_entered(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	_set_route_location("east_cave", east_cave_origin + _array_to_vector3(map_data["east_cave"]["entry"]), "VINESTONE CAVE - PLACEHOLDER MAP", "A small rocky cave dotted with blue flowers and vines.")
	camera.size = 12.0


func _on_east_cave_exited(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	_set_route_location("east_route", east_route_origin + _array_to_vector3(map_data["east_route"]["cave_return"]), "EASTERN RAINFOREST ROUTE", "Exited Vinestone Cave.")


func _on_city_entered(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	_set_route_location("city", city_origin + _array_to_vector3(map_data["rainforest_city"]["entry"]), "MOSSVALE RAINFOREST CITY", "Medical care and two family homes line the rainforest plaza.")


func _on_city_exited(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	_set_route_location("route", route_origin + _array_to_vector3(map_data["route"]["north_return"]), "CANOPY ROUTE - PLACEHOLDER MAP", "Returned from Mossvale City.")


func _on_city_ward_entered(body: Node3D) -> void:
	if body != player or in_battle or not door_warp_ready:
		return
	var ward: Dictionary = map_data["rainforest_city"]["medical_ward"]
	_set_route_location("city_ward", city_ward_origin + _array_to_vector3(ward["entry"]), "MOSSVALE MEDICAL WARD", "Your party was fully restored. Walk onto the door tile to leave.")
	camera.size = 9.0
	for mon: Dictionary in party:
		mon["current_hp"] = int(mon["max_hp"])
		mon["condition"] = ""
		mon["condition_turns"] = 0
	_refresh_party_menu()
	_auto_save()


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
	inside_medical_ward = false
	inside_house = false
	inside_route = location == "route"
	inside_east_route = location == "east_route"
	inside_west_route = location == "west_route"
	inside_east_cave = location == "east_cave"
	inside_city = location == "city"
	inside_city_ward = location == "city_ward"
	inside_orchid_house = location == "orchid_house"
	inside_family_house = location == "family_house"
	player.position = destination
	_place_follower_behind_player()
	camera.size = 24.0
	var indoors := inside_east_cave or inside_city_ward or inside_orchid_house or inside_family_house
	world_environment.background_color = Color("#3d453d") if indoors else Color("#587a43")
	map_title.text = title
	hint_label.text = hint
	_start_door_cooldown()
	_auto_save()


func _warp_to_medical_ward() -> void:
	var ward_data: Dictionary = map_data["medical_ward"]
	medical_origin = _array_to_vector3(ward_data["origin"])
	inside_medical_ward = true
	inside_house = false
	player.position = medical_origin + _array_to_vector3(ward_data["entry"])
	_place_follower_behind_player()
	camera.size = 9.0
	camera.position = Vector3(player.position.x, 7.0, player.position.z + 7.0)
	world_environment.background_color = Color("#354b5e")
	map_title.text = "MEDICAL WARD - PLACEHOLDER INTERIOR"
	for mon: Dictionary in party:
		mon["current_hp"] = int(mon["max_hp"])
		mon["condition"] = ""
		mon["condition_turns"] = 0
	hint_label.text = "Medical ward: the party was restored. Walk onto the door tile to leave."
	_refresh_party_menu()
	_start_door_cooldown()
	_auto_save()


func _start_door_cooldown() -> void:
	door_warp_ready = false
	await get_tree().create_timer(0.5).timeout
	door_warp_ready = true


func _on_battle_finished(player_won: bool, escaped: bool, captured_mon: Dictionary, experience_earned: int, experience_recipients: Array[int], _final_active_index: int, final_party_hp: Array[int], final_party_conditions: Array[Dictionary]) -> void:
	var capture_added := false
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
		if party.size() < 7:
			captured_mon["condition"] = String(captured_mon.get("condition", ""))
			captured_mon["condition_turns"] = int(captured_mon.get("condition_turns", 0))
			party.append(captured_mon)
			capture_added = true
		else:
			capture_added = false
	if not player_won and not escaped:
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
		player.position = spawn_position
		player.velocity = Vector3.ZERO
		_place_follower_behind_player()
		camera.size = 24.0
		world_environment.background_color = Color("#93c47d")
		map_title.text = "RAINFOREST CLEARING - PLACEHOLDER MAP"
	in_battle = false
	world.show()
	map_ui.visible = true
	var battle_kind := "wild encounter" if active_battle_is_wild else "trainer battle"
	if escaped:
		hint_label.text = "Escaped from the wild encounter."
	else:
		hint_label.text = ("Victory in the %s! You remain where the battle began." % battle_kind if player_won else "Defeat! Returned to the starting point.")
	if capture_added:
		hint_label.text += " Captured %s." % captured_mon["name"]
	elif not captured_mon.is_empty():
		hint_label.text += " Party full; storage is needed before another capture can be kept."
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
			if String(mon.get("condition", "")) == "Poisoned" and int(mon.get("current_hp", mon["max_hp"])) > 0:
				var poison_damage := int(battle.battle_data["conditions"]["Poisoned"]["overworld_damage_per_step"])
				mon["current_hp"] = maxi(0, int(mon.get("current_hp", mon["max_hp"])) - poison_damage)
				took_damage = true
	if took_damage:
		hint_label.text = "Poison damaged affected party members while walking. Visit the medical ward to cure them."
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
	mon.merge(evolved, true)
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


func _build_route(route_data: Dictionary) -> void:
	route_origin = _array_to_vector3(route_data["origin"])
	var route_size: Array = route_data["size"]
	_add_textured_block("CanopyRouteGround", route_origin + Vector3(0, -0.1, 0), Vector3(float(route_size[0]), 0.2, float(route_size[1])), TEX_GRASS, Color("#315f3b"), false)
	_build_forest_warp("CanopyRouteEntrance", _array_to_vector3(route_data["clearing_warp"]), _on_route_entrance_entered, "generic")
	_build_forest_warp("CanopyRouteExit", route_origin + _array_to_vector3(route_data["exit_warp"]), _on_route_exit_entered, "north")
	_build_forest_warp("CanopyRouteEastConnection", route_origin + _array_to_vector3(route_data["east_warp"]), _on_east_route_entered, "east")
	_build_forest_warp("CanopyRouteWestConnection", route_origin + _array_to_vector3(route_data["west_warp"]), _on_west_route_entered, "west")
	_build_forest_warp("CanopyRouteNorthConnection", route_origin + _array_to_vector3(route_data["north_warp"]), _on_city_entered, "generic")
	for grass_data: Dictionary in route_data["grass_zones"]:
		var placed_grass := grass_data.duplicate(true)
		var local_position := _array_to_vector3(placed_grass["position"])
		placed_grass["position"] = [route_origin.x + local_position.x, local_position.y, route_origin.z + local_position.z]
		placed_grass["species"] = route_data.get("tall_grass_species", [])
		_build_grass_tiles(placed_grass)
	for water_data: Array in route_data["water_blocks"]:
		var water_position := route_origin + Vector3(float(water_data[0]), float(water_data[1]), float(water_data[2]))
		var water_size := Vector3(float(water_data[3]), float(water_data[4]), float(water_data[5]))
		_add_textured_block("UncrossableWaterBlock", water_position, water_size, TEX_WATER, Color("#3188b8"), true)
	for flower_data: Array in route_data["tall_flowers"]:
		var flower_position := route_origin + Vector3(float(flower_data[0]), float(flower_data[1]), float(flower_data[2]))
		_add_prop_billboard("TallFlowerBlock", flower_position, TEX_FLOWER_RED, 0.9)
	for flower_data: Array in route_data.get("rare_torch_ginger", []):
		_add_prop_billboard("MagnificentTorchGinger", route_origin + _array_to_vector3(flower_data), TEX_FLOWER_TORCH_GINGER, 1.15)
	for tree_data: Array in route_data["trees"]:
		_add_tree(route_origin + Vector3(float(tree_data[0]), float(tree_data[1]), float(tree_data[2])), int(tree_data[3]), "Route")


func _build_side_route(route_data: Dictionary, prefix: String, is_east: bool) -> void:
	var origin := _array_to_vector3(route_data["origin"])
	if is_east:
		east_route_origin = origin
	else:
		west_route_origin = origin
	var route_size: Array = route_data["size"]
	_add_textured_block(prefix + "RainforestRouteGround", origin + Vector3(0, -0.1, 0), Vector3(float(route_size[0]), 0.2, float(route_size[1])), TEX_GRASS, Color("#376b42"), false)
	_build_forest_warp(prefix + "RouteReturnWarp", origin + _array_to_vector3(route_data["return_warp"]), _on_east_route_exited if is_east else _on_west_route_exited, "west" if is_east else "east")
	for grass_data: Dictionary in route_data["grass_zones"]:
		var placed_grass := grass_data.duplicate(true)
		var local_position := _array_to_vector3(placed_grass["position"])
		placed_grass["position"] = [origin.x + local_position.x, local_position.y, origin.z + local_position.z]
		placed_grass["species"] = route_data.get("tall_grass_species", [])
		_build_grass_tiles(placed_grass)
	for water_data: Array in route_data["water_blocks"]:
		_add_textured_block(prefix + "UncrossableWaterBlock", origin + Vector3(float(water_data[0]), float(water_data[1]), float(water_data[2])), Vector3(float(water_data[3]), float(water_data[4]), float(water_data[5])), TEX_WATER, Color("#3188b8"), true)
	for flower_data: Array in route_data["tall_flowers"]:
		_add_prop_billboard(prefix + "TallFlowerBlock", origin + Vector3(float(flower_data[0]), float(flower_data[1]), float(flower_data[2])), TEX_FLOWER_RED, 0.9)
	for flower_data: Array in route_data.get("rare_torch_ginger", []):
		_add_prop_billboard(prefix + "MagnificentTorchGinger", origin + _array_to_vector3(flower_data), TEX_FLOWER_TORCH_GINGER, 1.15)
	for tree_data: Array in route_data["trees"]:
		_add_tree(origin + Vector3(float(tree_data[0]), float(tree_data[1]), float(tree_data[2])), int(tree_data[3]), prefix + "Route")
	if is_east:
		_build_forest_warp("EasternRouteCaveEntrance", origin + _array_to_vector3(route_data["cave_warp"]), _on_east_cave_entered, "east")


func _build_east_cave(cave_data: Dictionary) -> void:
	east_cave_origin = _array_to_vector3(cave_data["origin"])
	var cave_size: Array = cave_data["size"]
	_add_textured_block("VinestoneCaveRockyGround", east_cave_origin + Vector3(0, -0.1, 0), Vector3(float(cave_size[0]), 0.2, float(cave_size[1])), TEX_STONE, Color("#595b55"), false)
	_build_forest_warp("VinestoneCaveExit", east_cave_origin + _array_to_vector3(cave_data["exit_warp"]), _on_east_cave_exited, "north")
	for rock_data: Array in cave_data["rocks"]:
		_add_textured_block("CaveRockBlock", east_cave_origin + Vector3(float(rock_data[0]), float(rock_data[1]), float(rock_data[2])), Vector3(float(rock_data[3]), float(rock_data[4]), float(rock_data[5])), TEX_STONE, Color("#777970"), true)
	for flower_data: Array in cave_data["blue_flowers"]:
		_add_prop_billboard("SmallBlueFlower", east_cave_origin + Vector3(float(flower_data[0]), float(flower_data[1]), float(flower_data[2])), TEX_FLOWER_BLUE, 0.45)
	for vine_data: Array in cave_data["vines"]:
		_add_prop_billboard("CaveVine", east_cave_origin + Vector3(float(vine_data[0]), float(vine_data[1]), float(vine_data[2])), TEX_VINES, 1.25)


func _build_rainforest_city(city_data: Dictionary) -> void:
	city_origin = _array_to_vector3(city_data["origin"])
	var city_size: Array = city_data["size"]
	_add_textured_block("MossvaleCityGround", city_origin + Vector3(0, -0.1, 0), Vector3(float(city_size[0]), 0.2, float(city_size[1])), TEX_GRASS, Color("#47784d"), false)
	_add_textured_block("MossvalePlazaPath", city_origin + Vector3(0, 0.02, 2), Vector3(5, 0.08, 16), TEX_STONE, Color("#a7956f"), false)
	_build_forest_warp("MossvaleCitySouthExit", city_origin + _array_to_vector3(city_data["return_warp"]), _on_city_exited, "north")
	for tree_data: Array in city_data["trees"]:
		_add_tree(city_origin + Vector3(float(tree_data[0]), float(tree_data[1]), float(tree_data[2])), int(tree_data[3]), "Mossvale")
	for flower_data: Array in city_data["flower_beds"]:
		_add_prop_billboard("MossvaleFlowerBed", city_origin + Vector3(float(flower_data[0]), float(flower_data[1]), float(flower_data[2])), TEX_FLOWER_BLUE, 0.45)
	_build_city_exterior(city_data["medical_ward"], "MossvaleMedicalWard", Color("#91cdd0"), _on_city_ward_entered)
	_build_city_exterior(city_data["orchid_house"], "GroundOrchidHouse", Color("#9b7359"), _on_orchid_house_entered)
	_build_city_exterior(city_data["family_house"], "MossvaleFamilyHouse", Color("#b08359"), _on_family_house_entered)
	_build_city_room(city_data["medical_ward"], "MossvaleWard", Color("#d8efec"), Color("#70d6d1"), _on_city_ward_exited)
	_build_city_room(city_data["orchid_house"], "OrchidHome", Color("#dac9aa"), Color("#e0b45b"), _on_orchid_house_exited)
	_build_city_room(city_data["family_house"], "FamilyHome", Color("#d7c29c"), Color("#e0b45b"), _on_family_house_exited)
	city_ward_origin = _array_to_vector3(city_data["medical_ward"]["origin"])
	orchid_house_origin = _array_to_vector3(city_data["orchid_house"]["origin"])
	family_house_origin = _array_to_vector3(city_data["family_house"]["origin"])
	for orchid_data: Array in city_data["orchid_house"]["orchids"]:
		_add_small_orchid(orchid_house_origin + _array_to_vector3(orchid_data))
	var orchid_npc := _add_talking_npc("GroundOrchidExpert", orchid_house_origin + _array_to_vector3(city_data["orchid_house"]["npc"]), Color("#b36bc9"), "ORCHID KEEPER", ["Ground orchids grow from the forest floor instead of clinging to trees. Their roots shelter in the rich leaf litter below the canopy."])
	_add_static_collision("GroundOrchidExpertCollision", orchid_npc.position, Vector3(0.8, 1.1, 0.8))
	var adult_data: Array = city_data["family_house"]["adults"]
	_add_talking_npc("EvolutionParent", family_house_origin + _array_to_vector3(adult_data[0]), Color("#d98b57"), "PARENT", ["Some Fakemon may evolve after earning enough experience. Training and exploring together can help them reach that turning point."])
	_add_talking_npc("DespairParent", family_house_origin + _array_to_vector3(adult_data[1]), Color("#5c8ecb"), "PARENT", ["Try not to let your Fakemon fall into Despair. A despairing partner struggles to give its best, so care and recovery matter as much as winning."])
	var child_data: Array = city_data["family_house"]["children"]
	for index in child_data.size():
		var child := _add_talking_npc("FamilyChild%d" % (index + 1), family_house_origin + _array_to_vector3(child_data[index]), Color("#e9c35b"), "CHILD", ["We like playing together inside when the rainforest rain gets heavy!"])
		family_children.append({"node": child, "target": child.position, "timer": randf_range(0.5, 2.0)})


func _build_city_exterior(building_data: Dictionary, building_name: String, color: Color, callback: Callable) -> void:
	var position := city_origin + _array_to_vector3(building_data["position"])
	var size := _array_to_vector3(building_data["size"])
	var texture := TEX_MEDICAL_WARD if building_name.contains("Medical") else TEX_HOUSE
	var width := size.x * (1.08 if building_name.contains("Medical") else 1.15)
	var building_art := _add_world_billboard(building_name, position, texture, width, 0.0)
	_add_static_collision(building_name + "Collision", position, size)
	_build_building_door_warp(building_art, building_name + "Door", city_origin + _array_to_vector3(building_data["door"]), callback, Vector3(1.5, 0.3, 0.9))


func _build_city_room(room_data: Dictionary, prefix: String, floor_color: Color, door_color: Color, callback: Callable) -> void:
	var origin := _array_to_vector3(room_data["origin"])
	var size: Array = room_data["interior_size"]
	_add_textured_block(prefix + "Floor", origin + Vector3(0, -0.1, 0), Vector3(float(size[0]), 0.2, float(size[1])), TEX_WOOD, floor_color, false)
	_add_colored_block(prefix + "BackWall", origin + Vector3(0, 1.2, -float(size[1]) * 0.5 + 0.15), Vector3(float(size[0]), 2.4, 0.3), floor_color.darkened(0.15), true)
	_add_colored_block(prefix + "LeftWall", origin + Vector3(-float(size[0]) * 0.5 + 0.15, 1.2, 0), Vector3(0.3, 2.4, float(size[1])), floor_color.darkened(0.2), true)
	_add_colored_block(prefix + "RightWall", origin + Vector3(float(size[0]) * 0.5 - 0.15, 1.2, 0), Vector3(0.3, 2.4, float(size[1])), floor_color.darkened(0.2), true)
	_build_colored_warp(prefix + "ExitDoor", origin + _array_to_vector3(room_data["exit_door"]), callback, door_color)


func _build_colored_warp(warp_name: String, position: Vector3, callback: Callable, color: Color) -> void:
	var warp := Area3D.new()
	warp.name = warp_name
	warp.position = position
	var size := Vector3(1.5, 0.3, 0.9)
	warp.add_child(_box_shape(size))
	_add_warp_rug_visual(warp, size.x)
	warp.body_entered.connect(callback)
	world.add_child(warp)


func _add_talking_npc(npc_name: String, position: Vector3, color: Color, speaker: String, pages: Array) -> Area3D:
	var npc := Area3D.new()
	npc.name = npc_name
	npc.position = position
	npc.add_child(_square_sprite(color, speaker, Vector2(0.8, 1.05)))
	npc.add_child(_box_shape(Vector3(0.8, 1.1, 0.8)))
	world.add_child(npc)
	npc_dialogues[npc.get_instance_id()] = {"speaker": speaker, "pages": pages}
	return npc


func _add_small_orchid(position: Vector3) -> void:
	_add_prop_billboard("GroundOrchidBloom", position, TEX_FLOWER_ORCHID_POT, 0.72)


func _build_forest_warp(warp_name: String, warp_position: Vector3, callback: Callable, facing: String) -> void:
	var warp := Area3D.new()
	warp.name = warp_name
	warp.position = warp_position
	var warp_size := Vector3(2.2, 0.4, 1.2)
	warp.add_child(_box_shape(warp_size))
	var texture := TEX_WARP_EAST if facing == "east" else (TEX_WARP_WEST if facing == "west" else (TEX_WARP_GENERIC if facing == "generic" else TEX_WARP_NORTH))
	var visual_height := 1.75 if facing == "north" else 2.1
	var visual := _billboard_sprite(texture, visual_height, "OutdoorWarpArt_%s" % facing.capitalize())
	visual.position = Vector3(0, visual_height * 0.5, -0.08)
	warp.add_child(visual)
	warp.body_entered.connect(callback)
	world.add_child(warp)


func _add_tree(tree_anchor: Vector3, variant: int, prefix: String) -> void:
	var texture := TEX_TREE_MAIN if variant == 0 else TEX_TREE_PALM
	var tree_height := 4.2 if variant == 0 else 3.8
	var tree := _add_world_billboard("%sCanopyArt" % prefix, tree_anchor, texture, texture.get_width() * tree_height / texture.get_height(), 0.0)
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


func _add_textured_block(block_name: String, block_position: Vector3, block_size: Vector3, texture: Texture2D, color: Color, solid: bool) -> void:
	var visual := MeshInstance3D.new()
	visual.name = block_name
	var mesh := BoxMesh.new()
	mesh.size = block_size
	visual.mesh = mesh
	visual.position = block_position
	visual.material_override = _textured_material(texture, color, Vector3(maxf(block_size.x, 1.0), maxf(block_size.z, 1.0), 1.0))
	world.add_child(visual)
	if solid:
		_add_static_collision(block_name + "Collision", block_position, block_size)


func _add_prop_billboard(prop_name: String, ground_position: Vector3, texture: Texture2D, height: float) -> Sprite3D:
	var sprite := _billboard_sprite(texture, height, prop_name)
	sprite.position = Vector3(ground_position.x, height * 0.5, ground_position.z)
	world.add_child(sprite)
	return sprite


func _add_world_billboard(sprite_name: String, anchor: Vector3, texture: Texture2D, width: float, z_offset: float) -> Sprite3D:
	var height := width * float(texture.get_height()) / float(texture.get_width())
	var sprite := _billboard_sprite(texture, height, sprite_name)
	sprite.position = Vector3(anchor.x, height * 0.5, anchor.z + z_offset)
	world.add_child(sprite)
	return sprite


func _build_building_door_warp(building_art: Node3D, warp_name: String, global_position: Vector3, callback: Callable, size: Vector3) -> Area3D:
	var warp := Area3D.new()
	warp.name = warp_name
	warp.position = building_art.to_local(global_position)
	warp.add_child(_box_shape(size))
	warp.body_entered.connect(callback)
	building_art.add_child(warp)
	return warp


func _add_warp_rug_visual(parent: Node3D, width: float) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = "WarpRugArt"
	var mesh := PlaneMesh.new()
	var aspect := float(TEX_WARP_BUILDING.get_width()) / float(TEX_WARP_BUILDING.get_height())
	mesh.size = Vector2(width, width / aspect)
	visual.mesh = mesh
	visual.position.y = 0.17
	visual.material_override = _textured_material(TEX_WARP_BUILDING, Color.WHITE)
	parent.add_child(visual)
	return visual


func _build_medical_ward(ward_data: Dictionary) -> void:
	medical_origin = _array_to_vector3(ward_data["origin"])
	var ward_size: Array = ward_data["size"]
	var floor := MeshInstance3D.new()
	floor.name = "MedicalWardFloor"
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(float(ward_size[0]), 0.2, float(ward_size[1]))
	floor.mesh = floor_mesh
	floor.position = medical_origin + Vector3(0, -0.1, 0)
	floor.material_override = _textured_material(TEX_WALL_GENERIC, Color("#d7f0ec"), Vector3(float(ward_size[0]), float(ward_size[1]), 1.0))
	world.add_child(floor)
	var center_tile := MeshInstance3D.new()
	center_tile.name = "MedicalWardCenterFloorTile"
	var center_mesh := BoxMesh.new()
	center_mesh.size = Vector3(4.5, 0.06, 3.2)
	center_tile.mesh = center_mesh
	center_tile.position = medical_origin + Vector3(0, 0.04, 0.3)
	center_tile.material_override = _textured_material(TEX_WALL_GENERIC, Color("#b8ddd9"), Vector3(4.5, 3.2, 1.0))
	world.add_child(center_tile)
	_add_ward_block("MedicalWardBackWall", medical_origin + Vector3(0, 1.25, -3.35), Vector3(8.0, 2.5, 0.3), Color("#eef5f3"))
	_add_ward_block("MedicalWardLeftWall", medical_origin + Vector3(-3.85, 1.25, 0), Vector3(0.3, 2.5, 6.7), Color("#c7dcdf"))
	_add_ward_block("MedicalWardRightWall", medical_origin + Vector3(3.85, 1.25, 0), Vector3(0.3, 2.5, 6.7), Color("#c7dcdf"))
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
	exit_door.name = "MedicalWardInteriorDoor"
	exit_door.position = medical_origin + _array_to_vector3(ward_data["exit_door"])
	var door_size := Vector3(1.5, 0.3, 0.9)
	exit_door.add_child(_box_shape(door_size))
	_add_warp_rug_visual(exit_door, door_size.x)
	exit_door.body_entered.connect(_on_interior_door_entered)
	world.add_child(exit_door)


func _build_house(house_data: Dictionary) -> void:
	var exterior_position := _array_to_vector3(house_data["position"])
	var exterior_size := _array_to_vector3(house_data["size"])
	var house_art := _add_world_billboard("HouseExteriorArt", exterior_position, TEX_HOUSE, 4.6, 0.0)
	_add_static_collision("HouseExteriorCollision", exterior_position, exterior_size)
	var door_size := Vector3(1.3, 0.3, 0.9)
	_build_building_door_warp(house_art, "HouseExteriorDoor", _array_to_vector3(house_data["door"]), _on_house_exterior_door_entered, door_size)

	house_origin = _array_to_vector3(house_data["origin"])
	var room_size: Array = house_data["interior_size"]
	var floor := MeshInstance3D.new()
	floor.name = "HouseInteriorFloor"
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(float(room_size[0]), 0.2, float(room_size[1]))
	floor.mesh = floor_mesh
	floor.position = house_origin + Vector3(0, -0.1, 0)
	floor.material_override = _textured_material(TEX_WOOD, Color("#d8c6a5"), Vector3(float(room_size[0]), float(room_size[1]), 1.0))
	world.add_child(floor)
	_add_ward_block("HouseBackWall", house_origin + Vector3(0, 1.2, -2.85), Vector3(7.0, 2.4, 0.3), Color("#eadcc5"))
	_add_ward_block("HouseLeftWall", house_origin + Vector3(-3.35, 1.2, 0), Vector3(0.3, 2.4, 5.7), Color("#c9ae87"))
	_add_ward_block("HouseRightWall", house_origin + Vector3(3.35, 1.2, 0), Vector3(0.3, 2.4, 5.7), Color("#c9ae87"))
	house_npc = Area3D.new()
	house_npc.name = "BurnTutorNPC"
	house_npc.position = house_origin + _array_to_vector3(house_data["npc"])
	house_npc.add_child(_square_sprite(Color("#f0a34a"), "BURN_TUTOR", Vector2(0.9, 1.15)))
	house_npc.add_child(_box_shape(Vector3(0.9, 1.2, 0.9)))
	world.add_child(house_npc)
	_add_static_collision("BurnTutorNPCCollision", house_npc.position, Vector3(0.9, 1.2, 0.9))

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


func _add_static_collision(collision_name: String, collision_position: Vector3, collision_size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = collision_name
	body.position = collision_position
	body.collision_layer = 1
	body.collision_mask = 1
	body.add_child(_box_shape(collision_size))
	world.add_child(body)


func _on_grass_tile_exited(body: Node3D, tile_id: String) -> void:
	if body == player and last_grass_tile == tile_id:
		last_grass_tile = ""


func _build_party_menu() -> void:
	var menu_button := Button.new()
	menu_button.text = "Party (P)"
	menu_button.pressed.connect(_toggle_party_menu)
	map_ui.add_child(menu_button)
	_set_bottom_right_rect(menu_button, Vector2(-139, -60), Vector2(115, 36))
	var save_button := Button.new()
	save_button.text = "Save Slot (F5)"
	save_button.pressed.connect(_save_game)
	map_ui.add_child(save_button)
	_set_bottom_right_rect(save_button, Vector2(-301, -60), Vector2(150, 36))
	var load_button := Button.new()
	load_button.text = "Load Slot (F9)"
	load_button.pressed.connect(_load_game)
	map_ui.add_child(load_button)
	_set_bottom_right_rect(load_button, Vector2(-463, -60), Vector2(150, 36))
	save_slot_selector = OptionButton.new()
	save_slot_selector.name = "SaveSlotSelector"
	for slot in SAVE_SLOT_COUNT:
		save_slot_selector.add_item("Slot %d" % (slot + 1), slot + 1)
	save_slot_selector.item_selected.connect(_on_save_slot_selected)
	map_ui.add_child(save_slot_selector)
	_set_bottom_right_rect(save_slot_selector, Vector2(-555, -60), Vector2(80, 36))
	save_status_label = Label.new()
	save_status_label.add_theme_font_size_override("font_size", 12)
	map_ui.add_child(save_status_label)
	_set_bottom_right_rect(save_status_label, Vector2(-555, -84), Vector2(531, 20))
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


func _build_dialog_ui() -> void:
	dialog_panel = PanelContainer.new()
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
	dialog_panel.hide()
	map_ui.add_child(dialog_panel)


func _start_burn_dialogue() -> void:
	_start_dialogue("RAINFOREST RESIDENT", burn_dialogue)


func _start_dialogue(speaker: String, pages: Array) -> void:
	active_dialogue.clear()
	for page: Variant in pages:
		active_dialogue.append(String(page))
	active_dialogue_speaker = speaker
	dialog_page = 0
	dialog_open = true
	dialog_panel.show()
	_update_dialogue()


func _advance_dialogue() -> void:
	dialog_page += 1
	if dialog_page >= active_dialogue.size():
		dialog_open = false
		dialog_panel.hide()
		return
	_update_dialogue()


func _update_dialogue() -> void:
	dialog_speaker.text = active_dialogue_speaker
	dialog_label.text = active_dialogue[dialog_page]
	dialog_button.text = "Close" if dialog_page == active_dialogue.size() - 1 else "Next"


func _update_family_children(delta: float) -> void:
	if not inside_family_house:
		return
	for child_data: Dictionary in family_children:
		var child: Area3D = child_data["node"]
		child_data["timer"] = float(child_data["timer"]) - delta
		if float(child_data["timer"]) <= 0.0 or child.position.distance_to(child_data["target"]) < 0.1:
			child_data["target"] = family_house_origin + Vector3(randf_range(-3.8, 3.8), 0.65, randf_range(-2.5, 2.0))
			child_data["timer"] = randf_range(1.5, 4.0)
		child.position = child.position.move_toward(child_data["target"], 1.2 * delta)


func _toggle_party_menu() -> void:
	if dex_panel.visible:
		dex_panel.hide()
	party_panel.visible = not party_panel.visible
	if party_panel.visible:
		_refresh_party_menu()


func _refresh_party_menu() -> void:
	if party_list == null:
		return
	for child in party_list.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = "PARTY (%d / 7) - click a mon to make active" % party.size()
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
	if dialog_open and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			_advance_dialogue()
		elif event.keycode == KEY_ESCAPE:
			dialog_open = false
			dialog_panel.hide()
		return
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
	subtitle.text = "Choose a gender and placeholder color. This choice is saved with your adventure."
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
		button.text = "%s\n%s" % [choice["gender"], choice["color_name"]]
		button.custom_minimum_size = Vector2(195, 145)
		button.add_theme_font_size_override("font_size", 18)
		button.pressed.connect(_on_player_choice_selected.bind(index))
		grid.add_child(button)
		var swatch := ColorRect.new()
		swatch.color = Color(choice["color"])
		swatch.position = Vector2(12, 12)
		swatch.size = Vector2(46, 46)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(swatch)
	add_child(player_selection_panel)


func _on_player_choice_selected(index: int) -> void:
	if index < 0 or index >= PLAYER_CHOICES.size():
		return
	var choice: Dictionary = PLAYER_CHOICES[index]
	player_gender = String(choice["gender"])
	player_color_name = String(choice["color_name"])
	player_color = Color(choice["color"])
	_apply_player_appearance()
	player_selection_panel.hide()
	battle.begin_adventure_selection()


func _apply_player_appearance() -> void:
	if player_sprite == null:
		return
	player_sprite.texture = _solid_texture(player_color)
	player.name = "%s%sPlayerPlaceholder" % [player_color_name.replace(" ", ""), player_gender]


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
	if not adventure_started or in_battle or party.is_empty():
		if show_feedback and save_status_label != null:
			save_status_label.text = "Saving is available while exploring."
		return false
	var location := _current_location()
	var save_data := {
		"version": SAVE_VERSION,
		"player_gender": player_gender,
		"player_color_name": player_color_name,
		"player_color": player_color.to_html(false),
		"party": party,
		"active_party_index": active_party_index,
		"location": location,
		"player_position": [player.position.x, player.position.y, player.position.z],
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
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if not parsed is Dictionary:
		if save_status_label != null:
			save_status_label.text = "Save file is invalid. Start a new adventure."
		return false
	var data := parsed as Dictionary
	player_gender = String(data.get("player_gender", "Male"))
	player_color_name = String(data.get("player_color_name", "Dark Blue"))
	player_color = Color(String(data.get("player_color", "173f73")))
	_apply_player_appearance()
	var loaded_party: Variant = data.get("party", [])
	if not loaded_party is Array or loaded_party.is_empty() or loaded_party.size() > 7:
		if save_status_label != null:
			save_status_label.text = "Save party is invalid. Start a new adventure."
		return false
	party.clear()
	for saved_mon: Variant in loaded_party:
		if saved_mon is Dictionary:
			party.append((saved_mon as Dictionary).duplicate(true))
	if party.is_empty():
		return false
	active_party_index = clampi(int(data.get("active_party_index", 0)), 0, party.size() - 1)
	poison_step_distance = clampf(float(data.get("poison_step_distance", 0.0)), 0.0, 0.999)
	var saved_position: Variant = data.get("player_position", map_data["player_spawn"])
	player.position = _array_to_vector3(saved_position as Array) if saved_position is Array and saved_position.size() >= 3 else spawn_position
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
	dialog_open = false
	dialog_panel.hide()
	player_selection_panel.hide()
	party_panel.hide()
	dex_panel.hide()
	last_grass_tile = ""
	_apply_loaded_location(location)
	player.velocity = Vector3.ZERO
	adventure_started = true
	in_battle = false
	battle.hide()
	world.show()
	map_ui.visible = true
	_update_follower_appearance()
	follower.show()
	_place_follower_behind_player()
	_refresh_party_menu()
	if save_status_label != null:
		save_status_label.text = ""
	return true


func _apply_loaded_location(location: String) -> void:
	if location == "medical_ward":
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
		camera.size = 24.0
		world_environment.background_color = Color("#587a43")
		map_title.text = "CANOPY ROUTE - PLACEHOLDER MAP"
		hint_label.text = "Loaded on Canopy Route. Water is uncrossable; the trainer waits at the far end."
	elif location == "east_route":
		camera.size = 24.0
		world_environment.background_color = Color("#587a43")
		map_title.text = "EASTERN RAINFOREST ROUTE"
		hint_label.text = "Loaded on the eastern route. The cave lies deeper in the rainforest."
	elif location == "west_route":
		camera.size = 24.0
		world_environment.background_color = Color("#587a43")
		map_title.text = "WESTERN RAINFOREST ROUTE"
		hint_label.text = "Loaded on the western rainforest route."
	elif location == "east_cave":
		camera.size = 12.0
		world_environment.background_color = Color("#3d453d")
		map_title.text = "VINESTONE CAVE - PLACEHOLDER MAP"
		hint_label.text = "Loaded in Vinestone Cave. Blue flowers and vines grow among the rocks."
	elif location == "city":
		camera.size = 24.0
		world_environment.background_color = Color("#668a57")
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
		camera.size = 24.0
		world_environment.background_color = Color("#93c47d")
		map_title.text = "RAINFOREST CLEARING - PLACEHOLDER MAP"
		hint_label.text = "Adventure loaded. Move with WASD / Arrow Keys."
	var is_inside := inside_medical_ward or inside_house or inside_east_cave or inside_city_ward or inside_orchid_house or inside_family_house
	camera.position = Vector3(player.position.x, 7.0 if is_inside else 18.0, player.position.z + (7.0 if is_inside else 18.0))


func _current_location() -> String:
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
	var dynamic_mask := 1 << (DYNAMIC_VISUAL_LAYER - 1)
	for node: Node in world.find_children("*", "GeometryInstance3D", true, false):
		var visual := node as GeometryInstance3D
		if visual == player_sprite or visual == follower_sprite:
			visual.layers = dynamic_mask
			continue
		var layer := _visual_layer_for_position(visual.global_position)
		visual.layers = 1 << (layer - 1)


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


func _set_active_visual_region(location: String) -> void:
	if camera == null:
		return
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
	var active_layer := int(location_layers.get(location, 1))
	camera.cull_mask = (1 << (active_layer - 1)) | (1 << (DYNAMIC_VISUAL_LAYER - 1))


func _clamp_player_to_region(origin: Vector3, region_size: Array) -> void:
	player.position.x = clampf(player.position.x, origin.x - float(region_size[0]) * 0.5 + 0.6, origin.x + float(region_size[0]) * 0.5 - 0.6)
	player.position.z = clampf(player.position.z, origin.z - float(region_size[1]) * 0.5 + 0.6, origin.z + float(region_size[1]) * 0.5 - 0.6)


func _load_map_data() -> Dictionary:
	var file := FileAccess.open(MAP_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not open rainforest map data.")
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _array_to_vector3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


func _solid_texture(color: Color) -> ImageTexture:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _billboard_sprite(texture: Texture2D, height: float, sprite_name: String) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.name = sprite_name
	sprite.texture = texture
	sprite.pixel_size = height / float(texture.get_height())
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	return sprite


func _square_sprite(color: Color, label_text: String, size: Vector2) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.texture = _solid_texture(color)
	sprite.pixel_size = 0.015
	sprite.scale = Vector3(size.x, size.y, 1.0)
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
	material.uv1_scale = uv_scale
	return material
