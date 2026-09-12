extends SceneTree

func _initialize() -> void:
	var scale_event := MoveAnimationEditorModel.default_event("scale_battler")
	var vertical := MoveAnimationEditorModel.default_event("vertical_sprite")
	assert(scale_event["scale_delta_percent"] == 50.0 and scale_event["loops"] == 1)
	assert(vertical["mode"] == "fall_to_anchor" and vertical["tint"] == "#FFFFFF")
	var model := MoveAnimationEditorModel.new();model.document.data["events"]=[vertical];assert(model.spawn_instance_ids().has("vertical_effect"))
	var layer:=Node2D.new();root.add_child(layer);var overlay:=ColorRect.new();root.add_child(overlay)
	var user:=Control.new();user.position=Vector2(40,160);user.scale=Vector2(1.2,0.8);root.add_child(user)
	var target:=Control.new();target.position=Vector2(320,60);target.scale=Vector2(0.9,1.1);root.add_child(target)
	var player:=MoveAnimationPlayer.new();root.add_child(player);await process_frame
	var context:=MoveAnimationContext.new();context.user=user;context.target=target;context.user_art_id="Lochirp";context.target_art_id="Flambian";context.user_side="Player";context.target_side="Wild";context.anchor_repository=GeneratedAnchorRepository.new();context.effect_layer=layer;context.background_overlay=overlay
	scale_event["time"]=0.0;scale_event["battler"]="user";scale_event["mode"]="stretch";scale_event["scale_delta_percent"]=50.0;scale_event["loops"]=1;scale_event["loop_duration"]=0.4
	var definition:=MoveAnimationDefinition.from_dictionary({"format_version":1,"id":"stretch_test","duration":0.4,"events":[scale_event]});assert(definition.validation_errors().is_empty());assert(is_equal_approx(definition.duration(),0.4))
	player.play(definition,context);await create_timer(0.19).timeout;assert(user.scale.x>1.7 and is_equal_approx(user.scale.y/user.scale.x,0.8/1.2),"Stretch must preserve proportions and reach about +50%.");await create_timer(0.24).timeout;assert(user.scale.is_equal_approx(Vector2(1.2,0.8)),"Stretch must return to the exact original scale.")
	scale_event["mode"]="shrink";scale_event["battler"]="target";scale_event["loops"]=2;definition=MoveAnimationDefinition.from_dictionary({"format_version":1,"id":"shrink_test","duration":0.8,"events":[scale_event]});assert(definition.validation_errors().is_empty());player.play(definition,context);await create_timer(0.19).timeout;assert(target.scale.x<0.55,"Shrink must affect the selected semantic Target.");player.cancel();await process_frame;assert(target.scale.is_equal_approx(Vector2(0.9,1.1)),"Cancel must restore scale during a loop.")
	vertical["time"]=0.0;vertical["duration"]=0.3;vertical["distance"]=100.0;vertical["tint"]="#80FF40";var anchor:=context.resolve(vertical["position"])
	definition=MoveAnimationDefinition.from_dictionary({"format_version":1,"id":"fall_test","duration":0.3,"events":[vertical]});assert(definition.validation_errors().is_empty());player.play(definition,context);await create_timer(0.03).timeout;var sprite:=layer.get_child(0) as Sprite2D;assert(sprite.position.y<anchor.y-70.0,"Fall mode must begin above its anchor.");assert(sprite.modulate.is_equal_approx(Color("#80FF40")),"Tint must use Godot modulation.");await create_timer(0.31).timeout;assert(layer.get_child_count()==0,"Vertical Sprite must clean up after movement.")
	vertical["mode"]="rise_from_anchor";definition=MoveAnimationDefinition.from_dictionary({"format_version":1,"id":"rise_test","duration":0.3,"events":[vertical]});player.play(definition,context);await create_timer(0.03).timeout;sprite=layer.get_child(0) as Sprite2D;assert(sprite.position.y<anchor.y and sprite.position.y>anchor.y-40.0,"Rise mode must begin at the anchor and move upward.");player.cancel();await process_frame;assert(layer.get_child_count()==0)
	var tinted_spawn:=MoveAnimationEditorModel.default_event("spawn_sprite");tinted_spawn["tint"]="#FF4080";definition=MoveAnimationDefinition.from_dictionary({"format_version":1,"id":"tint_spawn","duration":0.1,"events":[tinted_spawn]});assert(definition.validation_errors().is_empty());player.play(definition,context);await create_timer(0.02).timeout;assert((layer.get_child(0) as Sprite2D).modulate.is_equal_approx(Color("#FF4080")));player.cancel();await process_frame
	var invalid:=vertical.duplicate(true);invalid["tint"]="not-a-color";invalid["distance"]=0;var errors:=MoveAnimationDefinition.from_dictionary({"format_version":1,"id":"bad_vertical","duration":1.0,"events":[invalid]}).validation_errors();assert(" ".join(errors).contains("tint") and " ".join(errors).contains("distance"))
	print("SPRITE_TRANSFORM_EVENTS_TEST_PASSED");quit()
