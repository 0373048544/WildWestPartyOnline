extends PanelContainer

signal card_inspected(card: Dictionary)

var layout: Script = preload("res://scripts/ui/MatchLayout.gd")
var signature: String = ""
var title_label: Label
var items: HBoxContainer

func _ready() -> void:
	name = "PlayerLoadoutPanel"
	z_index = 180
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_theme_stylebox_override(
		"panel",
		SaloonTheme.panel(Color(0.055, 0.075, 0.075, 0.9), Color("#806445"), 9)
	)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	add_child(column)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 12)
	title_label.add_theme_color_override("font_color", SaloonTheme.GOLD)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title_label)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 48
	column.add_child(scroll)
	items = HBoxContainer.new()
	items.add_theme_constant_override("separation", 5)
	scroll.add_child(items)

func update_loadout(row: Dictionary) -> void:
	var next_signature := JSON.stringify([
		row.get("weapon_card", {}), row.get("equipment_cards", []),
		row.get("weapon_range", 1), get_window().size
	])
	if next_signature == signature:
		return
	signature = next_signature
	for child in items.get_children():
		child.queue_free()
	var weapon: Dictionary = row.get("weapon_card", {})
	var weapon_name := "Colt .45" if weapon.is_empty() else str(CardData.data(weapon.get("card_data_id", "")).get("name", "Colt .45"))
	title_label.text = "BÀI TRÊN BÀN CỦA BẠN · TẦM %d" % int(row.get("weapon_range", 1))
	_add_item(weapon_name, "♠", weapon, "Súng hiện tại · Tầm %d" % int(row.get("weapon_range", 1)))
	for card in row.get("equipment_cards", []):
		var data: Dictionary = CardData.data(card.get("card_data_id", ""))
		_add_item(str(data.get("name", "")), _icon(str(card.get("card_data_id", ""))), card, str(data.get("description", "")))
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
	var safe: Vector4 = layout.safe_insets(self) if mobile else Vector4.ZERO
	var width := minf(layout.units(self, 260.0) if mobile else 280.0, get_viewport_rect().size.x * (0.52 if mobile else 0.28))
	custom_minimum_size.x = width
	set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	var viewport_size := get_viewport_rect().size
	var middle_y := maxf(safe.y + layout.units(self, 66.0), viewport_size.y * (0.52 if mobile else 0.58))
	position = Vector2(viewport_size.x - safe.z - width - layout.units(self, 10.0), middle_y)
	visible = true
