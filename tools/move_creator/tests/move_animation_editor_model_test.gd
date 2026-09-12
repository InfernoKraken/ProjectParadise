extends SceneTree

func _initialize() -> void:
	var source := MoveAnimationDefinition.load_file("res://data/move_animations/projectile_test.json")
	assert(source != null and source.validation_errors().is_empty(), "v0.1 fixture must be valid.")
	var model := MoveAnimationEditorModel.new(); model.load_document(source)
	assert(model.document.data == source.data, "Structured model must preserve every loaded field.")
	assert(not model.validation_text().contains("[color="), "Validation must be human-readable, not raw BBCode.")
	var original_count: int = model.document.data["events"].size()
	var marker := model.add_event("marker"); marker["name"] = "release"
	assert(model.document.data["events"].size() == original_count + 1 and marker["name"] == "release")
	var copied_marker:=model.copy_selected_event_json();assert(not copied_marker.is_empty());assert(model.paste_event_json(copied_marker));assert(model.selected_event["type"]=="marker" and model.selected_event["name"]=="release" and model.document.data["events"].size()==original_count+2,"Copy/Paste must deep-copy the selected structured event.");model.selected_event["name"]="copied_release";assert(marker["name"]=="release","Editing a pasted event must not mutate its source.");assert(not model.paste_event_json("not an event"),"Invalid clipboard text must be rejected safely.");assert(model.delete_selected())
	model.selected_event = marker; assert(model.delete_selected(), "Delete Selected must remove the selected event."); assert(model.document.data["events"].size() == original_count)
	var late: Dictionary = model.document.data["events"][0]; model.set_event_time(late, 10.0); assert(model.document.data["events"][-1] == late, "Changing time must reorder while preserving selection.")
	model.load_document(source)
	var assets := model.effect_assets(); assert(assets.has("res://assets/move_effects/TestAirBlast.png"), "Asset selector must store res:// paths.")
	var import_entries:=model.effect_import_entries();assert(not import_entries.is_empty() and import_entries.all(func(entry):return (entry["path"].begins_with("res://assets/move_effects/") or entry["path"].begins_with("res://assets/battle/weather/")) and entry["status"] in ["Imported","Missing Import","Import Error"]),"Import status must cover move-effect and weather assets and distinguish disk discovery from usable Godot resources.");assert(import_entries.any(func(entry):return entry["path"].begins_with("res://assets/battle/weather/")),"Import tab must discover battle weather PNGs.")
	var blood_import:=model.import_effect_asset("res://assets/move_effects/Attack_Impact_Blood_Drops.png");assert(blood_import["error"]==OK and blood_import["path"]=="res://assets/move_effects/Attack_Impact_Blood_Drops.png","The Blood Drops PNG must pass the same importer used by the UI.");assert(model.effect_assets().has(String(blood_import["path"])),"Imported PNGs must immediately appear in effect asset selectors.");assert(MoveEffectAssetRules.load_texture(String(blood_import["path"]))!=null,"Imported PNGs must be immediately loadable for preview.")
	assert(model.spawn_instance_ids().has("projectile") and model.spawn_instance_ids().has("impact"), "Effect dropdown must discover spawn IDs.")
	var broken := MoveAnimationEditorModel.new(); broken.document.data["events"] = [MoveAnimationEditorModel.default_event("move_sprite")]; broken.document.data["events"][0]["instance_id"] = "missing_but_preserved"
	assert(broken.document.data["events"][0]["instance_id"] == "missing_but_preserved" and not broken.document.validation_errors().is_empty(), "Broken references must remain visible and validate as errors.")
	for event_type in MoveAnimationEditorModel.TYPES:
		var event := MoveAnimationEditorModel.default_event(event_type)
		assert(event["type"] == event_type and event.has("time"), "Every event type needs structured defaults.")
	var spawn := MoveAnimationEditorModel.default_event("spawn_sprite"); spawn["asset"] = assets[0]; spawn["position"]["battler"] = "target"; spawn["position"]["anchor"] = "mouth"
	assert(spawn["position"]["battler"] == "target" and spawn["position"]["anchor"] == "mouth", "Dropdown values must map to runtime strings.")
	spawn["is_behind"] = true; assert(spawn["is_behind"], "Spawn Sprite Is Behind must serialize through the structured model.")
	spawn["sprite_sheet"] = {"columns": 1, "rows": 1, "frame_count": 1, "fps": 12.0, "loop": true}
	assert(spawn["sprite_sheet"]["fps"] == 12.0 and spawn["sprite_sheet"]["loop"], "Sprite-sheet controls must serialize all settings.")
	spawn["sprite_sheet"] = null; assert(spawn["sprite_sheet"] == null, "Single image mode must serialize null sheet data.")
	var repository := GeneratedAnchorRepository.new(); var found_custom := false
	for art_id in ["Lochirp", "Flambian", "Hangrowl"]:
		for anchor in repository.get_anchor_names(art_id, "Player"):
			if anchor.begins_with("custom_"): found_custom = true
	assert(found_custom, "Generated custom anchors must be discoverable by the editor.")
	var roundtrip_path := "user://move_animation_editor_roundtrip.json"; assert(model.document.save_file(roundtrip_path) == OK)
	var reloaded := MoveAnimationDefinition.load_file(roundtrip_path); assert(reloaded != null and reloaded.data == model.document.data, "No-change structured round trip must be semantically equivalent.")
	print("MOVE_ANIMATION_EDITOR_MODEL_TEST_PASSED")
	quit()
