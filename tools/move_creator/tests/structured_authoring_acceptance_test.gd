extends SceneTree

func _initialize() -> void:
	var model := MoveAnimationEditorModel.new(); model.document.data["id"] = "v02_structured_projectile"
	var spawn := model.add_event("spawn_sprite"); spawn["time"] = 0.0; spawn["instance_id"] = "projectile"; spawn["asset"] = "res://assets/move_effects/TestAirBlast.png"; spawn["position"] = {"battler":"user","anchor":"mouth","offset":[0,0]}; spawn["scale"] = 0.35
	var move := model.add_event("move_sprite"); move["time"] = 0.1; move["instance_id"] = "projectile"; move["to"] = {"battler":"target","anchor":"origin","offset":[0,0]}; move["duration"] = 0.3
	var marker := model.add_event("marker"); marker["time"] = 0.4; marker["name"] = "impact"
	var shake := model.add_event("shake_battler"); shake["time"] = 0.4; shake["battler"] = "target"
	var destroy := model.add_event("destroy_sprite"); destroy["time"] = 0.45; destroy["instance_id"] = "projectile"; model.sort_events()
	assert(model.document.validation_errors().is_empty(), "Structured projectile authoring must produce valid runtime data.")
	var saved := "user://v02_structured_projectile.json"; assert(model.document.save_file(saved) == OK); var reloaded := MoveAnimationDefinition.load_file(saved); var normalized: Variant = JSON.parse_string(JSON.stringify(model.document.data)); assert(reloaded != null and reloaded.data == normalized, "Structured projectile must reconstruct after save/reload.")
	var status := MoveAnimationEditorModel.new(); status.document.data["id"] = "v02_structured_status"
	var tint := status.add_event("background_tint"); tint["time"] = 0.0
	var status_spawn := status.add_event("spawn_sprite"); status_spawn["time"] = 0.05; status_spawn["instance_id"] = "status_fx"; status_spawn["asset"] = "res://assets/move_effects/TestPetals.png"; status_spawn["position"] = {"battler":"user","anchor":"head","offset":[0,-10]}; status_spawn["sprite_sheet"] = {"columns":1,"rows":1,"frame_count":1,"fps":12.0,"loop":true}
	var fade := status.add_event("fade_sprite"); fade["time"] = 0.35; fade["instance_id"] = "status_fx"
	var restore := status.add_event("restore_background"); restore["time"] = 0.45
	var status_destroy := status.add_event("destroy_sprite"); status_destroy["time"] = 0.7; status_destroy["instance_id"] = "status_fx"; status.sort_events()
	assert(status.document.validation_errors().is_empty(), "Structured sprite-sheet/status authoring must produce valid runtime data.")
	var layer := Node2D.new(); root.add_child(layer); var overlay := ColorRect.new(); root.add_child(overlay); var user := Control.new(); user.position = Vector2(50,180); root.add_child(user); var target := Control.new(); target.position = Vector2(380,40); root.add_child(target); var player := MoveAnimationPlayer.new(); root.add_child(player); await process_frame
	var context := MoveAnimationContext.new(); context.user=user; context.target=target; context.anchor_repository=GeneratedAnchorRepository.new(); context.effect_layer=layer; context.background_overlay=overlay
	for setup in [["Lochirp","Player","Flambian","Wild"],["Flambian","Player","Lochirp","Wild"]]:
		context.user_art_id=setup[0];context.user_side=setup[1];context.target_art_id=setup[2];context.target_side=setup[3];assert(await player.play(reloaded,context),"Structured animation must preview in both orientations.");assert(layer.get_child_count()==0,"Preview must clean effects.")
	assert(await player.play(status.document,context),"Structured sprite-sheet/status preview must complete.");assert(not overlay.visible and layer.get_child_count()==0,"Status preview must restore background and effects.")
	print("STRUCTURED_AUTHORING_ACCEPTANCE_TEST_PASSED")
	quit()
