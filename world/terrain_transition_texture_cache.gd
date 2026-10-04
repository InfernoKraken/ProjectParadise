class_name TerrainTransitionTextureCache
extends RefCounted

const Resolver := preload("res://world/terrain_transition_resolver.gd")

const TextureAnimation := preload("res://world/overworld_texture_animation.gd")
static var _bake_frame := -1

static var _cache: Dictionary = {}
static var _base_cache: Dictionary = {}

static func base_texture(terrain_type:String)->Texture2D:
	if not Resolver.TERRAIN.has(terrain_type):return null
	if _bake_frame < 0:
		var animated := _animated_texture("base|"+terrain_type, [terrain_type], func(): return base_texture(terrain_type))
		if animated != null: return animated
	var base_key := terrain_type + "|" + str(_bake_frame)
	if _base_cache.has(base_key):return _base_cache[base_key]
	var image:=_terrain_image(terrain_type)
	if image==null or image.is_empty():return null
	var texture:=ImageTexture.create_from_image(image)
	_base_cache[base_key]=texture
	return texture

static func texture_for(terrain_a: String, terrain_b: String, mask_type: String, orientation: String,mask_variant:int=0) -> Texture2D:
	return texture_for_stack(terrain_b, [{"terrain_a":terrain_a, "mask_type":mask_type, "orientation":orientation,"mask_variant":mask_variant}])

static func texture_for_stack(base_terrain: String, operations: Array) -> Texture2D:
	if not Resolver.TERRAIN.has(base_terrain) or operations.is_empty(): return null
	var normalized: Array[Dictionary] = []
	for value: Variant in operations:
		if not value is Dictionary: continue
		var operation: Dictionary = value
		var terrain_a := String(operation.get("terrain_a", ""))
		var mask_type := String(operation.get("mask_type", ""))
		if Resolver.TERRAIN.has(terrain_a) and Resolver.MASKS.has(mask_type):
			normalized.append({"terrain_a":terrain_a, "mask_type":mask_type, "orientation":String(operation.get("orientation", "north")),"mask_variant":int(operation.get("mask_variant",0))})
	if normalized.is_empty(): return null
	normalized.sort_custom(func(a:Dictionary,b:Dictionary):
		var pa:=Resolver.priority(String(a.terrain_a));var pb:=Resolver.priority(String(b.terrain_a))
		if pa!=pb:return pa<pb
		return _operation_key(a)<_operation_key(b))
	if _bake_frame < 0:
		var types: Array = [base_terrain]
		for op: Dictionary in normalized: types.append(op.terrain_a)
		var animated := _animated_texture("stack|"+base_terrain+JSON.stringify(normalized), types, func(): return texture_for_stack(base_terrain, operations))
		if animated != null: return animated
	var key := "stack|%s|%d" % [base_terrain, _bake_frame]
	for operation: Dictionary in normalized: key += "|" + _operation_key(operation)
	if _cache.has(key): return _cache[key]
	var first_mask := _imported_image(Resolver.mask_path(String(normalized[0].mask_type),int(normalized[0].mask_variant)))
	var output := _terrain_image(base_terrain)
	if first_mask == null or first_mask.is_empty() or output == null or output.is_empty(): return null
	output.resize(first_mask.get_width(), first_mask.get_height(), Image.INTERPOLATE_NEAREST)
	for operation: Dictionary in normalized:
		var mask := _imported_image(Resolver.mask_path(String(operation.mask_type),int(operation.mask_variant)))
		var image_a := _terrain_image(String(operation.terrain_a))
		if mask == null or mask.is_empty() or image_a == null or image_a.is_empty(): return null
		_orient_mask(mask, String(operation.mask_type), String(operation.orientation))
		if mask.get_size() != output.get_size(): mask.resize(output.get_width(), output.get_height(), Image.INTERPOLATE_NEAREST)
		image_a.resize(output.get_width(), output.get_height(), Image.INTERPOLATE_NEAREST)
		for y in output.get_height():
			for x in output.get_width():
				# Black selects Terrain A; white preserves the already-composited lower
				# terrain. Repeating this operation composes edges without bespoke masks.
				if mask.get_pixel(x, y).get_luminance() < 0.5: output.set_pixel(x, y, image_a.get_pixel(x, y))
	var texture := ImageTexture.create_from_image(output)
	_cache[key] = texture
	return texture

static func texture_for_tile(base_terrain:String,patches:Array)->Texture2D:
	if not Resolver.TERRAIN.has(base_terrain) or patches.is_empty():return null
	var normalized:Array[Dictionary]=[]
	for value:Variant in patches:
		if value is Dictionary and Resolver.TERRAIN.has(String(value.get("terrain_a",""))) and Resolver.TERRAIN.has(String(value.get("terrain_b",""))) and Resolver.MASKS.has(String(value.get("mask_type",""))):normalized.append(value.duplicate(true))
	if normalized.is_empty():return null
	normalized.sort_custom(func(a:Dictionary,b:Dictionary):
		var pa:=Resolver.priority(String(a.terrain_a));var pb:=Resolver.priority(String(b.terrain_a))
		if pa!=pb:return pa<pb
		return _tile_patch_key(a)<_tile_patch_key(b))
	if _bake_frame < 0:
		var types: Array = [base_terrain]
		for patch: Dictionary in normalized: types.append_array([patch.terrain_a, patch.terrain_b])
		var animated := _animated_texture("tile|"+base_terrain+JSON.stringify(normalized), types, func(): return texture_for_tile(base_terrain, patches))
		if animated != null: return animated
	var key:="tile|%s|%d"%[base_terrain, _bake_frame]
	for patch:Dictionary in normalized:key+="|"+_tile_patch_key(patch)
	if _cache.has(key):return _cache[key]
	var first_pair:=texture_for(String(normalized[0].terrain_a),String(normalized[0].terrain_b),String(normalized[0].mask_type),String(normalized[0].orientation),int(normalized[0].get("mask_variant",0)))
	if first_pair==null:return null
	var size:=first_pair.get_image().get_size();var output:=_terrain_image(base_terrain);output.resize(size.x,size.y,Image.INTERPOLATE_NEAREST)
	for patch:Dictionary in normalized:
		var pair:=texture_for(String(patch.terrain_a),String(patch.terrain_b),String(patch.mask_type),String(patch.orientation),int(patch.get("mask_variant",0)))
		if pair==null:return null
		_apply_slice(output,pair.get_image(),String(patch.slice))
	var texture:=ImageTexture.create_from_image(output);_cache[key]=texture;return texture

static func _apply_slice(output:Image,source:Image,slice:String)->void:
	if source.get_size()!=output.get_size():source.resize(output.get_width(),output.get_height(),Image.INTERPOLATE_NEAREST)
	var w:=output.get_width();var h:=output.get_height();var hw:=w/2;var hh:=h/2;var source_rect:=Rect2i();var destination:=Vector2i.ZERO
	match slice:
		"vertical_negative":source_rect=Rect2i(0,0,hw,h);destination=Vector2i(w-hw,0)
		"vertical_positive":source_rect=Rect2i(w-hw,0,hw,h);destination=Vector2i.ZERO
		"horizontal_negative":source_rect=Rect2i(0,0,w,hh);destination=Vector2i(0,h-hh)
		"horizontal_positive":source_rect=Rect2i(0,h-hh,w,hh);destination=Vector2i.ZERO
		"corner_northwest":source_rect=Rect2i(0,0,hw,hh);destination=Vector2i(w-hw,h-hh)
		"corner_northeast":source_rect=Rect2i(w-hw,0,hw,hh);destination=Vector2i(0,h-hh)
		"corner_southwest":source_rect=Rect2i(0,h-hh,hw,hh);destination=Vector2i(w-hw,0)
		"corner_southeast":source_rect=Rect2i(w-hw,h-hh,hw,hh);destination=Vector2i.ZERO
		_:return
	output.blit_rect(source,source_rect,destination)

static func _operation_key(operation: Dictionary) -> String:
	return "%s:%s:%02d:%s" % [operation.terrain_a, operation.mask_type,int(operation.get("mask_variant",0)), operation.orientation]

static func _tile_patch_key(patch: Dictionary) -> String:
	# Unlike texture_for_stack(), a tile's base terrain is not necessarily the
	# lower terrain of every pair applied to it, so terrain_b is part of identity.
	return "%s:%s:%s:%02d:%s:%s" % [patch.terrain_a,patch.terrain_b,patch.mask_type,int(patch.get("mask_variant",0)),patch.orientation,patch.slice]

static func cache_size() -> int:
	return _cache.size()

static func clear() -> void:
	_cache.clear()
	_base_cache.clear()
	TextureAnimation.bindings.clear()

static func _imported_image(path: String) -> Image:
	var texture := ResourceLoader.load(path) as Texture2D
	return texture.get_image().duplicate() if texture != null else null

static func _terrain_image(terrain_type: String) -> Image:
	var definition: Dictionary = Resolver.TERRAIN.get(terrain_type, {})
	if definition.is_empty(): return null
	var path := String(definition.texture)
	var animation := TextureAnimation.definition(String(definition.get("animation", ""))) if definition.has("animation") else {}
	var image: Image
	if not animation.is_empty():
		image = animation.frames[maxi(_bake_frame, 0) % animation.frames.size()].get_image().duplicate()
	else:
		image = _imported_image(path)
	if image == null or image.is_empty(): return image
	if bool(definition.get("rotate_180", false)): image.rotate_180()
	var tint := Color(String(definition.get("tint", "ffffff")))
	if tint != Color.WHITE:
		for y in image.get_height():
			for x in image.get_width(): image.set_pixel(x, y, image.get_pixel(x, y) * tint)
	return image

static func _orient_mask(mask: Image, mask_type: String, orientation: String) -> void:
	if mask_type == "vertical_edge":
		# Source is black/A on west. East uses the same vertical source mirrored.
		if orientation == "east": mask.flip_x()
	elif mask_type == "horizontal_edge":
		# Source is black/A on north. South uses the same horizontal source mirrored.
		if orientation == "south": mask.flip_y()
	elif bool(Resolver.MASKS.get(mask_type, {}).get("rotation_safe", false)):
		# Corner masks are explicitly registered as rotation-safe; edge masks never
		# enter this branch and continue using their corresponding authored axis.
		match orientation:
			"northeast": mask.rotate_90(ClockDirection.CLOCKWISE)
			"southeast": mask.rotate_180()
			"southwest": mask.rotate_90(ClockDirection.COUNTERCLOCKWISE)

static func _animated_texture(key: String, types: Array, factory: Callable) -> Texture2D:
	var ids: Array[String] = []
	for type: String in types:
		var id := String(Resolver.TERRAIN.get(type, {}).get("animation", ""))
		if not id.is_empty() and not TextureAnimation.definition(id).is_empty() and not ids.has(id): ids.append(id)
	if ids.is_empty(): return null
	# First checkpoint supports one logical animation in a composite recipe.
	if ids.size() > 1:
		push_warning("Multiple animation clocks in one terrain composite are not supported yet: " + key)
		return null
	return TextureAnimation.shared_texture(key, ids[0], func(frame: int):
		_bake_frame = frame
		var texture: Texture2D = factory.call()
		_bake_frame = -1
		return texture)

