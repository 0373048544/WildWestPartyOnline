extends Control

signal card_clicked(uid: int)
signal preview_requested(card: Dictionary)
signal preview_closed

var cards: Array[Button] = []
var mobile_mode: bool = false
var focused_uid: int = -1
var scroll_offset: float = 0.0
var drag_origin := Vector2.ZERO
var dragging: bool = false
var touch_index: int = -1
var drag_distance: float = 0.0
var mobile_lift: float = 0.0
var scroller: HScrollBar
var configured_size := Vector2.ZERO
var layout_signature: String = ""
var gesture_was_drag: bool = false
var configured_match_id: int = -1
var hand_content_signature: String = ""
var scroll_layout_pending: bool = false

static var configure_calls: int = 0
static var arrange_calls: int = 0

var layout: Script = preload("res://scripts/ui/MatchLayout.gd")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(arrange)
	set_process(false)


func _exit_tree() -> void:
	cancel_active_gesture(false)


func configure(
	hand: Array,
	usable: Array,
	selected: Array,
	reactions: bool = false,
	reasons: Dictionary = {}
) -> void:
	configure_calls += 1
	var current_css_size: Vector2 = layout.css_size(self)
	var next_match_id: int = int(get_meta("match_id", -1))
	var next_hand_content_signature := str(hand.map(func(card): return [
		int(card.get("instance_id", -1)), str(card.get("card_data_id", "")),
		str(card.get("suit", "")), int(card.get("rank", 0))
	]))
	var match_changed: bool = configured_match_id >= 0 and next_match_id != configured_match_id
	var hand_content_changed: bool = (
		not hand_content_signature.is_empty()
		and next_hand_content_signature != hand_content_signature
	)
	if match_changed:
		focused_uid = -1
		scroll_offset = 0.0
		layout_signature = ""
	if match_changed or hand_content_changed:
		cancel_active_gesture()
	configured_match_id = next_match_id
	hand_content_signature = next_hand_content_signature
	# Safari's address bar changes CSS height while the hand and its width stay
	# the same. Preserve the user's position and let arrange() clamp only when
	# the actual available width/content range changes.
	configured_size = current_css_size

	var was_mobile_mode: bool = mobile_mode
	mobile_mode = bool(layout.mobile(self))
	if was_mobile_mode and not mobile_mode:
		cancel_active_gesture()

	var existing: Dictionary = {}

	for old_view in cards:
		if is_instance_valid(old_view):
			existing[int(old_view.get_meta("mobile_uid", -1))] = old_view

	cards.clear()

	if mobile_mode:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		mobile_lift = float(
			layout.hand_lift(
				self,
				bool(get_meta("target_mode", false))
			)
		)
	else:
		clip_contents = false
		mobile_lift = 0.0

	for card in hand:
		var uid: int = int(card.instance_id)
		var view: Button = existing.get(uid)

		if is_instance_valid(view):
			existing.erase(uid)
		else:
			view = load("res://scenes/ui/CardUI.tscn").instantiate()
			add_child(view)

			view.pressed.connect(
				_on_view_pressed.bind(view)
			)

			view.preview_requested.connect(
				_on_view_preview.bind(view)
			)

			view.preview_closed.connect(
				func():
					preview_closed.emit()
			)
		if not mobile_mode and bool(view.touch_layout):
			# Rebuild only when crossing back to the desktop layout profile; touch
			# cards use deliberate line breaks and different artwork geometry.
			view.content_signature = ""

		view.set_meta("mobile_uid", uid)
		view.set_meta("preview_card", card)

		view.configure(
			card,
			CardData.data(card.card_data_id),
			usable.has(card.instance_id),
			selected.has(card.instance_id),
			str(reasons.get(card.instance_id, ""))
		)

		view.compact(
			selected.has(card.instance_id),
			reactions and usable.has(card.instance_id)
		)

		if mobile_mode:
			var touch_width: float = minf(
				size.x,
				float(layout.touch_card_width(self))
			)
			view.touch_compact(touch_width)

		cards.append(view)

	for stale in existing.values():
		if is_instance_valid(stale):
			stale.queue_free()

	var ordered_uids: Array[int] = []
	for card_view in cards:
		ordered_uids.append(int(card_view.get_meta("mobile_uid", -1)))
	var next_layout_signature := str([
		ordered_uids, selected, mobile_mode, size, mobile_lift,
		float(layout.touch_card_width(self)) if mobile_mode else 158.0
	])
	if focused_uid not in ordered_uids:
		focused_uid = -1
	if next_layout_signature != layout_signature:
		layout_signature = next_layout_signature
		arrange()
		_configure_scrollbar()


func _configure_scrollbar() -> void:
	if mobile_mode:
		if not is_instance_valid(scroller):
			scroller = HScrollBar.new()
			scroller.name = "HandScroll"

			scroller.value_changed.connect(
				func(value):
					scroll_offset = float(value)
					arrange()
			)

			add_child(scroller)
			scroller.z_index = 300

		var bar_height: float = float(
			layout.hand_scrollbar_height(self)
		)

		scroller.position = Vector2(
			0.0,
			maxf(0.0, size.y - bar_height)
		)

		scroller.size = Vector2(
			size.x,
			bar_height
		)

		scroller.max_value = maxf(
			size.x,
			content_width()
		)

		scroller.page = size.x
		scroller.visible = scroller.max_value > size.x + 1.0
	else:
		if is_instance_valid(scroller):
			scroller.visible = false


func _on_view_pressed(view: Button) -> void:
	var pressed_uid: int = int(
		view.get_meta("mobile_uid", -1)
	)

	if view.block_activation:
		# Long press was used to inspect the card.
		return

	if mobile_mode:
		# A horizontal drag scrolls the hand and must never play a card.
		if gesture_was_drag or drag_distance > float(layout.drag_threshold(self)):
			return

		# Mobile interaction is intentionally one-tap:
		# tap = select/play, hold = preview, drag = scroll.
		focused_uid = pressed_uid
		card_clicked.emit(pressed_uid)
		return

	card_clicked.emit(pressed_uid)


func _on_view_preview(view: Button) -> void:
	preview_requested.emit(
		view.get_meta("preview_card", {})
	)


func card_spacing() -> float:
	var width: float = (
		cards[0].size.x
		if not cards.is_empty()
		else 158.0
	)

	var minimum: float = (
		float(layout.units(self, 42.0))
		if mobile_mode
		else 48.0
	)

	if cards.size() <= 1:
		return width

	var visible_target: int = (
		3 if layout.mobile_portrait(self)
		else (5 if layout.mobile_landscape(self) else 4)
	)

	return clampf(
		(size.x - width)
		/ maxf(
			1.0,
			float(mini(visible_target, cards.size()) - 1)
		),
		minimum,
		maxf(minimum, width * (0.92 if layout.mobile_landscape(self) else 0.82))
	)


func content_width() -> float:
	if cards.is_empty():
		return 0.0

	return cards[0].size.x + card_spacing() * float(cards.size() - 1)


func arrange() -> void:
	arrange_calls += 1
	if cards.is_empty():
		if is_instance_valid(scroller):
			scroller.visible = false
		return

	if mobile_mode:
		var spacing: float = card_spacing()
		var total: float = content_width()

		scroll_offset = clampf(
			scroll_offset,
			0.0,
			maxf(0.0, total - size.x)
		)

		var start_x: float = maxf(
			0.0,
			(size.x - total) / 2.0
		)

		for index in range(cards.size()):
			var card: Button = cards[index]

			var selected_card: bool = bool(
				card.get_meta("chosen_card", false)
			)

			var card_y: float = (
				0.0
				if selected_card
				else mobile_lift
			)

			card.position = Vector2(
				start_x
				+ float(index) * spacing
				- scroll_offset,
				card_y
			)

			card.rotation = 0.0
			card.z_index = 100 if selected_card else index

			# Keep a small margin so cards remain touchable near both edges.
			card.visible = (
				card.position.x + card.size.x > -8.0
				and card.position.x < size.x + 8.0
			)

		if is_instance_valid(scroller):
			var bar_height: float = float(
				layout.hand_scrollbar_height(self)
			)

			scroller.position = Vector2(
				0.0,
				maxf(0.0, size.y - bar_height)
			)

			scroller.size = Vector2(
				size.x,
				bar_height
			)

			scroller.max_value = maxf(
				size.x,
				total
			)

			scroller.page = size.x
			scroller.set_value_no_signal(scroll_offset)
			scroller.visible = total > size.x + 1.0

		# Clip only when the allocated hand really contains the full card and the
		# thin scrollbar. If browser scaling briefly reports a smaller height,
		# showing the complete card is preferable to cutting its interaction area.
		var tallest_card: float = 0.0
		for card_view in cards:
			tallest_card = maxf(tallest_card, card_view.size.y)
		var required_height: float = (
			tallest_card
			+ mobile_lift
			+ float(layout.hand_scrollbar_height(self))
		)
		clip_contents = size.y + 0.5 >= required_height

		return

	var gap: float = minf(
		136.0,
		maxf(
			18.0,
			(size.x - 158.0)
			/ maxf(
				1.0,
				float(cards.size() - 1)
			)
		)
	)

	var width: float = (
		158.0
		+ gap * float(cards.size() - 1)
	)

	for index in range(cards.size()):
		var view: Button = cards[index]

		var fraction: float = (
			float(index)
			/ maxf(
				1.0,
				float(cards.size() - 1)
			)
			- 0.5
		)

		view.position = Vector2(
			(size.x - width) / 2.0
			+ float(index) * gap,
			absf(fraction) * 7.0
			- 6.0
		)

		view.rotation = (
			fraction * 0.055
			- (
				0.06
				if bool(
					view.get_meta(
						"chosen_card",
						false
					)
				)
				else 0.0
			)
		)

		view.pivot_offset = Vector2(
			79.0,
			158.0
		)

		view.z_index = index


func _input(event: InputEvent) -> void:
	if not mobile_mode:
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			# A gesture keeps one owner from press through release. Ignore other
			# fingers until that owner's gesture finishes.
			if touch_index < 0 and get_global_rect().has_point(event.position):
				touch_index = event.index
				drag_origin = event.position
				dragging = true
				drag_distance = 0.0
				gesture_was_drag = false
				get_viewport().set_input_as_handled()
		elif event.index == touch_index:
			if dragging:
				get_viewport().set_input_as_handled()
			_cancel_touch_gesture(false)

	elif event is InputEventScreenDrag and dragging and event.index == touch_index:
		drag_distance = maxf(
			drag_distance,
			absf(event.position.x - drag_origin.x)
		)
		if not gesture_was_drag and drag_distance > float(layout.drag_threshold(self)):
			gesture_was_drag = true
			for card_view in cards:
				if is_instance_valid(card_view) and card_view.has_method("cancel_touch_hold_for_drag"):
					card_view.cancel_touch_hold_for_drag()

		# Offset follows every event, while geometry is coalesced to one update per
		# rendered frame. Browsers may deliver touch events faster than frame rate.
		scroll_offset -= event.relative.x
		scroll_layout_pending = true
		set_process(true)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if scroll_layout_pending:
		scroll_layout_pending = false
		arrange()
	set_process(false)


func _cancel_touch_gesture(clear_classification: bool = true) -> void:
	touch_index = -1
	dragging = false
	drag_distance = 0.0 if clear_classification else drag_distance
	if clear_classification:
		gesture_was_drag = false


func cancel_active_gesture(close_preview: bool = true) -> void:
	for card_view in cards:
		if is_instance_valid(card_view) and card_view.has_method("cancel_touch_hold_for_drag"):
			card_view.cancel_touch_hold_for_drag()
	_cancel_touch_gesture()
	if scroll_layout_pending:
		scroll_layout_pending = false
		arrange()
	set_process(false)
	if close_preview:
		preview_closed.emit()
