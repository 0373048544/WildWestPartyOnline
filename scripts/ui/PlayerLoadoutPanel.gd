extends PanelContainer

signal card_inspected(card: Dictionary)

var layout: Script = preload("res://scripts/ui/MatchLayout.gd")
var signature: String = ""
var title_button: Button
var details_scroll: ScrollContainer
var items: GridContainer
var expanded: bool = false
var current_weapon_name: String = "Colt .45"
var current_range: int = 1
var current_equipment_count: int = 0
var current_public_icons: Array[String] = []
var has_public_loadout: bool = false
var modal_blocked: bool = false

func _ready() -> void:
	name = "PlayerLoadoutPanel"
	z_index = layout.Z_EQUIPMENT
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
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
	title_button.add_theme_stylebox_override("normal", SaloonTheme.ribbon_panel(4.0))
	title_button.add_theme_stylebox_override("hover", SaloonTheme.ribbon_panel(4.0))
	title_button.add_theme_stylebox_override("pressed", SaloonTheme.ribbon_panel(4.0))
	title_button.custom_minimum_size.y = 36
	title_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_button.tooltip_text = "Chạm để xem bài đang trang bị"
	title_button.pressed.connect(_toggle_details)
	column.add_child(title_button)
	details_scroll = ScrollContainer.new()
	details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	column.add_child(details_scroll)
	items = GridContainer.new()
	items.columns = 1
	items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	items.add_theme_constant_override("separation", 5)
	details_scroll.add_child(items)

func update_loadout(row: Dictionary) -> void:
	var next_signature := JSON.stringify([
		row.get("weapon_card", {}), row.get("equipment_cards", []), row.get("delayed_cards", []),
		row.get("weapon_range", 1), layout.css_size(self), layout.mode(self)
	])
	if next_signature == signature:
		return
	var had_loadout: bool = not signature.is_empty()
	signature = next_signature
	for child in items.get_children():
		items.remove_child(child)
		child.queue_free()
	var weapon: Dictionary = row.get("weapon_card", {})
	# Colt .45 is presentation-only default weapon information. Keeping this
	# panel visible does not create a card or mutate the authoritative loadout.
	has_public_loadout = true
	var weapon_name := "Colt .45" if weapon.is_empty() else str(CardData.data(weapon.get("card_data_id", "")).get("name", "Colt .45"))
	current_weapon_name = weapon_name
	current_range = int(row.get("weapon_range", 1))
	current_equipment_count = (
		(0 if weapon.is_empty() else 1)
		+ row.get("equipment_cards", []).size()
		+ row.get("delayed_cards", []).size()
	)
	current_public_icons.clear()
	_add_item(weapon_name, "", weapon, "Súng hiện tại · Tầm %d" % int(row.get("weapon_range", 1)))
	for card in row.get("equipment_cards", []):
		var data: Dictionary = CardData.data(card.get("card_data_id", ""))
		var label := str(data.get("name", ""))
		_add_item(label, "", card, str(data.get("description", "")))
	for card in row.get("delayed_cards", []):
		var data: Dictionary = CardData.data(card.get("card_data_id", ""))
		var label := str(data.get("name", ""))
		_add_item(label, "", card, "HIỆU ỨNG TRÌ HOÃN • " + str(data.get("description", "")))
	_apply_layout()
	if had_loadout and visible and not VisualSettings.reduced_motion:
		modulate = Color("#fff0bf")
		create_tween().tween_property(self, "modulate", Color.WHITE, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func set_modal_blocked(value: bool) -> void:
	modal_blocked = value
	if value and expanded:
		expanded = false
		_apply_layout()
	visible = has_public_loadout and not modal_blocked

func _toggle_details() -> void:
	expanded = not expanded
	AudioManager.play_ui("button")
	_apply_layout()

func _add_item(label_text: String, icon: String, card: Dictionary, detail: String) -> void:
	var button := Button.new()
	button.name = "Loadout_" + str(items.get_child_count())
	button.text = label_text.left(20) if icon.is_empty() else icon + "  " + label_text.left(20)
	button.custom_minimum_size = Vector2(0.0, layout.units(self, 38.0))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.add_theme_font_size_override("font_size", roundi(layout.units(self, 9.5)))
	button.tooltip_text = label_text + "\n" + detail
	button.add_theme_stylebox_override("normal", SaloonTheme.panel(Color("#26333a"), Color("#806445"), 5))
	button.add_theme_stylebox_override("hover", SaloonTheme.panel(Color("#3e4846"), SaloonTheme.GOLD, 5))
	if not card.is_empty():
		button.pressed.connect(func():
			AudioManager.play_ui("button")
			card_inspected.emit(card))
	items.add_child(button)

func _apply_layout() -> void:
	var mobile: bool = bool(layout.mobile(self))
	var target_css_width := (210.0 if expanded else 190.0) if not mobile else (162.0 if expanded else 128.0)
	var width := minf(
		layout.units(self, target_css_width) if mobile else target_css_width,
		get_viewport_rect().size.x * (0.54 if expanded else 0.42)
	)
	var disclosure := "ĐÓNG" if expanded else "MỞ"
	title_button.text = (
		"TRANG BỊ · %s\n%s · TẦM %d · %d LÁ" % [disclosure, current_weapon_name.to_upper(), current_range, current_equipment_count]
		if mobile
		else "TRANG BỊ · %s\n%s · TẦM %d · %d LÁ" % [disclosure, current_weapon_name.to_upper(), current_range, current_equipment_count]
	)
	title_button.clip_text = true
	title_button.add_theme_font_size_override("font_size", roundi(layout.units(self, 8.0)) if mobile else 11)
	title_button.custom_minimum_size.y = (
		layout.units(self, 40.0 if layout.mobile_landscape(self) and expanded else 42.0)
		if mobile else 52.0
	)
	details_scroll.visible = expanded
	var visible_rows: int = mini(items.get_child_count(), 1 if layout.mobile_landscape(self) else 3)
	var details_height: float = (
		layout.units(self, maxf(38.0, visible_rows * 38.0))
		if mobile else minf(174.0, maxf(44.0, visible_rows * 44.0))
	)
	details_scroll.custom_minimum_size.y = details_height
	set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	var zone: Rect2 = layout.equipment_rect(self, expanded)
	width = minf(width, zone.size.x)
	var compact_height := zone.size.y
	if expanded:
		var header_height: float = title_button.custom_minimum_size.y
		compact_height = minf(zone.size.y, header_height + details_height + layout.units(self, 10.0))
	custom_minimum_size = Vector2(width, compact_height)
	reset_size()
	size = Vector2(width, compact_height)
	# Container minimums may make the real panel a few pixels taller than the
	# requested compact zone. Anchor its actual bottom above the action row so it
	# can never grow downward across End Turn.
	position = Vector2(zone.end.x - width, zone.end.y - size.y)
	visible = has_public_loadout and not modal_blocked
