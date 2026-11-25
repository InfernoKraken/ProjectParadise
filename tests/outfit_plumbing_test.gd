extends SceneTree

func _initialize() -> void:
	var outfit = preload("res://world/outfit_data.gd").new()
	outfit.outfit_id = "test_outfit"
	var image := Image.create(416, 336, false, Image.FORMAT_RGBA8)
	outfit.atlas = ImageTexture.create_from_image(image)
	outfit.frame_regions = {"walk_down_right": [Rect2(0, 0, 208, 336), Rect2(208, 0, 208, 336)]}
	var mask := ImageTexture.create_from_image(Image.create(208, 336, false, Image.FORMAT_RGBA8))
	outfit.visibility_masks = {"walk_down_right": [null, mask]}
	var game = preload("res://world/main.gd").new()
	game.player_sprite = Sprite3D.new()
	game.player_sprite.texture = outfit.frame("walk_down_right", 0)
	game.player_sort_root = Node2D.new()
	var base := Sprite2D.new()
	base.name = "Visual"
	game.player_sort_root.add_child(base)
	game.player_outfit_visual = Sprite2D.new()
	base.add_child(game.player_outfit_visual)
	game.player_animation = "walk_down_right"
	game.player_frame_index = 1
	assert(game.equip_player_outfit(outfit))
	var frame: Texture2D = game.player_outfit_visual.texture
	assert(frame.region == Rect2(208, 0, 208, 336))
	assert(base.material.get_shader_parameter("occlusion_mask") == mask)
	game._sync_player_outfit()
	assert(game.player_outfit_visual.texture == frame)
	game.player_frame_index = 0
	game._sync_player_outfit()
	assert(base.material == null)
	game.player_animation = "walk_up_left"
	game._sync_player_outfit()
	assert(not game.player_outfit_visual.visible)
	assert(game.player_outfit_visual.texture == null)
	outfit.body_type = "Female"
	assert(not game.equip_player_outfit(outfit))
	assert(game.equip_player_outfit(null))
	game.player_sprite.free()
	game.player_sort_root.free()
	game.free()
	print("OUTFIT_PLUMBING_PASSED")
	quit()
