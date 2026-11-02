extends VBoxContainer

var picked: Array = []

func configure(
	app: Node,
	cards: Array,
	count: int,
	submit: Callable,
	confirm_label: String = "XÁC NHẬN LỰA CHỌN",
	reset_label: String = "",
	confirm_question: String = ""
) -> void:
	var layout: Script = load("res://scripts/ui/MatchLayout.gd")
	var scroll := ScrollContainer.new()
	var usable_width: float = layout.modal_rect(self).size.x
	var width_ratio: float = 0.9 if layout.mobile_portrait(self) else (0.82 if layout.mobile_landscape(self) else 0.75)
	var card_strip_height: float = layout.units(self, 114 if layout.mobile_landscape(self) else 236)
	scroll.custom_minimum_size = Vector2(minf(760, usable_width * width_ratio), card_strip_height)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	scroll.add_child(row)
	var question := Label.new()
	question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	question.add_theme_font_size_override("font_size", int(layout.units(self, 17)))
	question.add_theme_color_override("font_color", SaloonTheme.CREAM)
	question.visible = false
	add_child(question)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", int(layout.units(self, 10)))
	add_child(actions)
	var confirm: Button = app.button(confirm_label, func(): submit.call(picked.duplicate()), actions, true)
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.custom_minimum_size.y = maxf(44, layout.units(self, 44))
	if count == 1 and reset_label.is_empty():
		# One-tap public market selection needs no dead confirmation control.
		confirm.visible = false
	var reset: Button
	if not reset_label.is_empty():
		reset = app.button(reset_label, func():
			picked.clear()
			confirm.disabled = true
			question.visible = false
			for child in row.get_children():
				child.modulate = Color.WHITE
		, actions)
		reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		reset.custom_minimum_size.y = confirm.custom_minimum_size.y
	if layout.mobile_landscape(self) and not actions.get_children().is_empty():
		# Keep confirm/reset above the horizontally scrolling cards so browser bars
		# can never hide the only way to complete a choice.
		move_child(actions, 0)
		move_child(question, 1)
	var reveal_index := 0
	for card in cards:
		var view: Button = load("res://scenes/ui/CardUI.tscn").instantiate()
		row.add_child(view)
		view.configure(card, CardData.data(card.card_data_id), true, false)
		if layout.mobile_landscape(self):
			view.touch_compact(layout.units(self, 108))
		# Fast staggered reveal communicates a market/deal without delaying input.
		# Buttons are interactive immediately, even while this cosmetic tween runs.
		view.modulate = Color(1, 1, 1, 0)
		view.scale = Vector2.ONE * 0.94
		view.pivot_offset = view.size * 0.5
		var reveal := view.create_tween().set_parallel()
		reveal.tween_property(view, "modulate:a", 1.0, 0.16).set_delay(reveal_index * 0.08)
		reveal.tween_property(view, "scale", Vector2.ONE, 0.18).set_delay(reveal_index * 0.08).set_trans(Tween.TRANS_BACK)
		reveal_index += 1
		var uid: int = card.instance_id
		view.pressed.connect(func():
			if count == 1 and reset_label.is_empty():
				submit.call([uid])
				return
			if count == 1:
				picked = [uid]
				for sibling in row.get_children():
					sibling.modulate = Color.WHITE
				view.modulate = Color("#ffe08b")
				var card_name: String = str(CardData.data(card.card_data_id).name)
				question.text = (
					confirm_question.replace("{card}", card_name)
					if not confirm_question.is_empty()
					else "%s %s?" % [confirm_label.capitalize(), card_name]
				)
				question.visible = true
				confirm.disabled = false
				return
			if picked.has(uid):
				picked.erase(uid)
				view.modulate = Color.WHITE
			elif picked.size() < count:
				picked.append(uid)
				view.modulate = Color("#ffe08b")
			confirm.disabled = picked.size() != count)
