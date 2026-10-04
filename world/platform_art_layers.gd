extends RefCounted

# Reuse the original texels as foreground cutouts. No resampling or replacement
# asset is needed, and the platform remains one stable participant in world sort.
static func build(sort_point:Node2D, texture:Texture2D, masks:Array, depth_lines:Array=[])->Dictionary:
	var proxy := Sprite2D.new()
	proxy.name = "PlatformActor"
	proxy.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	proxy.visible = false
	sort_point.add_child(proxy)
	var foreground := Node2D.new()
	foreground.name = "PlatformForeground"
	sort_point.add_child(foreground)
	for index in masks.size():
		var mask:Array = masks[index]
		var vertices := PackedVector2Array()
		for point:Array in mask:vertices.append(Vector2(float(point[0]),float(point[1])))
		var cutout := Polygon2D.new()
		cutout.polygon = vertices
		cutout.uv = vertices
		cutout.texture = texture
		cutout.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if index < depth_lines.size() and depth_lines[index] is Array and depth_lines[index].size()==2:
			var line:Array = depth_lines[index]
			var material := ShaderMaterial.new()
			material.shader = preload("res://world/platform_rail_occlusion.gdshader")
			material.set_shader_parameter("image_size",Vector2(texture.get_size()))
			material.set_shader_parameter("floor_start",Vector2(line[0][0],line[0][1]))
			material.set_shader_parameter("floor_end",Vector2(line[1][0],line[1][1]))
			cutout.material = material
		foreground.add_child(cutout)
	return {"actor":proxy,"foreground":foreground}

static func update(entry:Dictionary, actor_visual:Sprite2D, occupied:bool)->void:
	var layers:Dictionary = entry.platform_layers
	var proxy:Sprite2D = layers.actor
	var base:Sprite2D = (entry.sort_root as Node2D).get_node("Visual")
	var foreground:Node2D = layers.foreground
	foreground.transform = base.transform
	foreground.position -= Vector2(base.texture.get_size()) * base.scale * 0.5
	proxy.visible = occupied
	var actor_feet := base.to_local((actor_visual.get_parent() as Node2D).global_position)+Vector2(base.texture.get_size())*0.5
	for cutout:Polygon2D in foreground.get_children():
		if cutout.material is ShaderMaterial:
			cutout.material.set_shader_parameter("actor_present",occupied)
			cutout.material.set_shader_parameter("actor_depth",actor_feet.y)
	if occupied:
		proxy.texture = actor_visual.texture
		proxy.flip_h = actor_visual.flip_h
		proxy.flip_v = actor_visual.flip_v
		proxy.modulate = actor_visual.modulate
		proxy.global_transform = actor_visual.global_transform
