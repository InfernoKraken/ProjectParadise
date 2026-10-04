extends SceneTree

const NpcSpriteLibrary:=preload("res://world/npc_sprite_library.gd")


func _initialize()->void:
	for sprite_id in ["man","woman","boy","girl"]:
		var texture:=NpcSpriteLibrary.texture_for(sprite_id)
		assert(texture!=null,"%s NPC art must load from its configured sheet slice."%sprite_id)
		var image:=texture.get_image()
		assert(image.get_width()<260 and image.get_height()<400,"%s must be a trimmed character frame, not its full concept sheet."%sprite_id)
		if sprite_id in ["boy", "girl"]:
			assert(image.get_pixel(0,0).a==0.0,"%s sheet cells must preserve transparency."%sprite_id)
		for direction in ["down","up","left","right"]:
			assert(NpcSpriteLibrary.texture_for(sprite_id,direction)!=null,"%s must provide a %s idle pose."%[sprite_id,direction])
			assert(NpcSpriteLibrary.texture_for(sprite_id,direction,0)!=null,"%s must provide a %s walking pose."%[sprite_id,direction])
			if sprite_id in ["boy", "girl"]:
				assert(NpcSpriteLibrary.walk_frame_count(sprite_id) == 8, "Standard NPC sheets must use all eight columns.")
				for frame in 8:
					var walk_texture := NpcSpriteLibrary.texture_for(sprite_id, direction, frame)
					assert(walk_texture != null and walk_texture.get_width() < 95, "Each frame must contain one grid cell.")
	# Verify idle and all four walking frames come from the authoritative sheets.
	for sprite_id in ["man", "woman"]:
		var spec: Dictionary = NpcSpriteLibrary.SPRITES[sprite_id]
		var expected_path := "res://assets/trainers/%s Citizen.png" % ("Male" if sprite_id == "man" else "Female")
		assert(spec.grid_path == expected_path)
		assert(NpcSpriteLibrary.walk_frame_count(sprite_id) == 8)
		var source := (load(expected_path) as Texture2D).get_image()
		for row in 4:
			var direction: String = ["down", "up", "left", "right"][row]
			for step in 9:
				var column: int = [0,1,0,2,0,3,0,4,0][step]
				var rect := Rect2i(spec.x_edges[column], spec.y_edges[row], spec.x_edges[column + 1] - spec.x_edges[column], spec.y_edges[row + 1] - spec.y_edges[row])
				var expected := source.get_region(rect)
				expected.convert(Image.FORMAT_RGBA8)
				var actual := NpcSpriteLibrary.texture_for(sprite_id, direction, step).get_image()
				actual.convert(Image.FORMAT_RGBA8)
				assert(actual.get_data() == expected.get_data(), "Citizen frame must preserve its imported source pixels and alpha.")
			var idle := NpcSpriteLibrary.texture_for(sprite_id, direction).get_image().get_data()
			for step in [0,2,4,6,8]:
				assert(NpcSpriteLibrary.texture_for(sprite_id, direction, step).get_image().get_data() == idle, "Neutral pose must separate strides, including the loop boundary.")
	for alias: String in NpcSpriteLibrary.ALIASES:
		var canonical := NpcSpriteLibrary.canonical_id(alias)
		assert(NpcSpriteLibrary.walk_frame_count(alias) == NpcSpriteLibrary.walk_frame_count(canonical))
		for direction in ["down", "up", "left", "right"]:
			assert(NpcSpriteLibrary.texture_for(alias, direction) == NpcSpriteLibrary.texture_for(canonical, direction))
			assert(NpcSpriteLibrary.texture_for(alias, direction, 1) == NpcSpriteLibrary.texture_for(canonical, direction, 1))
	print("NPC sprite slicing checks passed.")
	quit()
