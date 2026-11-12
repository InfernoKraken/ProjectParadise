extends RefCounted

var game: Node
var map_file := ""
var hidden_objects: Dictionary = {}
var hidden_sprites: Dictionary = {}
var pictures: Dictionary = {}
var fade: ColorRect
var fade_tween: Tween
var owns_dialogue := false

func _init(world: Node) -> void:
	game = world

func _species_index(name: String) -> int:
	for i in game.battle.battle_data.fakemon.size():
		if game.battle.battle_data.fakemon[i].name == name: return i
	return -1

func execute(command: String, args: Array, resume: Callable) -> Dictionary:
	match command:
		"MoveSprite", "FollowSprite", "StopFollowing", "ResumeMovement", "FaceSprite", "WaitMovement":
			var ticket: int = game.script_runner.generation
			return game.npc_script_movement.request(map_file, command, args, resume, func(reason):game.script_runner.fail(reason, ticket))
		"Wait":
			if float(args[0]) <= 0: return {}
			game.get_tree().create_timer(float(args[0]), false).timeout.connect(resume, CONNECT_ONE_SHOT)
			return {"pending":true}
		"Lock", "Unlock": game.script_input_locked = command == "Lock"
		"TextBoxYesNo":
			owns_dialogue = true
			var ticket: int = game.script_runner.generation
			game._start_yes_no_dialogue(str(args[0]), func(yes: bool):owns_dialogue = false; game.script_runner.answer_choice(ticket,yes))
			return {"pending":true}
		"TextBox":
			owns_dialogue = true
			game._start_dialogue("", [args[0]], func():owns_dialogue = false; resume.call())
			return {"pending":true}
		"HealParty": game._heal_party_at_ward()
		"SaveGame":
			if not game._save_game(): return {"error":"Existing save service rejected the save."}
		"GiveFakemon":
			var capacity: int = game.fakemon_storage.PARTY_CAPACITY
			if game.party.size() >= capacity: return {"error":"Party is full (%d). Make room before accepting this Fakemon." % capacity}
			var index: int = _species_index(str(args[0]))
			if index < 0: return {"error":"Unknown species: " + str(args[0])}
			var mon: Dictionary = game.battle.create_fakemon(game.battle.battle_data.fakemon[index], int(args[1]))
			game.exhibits.record(mon)
			mon.experience = int(pow(float(mon.level), 3.0)); mon.current_hp = int(mon.max_hp); mon.condition = ""; mon.condition_turns = 0
			game.party.append(mon); game._refresh_party_menu(); game._update_follower_appearance()
			if game.party.size() == 1:
				game.active_party_index = 0
				game._place_follower_behind_player()
				if game.follower != null: game.follower.visible = not game.swimming
		"Warp":
			var filename: String = args[0] if String(args[0]).ends_with(".json") else String(args[0]) + ".json"
			var target: Dictionary = game.map_data.get("_map_files", {}).get(filename, {})
			var location: String = game._location_for_map_file(filename)
			if target.is_empty() or location.is_empty(): return {"error":"Map is not loaded/playable: " + filename}
			var origin: Vector3 = game._array_to_vector3(target.get("origin", [0,0,0]))
			game._set_route_location(location, origin + Vector3(args[1], 0.65, args[2]), filename.get_basename(), "Script warp")
			# V1 never carries a script execution across maps.
			game.script_runner.stop()
		"ShowSprite", "HideSprite":
			var key := str(args[0])
			var node: Node = game.npc_script_movement.actor(map_file, key)
			if node == null or node == game.player: return {"error":"Unknown map-local NPC ID: " + key}
			set_sprite_hidden(node, command == "HideSprite")
		"ShowObject", "HideObject":
			var found := false
			var layer: int = game._active_visual_layer()
			for entries: Array in [game.object_sort_entries, game.tree_sort_entries, game.background_object_sort_entries]:
				for entry: Dictionary in entries:
					if str(entry.get("instance_id", "")) == str(args[0]) and game._sort_entry_layer(entry, entry.placement) == layer: found = true
			if not found: return {"error":"Object has no registered visual: " + str(args[0])}
			hidden_objects[str(layer) + ":" + str(args[0])] = command == "HideObject"
		"FadeOut", "FadeIn":
			if fade == null:
				fade = ColorRect.new(); fade.color = Color.BLACK; fade.mouse_filter = Control.MOUSE_FILTER_IGNORE; fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); fade.modulate.a = 0.0; fade.z_index = 100
				game.map_ui.add_child(fade)
			fade_tween = game.create_tween(); fade_tween.tween_property(fade, "modulate:a", 1.0 if command == "FadeOut" else 0.0, 0.25)
			fade_tween.finished.connect(resume, CONNECT_ONE_SHOT)
			return {"pending":true}
		"ShowSpritePicture":
			var path := "res://assets/overworld/" + str(args[0])
			if not ResourceLoader.exists(path): return {"error":"Missing picture: " + path}
			var texture := load(path) as Texture2D
			if texture == null: return {"error":"Picture is not a texture."}
			if pictures.has(args[0]): pictures[args[0]].queue_free()
			var picture := TextureRect.new(); picture.texture = texture; picture.position = Vector2(args[1], args[2]); picture.mouse_filter = Control.MOUSE_FILTER_IGNORE; picture.z_index = 90
			game.map_ui.add_child(picture); pictures[args[0]] = picture
		"HideSpritePicture":
			if pictures.has(args[0]): pictures[args[0]].queue_free(); pictures.erase(args[0])
		_: return {"error":"No game adapter for command: " + command}
	return {}

func cleanup() -> void:
	game.script_input_locked = false
	game.npc_script_movement.cancel_waits()
	game.npc_script_movement.cancel_moves()
	if owns_dialogue:
		game.dialog_open = false; game.dialogue_complete_action = Callable(); game.dialog_panel.hide(); game._clear_dialogue_choice(); owns_dialogue = false
	if fade_tween != null: fade_tween.kill(); fade_tween = null
	if fade != null: fade.queue_free(); fade = null
	for picture: Node in pictures.values(): picture.queue_free()
	pictures.clear()

func object_hidden(entry: Dictionary) -> bool:
	var layer: int = game._sort_entry_layer(entry, entry.placement)
	return bool(hidden_objects.get(str(layer) + ":" + str(entry.get("instance_id", "")), false))

func sprite_hidden(node: Node) -> bool:
	return bool(hidden_sprites.get(str(node.get_meta("script_map", "")) + ":" + str(node.get_meta("script_npc_id", "")), node.get_meta("authored_hidden", false)))

# Capture while authored NPCs are created, before region activation changes them.
func remember_sprite_collision(node: Node) -> void:
	var colliders: Array = [node]
	colliders.append_array(node.find_children("*", "CollisionObject3D", true, false))
	for collider: CollisionObject3D in colliders:
		if not collider.has_meta("npc_authored_collision"):
			collider.set_meta("npc_authored_collision", {"layer":int(collider.get_meta("base_collision_layer", collider.collision_layer)), "mask":collider.collision_mask, "monitoring":collider.monitoring if collider is Area3D else false, "monitorable":collider.monitorable if collider is Area3D else false})
			if not collider.has_meta("base_collision_layer"): collider.set_meta("base_collision_layer", collider.collision_layer)

# Runtime enablement never mutates the authored NPC or editor state.
func set_sprite_hidden(node: Node, hidden: bool, refresh_visuals: bool = true) -> void:
	hidden_sprites[str(node.get_meta("script_map")) + ":" + str(node.get_meta("script_npc_id"))] = hidden
	remember_sprite_collision(node)
	node.set_meta("script_hidden", hidden)
	var colliders: Array = [node]
	colliders.append_array(node.find_children("*", "CollisionObject3D", true, false))
	for collider: CollisionObject3D in colliders:
		collider.set_meta("script_hidden", hidden)
		var original: Dictionary = collider.get_meta("npc_authored_collision")
		var active: bool = int(node.get_meta("visual_layer", game._active_visual_layer())) == game._active_visual_layer()
		collider.collision_layer = 0 if hidden or not active else int(original.layer)
		collider.collision_mask = 0 if hidden else int(original.mask)
		if collider is Area3D:
			collider.set_deferred("monitoring", not hidden and active and original.monitoring)
			collider.set_deferred("monitorable", not hidden and active and original.monitorable)
	if hidden: game.npc_script_movement.cancel_actor(node)
	if refresh_visuals: game._update_sort_canvas()

func reset_sprites() -> void:
	hidden_sprites.clear()
	for instances: Dictionary in game.runtime_npcs.values():
		for node: Node in instances.values():
			set_sprite_hidden(node, bool(node.get_meta("authored_hidden", false)), false)
	game._update_sort_canvas()
