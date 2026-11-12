extends SceneTree

const Document := preload("res://core/map_document.gd")

func _initialize() -> void:
	create_timer(20).timeout.connect(func(): push_error("Border editor test timed out"); quit(2))
	call_deferred("_test")

func _test() -> void:
	var editor = load("res://map_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	editor._open_border_editor()
	await process_frame
	var border = editor.border_editor
	assert(border.visible and border._canvas.size.y > 0)
	var map_size: Vector2 = editor._map_size()
	assert(border._priority.selected == 0)
	var terrain_ids := ["water", "sand", "mud", "stone"]
	for side in 4:
		border._side.select(side)
		border._refresh(true)
		border._enabled.button_pressed = true
		border._depth.value = side + 2
		var expected := Vector2(ceilf(map_size.x), side + 2) if side < 2 else Vector2(side + 2, ceilf(map_size.y))
		assert(border._canvas.map_size == expected)
		for index in border._terrain.item_count:
			if border._terrain.get_item_metadata(index) == terrain_ids[side]: border._terrain.select(index)
		# Send the same press/release events the canvas receives in the UI.
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = border._canvas.world_to_screen(Vector2.ZERO)
		click.pressed = true
		border._canvas._gui_input(click)
		click.pressed = false
		border._canvas._gui_input(click)
		assert(editor.document.data.borders[border._side_name()].cells["0,0"].terrain == terrain_ids[side])
	var before: Dictionary = editor.document.data.borders.duplicate(true)
	assert(not border._covers_player.button_pressed)
	border._covers_player.button_pressed = true
	assert(editor.document.data.borders.west.covers_player)
	border._side.select(1)
	border._refresh()
	assert(not border._covers_player.button_pressed)
	editor._undo()
	assert(_same_json(editor.document.data.borders, before))
	border._side.select(0)
	border._refresh(true)
	border._layer.select(1)
	border._refresh_layer()
	border._search.text = "Canal Lock"
	border._populate_art()
	border._scale.value = 1.5
	border._rotation.value = 37
	border._paint(Vector2i.ZERO, false)
	border._reset_stroke()
	var art: Dictionary = editor.document.data.borders.north.cells["0,0"].art
	assert(art.animation == "canal_lock" and art.size[1] == 6 and art.rotation == 37)
	assert(border._canvas.visual_texture(art.texture, art.animation) is AnimatedTexture)
	border._paint(Vector2i.ZERO, true)
	border._reset_stroke()
	assert(_same_json(editor.document.data.borders.north, before.north))
	editor._undo()
	var restored: Dictionary = editor.document.data.borders.north.cells["0,0"].art
	assert(restored.texture == art.texture and restored.rotation == art.rotation)
	assert(is_equal_approx(restored.size[0], art.size[0]))
	editor._redo()
	assert(_same_json(editor.document.data.borders, before))
	border._enabled.button_pressed = false
	assert(not editor.document.data.borders.north.enabled)
	for side in ["south", "east", "west"]:
		assert(_same_json(editor.document.data.borders[side], before[side]))
	border._priority.select(1)
	border._priority.item_selected.emit(1)
	assert(editor.document.data.border_corner_priority == "east_west")
	editor._undo()
	assert(border._priority.selected == 0 and not editor.document.data.has("border_corner_priority"))
	editor._redo()
	assert(border._priority.selected == 1)
	var original_north: Dictionary = editor.document.data.borders.north
	editor.document.data[editor._map_size_field()] = [map_size.x + 5, map_size.y + 3]
	border.refresh_map(editor.document.data)
	assert(border._canvas.map_size == Vector2(ceilf(map_size.x + 5), original_north.depth))
	assert(editor.document.data.borders.north == original_north)
	var legacy := {"enabled": true, "width": 2, "height": 3, "cells": {"0,0": {"terrain": "mud"}}}
	editor.document.data.borders.north = legacy
	border.refresh_map(editor.document.data)
	assert(border._canvas.cells["4,0"].terrain == "mud" and not border._canvas.cells.has("3,0"))
	border._depth.value = 4
	assert(editor.document.data.borders.north.depth == 4)
	assert(not editor.document.data.borders.north.has("width"))
	assert(editor.document.data.borders.north.cells["4,0"].terrain == "mud")
	border._search.text = "City Building 00"
	border._populate_art()
	border._scale.value = 1.0
	border._rotation.value = 0
	border._paint(Vector2i(10, 0), false)
	border._reset_stroke()
	var building: Dictionary = editor.document.data.borders.north.cells["10,0"].art
	assert(is_equal_approx(building.footprint[0], 11.353) and building.footprint[1] == 4 and building.size[1] > 4)
	assert(building.anchor_offset == [0.0, 3.5])
	border._scale.value = 1.5
	border._paint(Vector2i(11, 0), false)
	border._reset_stroke()
	assert(not editor.document.data.borders.north.get("cells").get("11,0", {}).has("art"))
	border._covers_player.button_pressed = true
	var path := "user://map_border_test.json"
	assert(editor.document.save_atomic(path) == OK)
	var reloaded := Document.load_file(path)
	assert(_same_json(reloaded.data.borders, editor.document.data.borders))
	assert(reloaded.data.border_corner_priority == "east_west")
	assert(reloaded.data.borders.north.covers_player)
	DirAccess.remove_absolute(path)
	border.hide()
	if DisplayServer.get_name() != "headless":
		var preview: CheckBox = editor.find_child("PlacementPreview", true, false)
		preview.button_pressed = true
		editor.canvas.frame_all()
		var bounds := Rect2(editor._map_center() - editor._map_size() * 0.5, editor._map_size())
		var border_point := bounds.position + Vector2(4.5, -3.5)
		var screen_point: Vector2 = editor.canvas.global_position + editor.canvas.world_to_screen(border_point)
		await RenderingServer.frame_post_draw
		var enabled_color := root.get_texture().get_image().get_pixelv(Vector2i(screen_point))
		editor.document.data.borders.north.enabled = false
		editor.canvas.queue_redraw()
		await RenderingServer.frame_post_draw
		var disabled_color := root.get_texture().get_image().get_pixelv(Vector2i(screen_point))
		assert(not enabled_color.is_equal_approx(disabled_color), "Placement Preview must draw enabled borders outside the map.")
	editor.queue_free()
	await process_frame
	print("MAP_BORDER_EDITOR_PASSED")
	quit()

func _same_json(a: Dictionary, b: Dictionary) -> bool:
	return Document.from_text(JSON.stringify(a)).semantic_equivalent(Document.from_text(JSON.stringify(b)))
