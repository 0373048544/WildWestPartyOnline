extends VBoxContainer

var picked: Array = []

func configure(app: Node, cards: Array, count: int, submit: Callable) -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(660, 236)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	scroll.add_child(row)
	var confirm: Button = app.button("XÁC NHẬN LỰA CHỌN", func(): submit.call(picked.duplicate()), self, true)
	for card in cards:
		var view: Button = load("res://scenes/ui/CardUI.tscn").instantiate()
		row.add_child(view)
		view.configure(card, CardData.data(card.card_data_id), true, false)
		var uid: int = card.instance_id
		view.pressed.connect(func():
			if count == 1:
				submit.call([uid])
				return
			if picked.has(uid):
				picked.erase(uid)
				view.modulate = Color.WHITE
			elif picked.size() < count:
				picked.append(uid)
				view.modulate = Color("#ffe08b")
			confirm.disabled = picked.size() != count)
