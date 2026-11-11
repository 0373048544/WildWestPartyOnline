extends PanelContainer

var app: Node
var match_id := -1
var expanded := false
var cached_events: Array[Dictionary] = []
var seen: Dictionary = {}
var toggle: Button
var body: ScrollContainer
var rows: VBoxContainer
var empty_label: Label
var layout: Script = preload("res://scripts/ui/MatchLayout.gd")

func setup(owner_app: Node) -> void:
	app = owner_app
	name = "MatchLog"
	z_index = layout.Z_CHAT - 10
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", SaloonTheme.panel(Color(0.055, 0.075, 0.075, 0.96), SaloonTheme.GOLD.darkened(0.18), 12))
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	add_child(stack)
	toggle = load("res://scripts/ui/WesternButton.gd").new()
	toggle.name = "ToggleHistory"
	toggle.custom_minimum_size.y = 40
	toggle.pressed.connect(func(): set_expanded(not expanded))
	stack.add_child(toggle)
	body = ScrollContainer.new()
	body.name = "HistoryScroll"
	body.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(body)
	rows = VBoxContainer.new()
	rows.name = "Rows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	body.add_child(rows)
	set_expanded(false)
	resized.connect(_apply_layout)

func sync(events: Array, next_match_id: int, force_collapse: bool = false) -> void:
	if match_id != next_match_id:
		match_id = next_match_id
		cached_events.clear()
		seen.clear()
		_clear_rows()
	if force_collapse and expanded:
		set_expanded(false)
	for raw in events:
		if not raw is Dictionary:
			continue
		var event: Dictionary = raw
		if int(event.get("match_id", next_match_id)) != next_match_id:
			continue
		var event_id := str(event.get("event_id", ""))
		if event_id.is_empty() or seen.has(event_id):
			continue
		seen[event_id] = true
		cached_events.append(event.duplicate(true))
		if cached_events.size() > 150:
			var removed: Dictionary = cached_events.pop_front()
			seen.erase(str(removed.get("event_id", "")))
			if expanded and rows.get_child_count() > 0:
				rows.get_child(0).queue_free()
		if expanded:
			_append_row(event)
	if expanded:
		_update_empty()
		call_deferred("_scroll_to_end")
	_apply_layout()

func sync_legacy(lines: Array, next_match_id: int, force_collapse: bool = false) -> void:
	var events: Array = []
	for index in range(lines.size()):
		events.append({
			"event_id": "legacy:%d:%d:%s" % [next_match_id, index, str(lines[index])],
			"match_id": next_match_id,
			"text": str(lines[index])
		})
	sync(events, next_match_id, force_collapse)

func set_expanded(value: bool) -> void:
	expanded = value
	if is_instance_valid(app):
		app.log_expanded = value
	if not is_instance_valid(body):
		return
	toggle.text = "NHẬT KÝ  ×" if expanded else "NHẬT KÝ"
	body.visible = expanded
	if expanded:
		_rebuild_rows()
	else:
		_clear_rows()
	_apply_layout()

func _rebuild_rows() -> void:
	_clear_rows()
	for event in cached_events:
		_append_row(event)
	_update_empty()
	call_deferred("_scroll_to_end")

func _append_row(event: Dictionary) -> void:
	if not expanded:
		return
	var row := Label.new()
	row.text = str(event.get("text", ""))
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size.x = 0.0
	row.add_theme_font_size_override("font_size", 13 if layout.mobile(self) else 14)
	row.add_theme_color_override("font_color", SaloonTheme.CREAM)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(row)

func _update_empty() -> void:
	if not expanded:
		return
	if cached_events.is_empty() and not is_instance_valid(empty_label):
		empty_label = Label.new()
		empty_label.text = "Chưa có hành động nào."
		empty_label.add_theme_color_override("font_color", Color("#a99d87"))
		rows.add_child(empty_label)
	elif not cached_events.is_empty() and is_instance_valid(empty_label):
		empty_label.queue_free()
		empty_label = null

func _clear_rows() -> void:
	if not is_instance_valid(rows):
		return
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	empty_label = null

func _scroll_to_end() -> void:
	if is_instance_valid(body) and expanded:
		body.scroll_vertical = int(body.get_v_scroll_bar().max_value)

func _apply_layout() -> void:
	if not is_inside_tree():
		return
	var mobile: bool = layout.mobile(self)
	var safe: Vector4 = layout.safe_insets(self) if mobile else Vector4.ZERO
	var target_width: float = minf(layout.units(self, 360.0) if mobile else 340.0, get_viewport_rect().size.x - safe.x - safe.z - layout.units(self, 16.0))
	var target_height: float = (
		minf(layout.units(self, 218.0), get_viewport_rect().size.y * 0.30)
		if mobile
		else 238.0
	)
	position = Vector2(safe.x + layout.units(self, 8.0), safe.y + layout.get_mobile_banner_height(self) + layout.units(self, 8.0)) if mobile else Vector2(12, 62)
	var intended_size := Vector2(
		minf(target_width, layout.units(self, 300.0)) if expanded and mobile else target_width if expanded else layout.units(self, 96.0) if mobile else 118.0,
		target_height if expanded else layout.units(self, 40.0) if mobile else 42.0
	)
	# Never copy Control.size back into minimum size: Containers may temporarily
	# clamp it to a stale child minimum during an orientation change.
	custom_minimum_size = intended_size
	size = intended_size
