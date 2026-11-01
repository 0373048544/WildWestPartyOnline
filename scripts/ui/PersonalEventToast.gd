extends Control

# Personal gameplay notifications using the exact visual language of ReactionBanner.
# No modal, no input blocking, no gameplay changes.

var pending: Array = []
var seen: Dictionary = {}
var current: Dictionary = {}
var panel: Panel
var countdown_label: Label
var match_id: int = -1
var deadline: float = 0.0

var layout: Script = preload("res://scripts/ui/MatchLayout.gd")


func _ready() -> void:
	name = "PersonalEventToasts"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 900
	set_process(false)
	resized.connect(_position_panel)


func _process(_delta: float) -> void:
	if is_instance_valid(countdown_label):
		countdown_label.text = "%.1f s" % maxf(
			0.0,
			deadline - Time.get_ticks_msec() / 1000.0
		)


func reset_for_match(next_match: int) -> void:
	if match_id == next_match:
		return

	match_id = next_match
	pending.clear()
	seen.clear()
	current.clear()
	deadline = 0.0
	set_process(false)

	if is_instance_valid(panel):
		panel.queue_free()

	panel = null
	countdown_label = null
	_clear_toast_rect()


func consume_event(event: Dictionary, local_id: int, state: Dictionary) -> void:
	if event.has("match_id"):
		if int(event.get("match_id", -1)) != int(state.get("match_id", -1)):
			return

	var event_id: String = str(
		event.get("event_id", event.get("audio_event_id", ""))
	)

	if event_id.is_empty():
		event_id = "event:%s" % JSON.stringify(event)

	if not _mark(event_id):
		return

	var item: Dictionary = _event_item(event, local_id, state)

	if not item.is_empty():
		_enqueue(item)


func show_notice(
	title_text: String,
	detail_text: String = "",
	tone: String = "neutral",
	icon_text: String = "✦",
	duration: float = 1.9
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
	var kind: String = str(event.get("kind", ""))
	var event_owner: int = int(
		event.get("player", event.get("target_player_id", 0))
	)

	match kind:
		"bang":
			var target: int = int(
				event.get("target", event.get("target_player_id", 0))
			)
			# Local BANG is already handled by ReactionBanner.
			if target == local_id:
				return {}

		"damage":
			if event_owner == local_id:
				var amount: int = int(event.get("amount", 1))
				_flash_hit()
				return _item(
					"Bạn mất %d máu" % amount,
					"",
					"danger",
					"✦",
					2.1
				)

		"heal":
			if event_owner == local_id:
				var amount: int = int(event.get("amount", 1))
				return _item(
					"+%d HP" % amount,
					"Bạn được hồi máu",
					"positive",
					"♥",
					1.8
				)

		"draw", "reclaim", "store_pick":
			if event_owner == local_id:
				var amount: int = int(event.get("count", 1))
				return _item(
					"Bạn nhận %d lá bài" % amount,
					"",
					"positive",
					"▣",
					1.6
				)

		"transfer":
			if event_owner == local_id:
				var actor: int = int(
					event.get("to", event.get("source_player_id", 0))
				)
				var actor_name: String = _player_name(actor, state)
				var steal: bool = bool(event.get("steal", true))

				if bool(event.get("hidden", true)):
					if steal:
						return _item(
							"%s đã lấy 1 lá bài của bạn" % actor_name,
							"",
							"warning",
							"◆",
							2.0
						)

					return _item(
						"%s đã bỏ 1 lá bài của bạn" % actor_name,
						"",
						"warning",
						"↘",
						2.0
					)

				var public_card: Dictionary = event.get("card", {})
				var card_id: String = str(public_card.get("card_data_id", ""))
				var card_name: String = "trang bị"

				if not card_id.is_empty():
					card_name = str(
						CardData.data(card_id).get("name", "trang bị")
					)

				if steal:
					return _item(
						"%s đã lấy %s của bạn" % [actor_name, card_name],
						"",
						"warning",
						"◆",
						2.1
					)

				return _item(
					"%s đã bỏ %s của bạn" % [actor_name, card_name],
					"",
					"warning",
					"↘",
					2.1
				)

		"equip":
			if event_owner == local_id:
				var from_player: int = int(event.get("from_player", local_id))
				var public_card: Dictionary = event.get("card", {})
				var card_id: String = str(public_card.get("card_data_id", ""))
				var card_name: String = "trang bị"

				if not card_id.is_empty():
					card_name = str(
						CardData.data(card_id).get("name", "trang bị")
					)

				if from_player != local_id:
					return _item(
						"%s đã đặt %s lên bạn" % [
							_player_name(from_player, state),
							card_name
						],
						"",
						"danger",
						"▥",
						2.1
					)

				return _item(
					"Bạn trang bị %s" % card_name,
					"",
					"neutral",
					"◆",
					1.8
				)

		"dynamite_pass":
			if int(event.get("to", 0)) == local_id:
				return _item(
					"THUỐC NỔ chuyển sang bạn",
					"",
					"danger",
					"✹",
					2.2
				)

		"dynamite_explode", "explosion":
			if event_owner == local_id:
				return _item(
					"THUỐC NỔ PHÁT NỔ!",
					"-3 HP",
					"danger",
					"✹",
					2.3
				)

		"jail_result":
			if event_owner == local_id:
				var escaped: bool = bool(event.get("escaped", false))

				if escaped:
					return _item(
						"Bạn thoát khỏi Nhà giam",
						"",
						"positive",
						"✓",
						1.8
					)

				return _item(
					"Bạn bị giữ trong Nhà giam",
					"",
					"danger",
					"▥",
					2.0
				)

		"missed", "dodge":
			if event_owner == local_id:
				return _item(
					"NÉ THÀNH CÔNG",
					"",
					"positive",
					"✓",
					1.5
				)

		"barrel_result":
			if event_owner == local_id and bool(event.get("success", false)):
				return _item(
					"THÙNG: NÉ THÀNH CÔNG",
					"",
					"positive",
					"▣",
					1.7
				)

		"ability":
			if event_owner == local_id:
				return _item(
					"Kỹ năng của bạn đã kích hoạt",
					"",
					"neutral",
					"★",
					1.8
				)

		"card_received":
			if event_owner == local_id:
				var amount: int = int(event.get("count", 1))
				return _item(
					"Bạn nhận %d lá bài" % amount,
					"",
					"positive",
					"▣",
					1.6
				)

		"card_lost":
			if event_owner == local_id:
				return _item(
					"Bạn mất 1 lá bài",
					"",
					"warning",
					"↘",
					1.8
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
			return str(row.get("display_name", "Cao bồi"))

	return "Cao bồi" if id != 0 else ""


func _enqueue(item: Dictionary) -> void:
	pending.append(item)

	if current.is_empty():
		_show_next()


func _show_next() -> void:
	if pending.is_empty():
		current.clear()
		set_process(false)
		_clear_toast_rect()
		return

	current = pending.pop_front()

	if is_instance_valid(panel):
		panel.queue_free()

	panel = Panel.new()
	panel.name = "PersonalToast"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 901
	panel.clip_contents = true
	add_child(panel)

	var tone: String = str(current.get("tone", "neutral"))
	var border: Color = _tone_color(tone)

	# Exact ReactionBanner panel language.
	panel.add_theme_stylebox_override(
		"panel",
		SaloonTheme.panel(
			Color(0.055, 0.075, 0.075, 0.97),
			border,
			18
		)
	)

	var margin: MarginContainer = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(layout.units(self, 16.0)))
	margin.add_theme_constant_override("margin_right", int(layout.units(self, 16.0)))
	margin.add_theme_constant_override("margin_top", int(layout.units(self, 10.0)))
	margin.add_theme_constant_override("margin_bottom", int(layout.units(self, 10.0)))
	panel.add_child(margin)

	var content: VBoxContainer = VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", int(layout.units(self, 4.0)))
	margin.add_child(content)

	var title_row: HBoxContainer = HBoxContainer.new()
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_theme_constant_override("separation", int(layout.units(self, 8.0)))
	content.add_child(title_row)

	var icon_label: Label = Label.new()
	icon_label.text = str(current.get("icon", "✦"))
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.custom_minimum_size.x = layout.units(self, 22.0)
	icon_label.add_theme_font_size_override(
		"font_size",
		int(layout.units(self, 20.0))
	)
	icon_label.add_theme_color_override("font_color", border)
	icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(icon_label)

	var title_label: Label = Label.new()
	title_label.text = str(current.get("text", ""))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.add_theme_font_size_override(
		"font_size",
		int(layout.units(self, 20.0 if layout.mobile(self) else 21.0))
	)
	title_label.add_theme_color_override("font_color", Color("#f8e4bd"))
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(title_label)

	countdown_label = Label.new()
	countdown_label.text = ""
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown_label.custom_minimum_size.x = layout.units(self, 54.0)
	countdown_label.add_theme_font_size_override(
		"font_size",
		int(layout.units(self, 14.0))
	)
	countdown_label.add_theme_color_override("font_color", SaloonTheme.GOLD)
	countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(countdown_label)

	var detail_text: String = str(current.get("detail", ""))

	if not detail_text.is_empty():
		var detail_label: Label = Label.new()
		detail_label.text = detail_text
		detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail_label.add_theme_font_size_override(
			"font_size",
			int(layout.units(self, 14.0))
		)
		detail_label.add_theme_color_override("font_color", Color("#d8ccb5"))
		detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(detail_label)

	var duration: float = float(current.get("duration", 1.9))
	deadline = Time.get_ticks_msec() / 1000.0 + duration
	set_process(true)

	_position_panel()
	_animate_in()

	var hold: Tween = create_tween()
	hold.tween_interval(duration)
	hold.tween_callback(_animate_out)


func _tone_color(tone: String) -> Color:
	match tone:
		"danger":
			return Color("#d97752")
		"warning":
			return SaloonTheme.GOLD
		"positive":
			return Color("#78b889")
		_:
			return SaloonTheme.GOLD


func _position_panel() -> void:
	if not is_instance_valid(panel):
		return

	var mobile: bool = bool(layout.mobile(self))
	var short_landscape: bool = mobile and size.x > size.y
	var safe: Vector4 = layout.safe_insets(self) if mobile else Vector4.ZERO

	# Same width as ReactionBanner.
	var width: float = minf(
		layout.units(self, 480.0 if short_landscape else 540.0),
		size.x - safe.x - safe.z - layout.units(self, 20.0)
	)

	# Compact version of ReactionBanner because there are no action buttons.
	var detail_text: String = str(current.get("detail", ""))
	var height: float = layout.units(
		self,
		72.0 if detail_text.is_empty() else 94.0
	)

	if mobile and not short_landscape:
		height = layout.units(
			self,
			82.0 if detail_text.is_empty() else 106.0
		)

	# Same vertical position as ReactionBanner when no reaction is active.
	var top: float = safe.y + layout.units(
		self,
		16.0 if short_landscape else (62.0 if mobile else 58.0)
	)

	# If ReactionBanner is active, place this directly underneath it.
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
					reaction_rect.end.y + layout.units(self, 8.0)
				)

	var left: float = (size.x - width) * 0.5

	panel.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	panel.offset_left = left
	panel.offset_top = top
	panel.offset_right = left + width
	panel.offset_bottom = top + height

	get_viewport().set_meta(
		"personal_toast_rect",
		panel.get_global_rect().grow(layout.units(self, 6.0))
	)


func _animate_in() -> void:
	if not is_instance_valid(panel):
		return

	var target: Vector2 = panel.position
	panel.position.y -= layout.units(self, 8.0)
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.985, 0.985)

	var tween: Tween = panel.create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "position", target, 0.20)
	tween.parallel().tween_property(panel, "modulate:a", 1.0, 0.16)
	tween.parallel().tween_property(panel, "scale", Vector2.ONE, 0.20)


func _animate_out() -> void:
	if not is_instance_valid(panel):
		_finish_current()
		return

	var tween: Tween = panel.create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(panel, "modulate:a", 0.0, 0.14)
	tween.parallel().tween_property(
		panel,
		"position:y",
		panel.position.y - layout.units(self, 8.0),
		0.14
	)
	tween.tween_callback(_finish_current)


func _finish_current() -> void:
	if is_instance_valid(panel):
		panel.queue_free()

	panel = null
	countdown_label = null
	current.clear()
	deadline = 0.0
	set_process(false)
	_clear_toast_rect()
	call_deferred("_show_next")


func _clear_toast_rect() -> void:
	if get_viewport().has_meta("personal_toast_rect"):
		get_viewport().remove_meta("personal_toast_rect")


func _flash_hit() -> void:
	var flash: ColorRect = ColorRect.new()
	flash.name = "LocalHitFlash"
	flash.color = Color(
		0.78,
		0.11,
		0.04,
		0.14 if layout.mobile(self) else 0.18
	)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.z_index = -1
	add_child(flash)

	var tween: Tween = flash.create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.22)
	tween.tween_callback(flash.queue_free)
