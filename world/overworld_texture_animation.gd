class_name OverworldTextureAnimation
extends RefCounted

# One real-time clock, independent of time-of-day jumps and gameplay clock speed.
static var elapsed := 0.0
static var definitions: Dictionary = {}
static var loaded := false
static var current_frames: Dictionary = {}
static var bindings: Dictionary = {}

static func definition(id: String) -> Dictionary:
	if not loaded:
		loaded = true
		var file := FileAccess.open("res://assets/overworld/anim/animations.json", FileAccess.READ)
		if file != null:
			var data: Variant = JSON.parse_string(file.get_as_text())
			if data is Dictionary:
				for name: String in data.get("animations", {}):
					var value: Variant = data.animations[name]
					if not value is Dictionary:
						push_warning("Invalid overworld animation definition: " + name)
						continue
					var record: Dictionary = value
					if int(record.get("frame_count", 0)) < 1 or int(record.get("frame_count", 0)) > 256 or not bool(record.get("loop", true)):
						push_warning("Invalid overworld animation frame count or loop setting: " + name)
						continue
					var paths: Array[String] = []
					for i in int(record.get("frame_count", 0)):
						paths.append("res://assets/overworld/anim/%s_%02d.png" % [name, i])
					var frames := validate_frames(paths, float(record.get("frame_duration", 0.0)))
					if frames.is_empty():
						push_warning("Overworld animation %s has missing, malformed, or mismatched frames; using static terrain." % name)
					else:
						definitions[name] = {"frames":frames, "frame_duration":float(record.frame_duration)}
	return definitions.get(id, {})

static func validate_frames(paths: Array[String], duration: float) -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	if paths.is_empty() or duration <= 0.0 or not is_finite(duration): return result
	var expected_size := Vector2.ZERO
	for i in paths.size():
		if not paths[i].get_basename().ends_with("_%02d" % i) or not ResourceLoader.exists(paths[i]): return []
		var texture := load(paths[i]) as Texture2D
		if texture == null: return []
		if i == 0: expected_size = texture.get_size()
		if texture.get_size() != expected_size: return []
		result.append(texture)
	return result

static func frame_index(id: String, seconds: float) -> int:
	var data := definition(id)
	return int(floor(maxf(seconds, 0.0) / float(data.frame_duration))) % data.frames.size() if not data.is_empty() else 0

static func shared_texture(key: String, id: String, factory: Callable) -> Texture2D:
	if bindings.has(key): return bindings[key].texture
	var data := definition(id)
	if data.is_empty(): return factory.call(0)
	var proxy := AnimatedTexture.new()
	proxy.frames = data.frames.size()
	proxy.pause = true
	proxy.speed_scale = 0.0
	for i in proxy.frames:
		var texture: Texture2D = factory.call(i)
		if texture == null: return null
		proxy.set_frame_texture(i, texture)
	proxy.current_frame = frame_index(id, elapsed)
	bindings[key] = {"id":id, "texture":proxy}
	return proxy

static func advance(delta: float) -> void:
	elapsed += delta
	var changed := false
	for id: String in definitions:
		var frame := frame_index(id, elapsed)
		if current_frames.get(id, -1) != frame:
			current_frames[id] = frame
			changed = true
	if not changed: return
	for key: String in bindings:
		var binding: Dictionary = bindings[key]
		var frame: int = current_frames[binding.id]
		if binding.texture.current_frame != frame: binding.texture.current_frame = frame
