extends Control

# Local-only presentation fed by authoritative events. It never infers card
# identity from hand changes or snapshot differences.
var pending: Array = []
var seen: Dictionary = {}
var current: Dictionary = {}
var panel: PanelContainer
var history: Array[String] = []
var match_id: int = -1
var layout: Script = preload("res://scripts/ui/MatchLayout.gd")

func _ready() -> void:
	name = "PersonalEventToasts"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 900
	resized.connect(_position_panel)

func reset_for_match(next_match: int) -> void:
	if match_id == next_match:
		return
	match_id = next_match
	pending.clear()
	seen.clear()
	current.clear()
	if is_instance_valid(panel):
		panel.queue_free()
	panel = null

func consume_event(event: Dictionary, local_id: int, state: Dictionary) -> void:
	if event.has("match_id") and int(event.match_id) != int(state.get("match_id", -1)):
		return
	var event_id := str(event.get("event_id", event.get("audio_event_id", "")))
	if event_id.is_empty():
		event_id = "event:%s" % JSON.stringify(event)
	if not _mark(event_id):
		return
	var item := _event_item(event, local_id, state)
	if not item.is_empty():
		_enqueue(item)

func consume_reaction(request: Dictionary, state: Dictionary) -> void:
	if request.is_empty():
		return
	var key := "reaction:%d:%d" % [int(state.get("match_id", 0)), int(request.get("request_id", 0))]
	if not _mark(key):
		return
	var kind := str(request.get("reaction_type", ""))
	var actor := _player_name(int(request.get("source_player_id", 0)), state)
	var title := ""
	var detail := ""
	match kind:
		"dodge":
			title = (actor + " đang bắn bạn!") if not actor.is_empty() else "Bạn đang bị bắn!"
			detail = "Dùng NÉ hoặc chịu 1 sát thương"
		"duel":
			title = (actor + " thách đấu bạn") if not actor.is_empty() else "Bạn đang bị thách đấu"
			detail = "Dùng BANG! để đáp lại hoặc chịu 1 sát thương"
		"indians":
			title = "Thổ dân tấn công"
			detail = "Dùng BANG! hoặc chịu 1 sát thương"
		"survive":
			title = "Bạn sắp bị loại"
			detail = "Dùng BIA để sống sót?"
		_:
			return
	_enqueue({"text": title, "detail": detail, "priority": 3, "tone": "danger", "duration": 2.8})

func _mark(key: String) -> bool:
	if seen.has(key):
		return false
	seen[key] = Time.get_ticks_msec()
	if seen.size() > 512:
		seen.erase(seen.keys()[0])
	return true

func _event_item(event: Dictionary, local_id: int, state: Dictionary) -> Dictionary:
	var kind := str(event.get("kind", ""))
	var owner := int(event.get("player", 0))
	match kind:
		"bang":
			if int(event.get("target", event.get("target_player_id", 0))) == local_id:
				return _item("%s dùng BANG! lên bạn." % _player_name(owner, state), 3, "danger")
		"damage":
			if owner == local_id:
				_flash_hit()
				return _item("Bạn bị mất %d máu." % int(event.get("amount", 1)), 3, "danger")
		"heal":
			if owner == local_id:
				return _item("+%d HP · Bạn được hồi máu." % int(event.get("amount", 1)), 1, "positive")
		"draw", "reclaim", "store_pick":
			if owner == local_id:
				return _item("Bạn nhận được %d lá bài." % int(event.get("count", 1)), 1, "positive")
		"transfer":
			if owner == local_id:
				var actor := int(event.get("to", 0))
				var actor_name := _player_name(actor, state)
				var verb := "lấy" if bool(event.get("steal", true)) else "bỏ"
				if bool(event.get("hidden", true)):
					return _item("%s đã %s 1 lá ngẫu nhiên trên tay bạn." % [actor_name, verb], 2, "warning")
				var public_card: Dictionary = event.get("card", {})
				var card_name: String = str(CardData.data(str(public_card.get("card_data_id", ""))).get("name", "trang bị"))
				return _item("%s đã %s %s của bạn." % [actor_name, verb, card_name], 2, "warning")
		"equip":
			if owner == local_id and int(event.get("from_player", local_id)) != local_id:
				var public_card: Dictionary = event.get("card", {})
				var card_name: String = str(CardData.data(str(public_card.get("card_data_id", ""))).get("name", "trang bị"))
				return _item("%s đã đặt %s lên bạn." % [_player_name(int(event.from_player), state), card_name], 3, "danger")
		"dynamite_pass":
			if int(event.get("to", 0)) == local_id:
				return _item("Thuốc nổ được chuyển sang bạn.", 3, "danger")
		"jail_result":
			if owner == local_id:
				return _item("Bạn thoát khỏi Nhà giam." if bool(event.get("escaped", false)) else "Bạn bị giữ trong Nhà giam.", 2, "positive" if bool(event.get("escaped", false)) else "danger")
		"missed":
			if owner == local_id:
				return _item("NÉ THÀNH CÔNG", 1, "positive")
		"barrel_result":
			if owner == local_id and bool(event.get("success", false)):
				return _item("Thùng: NÉ THÀNH CÔNG", 1, "positive")
		"ability":
			if owner == local_id:
				return _item("Kỹ năng của bạn đã kích hoạt.", 2, "positive")
	return {}

func _item(value: String, priority: int, tone: String) -> Dictionary:
	return {"text": value, "detail": "", "priority": priority, "tone": tone,
		"duration": 2.6 if priority >= 3 else 2.15}

func _player_name(id: int, state: Dictionary) -> String:
	for row in state.get("players", []):
		if int(row.get("player_id", 0)) == id:
			return str(row.get("display_name", "Người chơi"))
	return "Người chơi" if id != 0 else ""

func _enqueue(item: Dictionary) -> void:
	# Preserve authoritative event order. Priority changes styling/duration only;
	# it never replaces or jumps ahead of another personal event.
	pending.append(item)
	if current.is_empty():
		_show_next()

func _show_next() -> void:
	if pending.is_empty():
		current.clear()
		return
	current = pending.pop_front()
	history.append(str(current.text))
	if history.size() > 64:
		history.pop_front()
	panel = PanelContainer.new()
	panel.name = "PersonalToast"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(layout.units(self, 300), 0)
	var tone := str(current.tone)
	var border: Color = {"danger": Color("#d46b54"), "warning": Color("#d8a552"), "positive": Color("#78b889")}.get(tone, SaloonTheme.GOLD)
	panel.add_theme_stylebox_override("panel", SaloonTheme.panel(Color(0.055, 0.09, 0.11, 0.96), border, 16))
	add_child(panel)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	var title := Label.new()
	title.text = str(current.text)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", int(layout.units(self, 17 if layout.mobile(self) else 18)))
	column.add_child(title)
	if not str(current.detail).is_empty():
		var detail := Label.new()
		detail.text = str(current.detail)
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.add_theme_font_size_override("font_size", int(layout.units(self, 14)))
		detail.add_theme_color_override("font_color", SaloonTheme.CREAM)
		column.add_child(detail)
	_position_panel()
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.97, 0.97)
	var tween := panel.create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.15)
	tween.parallel().tween_property(panel, "scale", Vector2.ONE, 0.15)
	tween.tween_interval(float(current.duration))
	tween.tween_property(panel, "modulate:a", 0.0, 0.28)
	tween.tween_callback(_finish_current)

func _position_panel() -> void:
	if not is_instance_valid(panel):
		return
	var safe: Vector4 = layout.safe_insets(self) if layout.mobile(self) else Vector4.ZERO
	var width := minf(layout.units(self, 560), size.x - safe.x - safe.z - layout.units(self, 24))
	panel.size.x = maxf(layout.units(self, 280), width)
	panel.position.x = (size.x - panel.size.x) * 0.5
	panel.position.y = maxf(safe.y + layout.units(self, 14), size.y * (0.20 if layout.mobile(self) else 0.08))

func _finish_current() -> void:
	if is_instance_valid(panel):
		panel.queue_free()
	panel = null
	current.clear()
	call_deferred("_show_next")

func _flash_hit() -> void:
	var flash := ColorRect.new()
	flash.name = "LocalHitFlash"
	flash.color = Color(0.78, 0.11, 0.04, 0.20 if layout.mobile(self) else 0.25)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(flash)
	var tween := flash.create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.24)
	tween.tween_callback(flash.queue_free)
