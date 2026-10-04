extends SceneTree

const Document := preload("res://core/map_document.gd")
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
	print("PASS: " if ok else "FAIL: ", message)

func _initialize() -> void:
	create_timer(30).timeout.connect(func(): push_error("WATER_DECORATION_EDITOR_TIMEOUT"); quit(2))
	call_deferred("run")

func run() -> void:
	var editor: Control = load("res://map_editor.gd").new()
	root.add_child(editor); await process_frame
	editor._new_document()
	var ids := ["asset.floater_water_generic","asset.floater_water_lily","asset.submerged_water_props_generic"]
	for id: String in ids:
		check(editor.catalog.by_id.has(id),"palette contains " + id)
		if not editor.catalog.by_id.has(id): continue
		var entry: Dictionary = editor.catalog.by_id[id]
		check(entry.collision.shape == "none" and entry.supports_rotation,"noncolliding rotatable catalog entry " + id)
		editor._add_palette_object_at(Vector2(2,3),id)
	check(not editor.catalog.entries.any(func(e): return String(e.get("preview_texture","")).get_file().begins_with("semi_submerged_")),"semi-submerged assets remain outside palette for this checkpoint")
	var submerged_entry: Dictionary = editor.catalog.by_id.get("asset.submerged_water_props_generic",{})
	check(submerged_entry.get("variants",[]).size() == 2,"submerged 00 and 01 are selectable variants")
	var props: Array = editor.editor_objects.filter(func(o): return o.has("water_kind"))
	check(props.size() == 3,"palette placements build three water-decoration editor objects")
	if props.size() == 3:
		var submerged: Dictionary = props.filter(func(o): return o.water_kind == "submerged")[0]
		var floater: Dictionary = props.filter(func(o): return o.water_kind == "floater")[0]
		check(editor.canvas._draws_before(submerged,floater),"editor paints submerged props before floaters")
		editor.canvas.select_object(String(submerged.id))
		check(editor.inspector.get_node_or_null("OverlayRotationDegrees") != null,"water props expose rotation")
		check(editor.inspector.get_node_or_null("IsAttachedOverlay") == null,"water props do not expose object attachment behavior")
		var roundtrip := Document.from_text(editor.document.deterministic_json())
		check(roundtrip.parse_error.is_empty() and roundtrip.data.objects.size() == 3 and roundtrip.data.objects[2].asset_path.ends_with("submerged_water_props_generic_00.png"),"editor placement survives map serialization")
	editor.queue_free(); await process_frame
	print("WATER_DECORATION_EDITOR_TEST: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
