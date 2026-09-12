class_name MoveAnimationDefinition
extends RefCounted

const CONTEXTUAL_ASSETS := preload("res://battle/move_animation/contextual_move_effect_resolver.gd")

const FORMAT_VERSION := 1
const EVENT_TYPES := ["spawn_sprite", "impact_sprite", "beam", "vertical_sprite", "move_sprite", "fade_sprite", "destroy_sprite", "shake_battler", "move_battler", "scale_battler", "background_tint", "restore_background", "marker"]
const BATTLERS := ["user", "target"]
const ANCHORS := ["origin", "head", "mouth", "neck", "left_wing", "right_wing", "tail"]
const BEAM_LAYERS := ["behind_battlers", "between_battlers", "above_battlers", "below_user_above_target"]

var data: Dictionary = {}

static func from_dictionary(source: Dictionary) -> MoveAnimationDefinition:
	var result := MoveAnimationDefinition.new()
	result.data = source.duplicate(true)
	result.data["events"] = result.data.get("events", [])
	return result

static func load_file(path: String) -> MoveAnimationDefinition:
	if not FileAccess.file_exists(path):
		return null
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	var parsed: Variant = parser.data
	return from_dictionary(parsed) if parsed is Dictionary else null

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if int(data.get("format_version", 0)) != FORMAT_VERSION:
		errors.append("Unsupported format_version; expected %d." % FORMAT_VERSION)
	var animation_id := String(data.get("id", ""))
	if not is_valid_animation_id(animation_id):
		errors.append("Animation id must use lowercase snake_case (letters, numbers, and underscores; starting with a letter).")
	var events: Array = data.get("events", [])
	var live := {}
	var auto_expires := {}
	var last_time := -1.0
	var calculated_duration := 0.0
	for index in events.size():
		var event: Variant = events[index]
		if not event is Dictionary:
			errors.append("Event %d must be an object." % index)
			continue
		var e := event as Dictionary
		var prefix := "Event %d" % index
		var event_type := String(e.get("type", ""))
		var time := float(e.get("time", -1.0))
		for instance_id: String in auto_expires.keys():
			if float(auto_expires[instance_id]) <= time:
				live.erase(instance_id); auto_expires.erase(instance_id)
		if not EVENT_TYPES.has(event_type): errors.append("%s has unknown type '%s'." % [prefix, event_type])
		if time < 0.0: errors.append("%s time must be non-negative." % prefix)
		if time < last_time: errors.append("%s is not in chronological order." % prefix)
		last_time = maxf(last_time, time)
		var raw_duration := float(e.get("duration", 0.0))
		var duration := _event_duration(e)
		if raw_duration < 0.0 and not (event_type == "beam" and raw_duration == -1.0): errors.append("%s duration must be non-negative." % prefix)
		calculated_duration = maxf(calculated_duration, time + maxf(duration, 0.0))
		if event_type == "spawn_sprite":
			var instance_id := String(e.get("instance_id", ""))
			if instance_id.is_empty(): errors.append("%s requires instance_id." % prefix)
			elif live.has(instance_id): errors.append("%s spawns already-live instance '%s'." % [prefix, instance_id])
			else: live[instance_id] = true
			var asset := String(e.get("asset", ""))
			if not _valid_asset_reference(asset): errors.append("%s asset is missing or outside assets/move_effects." % prefix)
			_validate_position(e.get("position", {}), prefix, errors)
			var opacity := float(e.get("opacity", 1.0))
			if opacity < 0.0 or opacity > 1.0: errors.append("%s opacity must be between 0 and 1." % prefix)
			_validate_sprite_tint(e, prefix, errors)
			_validate_sheet(e.get("sprite_sheet"), asset, prefix, errors)
		elif event_type == "impact_sprite":
			var instance_id := String(e.get("instance_id", ""))
			# Missing IDs remain valid for authored v0.2 data, but new impacts are addressable.
			if not instance_id.is_empty():
				if live.has(instance_id): errors.append("%s spawns already-live instance '%s'." % [prefix, instance_id])
				else:
					live[instance_id] = true
					auto_expires[instance_id] = time + duration
			var asset := String(e.get("asset", ""))
			if not _valid_asset_reference(asset): errors.append("%s asset is missing or outside assets/move_effects." % prefix)
			_validate_position(e.get("position", {}), prefix, errors)
			var opacity := float(e.get("opacity", 1.0))
			if opacity < 0.0 or opacity > 1.0: errors.append("%s opacity must be between 0 and 1." % prefix)
			_validate_sprite_tint(e, prefix, errors)
			_validate_sheet(e.get("sprite_sheet"), asset, prefix, errors)
		elif event_type == "beam":
			var instance_id := String(e.get("instance_id", ""))
			if instance_id.is_empty(): errors.append("%s requires instance_id." % prefix)
			elif live.has(instance_id): errors.append("%s spawns already-live instance '%s'." % [prefix, instance_id])
			else:
				live[instance_id] = true
				if raw_duration >= 0.0: auto_expires[instance_id] = time + duration
			var asset := String(e.get("asset", ""))
			if not _valid_asset_reference(asset): errors.append("%s Beam texture is missing or outside assets/move_effects." % prefix)
			_validate_position(e.get("from", {}), "%s Beam start" % prefix, errors)
			_validate_position(e.get("to", {}), "%s Beam end" % prefix, errors)
			if float(e.get("width", 0.0)) <= 0.0: errors.append("%s Beam width must be greater than zero." % prefix)
			var opacity := float(e.get("opacity", -1.0))
			if opacity < 0.0 or opacity > 1.0: errors.append("%s opacity must be between 0 and 1." % prefix)
			_validate_sprite_tint(e, prefix, errors)
			if not BEAM_LAYERS.has(String(e.get("layer", ""))): errors.append("%s Beam layer is invalid." % prefix)
		elif event_type == "vertical_sprite":
			var instance_id := String(e.get("instance_id", ""))
			if instance_id.is_empty(): errors.append("%s requires instance_id." % prefix)
			elif live.has(instance_id): errors.append("%s spawns already-live instance '%s'." % [prefix, instance_id])
			else: live[instance_id] = true; auto_expires[instance_id] = time + duration
			var asset := String(e.get("asset", ""))
			if not _valid_asset_reference(asset): errors.append("%s asset is missing or outside assets/move_effects." % prefix)
			_validate_position(e.get("position", {}), prefix, errors)
			if not ["fall_to_anchor", "rise_from_anchor"].has(String(e.get("mode", ""))): errors.append("%s Vertical Sprite mode is invalid." % prefix)
			if float(e.get("distance", 0.0)) <= 0.0: errors.append("%s Vertical Sprite distance must be greater than zero." % prefix)
			var opacity := float(e.get("opacity", -1.0))
			if opacity < 0.0 or opacity > 1.0: errors.append("%s opacity must be between 0 and 1." % prefix)
			_validate_sprite_tint(e, prefix, errors)
		elif event_type in ["move_sprite", "fade_sprite", "destroy_sprite"]:
			var reference := String(e.get("instance_id", ""))
			if not live.has(reference): errors.append("%s references inactive instance '%s'." % [prefix, reference])
			if event_type == "move_sprite": _validate_position(e.get("to", {}), prefix, errors)
			if event_type == "fade_sprite":
				var opacity := float(e.get("opacity", -1.0))
				if opacity < 0.0 or opacity > 1.0: errors.append("%s opacity must be between 0 and 1." % prefix)
				if auto_expires.has(reference) and time + duration > float(auto_expires[reference]): errors.append("%s Fade duration extends past instance '%s' lifetime." % [prefix, reference])
			if event_type == "destroy_sprite": live.erase(reference); auto_expires.erase(reference)
		elif event_type in ["shake_battler", "move_battler", "scale_battler"]:
			if not BATTLERS.has(String(e.get("battler", ""))): errors.append("%s battler must be user or target." % prefix)
			if event_type == "move_battler" and not ["toward_target", "away_from_target", "vertical", "baseline"].has(String(e.get("direction", ""))): errors.append("%s has invalid movement direction." % prefix)
			if event_type == "scale_battler":
				if not ["stretch", "shrink"].has(String(e.get("mode", ""))): errors.append("%s Scale Battler mode is invalid." % prefix)
				var percent := float(e.get("scale_delta_percent", 0.0))
				if percent <= 0.0 or (String(e.get("mode", "")) == "shrink" and percent > 100.0): errors.append("%s scale change must be positive and Shrink cannot exceed 100%%." % prefix)
				if int(e.get("loops", 0)) < 1: errors.append("%s loops must be at least 1." % prefix)
				if float(e.get("loop_duration", 0.0)) <= 0.0: errors.append("%s loop duration must be greater than zero." % prefix)
		elif event_type == "marker" and String(e.get("name", "")).is_empty(): errors.append("%s marker name is required." % prefix)
		elif event_type == "background_tint":
			if not Color.html_is_valid(String(e.get("color", ""))): errors.append("%s background color is invalid." % prefix)
			var opacity := float(e.get("opacity", -1.0))
			if opacity < 0.0 or opacity > 1.0: errors.append("%s opacity must be between 0 and 1." % prefix)
	var explicit_duration := float(data.get("duration", calculated_duration))
	if explicit_duration < calculated_duration: errors.append("Animation duration does not cover all events.")
	return errors

static func is_valid_animation_id(animation_id: String) -> bool:
	if animation_id.is_empty() or not animation_id[0].to_lower() in "abcdefghijklmnopqrstuvwxyz": return false
	for character in animation_id:
		if not character in "abcdefghijklmnopqrstuvwxyz0123456789_": return false
	return true

func duration() -> float:
	var result := float(data.get("duration", 0.0))
	for event: Dictionary in data.get("events", []): result = maxf(result, float(event.get("time", 0.0)) + _event_duration(event))
	return result

static func _event_duration(event: Dictionary) -> float:
	if String(event.get("type", "")) == "scale_battler": return float(event.get("loop_duration", 0.0)) * maxi(int(event.get("loops", 0)), 0)
	return maxf(float(event.get("duration", 0.0)), 0.0)

func save_file(path: String) -> Error:
	if not validation_errors().is_empty(): return ERR_INVALID_DATA
	var directory := path.get_base_dir()
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if error != OK: return error
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "  ") + "\n")
	return OK

func _validate_position(value: Variant, prefix: String, errors: PackedStringArray) -> void:
	if not value is Dictionary:
		errors.append("%s position must be an object." % prefix); return
	var position := value as Dictionary
	if not BATTLERS.has(String(position.get("battler", ""))): errors.append("%s position battler is invalid." % prefix)
	var anchor := String(position.get("anchor", ""))
	if not ANCHORS.has(anchor) and not anchor.begins_with("custom_"): errors.append("%s anchor '%s' is invalid." % [prefix, anchor])
	var offset: Variant = position.get("offset", [])
	if not offset is Array or offset.size() != 2: errors.append("%s offset must contain two numbers." % prefix)

func _validate_sheet(value: Variant, asset: String, prefix: String, errors: PackedStringArray) -> void:
	if value == null: return
	if not value is Dictionary: errors.append("%s sprite_sheet must be null or an object." % prefix); return
	var sheet := value as Dictionary
	var columns := int(sheet.get("columns", 0)); var rows := int(sheet.get("rows", 0)); var frames := int(sheet.get("frame_count", 0)); var fps := float(sheet.get("fps", 0.0))
	if columns < 1 or rows < 1 or frames < 1 or frames > columns * rows or fps <= 0.0: errors.append("%s sprite-sheet settings are invalid." % prefix)
	if FileAccess.file_exists(asset):
		var texture := MoveEffectAssetRules.load_texture(asset)
		var image := texture.get_image() if texture != null else null
		if image == null or image.get_width() % maxi(columns, 1) != 0 or image.get_height() % maxi(rows, 1) != 0: errors.append("%s sprite-sheet grid does not divide the texture dimensions." % prefix)

func _valid_asset_reference(asset: String) -> bool:
	return CONTEXTUAL_ASSETS.is_contextual_asset(asset) or (asset.begins_with("res://assets/move_effects/") and FileAccess.file_exists(asset))

func _validate_sprite_tint(event: Dictionary, prefix: String, errors: PackedStringArray) -> void:
	if not Color.html_is_valid(String(event.get("tint", "#FFFFFF"))): errors.append("%s tint color is invalid." % prefix)
