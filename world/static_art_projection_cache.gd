extends RefCounted

const View := preload("res://world/terrain_camera_view.gd")

# Orthographic static art shares the camera's screen translation, while retaining
# individual Y-sort roots. Rendering/culling never disables gameplay or collision.
static func update(entry:Dictionary,camera:Camera3D,enabled:bool,geometry_key:Array,screen_origin:Vector2,pixels_per_unit:float,draw:Callable)->bool:
	var root:Node2D=entry.sort_root
	if not enabled:
		root.visible=false
		return false
	var visual:Sprite2D=root.get_node("Visual")
	var overhang:=maxf(float(entry.get("static_overhang",0)),float(entry.get("light_strength",0)) if entry.get("light_source",false) else 0.0)
	var key:Array=geometry_key+[entry.get("placement",entry.get("position")),entry.get("visual_center"),entry.get("height"),entry.get("size"),entry.get("wall_size"),entry.get("sort_offset_y",0),entry.get("wall_scale_x",1),visual.texture,visual.region_rect,root.rotation,root.scale,overhang,visual.offset,visual.centered,visual.region_enabled,visual.flip_h,visual.flip_v]
	if entry.get("projection_key",[])!=key:
		draw.call()
		var box:Rect2=root.transform*visual.transform*visual.get_rect()
		box=box.grow(overhang*pixels_per_unit)
		entry["projection_key"]=key
		entry["projection_position"]=root.position-screen_origin
		entry["projection_bounds"]=Rect2(box.position-screen_origin,box.size)
		entry["projection_rebuilds"]=int(entry.get("projection_rebuilds",0))+1
	var bounds:Rect2=entry.projection_bounds
	bounds.position+=screen_origin
	var viewport:=Rect2(Vector2.ZERO,camera.get_viewport().get_visible_rect().size).grow(View.PRELOAD_MARGIN_PIXELS)
	root.visible=viewport.intersects(bounds,true)
	if root.visible:
		var position:Vector2=entry.projection_position+screen_origin
		if root.position!=position:root.position=position
	return root.visible
