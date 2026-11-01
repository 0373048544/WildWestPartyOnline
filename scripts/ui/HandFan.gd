extends Control

signal card_clicked(uid: int)
signal preview_requested(card: Dictionary)
signal preview_closed
var cards: Array[Button] = []
var mobile_mode: bool = false
var focused_uid: int = -1
var scroll_offset: float = 0
var drag_origin := Vector2.ZERO
var dragging: bool = false
var drag_distance: float = 0
var mobile_lift: float = 0
var scroller: HScrollBar

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(arrange)

func configure(hand: Array, usable: Array, selected: Array, reactions: bool = false, reasons: Dictionary = {}) -> void:
	mobile_mode = load("res://scripts/ui/MatchLayout.gd").mobile(self)
	if mobile_mode:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		mobile_lift = load("res://scripts/ui/MatchLayout.gd").hand_lift(self,get_meta("target_mode",false))
	for card in hand:
		var view: Button = load("res://scenes/ui/CardUI.tscn").instantiate()
		add_child(view)
		view.configure(card, CardData.data(card.card_data_id), usable.has(card.instance_id), selected.has(card.instance_id), str(reasons.get(card.instance_id, "")))
		view.compact(selected.has(card.instance_id), reactions and usable.has(card.instance_id))
		if mobile_mode:
			view.touch_compact(minf(size.x,load("res://scripts/ui/MatchLayout.gd").units(self,144)))
		var uid: int = card.instance_id
		view.set_meta("mobile_uid",uid)
		view.pressed.connect(func():
			if not view.block_activation:
				if mobile_mode and drag_distance > 12:
					return
				if mobile_mode and focused_uid != uid:
					focused_uid = uid
					arrange()
				else:
					card_clicked.emit(uid))
		view.preview_requested.connect(func(): preview_requested.emit(card))
		view.preview_closed.connect(func(): preview_closed.emit())
		cards.append(view)
	arrange()
	if mobile_mode:
		scroller = HScrollBar.new()
		scroller.name = "HandScroll"
		scroller.position = Vector2(0,size.y-18)
		scroller.size = Vector2(size.x,18)
		scroller.max_value = maxf(size.x,content_width())
		scroller.page = size.x
		scroller.visible = scroller.max_value > size.x
		scroller.value_changed.connect(func(value): scroll_offset = value; arrange())
		add_child(scroller)
		scroller.z_index = 300

func card_spacing() -> float:
	var width: float = cards[0].size.x if not cards.is_empty() else 158
	var minimum: float = load("res://scripts/ui/MatchLayout.gd").units(self,48)
	return clampf((size.x-width)/maxf(1,mini(4,cards.size())-1),minimum,maxf(minimum,width*0.74))

func content_width() -> float:
	return (cards[0].size.x if not cards.is_empty() else 158) + card_spacing()*(cards.size()-1)

func arrange() -> void:
	if cards.is_empty():
		return
	if mobile_mode:
		var spacing: float = card_spacing()
		var total: float = content_width()
		scroll_offset = clampf(scroll_offset,0,maxf(0,total-size.x))
		for index in range(cards.size()):
			var card: Button = cards[index]
			var focused: bool = card.get_meta("chosen_card",false) or focused_uid == int(card.get_meta("mobile_uid",-2))
			card.position = Vector2(maxf(0,(size.x-total)/2)+index*spacing-scroll_offset, 0 if focused else mobile_lift+3)
			card.rotation = 0
			card.z_index = 100 if focused else index
			card.visible = card.position.x+card.size.x > 0 and card.position.x < size.x
		if is_instance_valid(scroller):
			scroller.position = Vector2(0,size.y-18)
			scroller.size.x = size.x
			scroller.max_value = maxf(size.x,total)
			scroller.page = size.x
			scroller.set_value_no_signal(scroll_offset)
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

func _input(event: InputEvent) -> void:
	if not mobile_mode:
		return
	if event is InputEventScreenTouch:
		if event.pressed and get_global_rect().has_point(event.position):
			drag_origin = event.position
			dragging = true
			drag_distance = 0
		elif not event.pressed:
			dragging = false
	elif event is InputEventScreenDrag and dragging:
		drag_distance = maxf(drag_distance,absf(event.position.x-drag_origin.x))
		scroll_offset -= event.relative.x
		arrange()
