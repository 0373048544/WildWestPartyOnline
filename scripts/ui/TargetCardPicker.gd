extends PanelContainer

signal choice_selected(token: Dictionary)
signal cancel_requested

var app: Node
var request: Dictionary = {}
var state: Dictionary = {}
var target_id: int = 0
var request_id: int = 0
var layout: Script = preload("res://scripts/ui/MatchLayout.gd")
var column: VBoxContainer
var heading: Label
var subtitle: Label
var table_row: HBoxContainer
var hand_row: HBoxContainer
var cancel_button: Button
var locked: bool = false
var content_signature: String = ""

func _ready() -> void:
	name = "TargetCardPicker"
	z_index = 920
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process(false)
	add_theme_stylebox_override(
		"panel",
		SaloonTheme.panel(Color(0.055, 0.075, 0.075, 0.98), SaloonTheme.GOLD, 12)
	)
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	heading = _label("", 18, SaloonTheme.GOLD)
	subtitle = _label("", 12, Color("#c9d2cd"))
	_build_section("BÀI TRÊN BÀN", true)
	_build_section("BÀI TRÊN TAY · CHỌN NGẪU NHIÊN", false)
	cancel_button = Button.new()
	cancel_button.text = "HỦY"
	cancel_button.custom_minimum_size.y = 38
	cancel_button.pressed.connect(func():
		AudioManager.play_ui("button")
		cancel_requested.emit())
	column.add_child(cancel_button)

func _label(value: String, font_size: int, color: Color) -> Label:
	var item := Label.new()
	item.text = value
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", color)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(item)
	return item

func _build_section(title: String, face_up: bool) -> void:
	_label(title, 11, Color("#d7ad6b"))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 62
	column.add_child(scroll)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(row)
	if face_up:
		table_row = row
	else:
		hand_row = row

func present(owner_app: Node, active: Dictionary, snapshot: Dictionary) -> void:
	app = owner_app
	request = active
	state = snapshot
	target_id = int(active.get("zone_player_id", 0))
	var next_request_id := int(active.get("request_id", 0))
	var animate := not visible or request_id != next_request_id
	request_id = next_request_id
	locked = false
	var target: Dictionary = _target_row()
	heading.text = str(target.get("display_name", "CAO BỒI"))
	subtitle.text = str(active.get("title", "CHỌN 1 LÁ ĐỂ LẤY / BỎ"))
	var next_signature := JSON.stringify([
		target.get("weapon_card", {}), target.get("equipment_cards", []),
		target.get("hand_count", 0), active.get("choices", [])
	])
	if next_signature != content_signature:
		content_signature = next_signature
		_rebuild_table_cards(target)
		_rebuild_hand_cards(int(target.get("hand_count", 0)))
	_apply_responsive_size()
	visible = true
	set_process(true)
	if animate:
		modulate.a = 0.0
		scale = Vector2(0.98, 0.98)
		var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "modulate:a", 1.0, 0.14)
		tween.parallel().tween_property(self, "scale", Vector2.ONE, 0.16)

func dismiss() -> void:
	visible = false
	set_process(false)

func _target_row() -> Dictionary:
	for row in state.get("players", []):
		if int(row.get("player_id", 0)) == target_id:
			return row
	return {}

func _allowed(option: String, instance_id: int = 0) -> bool:
	return request.get("choices", []).any(func(choice):
		return str(choice.get("id", "")) == option and (
			option == "hand" or int(choice.get("instance_id", -1)) == instance_id
		))

func _clear_row(row: HBoxContainer) -> void:
	for child in row.get_children():
		child.queue_free()

func _rebuild_table_cards(target: Dictionary) -> void:
	_clear_row(table_row)
	var entries: Array[Dictionary] = []
	var weapon: Dictionary = target.get("weapon_card", {})
	if not weapon.is_empty() and _allowed("weapon", int(weapon.get("instance_id", 0))):
		entries.append({"option": "weapon", "card": weapon})
	for card in target.get("equipment_cards", []):
		var option := str(card.get("card_data_id", ""))
		if _allowed(option, int(card.get("instance_id", 0))):
			entries.append({"option": option, "card": card})
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "Không có lá hợp lệ"
		empty.add_theme_font_size_override("font_size", 12)
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		table_row.add_child(empty)
		return
	for entry in entries:
		var card: Dictionary = entry.card
		var data: Dictionary = CardData.data(card.get("card_data_id", ""))
		var button := _mini_button(
			"%s\n%s" % [data.get("name", ""), CardInstance.corner(card)],
			Color("#a38748")
		)
		button.tooltip_text = "%s\n%s" % [data.get("name", ""), data.get("description", "")]
		var token := {"option": entry.option, "card": int(card.get("instance_id", 0))}
		button.pressed.connect(_choose.bind(button, token))
		table_row.add_child(button)

func _rebuild_hand_cards(count: int) -> void:
	_clear_row(hand_row)
	if count <= 0 or not _allowed("hand"):
		var empty := Label.new()
		empty.text = "Không có bài trên tay"
		empty.add_theme_font_size_override("font_size", 12)
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hand_row.add_child(empty)
		return
	for index in range(count):
		var back := _mini_button("▧\n?", Color("#844e46"))
		back.tooltip_text = "Lá úp %d/%d · Máy chủ chọn ngẫu nhiên" % [index + 1, count]
		back.pressed.connect(_choose.bind(back, {"option": "hand"}))
		hand_row.add_child(back)

func _mini_button(value: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size = Vector2(70, 54)
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_stylebox_override("normal", SaloonTheme.panel(Color("#26333a"), accent, 6))
	button.add_theme_stylebox_override("hover", SaloonTheme.panel(Color("#3d4645"), SaloonTheme.GOLD, 6))
	button.mouse_entered.connect(func():
		if not layout.mobile(self):
			button.create_tween().tween_property(button, "scale", Vector2(1.04, 1.04), 0.1))
	button.mouse_exited.connect(func(): button.create_tween().tween_property(button, "scale", Vector2.ONE, 0.1))
	return button

func _choose(button: Button, token: Dictionary) -> void:
	if locked:
		return
	locked = true
	AudioManager.play_card("select")
	button.add_theme_stylebox_override("normal", SaloonTheme.panel(Color("#6d512e"), Color("#ffe09b"), 6))
	button.create_tween().tween_property(button, "scale", Vector2(1.08, 1.08), 0.1)
	choice_selected.emit(token)

func _apply_responsive_size() -> void:
	var safe: Vector4 = layout.safe_insets(self) if layout.mobile(self) else Vector4.ZERO
	var width := minf(layout.units(self, 440.0) if layout.mobile(self) else 420.0, get_viewport_rect().size.x - safe.x - safe.z - layout.units(self, 20.0))
	custom_minimum_size.x = width
	cancel_button.custom_minimum_size.y = layout.units(self, 44.0) if layout.mobile(self) else 38.0

func _process(_delta: float) -> void:
	if not visible or not is_instance_valid(app) or not is_instance_valid(app.table):
		return
	_apply_responsive_size()
	var safe: Vector4 = layout.safe_insets(self) if layout.mobile(self) else Vector4.ZERO
	var viewport_size := get_viewport_rect().size
	var anchor := viewport_size * Vector2(0.5, 0.35)
	if app.table.avatars.has(target_id):
		anchor = app.table.camera.unproject_position(app.table.avatars[target_id].global_position + Vector3.UP * 3.0)
	var left: float = anchor.x - size.x * 0.5
	var top: float = anchor.y - size.y - float(layout.units(self, 12.0))
	if layout.mobile_portrait(self):
		left = (viewport_size.x - size.x) * 0.5
		top = maxf(safe.y + layout.units(self, 72.0), minf(anchor.y - size.y * 0.5, viewport_size.y * 0.48 - size.y))
	left = clampf(left, safe.x + 8.0, viewport_size.x - safe.z - size.x - 8.0)
	top = clampf(top, safe.y + 58.0, viewport_size.y - safe.w - size.y - 8.0)
	position = Vector2(left, top)
	pivot_offset = size * 0.5
