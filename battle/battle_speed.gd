extends RefCounted
## Presentation speed only; authored seconds are divided by this multiplier.
const MIN_SPEED := 0.75
const MAX_SPEED := 5.0
const DEFAULT_SPEED := 2.0
const SETTINGS_PATH := "user://presentation_settings.cfg"
static var _loaded := false
static var _speed := DEFAULT_SPEED

static func sanitize(value: float) -> float:
	return clampf(value, MIN_SPEED, MAX_SPEED) if is_finite(value) else DEFAULT_SPEED

static func multiplier() -> float:
	if not _loaded:
		_loaded = true
		var config := ConfigFile.new()
		if config.load(SETTINGS_PATH) == OK:
			var value: Variant = config.get_value("battle", "speed", DEFAULT_SPEED)
			if value is float or value is int:
				_speed = sanitize(float(value))
	return _speed

static func set_multiplier(value: float) -> void:
	_speed = sanitize(value)
	_loaded = true
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("battle", "speed", _speed)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save battle speed: %s" % error_string(error))

static func seconds(authored_seconds: float) -> float:
	return authored_seconds / multiplier()
