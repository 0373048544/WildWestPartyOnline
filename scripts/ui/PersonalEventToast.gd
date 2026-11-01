extends Control

# Toast gameplay nhỏ, local-only.
# Không block input, không thay đổi gameplay.
# Đồng bộ style với ReactionBanner.

var pending: Array = []
var seen: Dictionary = {}
var current: Dictionary = {}
var panel: PanelContainer
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
	if event.has("match_id"):
		if int(event.get("match_id", -1)) != int(state.get("match_id", -1)):
			return

	var event_id := str(event.get("event_id", event.get("audio_event_id", "")))

	if event_id.is_empty():
		event_id = "event:%s" % JSON.stringify(event)

	if not _mark(event_id):
		return

	var item := _event_item(event, local_id, state)

	if not item.is_empty():
		_enqueue(item)


func show_notice(
	title_text: String,
	detail_text: String = "",
	tone: String = "neutral",
	icon_text: String = "✦",
	duration: float = 2.2
) -> void:
	_enqueue({
		"text": title_text,
		"detail": detail_text,
		"tone": tone,
		"icon": icon_text,
		"duration": duration
	})


func _mark(key: String) -> bool:
	if seen.has(key):
		return false

	seen[key] = Time.get_ticks_msec()

	if seen.size() > 512:
		seen.erase(seen.keys()[0])

	return true


func _event_item(event: Dictionary, local_id: int, state: Dictionary) -> Dictionary:
	var kind := str(event.get("kind", ""))
	var owner := int(event.get("player", event.get("target_player_id", 0)))

	match kind:

		"bang":
			var target := int(event.get("target", event.get("target_player_id", 0)))

			# BANG vào local đã có ReactionBanner.
			# Không tạo toast trùng.
			if target == local_id:
				return {}

		"damage":
			if owner == local_id:
				var amount := int(event.get("amount", 1))
				_flash_hit()

				return _item(
					"Bạn mất %d máu" % amount,
					"",
					"danger",
					"✦",
					2.45
				)

		"heal":
			if owner == local_id:
				var amount := int(event.get("amount", 1))

				return _item(
					"+%d HP" % amount,
					"Bạn được hồi máu",
					"positive",
					"♥",
					2.0
				)

		"draw", "reclaim", "store_pick":
			if owner == local_id:
				var amount := int(event.get("count", 1))

				return _item(
					"Bạn nhận được %d lá bài" % amount,
					"",
					"positive",
					"▣",
					1.9
				)

		"transfer":
			if owner == local_id:
				var actor := int(event.get("to", event.get("source_player_id", 0)))
				var actor_name := _player_name(actor, state)
				var steal := bool(event.get("steal", true))

				if bool(event.get("hidden", true)):
					if steal:
						return _item(
							"%s đã lấy 1 lá bài của bạn" % actor_name,
							"",
							"warning",
							"◆",
							2.3
						)

					return _item(
						"%s đã bỏ 1 lá bài của bạn" % actor_name,
						"",
						"warning",
						"↘",
						2.3
					)

				var public_card: Dictionary = event.get("card", {})
				var card_id := str(public_card.get("card_data_id", ""))
				var card_name := "trang bị"

				if not card_id.is_empty():
					card_name = str(CardData.data(card_id).get("name", "trang bị"))

				if steal:
					return _item(
						"%s đã lấy %s của bạn" % [actor_name, card_name],
						"",
						"warning",
						"◆",
						2.35
					)

				return _item(
					"%s đã bỏ %s của bạn" % [actor_name, card_name],
					"",
					"warning",
					"↘",
					2.35
				)

		"equip":
			if owner == local_id:
				var from_player := int(event.get("from_player", local_id))
				var public_card: Dictionary = event.get("card", {})
				var card_id := str(public_card.get("card_data_id", ""))
				var card_name := "trang bị"

				if not card_id.is_empty():
					card_name = str(CardData.data(card_id).get("name", "trang bị"))

				if from_player != local_id:
					return _item(
						"%s đã đặt %s lên bạn" % [
							_player_name(from_player, state),
							card_name
						],
						"",
						"danger",
						"▥",
						2.5
					)

				return _item(
					"Bạn trang bị %s" % card_name,
					"",
					"neutral",
					"◆",
					2.0
				)

		"dynamite_pass":
			if int(event.get("to", 0)) == local_id:
				return _item(
					"THUỐC NỔ được chuyển sang bạn",
					"",
					"danger",
					"✹",
					2.6
				)

		"dynamite_explode", "explosion":
			if owner == local_id:
				return _item(
					"THUỐC NỔ PHÁT NỔ!",
					"-3 HP",
					"danger",
					"✹",
					2.7
				)

		"jail_result":
			if owner == local_id:
				var escaped := bool(event.get("escaped", false))

				if escaped:
					return _item(
						"Bạn thoát khỏi Nhà giam",
						"",
						"positive",
						"✓",
						2.1
					)

				return _item(
					"Bạn bị giữ trong Nhà giam",
					"",
					"danger",
					"▥",
					2.5
				)

		"missed", "dodge":
			if owner == local_id:
				return _item(
					"NÉ THÀNH CÔNG",
					"",
					"positive",
					"✓",
					1.85
				)

		"barrel_result":
			if owner == local_id and bool(event.get("success", false)):
				return _item(
					"THÙNG: NÉ THÀNH CÔNG",
					"",
					"positive",
					"▣",
					2.0
				)

		"ability":
			if owner == local_id:
				return _item(
					"Kỹ năng của bạn đã kích hoạt",
					"",
					"neutral",
					"★",
					2.0
				)

		"card_received":
			if owner == local_id:
				var amount := int(event.get("count", 1))

				return _item(
					"Bạn nhận được %d lá bài" % amount,
					"",
					"positive",
					"▣",
					1.9
				)

		"card_lost":
			if owner == local_id:
				return _item(
					"Bạn mất 1 lá bài",
					"",
					"warning",
					"↘",
					2.1
				)

	return {}


func _item(
	title_text: String,
	detail_text: String,
	tone: String,
	icon_text: String,
	duration: float
) -> Dictionary:
	return {
		"text": title_text,
		"detail": detail_text,
		"tone": tone,
		"icon": icon_text,
		"duration": duration
	}


func _player_name(id: int, state: Dictionary) -> String:
	for row in state.get("players", []):
		if int(row.get("player_id", 0)) == id:
			return str(row.get("display_name", "Người chơi"))

	return "Người chơi" if id != 0 else ""


func _enqueue(item: Dictionary) -> void:
	pending.append(item)

	if current.is_empty():
		_show_next()


func _show_next() -> void:
	if pending.is_empty():
		current.clear()
		return

	current = pending.pop_front()

	panel = PanelContainer.new()
	panel.name = "PersonalToast"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 901

	var tone := str(current.get("tone", "neutral"))
	var border := _tone_color(tone)

	var style: StyleBoxFlat = SaloonTheme.panel(
		Color(0.055, 0.075, 0.075, 0.97),
		border,
		18
	)

	style.shadow_color = Color(0, 0, 0, 0.38)
	style.shadow_size = int(layout.units(self, 10))
	style.shadow_offset = Vector2(0, layout.units(self, 4))

	panel.add_theme_stylebox_override("panel", style)

	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(layout.units(self, 14)))
	margin.add_theme_constant_override("margin_right", int(layout.units(self, 14)))
	margin.add_theme_constant_override("margin_top", int(layout.units(self, 9)))
	margin.add_theme_constant_override("margin_bottom", int(layout.units(self, 9)))

	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(layout.units(self, 11)))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	margin.add_child(row)

	var icon_box := CenterContainer.new()
	icon_box.custom_minimum_size.x = layout.units(self, 34)
	icon_box.custom_minimum_size.y = layout.units(self, 34)
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	row.add_child(icon_box)

	var icon := Label.new()
	icon.text = str(current.get("icon", "✦"))
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override(
		"font_size",
		int(layout.units(self, 22 if layout.mobile(self) else 24))
	)
	icon.add_theme_color_override("font_color", border)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

	icon_box.add_child(icon)

	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_theme_constant_override(
		"separation",
		int(layout.units(self, 2))
	)
	text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE

	row.add_child(text_column)

	var title := Label.new()
	title.text = str(current.get("text", ""))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(
		"font_size",
		int(layout.units(self, 16 if layout.mobile(self) else 18))
	)
	title.add_theme_color_override(
		"font_color",
		Color("#f8e4bd")
	)
	title.add_theme_color_override(
		"font_shadow_color",
		Color(0, 0, 0, 0.55)
	)
	title.add_theme_constant_override("shadow_offset_y", 1)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE

	text_column.add_child(title)

	var detail_text := str(current.get("detail", ""))

	if not detail_text.is_empty():
		var detail := Label.new()
		detail.text = detail_text
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.add_theme_font_size_override(
			"font_size",
			int(layout.units(self, 13 if layout.mobile(self) else 14))
		)
		detail.add_theme_color_override(
			"font_color",
			Color("#d6c9af")
		)
		detail.mouse_filter = Control.MOUSE_FILTER_IGNORE

		text_column.add_child(detail)

	_position_panel()

	var target_position: Vector2 = panel.position

	panel.position.y -= layout.units(self, 10)
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.975, 0.975)
	panel.pivot_offset = panel.size * 0.5

	var tween := panel.create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_property(
		panel,
		"position",
		target_position,
		0.18
	)

	tween.parallel().tween_property(
		panel,
		"modulate:a",
		1.0,
		0.15
	)

	tween.parallel().tween_property(
		panel,
		"scale",
		Vector2.ONE,
		0.18
	)

	tween.tween_interval(float(current.get("duration", 2.2)))

	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)

	tween.tween_property(
		panel,
		"modulate:a",
		0.0,
		0.24
	)

	tween.parallel().tween_property(
		panel,
		"position:y",
		panel.position.y - layout.units(self, 7),
		0.24
	)

	tween.tween_callback(_finish_current)


func _tone_color(tone: String) -> Color:
	match tone:
		"danger":
			return Color("#d97752")

		"warning":
			return Color("#d8a552")

		"positive":
			return Color("#78b889")

		_:
			return SaloonTheme.GOLD


func _position_panel() -> void:
	if not is_instance_valid(panel):
		return

	var mobile: bool = bool(layout.mobile(self))
	var safe: Vector4 = Vector4.ZERO

	if mobile:
		safe = layout.safe_insets(self) as Vector4

	var max_width: float = 0.0

	if mobile:
		max_width = size.x - safe.x - safe.z - float(layout.units(self, 28.0))
	else:
		max_width = minf(
			float(layout.units(self, 460.0)),
			size.x - 40.0
		)

	var min_width: float = float(
		layout.units(self, 290.0 if mobile else 320.0)
	)

	var preferred_width: float = float(
		layout.units(self, 460.0)
	)

	panel.size.x = maxf(
		min_width,
		minf(max_width, preferred_width)
	)

	panel.position.x = (size.x - panel.size.x) * 0.5

	var top: float = safe.y + float(
		layout.units(self, 66.0 if mobile else 62.0)
	)

	if get_viewport().has_meta("reaction_banner_rect"):
		var reaction_value: Variant = get_viewport().get_meta(
			"reaction_banner_rect",
			Rect2()
		)

		if reaction_value is Rect2:
			var reaction_rect: Rect2 = reaction_value

			if reaction_rect.has_area():
				top = maxf(
					top,
					reaction_rect.end.y
					+ float(layout.units(self, 10.0))
				)

	panel.position.y = top


func _finish_current() -> void:
	if is_instance_valid(panel):
		panel.queue_free()

	panel = null
	current.clear()

	call_deferred("_show_next")


func _flash_hit() -> void:
	var flash := ColorRect.new()
	flash.name = "LocalHitFlash"
	flash.color = Color(
		0.78,
		0.11,
		0.04,
		0.16 if layout.mobile(self) else 0.22
	)

	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.z_index = -1

	add_child(flash)

	var tween := flash.create_tween()
	tween.tween_property(
		flash,
		"modulate:a",
		0.0,
		0.24
	)

	tween.tween_callback(flash.queue_free)