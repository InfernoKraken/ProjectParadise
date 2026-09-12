extends SceneTree

const Model := preload("res://fakemon_editor_model.gd")

func _init() -> void:
	var root := ProjectSettings.globalize_path("res://../..").simplify_path()
	var model := Model.new(root)
	assert(model.load_all(), model.error)
	assert(not model.species_names().is_empty(), "Existing Fakemon must load.")
	assert(model.select_species("Scorchick"), "Known base Fakemon must be selectable.")
	assert(model.selected_source.ends_with("battle_data.json"), "Base ownership must be preserved.")
	assert(model.bst() == 310, "Scorchick BST must reflect all six existing stat fields.")
	assert(model.egg_groups_for() == ["Bird", "Cosmic"], "Egg groups must come from egg_groups.json.")
	assert(model.move_catalog().has("ignite"), "Move selectors must use runtime move IDs.")
	assert(model.sprite_paths().player.ends_with("Scorchick_Player.png"), "Sprite references must follow runtime art_id conventions.")
	assert(model.select_species("Scorcaw"), "Known evolved Fakemon must be selectable.")
	assert(model.selected_source.ends_with("evolved_fakemon.json"), "Evolved ownership must be preserved.")
	assert(String(model.draft.get("moveset_source")) == "Scorchick", "Shared movesets must expose the runtime relationship.")
	assert(model.select_species("Scorchick") and model.evolution_target_name == "Scorcaw" and model.evolution_level == 20, "Evolution target must be derived from the child-owned runtime fields.")
	var before := model.draft.duplicate(true)
	assert(not model.is_dirty(), "Loading must not dirty or normalize a Fakemon.")
	assert(model.draft == before, "Read-only inspection must not mutate data.")
	print("Fakemon Editor model: 11 assertions passed")
	quit()
