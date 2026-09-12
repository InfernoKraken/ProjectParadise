extends SceneTree

const CONTEXTUAL_ASSETS := preload("res://battle/move_animation/contextual_move_effect_resolver.gd")
const GENERIC_BUD := "res://assets/move_effects/Attack_Bloom_Bud_Generic.png"
const GENERIC_FLOWER := "res://assets/move_effects/Attack_Bloom_Generic.png"

func _initialize() -> void:
	_assert_variant({}, GENERIC_BUD, GENERIC_FLOWER)
	_assert_variant({"flowerType": ""}, GENERIC_BUD, GENERIC_FLOWER)
	_assert_variant({"flowerType": "unknown"}, GENERIC_BUD, GENERIC_FLOWER)
	_assert_variant({"flowerType": "orchid"}, "res://assets/move_effects/Attack_Bloom_Bud_Orchid.png", "res://assets/move_effects/Attack_Bloom_Orchid.png")
	_assert_variant({"flowerType": "birdofparadise"}, "res://assets/move_effects/Attack_Bloom_Bud_Birdofparadise.png", "res://assets/move_effects/Attack_Bloom_Birdofparadise.png")
	_assert_variant({"flowerType": "ginger"}, GENERIC_BUD, "res://assets/move_effects/Attack_Bloom_Ginger.png")
	assert(CONTEXTUAL_ASSETS.resolve_asset("res://assets/move_effects/TestFlame.png", {"flowerType":"orchid"}) == "res://assets/move_effects/TestFlame.png", "Fixed assets must bypass contextual resolution.")

	var battle_data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/battle_data.json"));var evolved:Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/evolved_fakemon.json"));var by_name:={}
	for species:Dictionary in battle_data["fakemon"]:by_name[String(species["name"])]=species
	for species:Dictionary in evolved:by_name[String(species["name"])]=species
	for species_name in ["Junrift","Keklid","Phaloa"]:assert(by_name[species_name].get("flowerType","")=="orchid","%s must use Orchid Bloom."%species_name)
	for species_name in ["Lochirp","Paratweet","Paradisia"]:assert(by_name[species_name].get("flowerType","")=="birdofparadise","%s must use Bird of Paradise Bloom."%species_name)

	var definition:=MoveAnimationDefinition.load_file("res://data/move_animations/bloom.json");assert(definition!=null and definition.validation_errors().is_empty(),"The single Bloom animation must load with contextual aliases.")
	assert(MoveAnimationEditorModel.new().discover_animations()["ids"].count("bloom")==1,"Bloom must remain one editable animation.")
	var layer:=Node2D.new();root.add_child(layer);var overlay:=ColorRect.new();root.add_child(overlay);var user:=Control.new();user.position=Vector2(40,180);root.add_child(user);var target:=Control.new();target.position=Vector2(380,40);root.add_child(target);var player:=MoveAnimationPlayer.new();root.add_child(player);await process_frame
	var context:=MoveAnimationContext.new();context.user=user;context.target=target;context.user_art_id="Junrift";context.target_art_id="Flambian";context.user_side="Player";context.target_side="Wild";context.user_effect_data={"flowerType":"orchid"};context.anchor_repository=GeneratedAnchorRepository.new();context.effect_layer=layer;context.background_overlay=overlay
	player.play(definition,context);await create_timer(0.1).timeout;assert(_texture_path(layer)=="res://assets/move_effects/Attack_Bloom_Bud_Orchid.png","Bloom must resolve its bud from the caster data.");player.cancel();await process_frame;assert(layer.get_child_count()==0)
	var flower_fixture:=MoveAnimationDefinition.from_dictionary({"format_version":1,"id":"bloom_flower_runtime","duration":0.2,"events":[{"time":0.0,"type":"spawn_sprite","instance_id":"flower","asset":"bloom_flower","sprite_sheet":null,"position":{"battler":"user","anchor":"origin","offset":[0,0]},"scale":1.0,"rotation":0.0,"opacity":1.0},{"time":0.15,"type":"destroy_sprite","instance_id":"flower"}]});assert(flower_fixture.validation_errors().is_empty());player.play(flower_fixture,context);await create_timer(0.05).timeout;assert(_texture_path(layer)=="res://assets/move_effects/Attack_Bloom_Orchid.png","The runtime must resolve bloom_flower from the caster data.");player.cancel();await process_frame;assert(layer.get_child_count()==0)
	print("BLOOM_ANIMATION_TEST_PASSED");quit()

func _assert_variant(data:Dictionary,expected_bud:String,expected_flower:String)->void:
	assert(CONTEXTUAL_ASSETS.resolve_asset("bloom_bud",data)==expected_bud)
	assert(CONTEXTUAL_ASSETS.resolve_asset("bloom_flower",data)==expected_flower)

func _texture_path(layer:Node2D)->String:
	assert(layer.get_child_count()>0)
	return String((layer.get_child(layer.get_child_count()-1) as Sprite2D).get_meta("resolved_asset_path",""))
