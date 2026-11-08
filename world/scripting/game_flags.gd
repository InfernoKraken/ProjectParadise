extends RefCounted

var values: Dictionary = {}

func has_flag(name: String) -> bool:
	return values.get(name, false) == true

func set_flag(name: String, enabled: bool) -> void:
	if enabled: values[name] = true
	else: values.erase(name)

func restore(saved: Variant) -> void:
	values.clear()
	if saved is Dictionary:
		for name: Variant in saved:
			if name is String and saved[name] == true: values[name] = true
