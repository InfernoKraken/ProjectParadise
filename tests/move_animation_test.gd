extends SceneTree

var markers: Array[String] = []
var finished_count := 0

func _initialize() -> void:
	var valid := MoveAnimationDefinition.load_file("res://data/move_animations/projectile_test.json")
	assert(valid != null and valid.validation_errors().is_empty(), "Valid animation must parse and validate.")
	var bad_version := MoveAnimationDefinition.from_dictionary({"format_version": 99, "id": "bad", "events": []})
	assert(not bad_version.validation_errors().is_empty(), "Unsupported versions must fail.")
	var missing_asset := MoveAnimationDefinition.from_dictionary({"format_version": 1, "id": "bad_asset", "events": [{"time": 0, "type": "spawn_sprite", "instance_id": "x", "asset": "res://assets/move_effects/missing.png", "sprite_sheet": null, "position": {"battler": "user", "anchor": "origin", "offset": [0, 0]}}]})
	assert(not missing_asset.validation_errors().is_empty(), "Missing assets must fail validation.")
	var repository := GeneratedAnchorRepository.new()
	assert(repository.get_battle_anchor("Lochirp", "Player", "mouth") != Vector2.ZERO, "Generated anchors must resolve.")
	assert(repository.get_battle_anchor("Lochirp", "Player", "does_not_exist") == repository.get_battle_anchor("Lochirp", "Player", "origin"), "Optional anchors must fall back to origin.")
	var warnings: Array[String] = []
	var malformed_repository := GeneratedAnchorRepository.new("res://tests/fixtures/malformed_battle_anchors.json")
	malformed_repository.warning_handler = func(message: String): warnings.append(message)
	assert(malformed_repository.get_battle_anchor("Test", "Player", "mouth") == Vector2(50, 30), "Missing requested anchor and origin must use processed center.")
	assert(warnings.size() == 1 and "no origin anchor" in warnings[0], "Missing origin must emit a useful warning.")
	var legacy := MoveAnimationResolver.resolve("legacy", {"animation_kind": "caster_lunge"})
	assert(legacy.animation_id == "" and legacy.fallback_animation == "caster_lunge", "Legacy animation_kind must remain supported.")
	var fallback := MoveAnimationResolver.resolve("fallback", {"fallback_animation": "target_burst"})
	assert(fallback.fallback_animation == "target_burst", "Canonical fallback_animation must select generic playback.")
	var custom := MoveAnimationResolver.resolve("custom", {"animation_id": "projectile_test"})
	assert(custom.animation_id == "projectile_test", "Valid custom animation must be selected.")
	var preferred := MoveAnimationResolver.resolve("preferred", {"animation_id": "projectile_test", "fallback_animation": "target_hit"})
	assert(preferred.animation_id == "projectile_test" and preferred.fallback_animation == "target_hit", "Custom animation must be preferred while retaining fallback.")
	var missing := MoveAnimationResolver.resolve("missing", {"animation_id": "not_present", "fallback_animation": "target_hit"})
	assert(missing.animation_id == "" and missing.fallback_animation == "target_hit" and not missing.warnings.is_empty(), "Missing custom animation must degrade to fallback with a warning.")
	var none := MoveAnimationResolver.resolve("none", {})
	assert(none.animation_id == "" and none.fallback_animation == "", "A move with no animation configuration must fail safely.")
	var both := MoveAnimationResolver.resolve("both", {"fallback_animation": "projectile", "animation_kind": "caster_lunge"})
	assert(both.fallback_animation == "projectile" and not both.warnings.is_empty(), "Canonical fallback must beat the deprecated alias and report the conflict.")
	var malformed := MoveAnimationResolver.resolve("malformed", {"animation_id": "not valid", "fallback_animation": "not_a_preset"})
	assert(malformed.animation_id == "" and malformed.fallback_animation == "" and malformed.warnings.size() == 2, "Malformed animation fields must be detected and ignored safely.")
	var layer := Node2D.new(); root.add_child(layer)
	var overlay := ColorRect.new(); root.add_child(overlay)
	var user := Control.new(); user.position = Vector2(40, 180); root.add_child(user)
	var target := Control.new(); target.position = Vector2(380, 40); root.add_child(target)
	var user_origin := user.position; var target_origin := target.position
	var context := MoveAnimationContext.new(); context.user = user; context.target = target; context.user_art_id = "Lochirp"; context.target_art_id = "Flambian"; context.user_side = "Player"; context.target_side = "Wild"; context.anchor_repository = repository; context.effect_layer = layer; context.background_overlay = overlay
	var player := MoveAnimationPlayer.new(); root.add_child(player); player.marker_reached.connect(func(name): markers.append(name)); player.animation_finished.connect(func(): finished_count += 1)
	await process_frame
	await player.play(valid, context)
	assert(markers == ["impact"] and finished_count == 1, "Marker and completion signals must emit.")
	assert(user.position == user_origin and target.position == target_origin, "Battlers must return exactly to baseline.")
	assert(layer.get_child_count() == 0 and not overlay.visible, "Effects and background state must clean up.")
	for iteration in 2:
		await process_frame
		await player.play(valid, context)
	assert(finished_count == 3 and layer.get_child_count() == 0 and user.position == user_origin and target.position == target_origin, "Repeated playback must not leak or drift.")
	var physical := MoveAnimationDefinition.load_file("res://data/move_animations/physical_test.json")
	await player.play(physical, context)
	assert(user.position == user_origin and target.position == target_origin, "Lunge and shake must restore baselines.")
	var status := MoveAnimationDefinition.load_file("res://data/move_animations/status_impact_test.json")
	player.play(status, context)
	await create_timer(0.15).timeout; player.cancel(); await process_frame
	assert(not overlay.visible and layer.get_child_count() == 0 and user.position == user_origin, "Interrupted playback must restore all temporary state.")
	var roundtrip_path := "user://move_animation_roundtrip.json"
	assert(valid.save_file(roundtrip_path) == OK, "Valid definitions must save.")
	var roundtrip := MoveAnimationDefinition.load_file(roundtrip_path)
	assert(roundtrip != null and roundtrip.data == valid.data, "Save/load must preserve animation meaning.")
	var sheet := MoveAnimationDefinition.from_dictionary({"format_version": 1, "id": "sheet", "duration": 0.2, "events": [{"time": 0, "type": "spawn_sprite", "instance_id": "sheet", "asset": "res://assets/move_effects/TestBeam.png", "sprite_sheet": {"columns": 1, "rows": 1, "frame_count": 1, "fps": 10, "loop": false}, "position": {"battler": "user", "anchor": "origin", "offset": [0, 0]}}, {"time": 0.15, "type": "destroy_sprite", "instance_id": "sheet"}]})
	assert(sheet.validation_errors().is_empty(), "Compatible uniform sheets must validate.")
	context.user_art_id = "Flambian"; context.target_art_id = "Lochirp"; context.user_side = "Wild"; context.target_side = "Player"
	await player.play(valid, context)
	assert(user.position == user_origin and target.position == target_origin and layer.get_child_count() == 0, "The same definition must replay with swapped species and sides.")
	print("MOVE_ANIMATION_TEST_PASSED")
	quit()
