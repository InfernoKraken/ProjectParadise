extends SceneTree

const PlayerPalette := preload("res://world/player_palette.gd")
const PlayerSpriteFrames := preload("res://world/player_sprite_frames.gd")

func _init() -> void:
	var source := PlayerPalette._load_png(PlayerPalette.SOURCE_PATH)
	var mask := PlayerPalette._load_png(PlayerPalette.MASK_PATH)
	assert(source.get_size() == mask.get_size(), "Canonical player sprite and mask dimensions must match.")
	var appearances := {"medium":PlayerPalette.create_texture(PlayerPalette.DEFAULT_PRESET), "light_blonde":PlayerPalette.create_texture("light_blonde"), "light_red":PlayerPalette.create_texture("light_red"), "dark_black":PlayerPalette.create_texture("dark_black")}
	assert(appearances["medium"] == PlayerPalette.create_texture(PlayerPalette.DEFAULT_PRESET), "Generated appearances must be cached.")
	assert(PlayerPalette.DEFAULT_PRESET == "medium", "Medium skin and medium brown hair must be the explicit normalized default.")
	for preset_name: String in appearances:
		var result: Image = appearances[preset_name].get_image()
		var preset: Dictionary = PlayerPalette.PRESETS[preset_name]
		var changed_hair := 0
		var changed_skin := 0
		for y in source.get_height():
			for x in source.get_width():
				var before := source.get_pixel(x,y)
				var after := result.get_pixel(x,y)
				var source_rgb := before.to_html(false)
				var mask_rgb := mask.get_pixel(x,y).to_html(false)
				if mask_rgb == "ff0000" and PlayerPalette.HAIR_SOURCE_ROLES.has(source_rgb):
					assert(after == preset["hair"][PlayerPalette.HAIR_SOURCE_ROLES[source_rgb]], "Hair must use its exact source role and selected destination palette.")
					changed_hair += 1
				elif mask_rgb == "00ff00" and PlayerPalette.SKIN_SOURCE_ROLES.has(source_rgb):
					assert(after == preset["skin"][PlayerPalette.SKIN_SOURCE_ROLES[source_rgb]], "Skin must use its exact source role and selected destination palette.")
					changed_skin += 1
				elif mask_rgb == "ffffff" and (source_rgb == "010000" or source_rgb == "000000"):
					assert(after.r == before.r and after.g == before.g and after.b == before.b and after.a == 0.0, "Exact atlas background pixels must preserve RGB and become transparent.")
				else:
					assert(after == before, "Non-material and unmapped pixels must remain unchanged.")
		assert(changed_hair > 0 and changed_skin > 0, "Every appearance must process both explicit material inventories.")
	for gender in ["Male","Female"]:
		for animation in ["idle_down","walk_down","idle_up","walk_up","idle_left","walk_left","idle_right","walk_right"]:
			for frame in PlayerSpriteFrames.frames(gender,animation,appearances["medium"]):
				assert(frame.region.position.x >= 0 and frame.region.position.y >= 0 and frame.region.end.x <= source.get_width() and frame.region.end.y <= source.get_height(), "Every explicit frame must remain inside the aligned atlases.")
	assert(PlayerSpriteFrames.REGIONS["Male"]["walk_right"] == [Rect2i(700,824,147,264),Rect2i(858,823,147,264)], "Male side strides must retain the clipping-safe authored overrides.")
	assert(PlayerSpriteFrames.REGIONS["Female"]["walk_left"] == [Rect2i(17,824,164,264),Rect2i(181,824,164,264)], "Female left strides must retain the clipping-safe authored overrides.")
	assert(PlayerSpriteFrames.REGIONS["Female"]["walk_right"] == [Rect2i(351,824,164,264),Rect2i(517,824,164,264)], "Female right strides must retain the clipping-safe authored overrides.")
	print("PLAYER_PALETTE_TEST_PASSED")
	quit()
