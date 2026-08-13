extends SceneTree


func _initialize() -> void:
	var scene := load("res://battle/vfx/battle_animator.tscn") as PackedScene
	assert(scene != null, "BattleAnimator scene must load.")
	var animator := scene.instantiate() as BattleAnimator
	root.add_child(animator)
	await process_frame
	assert(animator.vfx != null, "BattleAnimator must own one reusable MoveVFX node.")
	for preset: String in MoveVFX.PRESETS:
		assert(not preset.is_empty(), "Move VFX preset names must be valid.")
	assert(animator.default_preset({"damage_class": "Physical", "type": "Normal"}) == "caster_lunge")
	assert(animator.default_preset({"damage_class": "Special", "type": "Water"}) == "projectile")
	assert(animator.default_preset({"damage_class": "Special", "type": "Fire"}) == "target_burst")
	assert(animator.default_preset({"damage_class": "Status", "type": "Bug", "stat_changes": [{}]}) == "buff_swirl")
	assert(animator.default_preset({"damage_class": "Status", "type": "Plant", "sets_weather": "Rootmind"}) == "field_overlay")
	var dex_script: GDScript = load("res://dex/dex_view.gd") as GDScript
	var dex: Control = dex_script.new()
	var type_palette: GDScript = load("res://data/type_palette.gd") as GDScript
	for type_name: String in ["Air", "Bug", "Mystic", "Ghost", "Psychic", "Fighting"]:
		var expected_color: Color = type_palette.color_for(type_name)
		assert(animator.color_for_move({"type": type_name}) == expected_color, "Battle VFX must use the shared %s type color." % type_name)
		assert(dex._type_color(type_name) == expected_color, "Dex must use the shared %s type color." % type_name)
	var scorchick_portrait: Texture2D = dex._portrait_texture({"art_id": "Scorchick"})
	assert(scorchick_portrait != null and scorchick_portrait.resource_path.ends_with("battle/Scorchick_Player.png"), "Dex portraits must prefer player-side battle art for a Fakemon art_id.")
	assert(dex._portrait_texture({}) == null, "Dex must preserve the portrait placeholder fallback when art_id is unavailable.")
	var battle_scene := load("res://battle/battle.tscn") as PackedScene
	assert(battle_scene != null, "Battle scene must load.")
	var battle := battle_scene.instantiate()
	root.add_child(battle)
	await create_timer(0.1).timeout
	assert(is_zero_approx(battle.battle_screen.rotation), "Fakemon bobbing must not rotate the BattleScreen.")
	print("MOVE_VFX_TEST_PASSED")
	quit()
