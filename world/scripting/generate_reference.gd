extends SceneTree

func _initialize() -> void:
	var text := preload("command_reference.gd").render()
	DirAccess.make_dir_recursive_absolute("res://docs")
	var file := FileAccess.open("res://docs/scripting_reference.md", FileAccess.WRITE)
	if file == null: push_error("Cannot write scripting reference."); quit(1); return
	file.store_string(text); file.close(); print("SCRIPTING_REFERENCE_GENERATED"); quit()
