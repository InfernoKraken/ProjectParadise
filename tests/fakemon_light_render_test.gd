extends SceneTree

func _initialize() -> void:
	create_timer(30).timeout.connect(func(): quit(1))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256,256)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4
	camera.position = Vector3(0,0,3)
	viewport.add_child(camera)
	var white := Image.create(8,8,false,Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(white)
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new(); quad.size = Vector2(4,4); mesh.mesh = quad
	var base := StandardMaterial3D.new(); base.albedo_texture = texture; mesh.material_override = base
	mesh.add_to_group("day_night_terrain")
	viewport.add_child(mesh)
	var layer := CanvasLayer.new(); viewport.add_child(layer)
	var art_root := Node2D.new(); layer.add_child(art_root)
	var canvas := Sprite2D.new(); canvas.texture = texture; canvas.position = Vector2(64,128); canvas.scale = Vector2(16,32); art_root.add_child(canvas)
	var source := Sprite2D.new(); source.texture = texture; source.position = Vector2(32,32); source.scale = Vector2(2,2); source.set_meta("overworld_light_source", true); art_root.add_child(source)
	var clock = load("res://world/world_clock.gd").new(); clock.set_time(0,0)
	var controller = load("res://world/day_night_controller.gd").new(); layer.add_child(controller); controller.setup(clock,null)
	await process_frame
	controller.update_overworld_lights(camera,art_root,[{"position":Vector3.ZERO,"radius":1.0}])
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	assert(image.get_pixel(120,128).r > 0.95, "Canvas pixels near source must return to daylight.")
	assert(image.get_pixel(140,128).r > 0.95, "Terrain pixels near source must return to daylight.")
	assert(image.get_pixel(32,32).r > 0.95, "Entire source art must bypass night tint outside the radius.")
	assert(image.get_pixel(20,200).r < 0.5 and image.get_pixel(230,200).r < 0.5, "Canvas and terrain outside radius must stay dark.")
	controller.update_overworld_lights(camera,art_root,[{"position":Vector3(1,0,0),"radius":1.0}])
	await process_frame
	await RenderingServer.frame_post_draw
	image = viewport.get_texture().get_image()
	assert(image.get_pixel(120,128).r < 0.5, "Moving light must restore the night mask at its previous location.")
	assert(image.get_pixel(192,128).r > 0.95, "The light must illuminate its new terrain position.")
	controller.update_overworld_lights(camera,art_root,[])
	await process_frame
	await RenderingServer.frame_post_draw
	image = viewport.get_texture().get_image()
	assert(image.get_pixel(192,128).r < 0.5, "Removing a source must remove its illumination.")
	print("FAKEMON_LIGHT_RENDER_TEST_PASSED")
	clock.free()
	quit()
