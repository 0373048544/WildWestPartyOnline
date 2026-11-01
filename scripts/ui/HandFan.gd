extends Control

signal card_clicked(uid: int)
signal preview_requested(card: Dictionary)
signal preview_closed
var cards: Array[Button] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(arrange)

func configure(hand: Array, usable: Array, selected: Array, reactions: bool = false, reasons: Dictionary = {}) -> void:
	for card in hand:
		var view: Button = load("res://scenes/ui/CardUI.tscn").instantiate()
		add_child(view)
		view.configure(card, CardData.data(card.card_data_id), usable.has(card.instance_id), selected.has(card.instance_id), str(reasons.get(card.instance_id, "")))
		view.compact(selected.has(card.instance_id), reactions and usable.has(card.instance_id))
		var uid: int = card.instance_id
		view.pressed.connect(func():
			if not view.block_activation:
				card_clicked.emit(uid))
		view.preview_requested.connect(func(): preview_requested.emit(card))
		view.preview_closed.connect(func(): preview_closed.emit())
		cards.append(view)
	arrange()

func arrange() -> void:
	if cards.is_empty():
		return
	var gap: float = minf(136, maxf(18, (size.x - 158) / maxf(1, cards.size() - 1)))
	var width: float = 158 + gap * (cards.size() - 1)
	for index in range(cards.size()):
		var view: Button = cards[index]
		var fraction: float = float(index) / maxf(1, cards.size() - 1) - 0.5
		view.position = Vector2((size.x - width) / 2 + index * gap, absf(fraction) * 7 + 16)
		view.rotation = fraction * 0.055 - (0.06 if view.get_meta("chosen_card", false) else 0.0)
		view.pivot_offset = Vector2(79, 158)
		view.z_index = index
