extends SceneTree

const PROJECTILE_PATH := "res://assets/move_effects/Attack_Projectile_Fire.png"
const BEAM_PATH := "res://assets/move_effects/Attack_Beam_Fire.png"
const PARTICLE_PATH := "res://assets/move_effects/Attack_Particle_Embers.png"
const IMPACT_PATH := "res://assets/move_effects/Attack_Impact_Fire_Embers.png"

func _initialize() -> void:
	assert(MoveEffectAssetRules.category(PROJECTILE_PATH) == "projectile")
	assert(MoveEffectAssetRules.should_flip_h(PROJECTILE_PATH, "Player"))
	assert(not MoveEffectAssetRules.should_flip_h(PROJECTILE_PATH, "Wild"))
	assert(MoveEffectAssetRules.category(BEAM_PATH) == "beam")
	assert(MoveEffectAssetRules.should_flip_h(BEAM_PATH, "Player"))
	assert(not MoveEffectAssetRules.should_flip_h(BEAM_PATH, "Wild"))
	assert(not MoveEffectAssetRules.should_flip_h(PARTICLE_PATH, "Player"), "Particles must remain unchanged.")
	assert(not MoveEffectAssetRules.should_flip_h(IMPACT_PATH, "Player"), "Impact effects must remain unchanged.")

	var layer := Node2D.new()
	root.add_child(layer)
	var overlay := ColorRect.new()
	root.add_child(overlay)
	var user := Control.new()
	user.position = Vector2(40, 180)
	root.add_child(user)
	var target := Control.new()
	target.position = Vector2(380, 40)
	root.add_child(target)
	var player := MoveAnimationPlayer.new()
	root.add_child(player)
	await process_frame

	var context := MoveAnimationContext.new()
	context.user = user
	context.target = target
	context.user_art_id = "Lochirp"
	context.target_art_id = "Flambian"
	context.user_side = "Player"
	context.target_side = "Wild"
	context.anchor_repository = GeneratedAnchorRepository.new()
	context.effect_layer = layer
	context.background_overlay = overlay

	await _assert_spawn_flip(player, context, layer, PROJECTILE_PATH, true, "Player-side projectile must face its target.")
	context.user_side = "Wild"
	context.target_side = "Player"
	await _assert_spawn_flip(player, context, layer, PROJECTILE_PATH, false, "Opponent-side projectile must retain its authored direction.")

	context.user_side = "Player"
	context.target_side = "Wild"
	await _assert_spawn_flip(player, context, layer, PARTICLE_PATH, false, "Player-side particles must remain unchanged.")
	await _assert_spawn_flip(player, context, layer, IMPACT_PATH, false, "Player-side impact effects must remain unchanged.")

	assert(layer.get_child_count() == 0, "Mirrored effects must retain normal cleanup behavior.")
	print("MOVE_EFFECT_MIRRORING_TEST_PASSED")
	quit()

func _assert_spawn_flip(player: MoveAnimationPlayer, context: MoveAnimationContext, layer: Node2D, asset_path: String, expected: bool, message: String) -> void:
	var event := {
		"time": 0.0,
		"type": "spawn_sprite",
		"instance_id": "effect",
		"asset": asset_path,
		"sprite_sheet": null,
		"position": {"battler": "user", "anchor": "origin", "offset": [0, 0]},
		"scale": 1.0,
		"rotation": 0.0,
		"opacity": 1.0
	}
	var definition := MoveAnimationDefinition.from_dictionary({
		"format_version": 1,
		"id": "spawn_mirroring_test",
		"duration": 0.1,
		"events": [event]
	})
	assert(definition.validation_errors().is_empty())
	player.play(definition, context)
	await create_timer(0.03).timeout
	assert(layer.get_child_count() == 1)
	assert((layer.get_child(0) as Sprite2D).flip_h == expected, message)
	await create_timer(0.1).timeout
