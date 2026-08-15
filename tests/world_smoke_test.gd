extends SceneTree


func _initialize() -> void:
	var scene := load("res://world/main.tscn") as PackedScene
	assert(scene != null, "Main scene must load.")
	var main := scene.instantiate()
	root.add_child(main)
	await process_frame
	assert(main.player != null, "Player placeholder must be created.")
	assert(main.MAP_DATA_PATH == "res://data/maps/map_index.json", "World maps must load through the editable map index.")
	assert(FileAccess.file_exists("res://data/maps/rainforest_clearing.json"), "The clearing must have its own map data file.")
	assert(FileAccess.file_exists("res://data/maps/mossvale_family_house.json"), "Map interiors must have their own data files.")
	assert(InputMap.action_get_events("move_left").any(func(event: InputEvent) -> bool: return event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_LEFT), "move_left must include the Left Arrow key.")
	assert(InputMap.action_get_events("move_right").any(func(event: InputEvent) -> bool: return event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_RIGHT), "move_right must include the Right Arrow key.")
	assert(main.opponent != null, "Trainer placeholder must be created.")
	assert(main.route_origin == Vector3(80, 0, 0), "Canopy Route must be built as a separate map region.")
	assert(main.world.get_node_or_null("ClearingNorthExit") != null, "The clearing must own its forest route warp.")
	assert(main.map_data.has("grass_zones") and not main.map_data.has("wild_zone"), "The clearing must use the standard grass_zones terrain field.")
	var clearing_grass_tiles: Array = main.world.get_children().filter(func(node: Node) -> bool: return node.name.begins_with("GrassTile_"))
	assert(not clearing_grass_tiles.is_empty(), "Clearing grass zones must generate standard visible tall-grass tiles.")
	var clearing_warp_art := main.world.get_node("ClearingNorthExit/OutdoorWarpArt_Generic") as Sprite3D
	assert(clearing_warp_art.texture.resource_path.ends_with("warp_outdoor_generic.png"), "The clearing's top warp must use the generic arch art.")
	assert(main.world.get_node_or_null("CanopyRouteExit") != null, "The route must have a return warp.")
	assert(main.world.get_node_or_null("UncrossableWaterBlock") != null, "The route must contain water blocks.")
	assert(main.world.get_node_or_null("TallFlowerBlock") != null, "The route must contain tall flower variation.")
	assert(main.east_route_origin == Vector3(110, 0, 30), "The eastern rainforest route must be built separately.")
	assert(main.west_route_origin == Vector3(50, 0, 30), "The western rainforest route must be built separately.")
	assert(main.world.get_node_or_null("CanopyRouteEastConnection") != null, "Canopy Route must connect east.")
	assert(main.world.get_node_or_null("CanopyRouteWestConnection") != null, "Canopy Route must connect west.")
	assert(main.world.get_node_or_null("EasternRouteCaveEntrance") != null, "The eastern route must have a cave entrance.")
	assert(main.world.get_node_or_null("VinestoneCaveRockyGround") != null, "The cave must have rocky ground.")
	assert(main.world.get_node_or_null("SmallBlueFlower") != null, "The cave must contain small blue flowers.")
	assert(main.world.get_node_or_null("CaveVine") != null, "The cave must contain vines.")
	assert(main.world.get_node_or_null("CanopyRouteWestConnection").position.z == 6.5, "The west warp must be below the blocking water.")
	assert(main.world.get_node("CanopyRouteExit").position.z > 13.0, "The lower route warp must sit against the map edge without a grass gap.")
	assert(main.world.get_node_or_null("CanopyRouteNorthConnection") != null, "Canopy Route must connect north to the city.")
	var north_route_warp_art := main.world.get_node("CanopyRouteNorthConnection/OutdoorWarpArt_Generic") as Sprite3D
	assert(north_route_warp_art.texture.resource_path.ends_with("warp_outdoor_generic.png"), "The top Canopy Route connection must use the generic warp art.")
	var east_warp_art := main.world.get_node("CanopyRouteEastConnection/OutdoorWarpArt_East") as Sprite3D
	var west_warp_art := main.world.get_node("CanopyRouteWestConnection/OutdoorWarpArt_West") as Sprite3D
	assert(east_warp_art.texture.resource_path.ends_with("warp_outdoor_facing_east.png"), "Right-side warps must use east-facing art.")
	assert(west_warp_art.texture.resource_path.ends_with("warp_outdoor_facing_west.png"), "Left-side warps must use west-facing art.")
	var east_warp_position := Vector2(float(main.map_data["route"]["east_warp"][0]), float(main.map_data["route"]["east_warp"][2]))
	for tree_data: Array in main.map_data["route"]["trees"]:
		var tree_position := Vector2(float(tree_data[0]), float(tree_data[2]))
		assert(tree_position.distance_to(east_warp_position) > 2.25, "Trees must leave the eastern warp artwork and approach visible.")
	var route_visual := main.world.get_node("CanopyRouteGround") as GeometryInstance3D
	var house_visual := main.world.get_node("HouseInteriorFloor") as GeometryInstance3D
	assert(route_visual.layers != house_visual.layers, "Off-map interiors must use a separate visual layer.")
	main._set_active_visual_region("route")
	assert((main.camera.cull_mask & route_visual.layers) != 0 and (main.camera.cull_mask & house_visual.layers) == 0, "The route camera must hide house interiors.")
	main._set_active_visual_region("rainforest")
	assert(main.city_origin == Vector3(170, 0, 0), "Mossvale must be built as a separate city map.")
	var clinic_door := main.world.find_child("MossvaleMedicalWardDoor", true, false) as Area3D
	var orchid_door := main.world.find_child("GroundOrchidHouseDoor", true, false) as Area3D
	var family_door := main.world.find_child("MossvaleFamilyHouseDoor", true, false) as Area3D
	assert(clinic_door != null and orchid_door != null and family_door != null, "Mossvale buildings must have door-linked warp areas.")
	assert(clinic_door.get_parent() is Sprite3D and clinic_door.get_child_count() == 1, "Exterior clinic and home warps must be invisible triggers attached to their building art.")
	var city_data: Dictionary = main.map_data["rainforest_city"]
	assert(city_data["medical_ward"]["exterior_return"] != city_data["orchid_house"]["exterior_return"], "Each city building needs its own exterior return point.")
	assert(city_data["orchid_house"]["exterior_return"] != city_data["family_house"]["exterior_return"], "City house exits must not share the map center destination.")
	assert(main.world.get_node_or_null("GroundOrchidExpert") != null, "The orchid home needs its fact-giving NPC.")
	assert(main.world.get_node_or_null("GroundOrchidBloom") != null, "The orchid home must contain small ground orchids.")
	assert((main.world.get_node("GroundOrchidBloom") as Sprite3D).texture.resource_path.ends_with("flower_indoor_orchidpot.png"), "The orchid house must use potted orchid art.")
	assert(main.world.get_node_or_null("MagnificentTorchGinger") != null, "Rare torch ginger art must appear sparingly on rainforest routes.")
	assert(main.world.get_node_or_null("CaveVine") is Sprite3D, "Cave vines must use the vine sprite art.")
	var tree_art := main.world.find_child("ClearingCanopyArt", true, false) as Sprite3D
	var vine_art := main.world.get_node("CaveVine") as Sprite3D
	var first_tree_sort_entry: Dictionary = main.tree_sort_entries.filter(func(entry): return (entry.get("sort_root") as CanvasItem).visible)[0]
	var first_tree_sort_root := first_tree_sort_entry["sort_root"] as Node2D
	assert(not tree_art.visible and first_tree_sort_root != null and main.sort_root.y_sort_enabled, "Trees must render through generated Node2D Y-sort roots rather than their 3D collision/placement sprites.")
	assert(not main.follower_sprite.visible and main.follower_sort_root != null and main.follower_sort_root.get_parent()==main.player_sort_root.get_parent(), "The collision-free follower must share the player's generated occlusion/Y-sort layer.")
	assert(not main.follower is CollisionObject3D and main.follower.find_children("*", "CollisionShape3D", true, false).is_empty(), "The following Fakemon must not gain collision.")
	var sand_shore:=main.world.get_node_or_null("ClearingSandShore0") as MeshInstance3D
	assert(sand_shore!=null and sand_shore.material_override.albedo_texture.resource_path.ends_with("tile_sand_generic.png"), "Serialized sand shore blocks must use the sand texture.")
	assert(first_tree_sort_root.position.is_equal_approx(main.camera.unproject_position(Vector3(first_tree_sort_entry["placement"].x, 0.0, first_tree_sort_entry["placement"].z + float(first_tree_sort_entry["sort_offset_y"])))), "A tree's Y-sort root must use placement plus sort_offset_y while leaving its visual placement independent.")
	assert(tree_art.billboard == vine_art.billboard and tree_art.alpha_cut == vine_art.alpha_cut, "Tree source sprites must retain normal billboard material settings for compatibility.")
	assert(main.world.get_node_or_null("MedicalWardFurnishing0") != null and main.world.get_node_or_null("RainforestHouseFurnishing0") != null and main.world.get_node_or_null("FamilyHomeFurnishing0") != null, "Serialized indoor furniture must be placed in the existing indoor maps.")
	var house_table_sort := main.sort_root.get_node_or_null("RainforestHouseFurnishing2SortRoot") as Node2D
	assert(house_table_sort != null and main.world.get_node_or_null("RainforestHouseFurnishing2Collision") != null, "Indoor furniture must use the common Y-sort layer and retain a separate collision footprint.")
	assert(not main.player_sprite.visible and main.player_sort_root != null, "The player must share the generated Y-sort container so front/back overlap follows feet position.")
	var building_sort_root := main.sort_root.get_node_or_null("MedicalWardExteriorSortRoot") as Node2D
	var warp_sort_root := main.sort_root.get_node_or_null("ClearingNorthExitSortRoot") as Node2D
	assert(building_sort_root != null and warp_sort_root != null, "Buildings and visible outdoor warps must use generated Y-sort roots.")
	assert(not (main.world.get_node("MedicalWardExteriorArt") as Sprite3D).visible and not (main.world.get_node("ClearingNorthExit/OutdoorWarpArt_Generic") as Sprite3D).visible, "Source building and warp sprites must be hidden after their collision-safe sorted visuals are generated.")
	assert(not main.sort_canvas.visible, "The world Y-sort canvas must remain hidden behind the start screen.")
	var house_exit_rug := main.world.get_node("HouseInteriorDoor/WarpRugArt") as MeshInstance3D
	var rug_size := (house_exit_rug.mesh as PlaneMesh).size
	assert(is_equal_approx(rug_size.x / rug_size.y, float(main.TEX_WARP_BUILDING.get_width()) / float(main.TEX_WARP_BUILDING.get_height())), "Warp rugs must preserve the source aspect ratio on a flat plane.")
	var battle_background := main.battle.battle_screen.get_node("BattleBackgroundArt") as TextureRect
	assert(battle_background.texture.resource_path.ends_with("battle_background.png"), "Battles must use the rainforest battle background art.")
	assert(main.battle.opponent_square.position == main.battle.OPPONENT_ART_POSITION, "Opponent art must align with the upper-right battle platform.")
	assert(main.battle.player_square.position == main.battle.PLAYER_ART_POSITION, "Player art must align with the lower-left battle platform.")
	assert(main.map_data["rainforest_city"]["orchid_house"]["orchids"].size() == 6, "The orchid arrangement must remain data-driven.")
	assert(main.world.get_node_or_null("EvolutionParent") != null, "The family needs an evolution parent.")
	assert(main.world.get_node_or_null("DespairParent") != null, "The family needs a Despair parent.")
	assert(main.family_children.size() == 3, "The family must include three wandering children.")
	assert(main.save_slot_selector.item_count == 5, "The manual save UI must expose five states.")
	assert(main.save_slot_selector.anchor_left == 1.0 and main.save_slot_selector.anchor_top == 1.0 and main.save_slot_selector.offset_top < 0.0, "Save controls must stay anchored to the bottom-right corner.")
	assert(main._manual_save_path(1) != main._manual_save_path(5), "Manual save states must use independent files.")
	assert(main.world.visible == false, "Player selection must appear before the map.")
	assert(main.battle.visible == false, "Starter selection must wait for player selection.")
	assert(main.player_selection_panel.visible, "Player selection must be the first new-adventure screen.")
	assert(main.PLAYER_CHOICES.size() == 8, "Player selection must offer four colors for each gender.")
	main._on_player_choice_selected(5)
	assert(main.player_gender == "Female" and main.player_color_name == "Pink", "The selected player gender and color must be retained.")
	assert(main.battle.visible, "Starter selection must open after choosing a player.")
	assert(main.battle.battle_data["fakemon"][0]["name"] == "Scorchick", "Scorchick must replace Ember Square in the roster.")
	var keklid: Dictionary = main.battle.battle_data["fakemon"][2]
	assert(keklid["name"] == "Keklid", "Keklid must replace Sprout Square in the roster.")
	assert(main.map_data["tall_grass_species"] is Array and main.map_data["medical_ward"]["tall_grass_species"] is Array and main.map_data["house"]["tall_grass_species"] is Array and main.map_data["route"]["tall_grass_species"] is Array and main.map_data["east_route"]["tall_grass_species"] is Array and main.map_data["west_route"]["tall_grass_species"] is Array and main.map_data["east_cave"]["tall_grass_species"] is Array and main.map_data["rainforest_city"]["tall_grass_species"] is Array and main.map_data["rainforest_city"]["medical_ward"]["tall_grass_species"] is Array and main.map_data["rainforest_city"]["orchid_house"]["tall_grass_species"] is Array and main.map_data["rainforest_city"]["family_house"]["tall_grass_species"] is Array, "Every map must define an editable tall-grass encounter species array.")
	assert(keklid["egg_groups"] == ["Plant", "Cosmic"], "Keklid's egg groups must be Plant and Cosmic.")
	var slumboth: Dictionary = main.battle.battle_data["fakemon"][3]
	assert(slumboth["name"] == "Slumboth" and slumboth["egg_groups"] == ["Mammal", "Mineral"], "Slumboth must replace Plain Square and use its assigned egg groups.")
	assert(main.dex_panel._move_effect_summary(main.battle.battle_data["moves"]["flutter"]) == "Raises the user's Special Attack and Special Defense by 10%.", "Dex move details must describe Flutter's stat boosts.")
	main.battle._set_fakemon_art(main.battle.opponent_square, keklid, "Wild")
	assert(main.battle.opponent_square.texture.resource_path.ends_with("Keklid_Wild.png"), "Keklid must use its wild-side battle sprite.")
	assert(main.battle._get_type_effectiveness("Fire", "Air") == 2.0, "Fire and Air must be super effective against each other.")
	assert(main.battle._get_type_effectiveness("Air", "Fire") == 2.0, "Air and Fire must be super effective against each other.")
	assert(main.battle._get_type_effectiveness("Bug", "Plant") == 2.0 and main.battle._get_type_effectiveness("Plant", "Bug") == 0.5, "Bug must be strong against and resist Plant.")
	assert(main.battle._get_type_effectiveness("Light", "Ghost") == 2.0 and main.battle._get_type_effectiveness("Ghost", "Light") == 0.5, "Light must be strong against and resist Ghost.")
	assert(main.battle._get_type_effectiveness("Mystic", "Fire") == 1.0 and main.battle._get_type_effectiveness("Fire", "Mystic") == 1.0, "Mystic interactions must remain neutral for now.")
	main._on_fakemon_selected(0)
	assert(main.follower.name == "ScorchickFollower", "Scorchick must use its overworld follower art.")
	assert(main.follower_sprite.texture.resource_path.ends_with("Scorchick_Follow_Down.png"), "Scorchick must initially face down behind the player.")
	var movement_start: Vector3 = main.player.position
	Input.action_press("move_up")
	main._physics_process(0.1)
	Input.action_release("move_up")
	assert(main.player.position.z < movement_start.z, "The configured move_up action must move the player north.")
	movement_start = main.player.position
	Input.action_press("move_right")
	main._physics_process(0.1)
	Input.action_release("move_right")
	assert(main.player.position.x > movement_start.x, "The configured move_right action must move the player east.")
	main.follower_facing = "Down"
	main._update_follower_appearance()
	assert(main.evolution_screen != null and not main.evolution_screen.visible, "The evolution overlay must be built and hidden until a level-up evolution is pending.")
	var evolving_keklid: Dictionary = main.battle.create_fakemon(main.battle.battle_data["fakemon"][2])
	evolving_keklid["level"] = 39
	evolving_keklid["experience"] = int(pow(40.0, 3.0)) - 1
	evolving_keklid["current_hp"] = int(evolving_keklid["max_hp"])
	main.pending_evolutions.clear()
	main._award_experience(evolving_keklid, 1)
	assert(evolving_keklid["level"] == 40 and main.pending_evolutions.size() == 1 and main.pending_evolutions[0]["target"]["name"] == "Phaloa", "A level-40 Keklid must queue Phaloa first, rather than skipping to Junrift.")
	main._apply_evolution(evolving_keklid, main.pending_evolutions[0]["target"])
	main.pending_evolutions.clear()
	assert(evolving_keklid["name"] == "Phaloa" and evolving_keklid["level"] == 40 and main._eligible_evolution(evolving_keklid)["name"] == "Junrift", "Keklid must become Phaloa while retaining its level, with Junrift eligible only later.")
	main._award_experience(evolving_keklid, int(pow(41.0, 3.0)) - int(evolving_keklid["experience"]))
	assert(main.pending_evolutions.size() == 1 and main.pending_evolutions[0]["target"]["name"] == "Junrift", "Phaloa must queue Junrift after a subsequent level gain.")
	main.pending_evolutions.clear()
	var scorchick: Dictionary = main.party[0]
	main.party[0] = main.battle.create_fakemon(keklid)
	main._update_follower_appearance()
	assert(main.follower.name == "KeklidFollower", "Keklid must use its overworld follower art.")
	assert(main.follower_sprite.texture.resource_path.ends_with("Keklid_Follow_Down.png"), "Keklid must initially face down behind the player.")
	main.party[0] = scorchick
	main._update_follower_appearance()
	var autosave_position: Vector3 = main.player.position
	main._auto_save()
	main.selected_save_slot = 1
	main.player.position = Vector3(1, 0.65, 1)
	assert(main._save_game(), "Manual state 1 must save.")
	main.selected_save_slot = 2
	main.player.position = Vector3(2, 0.65, 2)
	assert(main._save_game(), "Manual state 2 must save independently.")
	assert(main._load_game(1) and main.player.position == Vector3(1, 0.65, 1), "State 1 must restore its own snapshot.")
	assert(main._load_game(2) and main.player.position == Vector3(2, 0.65, 2), "State 2 must restore its own snapshot.")
	assert(main._load_game(0) and main.player.position == autosave_position, "Autosave must remain independent from manual states.")
	var second_mon: Dictionary = main.battle.create_fakemon(main.battle.battle_data["fakemon"][1])
	assert(second_mon["name"] == "Sylvafin", "Sylvafin must replace Brook Square in the roster.")
	second_mon["experience"] = int(pow(float(second_mon["level"]), 3.0))
	second_mon["current_hp"] = int(second_mon["max_hp"])
	second_mon["condition"] = ""
	second_mon["condition_turns"] = 0
	main.party.append(second_mon)
	main._select_party_mon(1)
	var selected_name: String = second_mon["name"]
	assert(main.follower.name == "SylvafinFollower", "Sylvafin must use its overworld follower art.")
	assert(main.follower_sprite.texture.resource_path.ends_with("Sylvafin_Follow_Down.png"), "Sylvafin must initially face down behind the player.")
	main._open_battle(0)
	assert(main.battle.active_party_index == 1, "Battle must start at the selected overworld party index.")
	assert(main.battle.player["name"] == selected_name, "The visible follower must be sent into battle first.")
	assert(main.battle.player_square.texture.resource_path.ends_with("Sylvafin_Player.png"), "Sylvafin must use its player-side battle sprite.")
	assert(main.battle.opponent_square.texture.resource_path.ends_with("Scorchick_Wild.png"), "Scorchick must use its wild-side battle sprite.")
	assert(main.battle.player_name_label.text.contains(String(second_mon["gender"])), "The battle header must display the Fakemon's gender.")
	assert(not main.battle.player_name_label.text.contains("SPD"), "The battle header must not display the speed label.")
	main.battle._select_battle_party_mon(0)
	assert(main.battle.participating_party_indices == [1, 0], "The opener and switched-in Fakemon must both count as participants.")
	var first_exp := int(main.party[0]["experience"])
	var second_exp := int(main.party[1]["experience"])
	var conditions: Array[Dictionary] = [{"condition": "", "condition_turns": 0}, {"condition": "", "condition_turns": 0}]
	var final_hp: Array[int] = [int(main.party[0]["current_hp"]), int(main.party[1]["current_hp"])]
	main._on_battle_finished(true, false, {}, 40, main.battle.participating_party_indices, 0, final_hp, conditions)
	assert(int(main.party[0]["experience"]) == first_exp + 20, "The first participant must receive half of 40 EXP.")
	assert(int(main.party[1]["experience"]) == second_exp + 20, "The second participant must receive half of 40 EXP.")
	var city_ward: Dictionary = main.map_data["rainforest_city"]["medical_ward"]
	var city_checkpoint: Vector3 = main.city_origin + main._array_to_vector3(city_ward["exterior_return"])
	main._set_respawn_checkpoint("city", city_checkpoint, "MOSSVALE RAINFOREST CITY")
	main._restore_respawn_checkpoint()
	assert(main._current_location() == "city" and main.player.position == city_checkpoint, "A visited medical ward must become the active cross-map defeat checkpoint.")
	print("WORLD_SMOKE_TEST_PASSED")
	quit()
