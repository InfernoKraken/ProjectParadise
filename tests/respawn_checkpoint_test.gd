extends SceneTree


func _initialize() -> void:
	var scene := load("res://world/main.tscn") as PackedScene
	assert(scene != null, "World scene must load.")
	var main := scene.instantiate()
	root.add_child(main)
	await process_frame
	assert(main.world.get_node_or_null("ClearingTrainer1") != null and main.world.get_node_or_null("MossvaleTrainer2") != null, "Outdoor maps must build their data-driven trainer placeholders.")
	assert(main.world.get_node_or_null("MedicalWardAttendant") != null and main.world.get_node_or_null("MossvaleWardAttendant") != null, "Both medical wards must have a counter attendant.")
	main.party.clear()
	main.party.append({"name": "Test Mon", "level": 5, "max_hp": 20, "current_hp": 3, "condition": "Burned", "condition_turns": 0, "experience": 125, "moves": []})
	main._heal_party_at_ward()
	assert(main.party[0]["current_hp"] == 20 and main.party[0]["condition"].is_empty(), "Ward care must restore HP and conditions only when the attendant is spoken to.")
	var ward: Dictionary = main.map_data["rainforest_city"]["medical_ward"]
	var checkpoint: Vector3 = main.city_origin + main._array_to_vector3(ward["exterior_return"])
	main._set_respawn_checkpoint("city", checkpoint, "MOSSVALE RAINFOREST CITY")
	main._restore_respawn_checkpoint()
	assert(main._current_location() == "city", "The city ward checkpoint must restore the city map state.")
	assert(main.player.position == checkpoint, "The city ward checkpoint must restore its exterior position.")
	assert(main.map_title.text == "MOSSVALE RAINFOREST CITY", "The respawn must restore the matching map presentation.")
	print("RESPAWN_CHECKPOINT_TEST_PASSED")
	quit()
