extends SceneTree

const TEXTURE := "res://assets/move_effects/Attack_Beam_Light.png"

func _initialize() -> void:
	var model := MoveAnimationEditorModel.new(); var beam := MoveAnimationEditorModel.default_event("beam", 0.1)
	assert(MoveAnimationEditorModel.TYPES.has("beam") and beam["duration"] == 0.5)
	model.document = MoveAnimationDefinition.from_dictionary({"format_version":1,"id":"beam_roundtrip","duration":0.7,"events":[beam]})
	assert(model.document.validation_errors().is_empty(), "Beam must serialize in additive schema v1.")
	var copy := MoveAnimationDefinition.from_dictionary(model.document.data); assert(copy.data["events"][0]["from"]["battler"] == "user")
	assert(model.spawn_instance_ids().has("beam"), "Visual-instance selectors must discover Beam IDs.")

	var layer := Node2D.new(); root.add_child(layer); var overlay := ColorRect.new(); root.add_child(overlay)
	var user := Control.new(); user.position=Vector2(20,100); user.z_index=10; root.add_child(user)
	var target := Control.new(); target.position=Vector2(220,40); target.z_index=10; root.add_child(target)
	var player := MoveAnimationPlayer.new(); root.add_child(player); await process_frame
	var context := MoveAnimationContext.new(); context.user=user;context.target=target;context.user_art_id="Lochirp";context.target_art_id="Flambian";context.user_side="Player";context.target_side="Wild";context.anchor_repository=GeneratedAnchorRepository.new();context.effect_layer=layer;context.background_overlay=overlay
	beam["time"]=0.0; beam["from"]={"battler":"user","anchor":"origin","offset":[0,0]};beam["to"]={"battler":"target","anchor":"origin","offset":[0,0]};beam["asset"]=TEXTURE;beam["duration"]=-1.0;beam["width"]=24.0
	var definition:=MoveAnimationDefinition.from_dictionary({"format_version":1,"id":"beam_geometry","duration":1.0,"events":[beam]});assert(definition.validation_errors().is_empty())
	player.play(definition,context);await create_timer(0.05).timeout;var sprite:=layer.get_child(0) as Sprite2D;var start:=context.resolve(beam["from"]);var end:=context.resolve(beam["to"]);var texture_size:=sprite.texture.get_size()
	assert(sprite.flip_h,"Player-side Beam must horizontally mirror toward its target.")
	assert(sprite.position.is_equal_approx((start+end)*0.5));assert(is_equal_approx(sprite.rotation,(end-start).angle()));assert(is_equal_approx(sprite.scale.x*texture_size.x,start.distance_to(end)));assert(is_equal_approx(sprite.scale.y*texture_size.y,24.0),"Width must affect thickness independently.")
	var first_angle:=sprite.rotation;player.cancel();await process_frame;assert(layer.get_child_count()==0,"Cancel must clean persistent Beam.")
	user.position=Vector2(220,40);target.position=Vector2(20,100);player.play(definition,context);await create_timer(0.05).timeout;sprite=layer.get_child(0) as Sprite2D;assert(not is_equal_approx(sprite.rotation,first_angle),"Swapping endpoints must reverse angle automatically.");assert(sprite.flip_h,"Endpoint geometry must not disable Player-side texture mirroring.");player.cancel();await process_frame
	context.user_side="Wild";context.target_side="Player";player.play(definition,context);await create_timer(0.05).timeout;sprite=layer.get_child(0) as Sprite2D;assert(not sprite.flip_h,"Opponent-side Beam must retain its authored direction.");player.cancel();await process_frame
	context.user_side="Player";context.target_side="Wild"

	await _test_layer(player,context,layer,user,target,"behind_battlers",5)
	await _test_layer(player,context,layer,user,target,"above_battlers",20)
	await _test_layer(player,context,layer,user,target,"between_battlers",10)
	player.cancel();await process_frame
	await _test_semantic_layer(player,context,layer,user,target,"Player","Wild")
	await _test_semantic_layer(player,context,layer,user,target,"Wild","Player")

	beam["duration"]=0.08;beam["layer"]="above_battlers";definition=MoveAnimationDefinition.from_dictionary({"format_version":1,"id":"beam_timed","duration":0.2,"events":[beam]});player.play(definition,context);await create_timer(0.03).timeout;assert(layer.get_child_count()==1);await create_timer(0.09).timeout;assert(layer.get_child_count()==0,"Positive duration must auto-clean Beam.")
	beam["duration"]=-1.0;definition=MoveAnimationDefinition.from_dictionary({"format_version":1,"id":"beam_destroy","duration":0.2,"events":[beam,{"time":0.08,"type":"destroy_sprite","instance_id":"beam"}]});assert(definition.validation_errors().is_empty());player.play(definition,context);await create_timer(0.04).timeout;assert(layer.get_child_count()==1);await create_timer(0.08).timeout;assert(layer.get_child_count()==0,"Destroy Sprite must destroy persistent Beam.")

	var invalid:=beam.duplicate(true);invalid["width"]=0;invalid["asset"]="res://assets/move_effects/missing.png";var errors:=MoveAnimationDefinition.from_dictionary({"format_version":1,"id":"invalid_beam","duration":1.0,"events":[invalid]}).validation_errors();assert(" ".join(errors).contains("width") and " ".join(errors).contains("texture"))
	assert(MoveAnimationDefinition.load_file("res://data/move_animations/projectile_test.json").validation_errors().is_empty(),"Existing non-Beam definitions must still load.")
	print("BEAM_EVENT_TEST_PASSED");quit()

func _test_layer(player:MoveAnimationPlayer,context:MoveAnimationContext,layer:Node2D,user:Control,target:Control,layer_name:String,expected:int)->void:
	var beam:=MoveAnimationEditorModel.default_event("beam");beam["duration"]=-1.0;beam["layer"]=layer_name;var definition:=MoveAnimationDefinition.from_dictionary({"format_version":1,"id":"beam_layer_test","duration":0.2,"events":[beam]});player.play(definition,context);await create_timer(0.03).timeout;assert((layer.get_child(0) as Sprite2D).z_index==expected);if layer_name=="between_battlers":assert(user.z_index != target.z_index);player.cancel();await process_frame

func _test_semantic_layer(player:MoveAnimationPlayer,context:MoveAnimationContext,layer:Node2D,user:Control,target:Control,user_side:String,target_side:String)->void:
	context.user_side=user_side;context.target_side=target_side;var beam:=MoveAnimationEditorModel.default_event("beam");beam["duration"]=-1.0;beam["layer"]="below_user_above_target";var definition:=MoveAnimationDefinition.from_dictionary({"format_version":1,"id":"beam_semantic_test","duration":0.2,"events":[beam]});player.play(definition,context);await create_timer(0.03).timeout;var sprite:=layer.get_child(0) as Sprite2D;assert(target.z_index<sprite.z_index and sprite.z_index<user.z_index,"Layer must follow User/Target semantics, not screen side.");player.cancel();await process_frame
