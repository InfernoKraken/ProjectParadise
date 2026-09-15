extends SceneTree


func _initialize()->void:
	var scene:=load("res://world/main.tscn") as PackedScene
	var main:=scene.instantiate()
	root.add_child(main)
	await process_frame
	var child:Area3D=main.family_children[0].node
	var foot:=child.get_node("FootCollision") as StaticBody3D
	var foot_shape:BoxShape3D=(foot.get_child(0) as CollisionShape3D).shape
	assert(foot!=null and foot_shape.size==main.NPC_FOOT_COLLISION_SIZE and foot.position.y<0.0,"NPCs must carry compact foot-level collision that follows wandering actors.")
	assert(is_equal_approx(float(child.get_meta("visual_height")),main.NPC_CHILD_VISUAL_HEIGHT),"Children must use the larger normalized child display height.")
	assert(main.NPC_ADULT_VISUAL_HEIGHT>=main.PLAYER_VISUAL_HEIGHT,"Adult NPCs should be approximately player-sized.")
	main.inside_family_house=true
	main.family_children[0].target=child.position+Vector3.RIGHT*2.0
	var idle_texture:Texture2D=(child.get_child(0) as Sprite3D).texture
	main._update_family_children(0.17)
	assert(child.get_meta("facing")=="right" and (child.get_child(0) as Sprite3D).texture!=idle_texture,"A wandering child must select a directional walking frame.")
	main.player.position=child.position+Vector3.LEFT
	main._face_npc_toward_player(child)
	assert(child.get_meta("facing")=="left","The face-player command must choose the nearest cardinal direction.")
	print("NPC runtime behavior checks passed.")
	quit()
