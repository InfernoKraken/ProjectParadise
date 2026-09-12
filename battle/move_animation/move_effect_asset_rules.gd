class_name MoveEffectAssetRules
extends RefCounted

const PROJECTILE_PREFIX := "Attack_Projectile_"
const BEAM_PREFIX := "Attack_Beam_"
const PARTICLE_PREFIX := "Attack_Particle_"

static func category(asset_path: String) -> String:
	var filename := asset_path.get_file()
	if filename.begins_with(PROJECTILE_PREFIX): return "projectile"
	if filename.begins_with(BEAM_PREFIX): return "beam"
	if filename.begins_with(PARTICLE_PREFIX): return "particle"
	return "effect"

static func should_flip_h(asset_path: String, battler_side: String) -> bool:
	return category(asset_path) in ["projectile", "beam"] and battler_side == "Player"

static func load_texture(asset_path: String) -> Texture2D:
	if ResourceLoader.exists(asset_path, "Texture2D"):
		var texture := ResourceLoader.load(asset_path, "Texture2D", ResourceLoader.CACHE_MODE_REPLACE) as Texture2D
		if texture != null: return texture
	var image := Image.load_from_file(ProjectSettings.globalize_path(asset_path))
	return ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null

static func authoring_note(asset_path: String) -> String:
	match category(asset_path):
		"projectile": return "Auto mirror: flips horizontally when the animation User is on the Player side."
		"beam": return "Auto mirror: flips horizontally when the animation User is on the Player side."
		"particle": return "Auto mirror: unchanged on both battle sides."
		_: return "Auto mirror: unchanged."
