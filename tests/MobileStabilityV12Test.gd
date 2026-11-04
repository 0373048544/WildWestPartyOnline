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
	var initial_nodes := count_nodes(hand)
	var initial_rebuilds: int = CARD_VIEW.visual_rebuilds
	var initial_arranges: int = HAND_FAN.arrange_calls
	var initial_views: Array = hand.cards.duplicate()
	hand.scroll_offset = 17.0

	var total_usec := 0
	var max_usec := 0
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
	hand._input(drag)
	dragged_view._process(0.5)
	var touch_up := InputEventScreenTouch.new()
	touch_up.index = 3
	touch_up.pressed = false
	touch_up.position = Vector2(20, 80)
	hand._input(touch_up)
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

	# A rematch/new deal may reuse numeric instance IDs. Card identity therefore
	# includes card_data_id/suit/rank and must replace every stale face in-place.
	var rematch_cards: Array = [
		make_card(12001, "drink"), make_card(12002, "jail"), make_card(12003, "gatling")
	]
	var rebuilds_before_rematch: int = CARD_VIEW.visual_rebuilds
	hand.configure(rematch_cards, [12001, 12002, 12003], [], false, {})
	expect(CARD_VIEW.visual_rebuilds == rebuilds_before_rematch + 3,
		"rematch with reused instance IDs must rebuild the three changed faces")
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
		var title: Label = title_view.visual.get_node("CardName") as Label
		var art: Control = title_view.visual.get_node("ArtworkFrame") as Control
		expect(title.visible and not title.text.is_empty(), "%s title must be visible" % card_id)
		expect(title.position.y + title.size.y <= art.position.y + 0.5, "%s header must not overlap artwork" % card_id)
		expect(title.max_lines_visible <= 2, "%s compact title must use at most two lines" % card_id)
		if title.text.length() <= 11:
			expect(title.get_minimum_size().x <= title.size.x + 0.5, "%s single-line title must fit its header" % card_id)
		title_view.queue_free()

	print("V12 PROFILE identical_hand_update avg_usec=", float(total_usec) / 50.0,
		" max_usec=", max_usec, " configure_calls=", HAND_FAN.configure_calls,
		" visual_rebuilds=", CARD_VIEW.visual_rebuilds, " arrange_calls=", HAND_FAN.arrange_calls,
		" stable_nodes=", initial_nodes)
	if failures.is_empty():
		print("PASS: ", checks, " mobile snapshot reuse, gesture, title and signal checks")
		get_tree().quit(0)
	else:
		print("FAIL: ", failures.size(), "/", checks, " V12 checks")
		get_tree().quit(1)
