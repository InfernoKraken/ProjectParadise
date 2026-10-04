extends SceneTree

class RecordingModel:
	extends "res://fakemon_editor_model.gd"
	var written: Dictionary = {}
	func _write_json(relative: String, value: Variant) -> bool:
		written[relative] = JSON.parse_string(JSON.stringify(value))
		return true

func _initialize() -> void:
	create_timer(15).timeout.connect(func(): quit(1))
	var editor = load("res://fakemon_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	var model := RecordingModel.new(ProjectSettings.globalize_path("res://../..").simplify_path())
	assert(model.load_all())
	editor.model = model
	editor._select("Scorchick")
	assert(editor.light_source_box.button_pressed and editor.light_strength_spin.editable)
	assert(is_equal_approx(editor.light_strength_spin.value, 0.5) and not model.is_dirty())
	editor.light_strength_spin.value = 1.25
	editor.light_source_box.button_pressed = false
	assert(model.is_dirty() and not editor.light_strength_spin.editable)
	assert(model.save_selected(), model.error)
	var saved: Dictionary = model.written[model.BASE_FILE].fakemon.filter(func(mon): return mon.name == "Scorchick")[0]
	assert(saved.light_source == false and is_equal_approx(float(saved.light_strength), 1.25), "Stats edits must survive JSON serialization through the normal save path.")
	editor._select("Scorcaw")
	assert(editor.light_source_box.button_pressed and is_equal_approx(editor.light_strength_spin.value, 1.0))
	editor.light_strength_spin.value = 2.5
	assert(model.save_selected(), model.error)
	var evolved: Dictionary = model.written[model.EVOLVED_FILE].filter(func(mon): return mon.name == "Scorcaw")[0]
	assert(evolved.light_source and is_equal_approx(float(evolved.light_strength), 2.5))
	editor._select("Moach")
	assert(not editor.light_source_box.button_pressed and not editor.light_strength_spin.editable and not model.is_dirty())
	assert(model.add_species("LightingEditorFixture"))
	assert(model.draft.light_source == false and is_equal_approx(float(model.draft.light_strength), 0.5))
	print("LIGHT_FIELDS_TEST_PASSED")
	quit()
