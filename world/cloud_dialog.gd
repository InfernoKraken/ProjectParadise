extends AcceptDialog

const FakemonStorage = preload("res://world/fakemon_storage.gd")

var storage: FakemonStorage
var party_list := ItemList.new()
var cloud_list := ItemList.new()
var party_heading := Label.new()
var cloud_heading := Label.new()
var feedback := Label.new()


func _ready() -> void:
	title = "Cloud"
	ok_button_text = "Close"
	exclusive = true
	var content := VBoxContainer.new()
	add_child(content)
	var columns := HBoxContainer.new()
	content.add_child(columns)
	_add_column(columns, party_heading, party_list, "Store", true)
	_add_column(columns, cloud_heading, cloud_list, "Withdraw", false)
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.custom_minimum_size.y = 42
	content.add_child(feedback)


func open() -> void:
	feedback.text = ""
	_refresh()
	popup_centered()


func _add_column(columns: HBoxContainer, heading: Label, roster: ItemList, action: String, storing: bool) -> void:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(column)
	column.add_child(heading)
	roster.custom_minimum_size = Vector2(180, 180)
	roster.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(roster)
	var button := Button.new()
	button.text = action
	button.pressed.connect(_transfer.bind(roster, storing))
	column.add_child(button)


func _refresh() -> void:
	party_heading.text = "Party (%d / %d)" % [storage.party.size(), FakemonStorage.PARTY_CAPACITY]
	cloud_heading.text = "Cloud (%d)" % storage.cloud.size()
	_fill_list(party_list, storage.party)
	_fill_list(cloud_list, storage.cloud)


func _fill_list(list: ItemList, roster: Array[Dictionary]) -> void:
	list.clear()
	for mon: Dictionary in roster:
		list.add_item("%s  Lv.%d" % [str(mon.get("name", "Unknown")), int(mon.get("level", 0))])


func _transfer(list: ItemList, storing: bool) -> void:
	var selected := list.get_selected_items()
	var index := -1 if selected.is_empty() else selected[0]
	var message: String = storage.store(index) if storing else storage.withdraw(index)
	if not message.is_empty():
		feedback.text = message
		return
	_refresh()
	feedback.text = "Fakemon stored in the Cloud." if storing else "Fakemon withdrawn to your party."
