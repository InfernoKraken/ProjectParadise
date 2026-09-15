extends SceneTree

const NpcSpriteLibrary:=preload("res://world/npc_sprite_library.gd")


func _initialize()->void:
	assert(NpcSpriteLibrary.SPRITES.boy.idle_path==NpcSpriteLibrary.CHILD_SHEET_PATH and NpcSpriteLibrary.SPRITES.girl.idle_path==NpcSpriteLibrary.CHILD_SHEET_PATH,"The combined child sheet must be the canonical idle source.")
	assert(not NpcSpriteLibrary.SPRITES.boy.get("remove_background",false) and not NpcSpriteLibrary.SPRITES.girl.get("remove_background",false),"Already-transparent child art must bypass destructive background removal.")
	for sprite_id in ["man","woman","boy","girl"]:
		var texture:=NpcSpriteLibrary.texture_for(sprite_id)
		assert(texture!=null,"%s NPC art must load from its configured sheet slice."%sprite_id)
		var image:=texture.get_image()
		assert(image.get_width()<260 and image.get_height()<400,"%s must be a trimmed character frame, not its full concept sheet."%sprite_id)
		assert(image.get_pixel(0,0).a==0.0,"%s concept-sheet background must be transparent at the frame edge."%sprite_id)
		for direction in ["down","up","left","right"]:
			assert(NpcSpriteLibrary.texture_for(sprite_id,direction)!=null,"%s must provide a %s idle pose."%[sprite_id,direction])
			assert(NpcSpriteLibrary.texture_for(sprite_id,direction,0)!=null,"%s must provide a %s walking pose."%[sprite_id,direction])
	print("NPC sprite slicing checks passed.")
	quit()
