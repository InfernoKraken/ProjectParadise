extends SceneTree


func _initialize() -> void:
	var scene := load("res://world/main.tscn") as PackedScene
	var main := scene.instantiate()
	root.add_child(main)
	await process_frame
	assert(main.family_children.size() == 3, "The family house must spawn three children.")
	assert(main.world.find_children("FamilyChild*", "Area3D", true, false).size() == 3, "Each child must have one NPC node.")
	main.inside_family_house = true
	for child_data: Dictionary in main.family_children:
		var child: Area3D = child_data["node"]
		assert((child.get_child(0) as Sprite3D).texture != null, "Each child must have an idle sprite.")
		child_data["target"] = child.position + Vector3.RIGHT * 2.0
		child_data["timer"] = 3.0
	main._update_family_children(0.17)
	main._update_sort_canvas()
	for child_data: Dictionary in main.family_children:
		var child: Area3D = child_data["node"]
		var visual := child.get_child(0) as Sprite3D
		assert(child.get_meta("facing") == "right", "Every moving child must face its movement direction.")
		assert(visual.texture == main.NpcSpriteLibrary.texture_for(String(child.get_meta("sprite_id")), "right", 1), "Every child must advance its own sheet animation.")
		var entry: Dictionary = main.npc_sort_entries.filter(func(candidate: Dictionary) -> bool: return candidate["node"] == child)[0]
		assert(not visual.visible, "The source 3D sprite must stay hidden when the sorted sprite is used.")
		assert((entry["sort_root"] as Node2D).get_node("Visual").texture == visual.texture, "The sorted visual must follow the current animation frame.")
	print("NPC_BEHAVIOR_TEST_PASSED")
	quit()
