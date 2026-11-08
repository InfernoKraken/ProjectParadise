extends RefCounted

# Warm tiles before they enter the viewport; screen pixels remain consistent at
# different zoom levels. This only gates visuals, never terrain/collision data.
const PRELOAD_MARGIN_PIXELS := 128.0

static func signature(camera:Camera3D)->Array:
	return [camera.get_instance_id(),camera.global_transform,camera.projection,camera.size,camera.fov,camera.keep_aspect,camera.h_offset,camera.v_offset,camera.get_viewport().get_visible_rect().size]

static func ground_rect(camera:Camera3D,height:float=0.401)->Rect2:
	var size:=camera.get_viewport().get_visible_rect().size
	var screen:=Rect2(Vector2.ZERO,size).grow(PRELOAD_MARGIN_PIXELS)
	var plane:=Plane(Vector3.UP,height)
	var result:=Rect2()
	var first:=true
	for pixel in [screen.position,Vector2(screen.end.x,screen.position.y),screen.end,Vector2(screen.position.x,screen.end.y)]:
		var hit:Variant=plane.intersects_ray(camera.project_ray_origin(pixel),camera.project_ray_normal(pixel))
		# A horizon-crossing camera needs conservative visibility.
		if hit==null:return Rect2(-1e8,-1e8,2e8,2e8)
		var point:=Vector2(hit.x,hit.z)
		if first:result=Rect2(point,Vector2.ZERO);first=false
		else:result=result.expand(point)
	return result
