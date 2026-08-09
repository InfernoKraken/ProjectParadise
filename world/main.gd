extends Node

const MAP_DATA_PATH := "res://data/rainforest_map.json"
const SAVE_PATH := "user://project_paradise_save.json"
const SAVE_VERSION := 1
const MOVE_SPEED := 5.0
const DEX_VIEW_SCENE := preload("res://dex/dex_view.tscn")

@onready var world: Node3D = $World
@onready var battle: Control = $Battle

var map_data: Dictionary
var player: CharacterBody3D
var follower: Node3D
var follower_sprite: Sprite3D
var follower_target := Vector3.ZERO
var opponent: Area3D
var camera: Camera3D
var spawn_position: Vector3
var opponent_fakemon_index := 2
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
var medical_origin := Vector3.ZERO
var house_origin := Vector3.ZERO
var adventure_started := false
var poison_step_distance := 0.0
var world_environment: Environment
var map_title: Label
var house_npc: Area3D
var dialog_panel: PanelContainer
var dialog_label: Label
var dialog_button: Button
var dialog_page := 0
var dialog_open := false
var save_status_label: Label
var startup_panel: PanelContainer
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
	world.hide()
	map_ui.visible = false
	battle.begin_adventure_selection()
	if FileAccess.file_exists(SAVE_PATH):
		_build_startup_save_prompt()


func _physics_process(delta: float) -> void:
	if not adventure_started or in_battle or dialog_open or player == null or (party_panel != null and party_panel.visible) or (dex_panel != null and dex_panel.visible):
		return
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if Input.is_key_pressed(KEY_LEFT):
		input_vector.x = -1.0
	elif Input.is_key_pressed(KEY_RIGHT):
		input_vector.x = 1.0
	player.velocity = Vector3(input_vector.x, 0.0, input_vector.y) * MOVE_SPEED
	var position_before_move := player.position
	player.move_and_slide()
	if player.velocity.length_squared() > 0.01:
		follower_target = player.position - player.velocity.normalized() * 1.25
	if follower != null and follower.visible:
		follower.position = follower.position.move_toward(follower_target, MOVE_SPEED * 0.85 * delta)
	if inside_medical_ward:
		var ward_size: Array = map_data["medical_ward"]["size"]
		player.position.x = clampf(player.position.x, medical_origin.x - float(ward_size[0]) * 0.5 + 0.5, medical_origin.x + float(ward_size[0]) * 0.5 - 0.5)
		player.position.z = clampf(player.position.z, medical_origin.z - float(ward_size[1]) * 0.5 + 0.5, medical_origin.z + float(ward_size[1]) * 0.5 - 0.5)
	elif inside_house:
		var house_size: Array = map_data["house"]["interior_size"]
		player.position.x = clampf(player.position.x, house_origin.x - float(house_size[0]) * 0.5 + 0.5, house_origin.x + float(house_size[0]) * 0.5 - 0.5)
		player.position.z = clampf(player.position.z, house_origin.z - float(house_size[1]) * 0.5 + 0.5, house_origin.z + float(house_size[1]) * 0.5 - 0.5)
	else:
		var map_size: Array = map_data["map_size"]
		player.position.x = clampf(player.position.x, -float(map_size[0]) * 0.5 + 0.6, float(map_size[0]) * 0.5 - 0.6)
		player.position.z = clampf(player.position.z, -float(map_size[1]) * 0.5 + 0.6, float(map_size[1]) * 0.5 - 0.6)
	_process_poison_steps(position_before_move.distance_to(player.position))
	camera.position.x = player.position.x
	var is_inside := inside_medical_ward or inside_house
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
	ground.material_override = _material(Color("#39734b"))
	world.add_child(ground)

	spawn_position = _array_to_vector3(map_data["player_spawn"])
	player = CharacterBody3D.new()
	player.name = "PlayerPlaceholder"
	player.position = spawn_position
	player.add_child(_square_sprite(Color("#55e36a"), "PLAYER", Vector2(1.0, 1.25)))
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
	opponent = Area3D.new()
	opponent.name = "RainforestTrainerPlaceholder"
	opponent.position = _array_to_vector3(opponent_data["position"])
	opponent.add_child(_square_sprite(Color("#df6d5f"), "BATTLE", Vector2(1.0, 1.25)))
	opponent.add_child(_box_shape(Vector3(1.0, 1.3, 1.0)))
	world.add_child(opponent)

	var building_data: Dictionary = map_data["building"]
	var building := MeshInstance3D.new()
	building.name = "BuildingTilePlaceholder"
	var building_size := _array_to_vector3(building_data["size"])
	var building_mesh := BoxMesh.new()
	building_mesh.size = building_size
	building.mesh = building_mesh
	building.position = _array_to_vector3(building_data["position"])
	building.material_override = _material(Color("#b58a5a"))
	world.add_child(building)
	var building_body := StaticBody3D.new()
	building_body.name = "BuildingCollision"
	building_body.position = building.position
	building_body.add_child(_box_shape(building_size))
	world.add_child(building_body)
	var healing_entrance := Area3D.new()
	healing_entrance.name = "MedicalWardExteriorDoor"
	healing_entrance.position = _array_to_vector3(building_data["door"])
	var entrance_size := Vector3(1.5, 0.3, 1.0)
	healing_entrance.add_child(_box_shape(entrance_size))
	var entrance_visual := MeshInstance3D.new()
	var entrance_mesh := BoxMesh.new()
	entrance_mesh.size = entrance_size
	entrance_visual.mesh = entrance_mesh
	entrance_visual.material_override = _material(Color("#70d6d1"))
	healing_entrance.add_child(entrance_visual)
	healing_entrance.body_entered.connect(_on_exterior_door_entered)
	world.add_child(healing_entrance)
	_build_medical_ward(map_data["medical_ward"])
	_build_house(map_data["house"])

	_build_grass_tiles(map_data["wild_zone"])

	for tree_data: Array in map_data["trees"]:
		var tree_anchor := Vector3(float(tree_data[0]), float(tree_data[1]), float(tree_data[2]))
		var tree := Sprite3D.new()
		var tree_index := tree.get_instance_id()
		tree.name = "CanopyPlaceholder_%d" % tree_index
		# The billboard sits slightly behind its trunk anchor for correct front/back 2.5D layering.
		tree.position = tree_anchor + Vector3(0, 0, -0.45)
		tree.texture = _solid_texture(Color("#175c35") if int(tree_data[3]) == 0 else Color("#267a46"))
		tree.pixel_size = 0.012
		tree.scale = Vector3(2.5, 3.5, 1.0)
		tree.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tree.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		world.add_child(tree)
		var trunk_position := Vector3(tree_anchor.x, 0.75, tree_anchor.z)
		_add_static_collision("TreeTrunkCollision_%d" % tree_index, trunk_position, Vector3(0.9, 1.5, 0.9))

	camera = Camera3D.new()
	camera.name = "RainforestCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 24.0
	camera.position = Vector3(0, 18, 18)
	camera.rotation_degrees = Vector3(-45, 0, 0)
	camera.current = true
	world.add_child(camera)

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
	_open_battle(opponent_fakemon_index)


func _open_battle(enemy_index: int) -> void:
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
	in_battle = true
	world.hide()
	map_ui.visible = false
	battle.begin_battle_with_party(party, active_party_index, enemy_index, active_battle_is_wild)


func _on_fakemon_selected(index: int) -> void:
	var starter: Dictionary = battle.battle_data["fakemon"][index].duplicate(true)
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
	_save_game(false)


func _on_grass_tile_entered(body: Node3D, tile_id: String, encounter_chance: float) -> void:
	if body != player or in_battle:
		return
	if tile_id == last_grass_tile:
		return
	last_grass_tile = tile_id
	if randf() < encounter_chance:
		active_battle_is_wild = true
		var roster_size: int = battle.battle_data["fakemon"].size()
		_open_battle(randi_range(0, roster_size - 1))
	else:
		hint_label.text = "No encounter on this grass tile. Each newly stepped-on tile rolls 20%."


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
	_save_game(false)


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
	hint_label.text = "Click the orange resident to talk. Walk onto the gold door tile to leave."
	_start_door_cooldown()
	_save_game(false)


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
	_save_game(false)


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
	hint_label.text = "Medical ward: the party was restored. Walk onto the cyan door tile to leave."
	_refresh_party_menu()
	_start_door_cooldown()
	_save_game(false)


func _start_door_cooldown() -> void:
	door_warp_ready = false
	await get_tree().create_timer(0.5).timeout
	door_warp_ready = true


func _on_battle_finished(player_won: bool, escaped: bool, captured_mon: Dictionary, experience_earned: int, experience_recipient: int, final_active_index: int, final_party_hp: Array[int], final_party_conditions: Array[Dictionary]) -> void:
	var capture_added := false
	active_party_index = clampi(final_active_index, 0, party.size() - 1)
	if experience_earned > 0 and experience_recipient >= 0 and experience_recipient < party.size():
		_award_experience(party[experience_recipient], experience_earned)
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
		player.position = spawn_position
		player.velocity = Vector3.ZERO
		_place_follower_behind_player()
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
	_save_game(false)


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
		mon["level"] = int(mon["level"]) + 1
		mon["max_hp"] = int(mon["max_hp"]) + 3
		mon["attack"] = int(mon["attack"]) + 2
		mon["defense"] = int(mon["defense"]) + 2
		mon["special_attack"] = int(mon["special_attack"]) + 2
		mon["special_defense"] = int(mon["special_defense"]) + 2
		mon["speed"] = int(mon["speed"]) + 2


func _build_grass_tiles(wild_data: Dictionary) -> void:
	var center := _array_to_vector3(wild_data["position"])
	var zone_size := _array_to_vector3(wild_data["size"])
	var columns := int(floor(zone_size.x))
	var rows := int(floor(zone_size.z))
	for x in columns:
		for z in rows:
			var tile_id := "%d:%d" % [x, z]
			var tile := Area3D.new()
			tile.name = "GrassTile_" + tile_id.replace(":", "_")
			tile.position = center + Vector3(x - (columns - 1) * 0.5, 0.0, z - (rows - 1) * 0.5)
			var tile_size := Vector3(0.92, zone_size.y, 0.92)
			tile.add_child(_box_shape(tile_size))
			var visual := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = tile_size
			visual.mesh = mesh
			visual.material_override = _material(Color("#67a844"))
			tile.add_child(visual)
			tile.body_entered.connect(_on_grass_tile_entered.bind(tile_id, float(wild_data["encounter_chance"])))
			tile.body_exited.connect(_on_grass_tile_exited.bind(tile_id))
			world.add_child(tile)


func _build_medical_ward(ward_data: Dictionary) -> void:
	medical_origin = _array_to_vector3(ward_data["origin"])
	var ward_size: Array = ward_data["size"]
	var floor := MeshInstance3D.new()
	floor.name = "MedicalWardFloor"
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(float(ward_size[0]), 0.2, float(ward_size[1]))
	floor.mesh = floor_mesh
	floor.position = medical_origin + Vector3(0, -0.1, 0)
	floor.material_override = _material(Color("#d7f0ec"))
	world.add_child(floor)
	var center_tile := MeshInstance3D.new()
	center_tile.name = "MedicalWardCenterFloorTile"
	var center_mesh := BoxMesh.new()
	center_mesh.size = Vector3(4.5, 0.06, 3.2)
	center_tile.mesh = center_mesh
	center_tile.position = medical_origin + Vector3(0, 0.04, 0.3)
	center_tile.material_override = _material(Color("#b8ddd9"))
	world.add_child(center_tile)
	_add_ward_block("MedicalWardBackWall", medical_origin + Vector3(0, 1.25, -3.35), Vector3(8.0, 2.5, 0.3), Color("#eef5f3"))
	_add_ward_block("MedicalWardLeftWall", medical_origin + Vector3(-3.85, 1.25, 0), Vector3(0.3, 2.5, 6.7), Color("#c7dcdf"))
	_add_ward_block("MedicalWardRightWall", medical_origin + Vector3(3.85, 1.25, 0), Vector3(0.3, 2.5, 6.7), Color("#c7dcdf"))
	var reception := MeshInstance3D.new()
	reception.name = "MedicalWardCounterPlaceholder"
	var counter_mesh := BoxMesh.new()
	counter_mesh.size = Vector3(4.5, 1.0, 0.8)
	reception.mesh = counter_mesh
	reception.position = medical_origin + Vector3(0, 0.5, -2.2)
	reception.material_override = _material(Color("#e89aae"))
	world.add_child(reception)
	_add_static_collision("MedicalWardCounterCollision", reception.position, counter_mesh.size)
	var exit_door := Area3D.new()
	exit_door.name = "MedicalWardInteriorDoor"
	exit_door.position = medical_origin + _array_to_vector3(ward_data["exit_door"])
	var door_size := Vector3(1.5, 0.3, 0.9)
	exit_door.add_child(_box_shape(door_size))
	var door_visual := MeshInstance3D.new()
	var door_mesh := BoxMesh.new()
	door_mesh.size = door_size
	door_visual.mesh = door_mesh
	door_visual.material_override = _material(Color("#70d6d1"))
	exit_door.add_child(door_visual)
	exit_door.body_entered.connect(_on_interior_door_entered)
	world.add_child(exit_door)


func _build_house(house_data: Dictionary) -> void:
	var exterior_position := _array_to_vector3(house_data["position"])
	var exterior_size := _array_to_vector3(house_data["size"])
	var exterior := MeshInstance3D.new()
	exterior.name = "HouseExteriorPlaceholder"
	var exterior_mesh := BoxMesh.new()
	exterior_mesh.size = exterior_size
	exterior.mesh = exterior_mesh
	exterior.position = exterior_position
	exterior.material_override = _material(Color("#8f6c50"))
	world.add_child(exterior)
	_add_static_collision("HouseExteriorCollision", exterior_position, exterior_size)
	var exterior_door := Area3D.new()
	exterior_door.name = "HouseExteriorDoor"
	exterior_door.position = _array_to_vector3(house_data["door"])
	var door_size := Vector3(1.3, 0.3, 0.9)
	exterior_door.add_child(_box_shape(door_size))
	var exterior_door_visual := MeshInstance3D.new()
	var exterior_door_mesh := BoxMesh.new()
	exterior_door_mesh.size = door_size
	exterior_door_visual.mesh = exterior_door_mesh
	exterior_door_visual.material_override = _material(Color("#e0b45b"))
	exterior_door.add_child(exterior_door_visual)
	exterior_door.body_entered.connect(_on_house_exterior_door_entered)
	world.add_child(exterior_door)

	house_origin = _array_to_vector3(house_data["origin"])
	var room_size: Array = house_data["interior_size"]
	var floor := MeshInstance3D.new()
	floor.name = "HouseInteriorFloor"
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(float(room_size[0]), 0.2, float(room_size[1]))
	floor.mesh = floor_mesh
	floor.position = house_origin + Vector3(0, -0.1, 0)
	floor.material_override = _material(Color("#d8c6a5"))
	world.add_child(floor)
	_add_ward_block("HouseBackWall", house_origin + Vector3(0, 1.2, -2.85), Vector3(7.0, 2.4, 0.3), Color("#eadcc5"))
	_add_ward_block("HouseLeftWall", house_origin + Vector3(-3.35, 1.2, 0), Vector3(0.3, 2.4, 5.7), Color("#c9ae87"))
	_add_ward_block("HouseRightWall", house_origin + Vector3(3.35, 1.2, 0), Vector3(0.3, 2.4, 5.7), Color("#c9ae87"))
	var rug := MeshInstance3D.new()
	rug.name = "HouseRugPlaceholder"
	var rug_mesh := BoxMesh.new()
	rug_mesh.size = Vector3(3.2, 0.05, 2.2)
	rug.mesh = rug_mesh
	rug.position = house_origin + Vector3(0, 0.03, 0.2)
	rug.material_override = _material(Color("#b86f63"))
	world.add_child(rug)

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
	var interior_door_visual := MeshInstance3D.new()
	var interior_door_mesh := BoxMesh.new()
	interior_door_mesh.size = door_size
	interior_door_visual.mesh = interior_door_mesh
	interior_door_visual.material_override = _material(Color("#e0b45b"))
	interior_door.add_child(interior_door_visual)
	interior_door.body_entered.connect(_on_house_interior_door_entered)
	world.add_child(interior_door)


func _add_ward_block(block_name: String, block_position: Vector3, block_size: Vector3, color: Color) -> void:
	var visual := MeshInstance3D.new()
	visual.name = block_name
	var mesh := BoxMesh.new()
	mesh.size = block_size
	visual.mesh = mesh
	visual.position = block_position
	visual.material_override = _material(color)
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
	menu_button.position = Vector2(820, 16)
	menu_button.size = Vector2(115, 36)
	menu_button.pressed.connect(_toggle_party_menu)
	map_ui.add_child(menu_button)
	var save_button := Button.new()
	save_button.text = "Save (F5)"
	save_button.position = Vector2(690, 16)
	save_button.size = Vector2(120, 36)
	save_button.pressed.connect(_save_game)
	map_ui.add_child(save_button)
	var load_button := Button.new()
	load_button.text = "Load (F9)"
	load_button.position = Vector2(560, 16)
	load_button.size = Vector2(120, 36)
	load_button.pressed.connect(_load_game)
	map_ui.add_child(load_button)
	save_status_label = Label.new()
	save_status_label.position = Vector2(560, 55)
	save_status_label.add_theme_font_size_override("font_size", 12)
	map_ui.add_child(save_status_label)
	party_panel = PanelContainer.new()
	party_panel.position = Vector2(480, 60)
	party_panel.size = Vector2(465, 455)
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
	dex_panel = DEX_VIEW_SCENE.instantiate()
	dex_panel.return_requested.connect(_return_from_dex)
	map_ui.add_child(dex_panel)


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
	var speaker := Label.new()
	speaker.text = "RAINFOREST RESIDENT"
	speaker.add_theme_font_size_override("font_size", 16)
	content.add_child(speaker)
	dialog_label = Label.new()
	dialog_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialog_label.add_theme_font_size_override("font_size", 17)
	content.add_child(dialog_label)
	dialog_button = Button.new()
	dialog_button.pressed.connect(_advance_burn_dialogue)
	content.add_child(dialog_button)
	dialog_panel.hide()
	map_ui.add_child(dialog_panel)


func _start_burn_dialogue() -> void:
	dialog_page = 0
	dialog_open = true
	dialog_panel.show()
	_update_burn_dialogue()


func _advance_burn_dialogue() -> void:
	dialog_page += 1
	if dialog_page >= burn_dialogue.size():
		dialog_open = false
		dialog_panel.hide()
		return
	_update_burn_dialogue()


func _update_burn_dialogue() -> void:
	dialog_label.text = burn_dialogue[dialog_page]
	dialog_button.text = "Close" if dialog_page == burn_dialogue.size() - 1 else "Next"


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
	_save_game(false)


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
	_save_game(false)


func _update_follower_appearance() -> void:
	if follower_sprite == null or party.is_empty():
		return
	var leading_mon: Dictionary = party[active_party_index]
	follower_sprite.texture = _solid_texture(Color(leading_mon["color"]))
	follower.name = "%sFollowerPlaceholder" % leading_mon["name"].replace(" ", "")


func _place_follower_behind_player() -> void:
	if follower == null:
		return
	follower.position = player.position + Vector3(0, 0, 1.25)
	follower_target = follower.position


func _input(event: InputEvent) -> void:
	if dialog_open and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			_advance_burn_dialogue()
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
	_load_game()


func _start_new_adventure() -> void:
	startup_panel.queue_free()
	startup_panel = null
	battle.begin_adventure_selection()


func _save_game(show_feedback: bool = true) -> bool:
	if not adventure_started or in_battle or party.is_empty():
		if show_feedback and save_status_label != null:
			save_status_label.text = "Saving is available while exploring."
		return false
	var location := "medical_ward" if inside_medical_ward else ("house" if inside_house else "rainforest")
	var save_data := {
		"version": SAVE_VERSION,
		"party": party,
		"active_party_index": active_party_index,
		"location": location,
		"player_position": [player.position.x, player.position.y, player.position.z],
		"poison_step_distance": poison_step_distance
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		if save_status_label != null:
			save_status_label.text = "Save failed: storage could not be opened."
		return false
	file.store_string(JSON.stringify(save_data, "  "))
	if show_feedback and save_status_label != null:
		save_status_label.text = "Adventure saved."
	return true


func _load_game() -> bool:
	if in_battle or not FileAccess.file_exists(SAVE_PATH):
		if save_status_label != null:
			save_status_label.text = "No save can be loaded right now."
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if not parsed is Dictionary:
		if save_status_label != null:
			save_status_label.text = "Save file is invalid. Start a new adventure."
		return false
	var data := parsed as Dictionary
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
	dialog_open = false
	dialog_panel.hide()
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
		save_status_label.text = "Adventure loaded."
	return true


func _apply_loaded_location(location: String) -> void:
	if location == "medical_ward":
		camera.size = 9.0
		world_environment.background_color = Color("#354b5e")
		map_title.text = "MEDICAL WARD - PLACEHOLDER INTERIOR"
		hint_label.text = "Loaded inside the medical ward. Walk onto the cyan door tile to leave."
	elif location == "house":
		camera.size = 8.0
		world_environment.background_color = Color("#55483d")
		map_title.text = "RAINFOREST HOUSE - PLACEHOLDER INTERIOR"
		hint_label.text = "Loaded inside the house. Click the orange resident to talk."
	else:
		inside_medical_ward = false
		inside_house = false
		camera.size = 24.0
		world_environment.background_color = Color("#93c47d")
		map_title.text = "RAINFOREST CLEARING - PLACEHOLDER MAP"
		hint_label.text = "Adventure loaded. Move with WASD / Arrow Keys."
	var is_inside := inside_medical_ward or inside_house
	camera.position = Vector3(player.position.x, 7.0 if is_inside else 18.0, player.position.z + (7.0 if is_inside else 18.0))


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
