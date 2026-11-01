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
var configured_size := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(arrange)

func configure(hand: Array, usable: Array, selected: Array, reactions: bool = false, reasons: Dictionary = {}) -> void:
	var current_css_size: Vector2 = Vector2(get_window().size)
	if not configured_size.is_equal_approx(current_css_size):
		focused_uid = -1
		configured_size = current_css_size
	mobile_mode = load("res://scripts/ui/MatchLayout.gd").mobile(self)
	var existing: Dictionary = {}
	for old_view in cards:
		if is_instance_valid(old_view):
			existing[int(old_view.get_meta("mobile_uid", -1))] = old_view
	cards.clear()

	if mobile_mode:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		mobile_lift = load("res://scripts/ui/MatchLayout.gd").hand_lift(self,get_meta("target_mode",false))
	else:
		clip_contents = false
		mobile_lift = 0

	for card in hand:
		var uid: int = int(card.instance_id)
		var view: Button = existing.get(uid)
		if is_instance_valid(view):
			existing.erase(uid)
		else:
			view = load("res://scenes/ui/CardUI.tscn").instantiate()
			add_child(view)
			view.pressed.connect(_on_view_pressed.bind(view))
			view.preview_requested.connect(_on_view_preview.bind(view))
			view.preview_closed.connect(func(): preview_closed.emit())

		view.set_meta("mobile_uid",uid)
		view.set_meta("preview_card",card)
		view.configure(card, CardData.data(card.card_data_id), usable.has(card.instance_id), selected.has(card.instance_id), str(reasons.get(card.instance_id, "")))
		view.compact(selected.has(card.instance_id), reactions and usable.has(card.instance_id))
		if mobile_mode:
			view.touch_compact(minf(size.x,load("res://scripts/ui/MatchLayout.gd").units(self,144)))
		cards.append(view)

	for stale in existing.values():
		if is_instance_valid(stale):
			stale.queue_free()

	arrange()
	if mobile_mode:
		if not is_instance_valid(scroller):
			scroller = HScrollBar.new()
			scroller.name = "HandScroll"
			scroller.value_changed.connect(func(value): scroll_offset = value; arrange())
			add_child(scroller)
			scroller.z_index = 300
		scroller.position = Vector2(0,size.y-18)
		scroller.size = Vector2(size.x,18)
		scroller.max_value = maxf(size.x,content_width())
		scroller.page = size.x
		scroller.visible = scroller.max_value > size.x
	elif is_instance_valid(scroller):
		scroller.visible = false

func _on_view_pressed(view: Button) -> void:
	var pressed_uid := int(view.get_meta("mobile_uid", -1))
	if view.block_activation:
		return
	if mobile_mode and drag_distance > 12:
		return
	if mobile_mode and focused_uid != pressed_uid:
		focused_uid = pressed_uid
		arrange()
	else:
		card_clicked.emit(pressed_uid)

func _on_view_preview(view: Button) -> void:
	preview_requested.emit(view.get_meta("preview_card", {}))

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
