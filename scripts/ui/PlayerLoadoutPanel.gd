extends PanelContainer

signal card_inspected(card: Dictionary)

var layout: Script = preload("res://scripts/ui/MatchLayout.gd")
var signature: String = ""
var title_button: Button
var details_scroll: ScrollContainer
var items: HBoxContainer
var expanded: bool = false
var current_weapon_name: String = "Colt .45"
var current_range: int = 1
var current_equipment_count: int = 0
var has_public_loadout: bool = false
var modal_blocked: bool = false

func _ready() -> void:
	name = "PlayerLoadoutPanel"
	z_index = layout.Z_EQUIPMENT
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_theme_stylebox_override(
		"panel",
		SaloonTheme.panel(Color(0.055, 0.075, 0.075, 0.9), Color("#806445"), 9)
	)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	add_child(column)
	title_button = Button.new()
	title_button.add_theme_font_size_override("font_size", 12)
	title_button.add_theme_color_override("font_color", SaloonTheme.GOLD)
	title_button.custom_minimum_size.y = 36
	title_button.tooltip_text = "Chạm để xem bài đang trang bị"
	title_button.pressed.connect(_toggle_details)
	column.add_child(title_button)
	details_scroll = ScrollContainer.new()
	details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	details_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details_scroll.custom_minimum_size.y = 48
	column.add_child(details_scroll)
	items = HBoxContainer.new()
	items.add_theme_constant_override("separation", 5)
	details_scroll.add_child(items)

func update_loadout(row: Dictionary) -> void:
	var next_signature := JSON.stringify([
		row.get("weapon_card", {}), row.get("equipment_cards", []), row.get("delayed_cards", []),
		row.get("weapon_range", 1), layout.css_size(self), layout.mode(self)
	])
	if next_signature == signature:
		return
	signature = next_signature
	for child in items.get_children():
		child.queue_free()
	var weapon: Dictionary = row.get("weapon_card", {})
	has_public_loadout = not weapon.is_empty() or not row.get("equipment_cards", []).is_empty() or not row.get("delayed_cards", []).is_empty()
	var weapon_name := "Colt .45" if weapon.is_empty() else str(CardData.data(weapon.get("card_data_id", "")).get("name", "Colt .45"))
	current_weapon_name = weapon_name
	current_range = int(row.get("weapon_range", 1))
	current_equipment_count = row.get("equipment_cards", []).size() + row.get("delayed_cards", []).size()
	_add_item(weapon_name, "♠", weapon, "Súng hiện tại · Tầm %d" % int(row.get("weapon_range", 1)))
	for card in row.get("equipment_cards", []):
		var data: Dictionary = CardData.data(card.get("card_data_id", ""))
		_add_item(str(data.get("name", "")), _icon(str(card.get("card_data_id", ""))), card, str(data.get("description", "")))
	for card in row.get("delayed_cards", []):
		var data: Dictionary = CardData.data(card.get("card_data_id", ""))
		_add_item(str(data.get("name", "")), _icon(str(card.get("card_data_id", ""))), card, "HIỆU ỨNG TRÌ HOÃN • " + str(data.get("description", "")))
	_apply_layout()

func set_modal_blocked(value: bool) -> void:
	modal_blocked = value
	visible = has_public_loadout and not modal_blocked

func _toggle_details() -> void:
	expanded = not expanded
	AudioManager.play_ui("button")
	_apply_layout()

func _add_item(label_text: String, icon: String, card: Dictionary, detail: String) -> void:
	var button := Button.new()
	button.text = icon + "\n" + label_text.left(10)
	button.custom_minimum_size = Vector2(68, 44)
	button.add_theme_font_size_override("font_size", 11)
	button.tooltip_text = label_text + "\n" + detail
	button.add_theme_stylebox_override("normal", SaloonTheme.panel(Color("#26333a"), Color("#806445"), 5))
	button.add_theme_stylebox_override("hover", SaloonTheme.panel(Color("#3e4846"), SaloonTheme.GOLD, 5))
	if not card.is_empty():
		button.pressed.connect(func():
			AudioManager.play_ui("button")
			card_inspected.emit(card))
	items.add_child(button)

func _icon(card_id: String) -> String:
	return {
		"horse": "♞", "spyglass": "⌕", "barrel": "▣",
		"dynamite": "✹", "jail": "▥"
	}.get(card_id, "◆")

func _apply_layout() -> void:
	var mobile: bool = bool(layout.mobile(self))
	var compact: bool = bool(layout.get_equipment_compact_mode(self))
	var width: float
	if compact:
		width = minf(layout.units(self, 180.0), get_viewport_rect().size.x * 0.28)
	else:
		width = minf(layout.units(self, 260.0) if mobile else 280.0, get_viewport_rect().size.x * (0.52 if mobile else 0.28))
	title_button.text = (
		"♠ %s · T%d%s" % [current_weapon_name.left(9), current_range, " · +%d" % current_equipment_count if current_equipment_count > 0 else ""]
		if compact
		else "BÀI TRÊN BÀN CỦA BẠN · TẦM %d" % current_range
	)
	title_button.custom_minimum_size.y = layout.units(self, 34.0) if compact else 36.0
	details_scroll.visible = not compact or expanded
	set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	var zone: Rect2 = layout.equipment_rect(self, details_scroll.visible)
	width = minf(width, zone.size.x)
	custom_minimum_size = Vector2(width, 0.0)
	reset_size()
	size.x = width
	position = Vector2(zone.end.x - width, zone.position.y)
	visible = has_public_loadout and not modal_blocked
