extends Node

const HAND_FAN = preload("res://scripts/ui/HandFan.gd")
const CARD_VIEW = preload("res://scripts/ui/CardView.gd")

var checks: int = 0
var failures: Array[String] = []
var click_count: int = 0
var preview_count: int = 0

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("V12 FAIL: " + message)

func make_card(uid: int, id: String) -> Dictionary:
	return CardInstance.make(uid, id, "HEART", 7)

func count_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += count_nodes(child)
	return total

func _ready() -> void:
	get_window().size = Vector2i(390, 844)
	get_window().content_scale_size = Vector2i(600, 1298)
	get_viewport().set_meta("match_css_size", Vector2(390, 844))
	get_viewport().set_meta("match_force_mobile_device", true)
	get_viewport().set_meta("match_safe_insets", Vector4(8, 24, 8, 18))

	var hand: Control = HAND_FAN.new()
	hand.size = Vector2(600, 200)
	hand.set_meta("match_id", 1)
	add_child(hand)
	hand.card_clicked.connect(func(_uid: int): click_count += 1)
	hand.preview_requested.connect(func(_card: Dictionary): preview_count += 1)
	await get_tree().process_frame

	var cards: Array = [make_card(12001, "shoot"), make_card(12002, "dodge"), make_card(12003, "department_store")]
	var usable: Array = [12001, 12002, 12003]
	CARD_VIEW.configure_calls = 0
	CARD_VIEW.visual_rebuilds = 0
	HAND_FAN.configure_calls = 0
	HAND_FAN.arrange_calls = 0
	hand.configure(cards, usable, [], false, {})
	await get_tree().process_frame
	# Exercise Godot's real input dispatch order. Calling HandFan/CardView methods
	# directly cannot detect an _input() handler that consumes the event before
	# Controls receive _gui_input(). A clean viewport-dispatched tap must reach the
	# Button and emit exactly one card action.
	var dispatch_center: Vector2 = hand.cards[0].get_global_rect().get_center()
	var dispatch_down := InputEventScreenTouch.new()
	dispatch_down.index = 19
	dispatch_down.pressed = true
	dispatch_down.position = dispatch_center
	Input.parse_input_event(dispatch_down)
	await get_tree().process_frame
	var dispatch_up := InputEventScreenTouch.new()
	dispatch_up.index = 19
	dispatch_up.pressed = false
	dispatch_up.position = dispatch_center
	Input.parse_input_event(dispatch_up)
	await get_tree().process_frame
	expect(click_count == 1, "viewport-dispatched mobile tap must emit exactly one card intent")
	click_count = 0
	# The same real dispatch path must classify a horizontal gesture as scroll,
	# cancel CardView's hold, and suppress the Button activation on release.
	dispatch_down.index = 20
	dispatch_down.pressed = true
	dispatch_down.position = dispatch_center
	Input.parse_input_event(dispatch_down)
	await get_tree().process_frame
	var dispatch_drag := InputEventScreenDrag.new()
	dispatch_drag.index = 20
	dispatch_drag.position = dispatch_center + Vector2(-80.0, 0.0)
	dispatch_drag.relative = Vector2(-80.0, 0.0)
	Input.parse_input_event(dispatch_drag)
	await get_tree().process_frame
	dispatch_up.index = 20
	dispatch_up.position = dispatch_drag.position
	Input.parse_input_event(dispatch_up)
	await get_tree().process_frame
	expect(click_count == 0, "viewport-dispatched drag must not emit a card intent")
	expect(preview_count == 0, "viewport-dispatched drag must not open a preview")
	# Long press is also verified through Viewport dispatch rather than private
	# helper calls: one preview, no card action when the finger is released.
	var hold_center: Vector2 = hand.cards[1].get_global_rect().get_center()
	dispatch_down.index = 21
	dispatch_down.position = hold_center
	Input.parse_input_event(dispatch_down)
	await get_tree().create_timer(0.48).timeout
	dispatch_up.index = 21
	dispatch_up.position = hold_center
	Input.parse_input_event(dispatch_up)
	await get_tree().process_frame
	expect(preview_count == 1, "viewport-dispatched long press must open exactly one preview")
	expect(click_count == 0, "viewport-dispatched long press must not emit a card intent")
	preview_count = 0
	var initial_nodes := count_nodes(hand)
	var initial_rebuilds: int = CARD_VIEW.visual_rebuilds
	var initial_arranges: int = HAND_FAN.arrange_calls
	var initial_views: Array = hand.cards.duplicate()
	hand.scroll_offset = 17.0

	var total_usec := 0
	var max_usec := 0
	var drag_profile_usec := 0
	for _index in range(50):
		var started := Time.get_ticks_usec()
		hand.configure(cards, usable, [], false, {})
		var elapsed := int(Time.get_ticks_usec() - started)
		total_usec += elapsed
		max_usec = maxi(max_usec, elapsed)

	expect(CARD_VIEW.visual_rebuilds == initial_rebuilds, "identical snapshots must not rebuild card visual trees")
	expect(HAND_FAN.arrange_calls == initial_arranges, "identical snapshots must not rearrange the hand")
	expect(is_equal_approx(hand.scroll_offset, 17.0), "identical snapshots must preserve scroll offset")
	expect(count_nodes(hand) == initial_nodes, "identical snapshots must keep the UI node count stable")
	for index in range(initial_views.size()):
		expect(hand.cards[index] == initial_views[index], "card nodes must be reused at index %d" % index)
		expect(hand.cards[index].pressed.get_connections().size() == 1, "pressed signal must not be duplicated at index %d" % index)
		expect(hand.cards[index].preview_requested.get_connections().size() == 1, "preview signal must not be duplicated at index %d" % index)

	# Safari collapses/expands its toolbar by changing CSS height only. Exercise a
	# genuinely scrollable ten-card hand so the preserved offset is valid.
	var resize_hand: Control = HAND_FAN.new()
	resize_hand.size = Vector2(600, 200)
	resize_hand.set_meta("match_id", 1)
	add_child(resize_hand)
	var resize_cards: Array = []
	var resize_usable: Array = []
	for index in range(10):
		resize_cards.append(make_card(12500 + index, "shoot"))
		resize_usable.append(12500 + index)
	resize_hand.configure(resize_cards, resize_usable, [], false, {})
	resize_hand.scroll_offset = 100.0
	resize_hand.arrange()
	var valid_offset_before_height_change: float = resize_hand.scroll_offset
	get_viewport().set_meta("match_css_size", Vector2(390, 760))
	resize_hand.configure(resize_cards, resize_usable, [], false, {})
	expect(is_equal_approx(resize_hand.scroll_offset, valid_offset_before_height_change),
		"height-only Safari resize must preserve a valid scroll offset")
	get_viewport().set_meta("match_css_size", Vector2(390, 844))
	var profile_touch := InputEventScreenTouch.new()
	profile_touch.index = 11
	profile_touch.pressed = true
	profile_touch.position = Vector2(300, 80)
	resize_hand._input(profile_touch)
	var profile_arranges_before: int = HAND_FAN.arrange_calls
	var drag_started: int = Time.get_ticks_usec()
	for step in range(120):
		var profile_drag := InputEventScreenDrag.new()
		profile_drag.index = 11
		profile_drag.position = Vector2(300 - step, 80)
		profile_drag.relative = Vector2(-1, 0)
		resize_hand._input(profile_drag)
	drag_profile_usec = int(Time.get_ticks_usec() - drag_started)
	expect(HAND_FAN.arrange_calls == profile_arranges_before,
		"120 ten-card drag events must not run layout inside the event loop")
	await get_tree().process_frame
	expect(HAND_FAN.arrange_calls == profile_arranges_before + 1,
		"120 ten-card drag events must produce one layout on the next frame")
	profile_touch.pressed = false
	resize_hand._input(profile_touch)
	resize_hand.scroll_offset = 9999.0
	resize_hand.size.x = 320.0
	await get_tree().process_frame
	var resized_max_scroll: float = maxf(0.0, resize_hand.content_width() - resize_hand.size.x)
	expect(resize_hand.scroll_offset >= 0.0 and resize_hand.scroll_offset <= resized_max_scroll + 0.5,
		"width resize must clamp scroll offset to the valid content range")
	resize_hand.queue_free()

	# Playability is dynamic and must update without rebuilding card content.
	var rebuilds_before_playability: int = CARD_VIEW.visual_rebuilds
	hand.configure(cards, [12001, 12003], [], false, {12002: "Không thể dùng"})
	expect(CARD_VIEW.visual_rebuilds == rebuilds_before_playability,
		"playable-state changes must not rebuild card visual trees")
	expect(hand.cards[1].disabled and str(hand.cards[1].get_meta("disabled_reason", "")) == "Không thể dùng",
		"playable-state changes must update disabled state and reason")
	hand.configure(cards, usable, [], false, {})

	# Selection is dynamic state: it may arrange/lift the card, but it must not
	# reconstruct artwork, labels, textures, or signal connections.
	var rebuilds_before_selection: int = CARD_VIEW.visual_rebuilds
	hand.configure(cards, usable, [12002], false, {})
	expect(CARD_VIEW.visual_rebuilds == rebuilds_before_selection,
		"selection changes must not rebuild card visual trees")
	expect(bool(hand.cards[1].get_meta("chosen_card", false)),
		"selection changes must update the chosen card")
	expect(hand.cards[1] == initial_views[1], "selection must preserve the selected node identity")
	hand.configure(cards, usable, [], false, {})

	# A horizontal drag owns the gesture, scrolls the hand, and cannot play a card.
	var touch_down := InputEventScreenTouch.new()
	touch_down.index = 3
	touch_down.pressed = true
	touch_down.position = Vector2(60, 80)
	hand._input(touch_down)
	var foreign_drag := InputEventScreenDrag.new()
	foreign_drag.index = 4
	foreign_drag.position = Vector2(10, 80)
	foreign_drag.relative = Vector2(-50, 0)
	var scroll_before_foreign_drag: float = hand.scroll_offset
	hand._input(foreign_drag)
	expect(is_equal_approx(hand.scroll_offset, scroll_before_foreign_drag),
		"a second finger must not control the active hand gesture")
	expect(hand.touch_index == 3, "the first finger must keep gesture ownership")
	var drag := InputEventScreenDrag.new()
	drag.index = 3
	drag.position = Vector2(20, 80)
	drag.relative = Vector2(-40, 0)
	var dragged_view: Button = hand.cards[0]
	dragged_view._press_started()
	var arranges_before_drag_events: int = HAND_FAN.arrange_calls
	hand._input(drag)
	for step in range(4):
		drag.position.x -= 8.0
		drag.relative = Vector2(-8.0, 0.0)
		hand._input(drag)
	expect(HAND_FAN.arrange_calls == arranges_before_drag_events,
		"rapid drag events must defer geometry instead of arranging per event")
	dragged_view._process(0.5)
	var touch_up := InputEventScreenTouch.new()
	touch_up.index = 3
	touch_up.pressed = false
	touch_up.position = Vector2(20, 80)
	hand._input(touch_up)
	await get_tree().process_frame
	expect(HAND_FAN.arrange_calls == arranges_before_drag_events + 1,
		"rapid drag events must coalesce to one arrange in the next frame")
	hand._on_view_pressed(hand.cards[0])
	expect(click_count == 0, "horizontal drag must not emit a card intent")
	expect(preview_count == 0, "horizontal drag must cancel long-press preview")
	expect(not hand.dragging, "drag state must end on touch release")
	expect(hand.touch_index == -1, "touch ownership must end on owner release")

	# A clean tap remains a one-tap card intent.
	hand.cards[0]._press_started()
	touch_down.position = Vector2(60, 80)
	hand._input(touch_down)
	touch_up.position = Vector2(60, 80)
	hand._input(touch_up)
	hand.cards[0]._press_ended()
	hand._on_view_pressed(hand.cards[0])
	expect(click_count == 1, "tap must emit exactly one card intent")

	# Long press emits one preview and blocks the subsequent Button activation.
	var view: Button = hand.cards[1]
	view._press_started()
	view._process(0.46)
	view._process(0.46)
	view._press_ended()
	hand._on_view_pressed(view)
	expect(preview_count == 1, "long press must emit exactly one preview")
	expect(click_count == 1, "long press release must not emit a card intent")

	# Modal/scene transitions synchronously release both HandFan and CardView
	# ownership so no hidden hold can fire after the HUD becomes visible again.
	hand.cards[0]._press_started()
	hand._input(touch_down)
	hand.cancel_active_gesture()
	expect(hand.touch_index == -1 and not hand.dragging and not hand.cards[0].holding,
		"modal cleanup must release hand and card gesture ownership")
	hand.cards[0]._process(0.5)
	expect(preview_count == 1, "cleaned-up modal gesture must not open another preview")

	# A rematch/new deal may reuse numeric instance IDs. Card identity therefore
	# includes card_data_id/suit/rank and must replace every stale face in-place.
	var rematch_cards: Array = [
		make_card(12001, "drink"), make_card(12002, "jail"), make_card(12003, "gatling")
	]
	var rebuilds_before_rematch: int = CARD_VIEW.visual_rebuilds
	hand.scroll_offset = 25.0
	hand.set_meta("match_id", 2)
	hand.configure(rematch_cards, [12001, 12002, 12003], [], false, {})
	expect(CARD_VIEW.visual_rebuilds == rebuilds_before_rematch + 3,
		"rematch with reused instance IDs must rebuild the three changed faces")
	expect(is_zero_approx(hand.scroll_offset), "new match must reset the previous match scroll offset")
	for index in range(rematch_cards.size()):
		expect(hand.cards[index] == initial_views[index], "rematch should reuse card nodes at index %d" % index)
		expect(str(hand.cards[index].get_meta("preview_card", {}).get("card_data_id", "")) == str(rematch_cards[index].card_data_id),
			"rematch must not retain the previous card at index %d" % index)

	# Required Vietnamese titles use the single real CardName label and remain
	# above the artwork in the compact touch profile.
	for card_id in ["shoot", "dodge", "drink", "department_store", "gatling", "barrel", "spyglass", "panic"]:
		var definition: Dictionary = CardData.data(card_id)
		expect(not definition.is_empty(), "%s definition must exist" % card_id)
		var title_view: Button = load("res://scenes/ui/CardUI.tscn").instantiate()
		add_child(title_view)
		title_view.configure(make_card(13000 + checks, card_id), definition, true, false)
		title_view.compact(false, false)
		title_view.touch_compact(load("res://scripts/ui/MatchLayout.gd").touch_card_width(title_view))
		var header: Control = title_view.visual.get_node("HeaderRegion") as Control
		var title: Label = header.get_node("CardName") as Label
		var corner: Label = header.get_node("RankSuitCorner") as Label
		var art: Control = title_view.visual.get_node("ArtworkFrame") as Control
		var type_region: Control = title_view.visual.get_node("TypeRegion") as Control
		expect(title.visible and not title.text.is_empty(), "%s title must be visible" % card_id)
		expect(not header.get_rect().intersects(art.get_rect()), "%s header must not overlap artwork" % card_id)
		expect(not art.get_rect().intersects(type_region.get_rect()), "%s artwork must not overlap card type" % card_id)
		expect(title.max_lines_visible == 1 and title.clip_text, "%s compact title must use controlled single-line ellipsis" % card_id)
		expect(not title.get_rect().intersects(corner.get_rect()), "%s title must not overlap rank/suit" % card_id)
		expect(title_view.visual.find_children("CardName", "Label", true, false).size() == 1, "%s must have one title renderer" % card_id)
		title_view.queue_free()

	print("V12 PROFILE identical_hand_update avg_usec=", float(total_usec) / 50.0,
		" max_usec=", max_usec, " configure_calls=", HAND_FAN.configure_calls,
		" visual_rebuilds=", CARD_VIEW.visual_rebuilds, " arrange_calls=", HAND_FAN.arrange_calls,
		" stable_nodes=", initial_nodes, " drag_120_events_usec=", drag_profile_usec)
	if failures.is_empty():
		print("PASS: ", checks, " mobile snapshot reuse, gesture, title and signal checks")
		get_tree().quit(0)
	else:
		print("FAIL: ", failures.size(), "/", checks, " V12 checks")
		get_tree().quit(1)
