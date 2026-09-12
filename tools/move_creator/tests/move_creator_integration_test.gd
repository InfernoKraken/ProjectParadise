extends SceneTree

func _initialize()->void:
	var scene:=load("res://tools/move_creator/move_creator.tscn") as PackedScene;assert(scene!=null);var creator:=scene.instantiate();root.add_child(creator);await process_frame;await process_frame
	assert(root.content_scale_mode==Window.CONTENT_SCALE_MODE_DISABLED,"Move Creator must use real fullscreen dimensions instead of stretching the 960x540 game canvas.")
	assert(creator.tabs.get_tab_count()==4 and creator.tabs.get_tab_title(0)=="Move Data" and creator.tabs.get_tab_title(1)=="Animation" and creator.tabs.get_tab_title(2)=="Weather" and creator.tabs.get_tab_title(3)=="Import","Move Creator must contain Move Data, Animation, Weather, and Import tabs.")
	var import_panel=creator.tabs.get_node("Import");assert(import_panel!=null and not import_panel.entries.is_empty(),"Import tab must scan move-effect PNGs.");assert(import_panel.entries.all(func(entry):return entry.has("path") and entry.has("status") and entry.has("warning")),"Import rows must expose path, Godot import status, and advisory naming warnings.");assert(import_panel.entries.any(func(entry):return entry["path"].begins_with("res://assets/battle/weather/")),"Import tab must include battle weather PNGs.")
	var weather_editor=creator.tabs.get_node("Weather");assert(weather_editor!=null and weather_editor.model.duration()>0 and weather_editor.renderer!=null,"Weather tab must load canonical runtime data and its preview renderer.")
	assert(weather_editor.preview.get_node("SampleBattleBackground").texture.resource_path=="res://assets/battle/battle_background.png","Weather preview must use the real sample battle background.")
	weather_editor.current_turn=3;weather_editor._sync_preview();weather_editor._previous_turn();weather_editor._previous_turn();assert(weather_editor.current_turn==1 and weather_editor.turn_label.text.begins_with("Turn 1 /"),"Previous Turn must refresh the visible label when returning to turn 1.")
	weather_editor.model.add_element("lighting_effect");weather_editor._light_type_changed("beam");assert(weather_editor.model.selected_element["type"]=="beam" and weather_editor.model.selected_element.has("anchor"),"Changing a light type must immediately update its runtime-backed properties.")
	assert(_label_texts(weather_editor.properties).has("Start X Offset") and _label_texts(weather_editor.properties).has("End X Offset"),"Beam controls must expose the canonical start and end offset fields.")
	var picker := _find_color_picker(weather_editor.properties); assert(picker != null); picker.color = Color("#34aaff"); picker.color_changed.emit(picker.color); assert(is_instance_valid(picker) and picker.is_inside_tree(), "Live color changes must not rebuild the selected-element editor."); assert(weather_editor.model.selected_element["color"] == "#34aaff", "Live color changes must update canonical element data in place.")
	assert(weather_editor.model.select_weather("Celestial Chorus"));weather_editor._refresh_elements();var scrolling_index:=-1
	for index in weather_editor.element_list.item_count:
		var entry:Dictionary=weather_editor.element_list.get_item_metadata(index)
		if entry["category"]=="sprite_effect" and String(entry["element"].get("sprite_mode","static"))=="scrolling":scrolling_index=index;break
	assert(scrolling_index>=0,"Canonical saved data must contain a scrolling sprite effect for reconstruction testing.");weather_editor.element_list.select(scrolling_index);weather_editor._select_element(scrolling_index);await process_frame
	var scrolling_labels:=_label_texts(weather_editor.properties);assert(scrolling_labels.has("Scroll direction") and scrolling_labels.has("Scroll speed") and scrolling_labels.has("Transition overlap"),"A scrolling sprite effect must remain editable after the editor reconstructs it from saved data.")
	var sprite_mode_option:=_option_for_label(weather_editor.properties,"Sprite mode");assert(sprite_mode_option!=null and sprite_mode_option.item_selected.get_connections().size()==1,"Reconstructed dropdowns must have exactly one selection callback.")
	assert(creator.animation_editor.embedded_mode and creator.animation_editor.size_flags_horizontal==Control.SIZE_EXPAND_FILL and creator.animation_editor.size_flags_vertical==Control.SIZE_EXPAND_FILL,"Animation editor must use its compact expanding embedded layout.")
	assert(creator.animation_editor.main_split is HSplitContainer and creator.animation_editor.left_split is VSplitContainer and creator.animation_editor.right_split is VSplitContainer,"Animation workspace must use responsive nested split containers.")
	assert(creator.animation_editor.property_scroll is ScrollContainer and creator.animation_editor.property_scroll.size_flags_vertical==Control.SIZE_EXPAND_FILL,"Event Properties must remain vertically scrollable.")
	creator.tabs.current_tab=1
	for test_size in [Vector2i(1366,768),Vector2i(1920,1080)]:
		root.size=test_size;await process_frame;await process_frame
		assert(creator.animation_editor.preview.size.x>0 and creator.animation_editor.preview.size.y>0,"Preview must remain visible after resize.")
		assert(creator.animation_editor.validation_label.is_visible_in_tree() and creator.animation_editor.event_list.is_visible_in_tree(),"Playback status and event list must remain reachable after resize.")
	creator.tabs.current_tab=0
	assert(creator.model.select_move("pounce"));creator._build_move_form();assert(creator.id_label.text.contains("pounce") and creator.model.selected_move["name"]=="Pounce","Simple move must reconstruct in the GUI model.")
	creator.model.data["moves"]["pounce"].erase("description");creator._refresh_moves("pounce");assert(creator.description_warning_label.text.begins_with("⚠") and creator.move_select.get_item_text(creator.move_select.selected).begins_with("⚠"),"Move Creator must visibly warn when a move has no description.")
	creator._request_delete_move();assert(creator.delete_move_dialog.visible and creator.delete_move_dialog.dialog_text.contains("Shared animations"),"Delete Move must require explicit confirmation and explain asset preservation.");creator.delete_move_dialog.hide()
	creator.model.set_field("animation_id","projectile_test");creator._edit_animation();await process_frame;assert(creator.tabs.current_tab==1 and creator.animation_editor.model.document.data["id"]=="projectile_test","Edit Animation must hand the selected ID to the embedded editor.")
	creator.model.set_field("animation_id",null);creator._new_animation();assert(creator.animation_editor.id_edit.text=="pounce","New Animation must suggest the move ID.")
	creator._load_animation_in_editor("projectile_test");await process_frame;creator._assign_current_animation();assert(creator.model.selected_move["animation_id"]=="projectile_test" and creator.model.dirty,"A saved animation can be explicitly assigned back to the move.")
	assert(creator.model.select_move("seed"));creator._build_move_form();var initial_animation:=String(creator.model.selected_move["animation_id"]);creator._edit_effect_animation();await process_frame;assert(creator.tabs.current_tab==1 and creator.animation_editor.model.document.data["id"]=="seed_heal","Edit Activation Animation must load the nested animation link.");creator._assign_current_animation();assert(creator.model.selected_move["scheduled_effect"]["animation_id"]=="seed_heal" and creator.model.selected_move["animation_id"]==initial_animation,"Activation assignment must not overwrite the initial move animation.")
	creator.model.data["moves"]["pounce"]["animation_id"]="projectile_test";creator._orphan_animation_id="projectile_test";assert(creator.model.animation_reference_count("projectile_test")>0);creator._confirm_delete_animation();assert(FileAccess.file_exists("res://data/move_animations/projectile_test.json"),"The final safety check must refuse deletion when an animation is referenced.")
	print("MOVE_CREATOR_INTEGRATION_TEST_PASSED");quit()

func _find_color_picker(node: Node) -> ColorPickerButton:
	for child: Node in node.get_children():
		if child is ColorPickerButton: return child
		var nested := _find_color_picker(child)
		if nested != null: return nested
	return null

func _label_texts(node: Node) -> PackedStringArray:
	var result := PackedStringArray()
	for child: Node in node.get_children():
		if child is Label: result.append((child as Label).text)
		result.append_array(_label_texts(child))
	return result

func _option_for_label(node:Node,label_text:String)->OptionButton:
	for child:Node in node.get_children():
		if child is HBoxContainer and child.get_child_count()>=2 and child.get_child(0) is Label and (child.get_child(0) as Label).text==label_text and child.get_child(1) is OptionButton:return child.get_child(1) as OptionButton
		var nested:=_option_for_label(child,label_text)
		if nested!=null:return nested
	return null
