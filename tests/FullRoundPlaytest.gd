extends Node

class PlaytestNetwork:
	extends Node
	var owner_test: Node
	var session_port := 7000
	var sequence := 0
	var public_events: Array = []
	var private_events: Dictionary = {}
	func is_authority() -> bool: return true
	func host_player_id() -> int: return 1
	func is_room_host(id: int) -> bool: return id == 1
	func publish_game(game: Node) -> void:
		NetworkManager.receive_public(game.public_snapshot())
		NetworkManager.receive_private(game.private_snapshot(1))
	func broadcast_animation(actor: int, kind: String, target: int = 0) -> void:
		broadcast_table_event({"kind":"animation", "actor":actor, "animation":kind, "target":target})
	func _stamp(event: Dictionary) -> Dictionary:
		sequence += 1
		var copy := event.duplicate(true)
		copy["audio_event_id"] = "full-round:%d:%d" % [GameManager.match_id, sequence]
		copy["event_id"] = copy.audio_event_id
		return copy
	func broadcast_table_event(event: Dictionary) -> void:
		var stamped := _stamp(event)
		public_events.append(stamped.duplicate(true))
		NetworkManager.receive_table_event(stamped)
	func send_private_event(id: int, event: Dictionary) -> void:
		var stamped := _stamp(event)
		if not private_events.has(id): private_events[id] = []
		private_events[id].append(stamped.duplicate(true))
		if id == 1: NetworkManager.receive_table_event(stamped)
	func send_notice(id: int, message: String) -> void:
		if id == 1: NetworkManager.notice(message)

var checks := 0
var failures: Array[String] = []
var app: Node
var net: PlaytestNetwork
var played_audio: Array[String] = []
var capture_enabled := false
var artifact_dir := "res://tests/artifacts/full-round"

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("FULL ROUND FAILED: " + message)

func settle(seconds: float = 0.14) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().physics_frame

func wait_for_audio_count(cue: String, expected: int, timeout: float = 4.0) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while played_audio.count(cue) < expected and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

func drain_presentation(timeout: float = 5.0) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var table_done: bool = not is_instance_valid(app) or not is_instance_valid(app.table) or (app.table.presentation_queue.is_empty() and app.table.presentation_wait <= 0.0)
		if table_done and AudioManager.pending.is_empty():
			break
		await get_tree().process_frame
	await settle(0.08)

func screenshot(layout_name: String, state_name: String) -> void:
	if not capture_enabled:
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s-%s.png" % [artifact_dir, layout_name, state_name])

func take_card(id: int, card_id: String) -> Dictionary:
	for index in range(GameManager.deck.draw_pile.size()):
		var card: Dictionary = GameManager.deck.draw_pile[index]
		if str(card.card_data_id) == card_id:
			GameManager.deck.draw_pile.remove_at(index)
			GameManager.players[id].hand.append(card)
			return card
	check(false, "physical deck contains required card " + card_id)
	return {}

func return_all_hands_to_deck() -> void:
	for player in GameManager.players.values():
		GameManager.deck.draw_pile.append_array(player.hand)
		player.hand.clear()
	GameManager.deck.draw_pile.shuffle()

func all_zone_cards() -> Array:
	var cards: Array = []
	cards.append_array(GameManager.deck.draw_pile)
	cards.append_array(GameManager.deck.discard_pile)
	cards.append_array(GameManager.flow.market)
	for player in GameManager.players.values():
		cards.append_array(player.hand)
		if not player.weapon.is_empty(): cards.append(player.weapon)
		cards.append_array(player.equipment.values())
		if not player.dynamite.is_empty():
			cards.append(player.dynamite)
	return cards

func verify_physical_cards(label: String) -> void:
	var cards := all_zone_cards()
	var ids: Dictionary = {}
	for card in cards:
		var uid := int(card.get("instance_id", -1))
		check(uid > 0, label + ": every physical card has an ID")
		check(not ids.has(uid), label + ": no duplicated physical card ID %d" % uid)
		ids[uid] = true
	check(cards.size() == 86, "%s: exactly 86 cards remain across all authoritative zones (actual %d)" % [label, cards.size()])

func visible_buttons(node: Node) -> Array:
	var result: Array = []
	if node is Button and node.visible:
		result.append(node)
	for child in node.get_children():
		result.append_array(visible_buttons(child))
	return result

func check_ui_bounds(label: String) -> void:
	var viewport_rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	for button in visible_buttons(app.root):
		var rect: Rect2 = button.get_global_rect()
		check(rect.size.x >= 1 and rect.size.y >= 1, label + ": visible button has non-zero layout")
		check(viewport_rect.intersects(rect), label + ": visible button remains reachable in viewport: " + button.text)
	if is_instance_valid(app.match_hud) and is_instance_valid(app.match_hud.hand):
		var hand_rect: Rect2 = app.match_hud.hand.get_global_rect()
		check(viewport_rect.intersects(hand_rect), label + ": hand remains in viewport")
		for card in app.match_hud.hand.cards:
			check(hand_rect.grow(3).intersects(card.get_global_rect()), label + ": hand card remains inside usable hand area")
	if is_instance_valid(app.reaction_banner) and app.reaction_banner.visible:
		var banner_rect: Rect2 = app.reaction_banner.get_node("Banner").get_global_rect()
		check(not banner_rect.intersects(app.match_hud.hand.get_global_rect()), label + ": reaction banner does not overlap hand")

func find_card_button(card_name: String) -> Button:
	if not is_instance_valid(app.overlay):
		return null
	for candidate in app.overlay.find_children("*", "Button", true, false):
		var name_node: Node = candidate.find_child("CardName", true, false)
		if name_node and str(name_node.text) == card_name:
			return candidate
	return null

func press_button_text(text_value: String) -> bool:
	if not is_instance_valid(app.overlay): return false
	for button in app.overlay.find_children("*", "Button", true, false):
		if button.text == text_value and button.visible and not button.disabled:
			button.pressed.emit()
			return true
	return false

func setup_round() -> Dictionary:
	GameManager.clear()
	net.public_events.clear()
	net.private_events.clear()
	played_audio.clear()
	for id in range(1, 5):
		GameManager.add_player(id, "Cao bồi %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()
	for id in GameManager.players:
		GameManager.selection.choose(GameManager, id, GameManager.selection.options[id][0])
	# Character selection dealt opening hands and began a turn. A randomly chosen
	# draw ability (notably Kit Carlson) may already have reserved cards inside a
	# pending choice job, so collecting hands alone is not a complete reset. Rebuild
	# the physical deck before constructing the deterministic round fixture.
	check(GameManager.deck.reset(), "full-round fixture rebuilds the 86-card deck")
	for card in GameManager.deck.draw_pile:
		card.instance_id += GameManager.match_id * 1000
	GameManager.deck.next_id += GameManager.match_id * 1000
	GameManager.flow.jobs.clear()
	GameManager.flow.market.clear()
	GameManager.reactions.active = {}
	for id in GameManager.players:
		var p: PlayerState = GameManager.players[id]
		p.hand.clear()
		p.weapon = {}
		p.equipment.clear()
		p.ability_id = ""
		p.max_hp = 4
		p.current_hp = 4
		p.role = PlayerState.Role.OUTLAW
		p.shoot_used_this_action_turn = false
	GameManager.players[1].role = PlayerState.Role.SHERIFF
	GameManager.players[4].role = PlayerState.Role.RENEGADE
	var cards := {
		"bang": take_card(2, "shoot"),
		"beer": take_card(2, "drink"),
		"tea": take_card(2, "iced_tea"),
		"store": take_card(2, "general_store"),
		"department": take_card(2, "department_store"),
		"panic_first": take_card(2, "panic"),
		"panic_stolen": take_card(3, "panic"),
		"dodge": take_card(1, "dodge"),
		"rescue_tea": take_card(1, "iced_tea"),
		"weapon": take_card(3, "winchester")
	}
	GameManager.players[3].hand.erase(cards.weapon)
	GameManager.players[3].weapon = cards.weapon
	GameManager.begin_turn(2)
	GameManager.publish()
	app.seen_role = GameManager.match_id
	app.menu_open = false
	app.refresh()
	return cards

func run_round(layout_name: String, viewport_size: Vector2i) -> void:
	get_window().size = viewport_size
	get_window().content_scale_size = viewport_size
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	get_viewport().set_meta("match_css_size", Vector2(viewport_size))
	get_viewport().set_meta("match_safe_insets", Vector4(10, 24, 10, 22) if layout_name != "desktop" else Vector4.ZERO)
	if is_instance_valid(app):
		app.queue_free()
		await get_tree().process_frame
	app = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	var cards := setup_round()
	await settle(0.32)
	check(GameManager.turns.current_player == 2 and GameManager.turns.phase == "ACTION_PHASE", layout_name + ": normal draw reaches player 2 action phase")
	check(GameManager.players[2].hand.size() == 8, layout_name + ": normal draw added exactly two cards to prepared six-card hand")
	check_ui_bounds(layout_name + " normal action")
	await screenshot(layout_name, "01-normal-action")
	verify_physical_cards(layout_name + " after draw")
	# Mobile-first chat stays above action/hand zones and releases input on close.
	var chat: ChatPanel = app.chat_panel
	check(chat.toggle_button.visible, layout_name + ": collapsed chat button is visible in active match")
	var journal_button: Button = app.match_hud.get_node("MatchLog").find_child("ToggleHistory", true, false)
	var journal_rect := journal_button.get_global_rect()
	var chat_button_rect := chat.toggle_button.get_global_rect()
	check(absf(chat_button_rect.position.y - journal_rect.position.y) <= 1.0 and chat_button_rect.position.x >= journal_rect.end.x,
		layout_name + ": collapsed Chat shares Journal's compact HUD row (chat=%s journal=%s)" % [chat_button_rect, journal_rect])
	check(chat_button_rect.size.is_equal_approx(journal_rect.size) and chat_button_rect.size.y >= load("res://scripts/ui/MatchLayout.gd").units(chat, 40.0),
		layout_name + ": Chat exactly matches Journal size and remains touch-friendly (chat=%s journal=%s)" % [chat_button_rect, journal_rect])
	chat.append_message({"message_id":"round:%s" % layout_name, "sender_id":3, "sender_name":"Cao Bồi Không Bao Giờ Ngủ", "text":"coi chừng ông bên trái 😂", "timestamp":1}, true)
	chat.open_chat()
	await settle(0.05)
	check(chat.panel.visible and not chat.panel.get_global_rect().intersects(app.match_hud.hand.get_global_rect()), layout_name + ": open chat does not cover hand")
	check(not chat.panel.get_global_rect().intersects(load("res://scripts/ui/MatchLayout.gd").action_rect(chat)), layout_name + ": open chat does not cover End Turn/action zone")
	if load("res://scripts/ui/MatchLayout.gd").mobile_portrait(chat):
		var usable: Rect2 = load("res://scripts/ui/MatchLayout.gd").safe_rect(chat)
		check(chat.panel.size.x <= usable.size.x * 0.82 + 1.0 and chat.panel.size.y <= usable.size.y * 0.32 + 1.0,
			layout_name + ": portrait chat stays within compact 82% × 32% envelope")
	await screenshot(layout_name, "01a-chat-open")
	chat.close_chat()
	check(not chat.panel.visible and chat.mouse_filter == Control.MOUSE_FILTER_IGNORE, layout_name + ": closed chat releases gameplay input")

	# BANG -> local compact reaction banner -> DODGE.
	chat.open_chat()
	GameManager.resolver.play(GameManager, 2, cards.bang.instance_id, 1)
	GameManager.publish()
	await settle()
	check(GameManager.reactions.active.get("reaction_type", "") == "dodge", layout_name + ": BANG opens authoritative dodge reaction")
	check(app.reaction_banner.visible and not app.reaction_banner.primary_button.disabled, layout_name + ": reaction banner exposes usable DÙNG NÉ")
	check(not chat.expanded and not chat.toggle_button.visible, layout_name + ": incoming BANG collapses chat below ReactionBanner")
	check(not is_instance_valid(app.overlay), layout_name + ": BANG does not open fullscreen modal")
	check_ui_bounds(layout_name + " BANG reaction")
	await screenshot(layout_name, "02-bang-dodge")
	app.reaction_banner.primary_button.pressed.emit()
	await settle(0.25)
	check(GameManager.reactions.active.is_empty() and GameManager.players[1].current_hp == 4, layout_name + ": DODGE clears reaction without damage")
	check(not app.reaction_banner.visible and not app.table.targeting.blocked, layout_name + ": reaction clears banner and input lock")

	# Custom Panic rule: the first Panic steals a second physical Panic, but the
	# newly received card remains disabled until this player's next action turn.
	chat.open_chat()
	GameManager.resolver.play(GameManager, 2, cards.panic_first.instance_id, 3)
	GameManager.publish()
	await settle(0.12)
	check(not chat.expanded, layout_name + ": Panic card-choice prompt auto-collapses chat")
	check(GameManager.reactions.active.get("reaction_type", "") == "transfer", layout_name + ": first Panic opens existing transfer chooser")
	check(GameManager.flow.resolve({"accept":true, "option":"hand"}), layout_name + ": Panic steals opponent's hidden hand card")
	GameManager.publish()
	await settle(0.12)
	check(GameManager.players[2].hand.has(cards.panic_stolen), layout_name + ": first Panic obtains opponent's second Panic")
	var panic_hand_before: int = GameManager.players[2].hand.size()
	var panic_discard_before: int = GameManager.deck.discard_pile.size()
	GameManager.resolver.play(GameManager, 2, cards.panic_stolen.instance_id, 3)
	check(GameManager.players[2].hand.size() == panic_hand_before and GameManager.deck.discard_pile.size() == panic_discard_before and GameManager.reactions.active.is_empty(),
		layout_name + ": authority rejects stolen Panic in same action turn without consuming it")
	check(GameManager.private_snapshot(2).disabled_reasons[cards.panic_stolen.instance_id] == "Bạn đã dùng HOẢNG LOẠN trong lượt hành động này.",
		layout_name + ": stolen Panic exposes exact disabled reason")

	# Successful tea, then rejected full-HP Beer must stay silent and remain in hand.
	GameManager.players[2].current_hp = 3
	var tea_drink_before: int = played_audio.count("iced_tea_drink")
	var heal_before: int = played_audio.count("heal")
	GameManager.resolver.play(GameManager, 2, cards.tea.instance_id, 2)
	GameManager.publish()
	await wait_for_audio_count("iced_tea_drink", tea_drink_before + 1)
	await wait_for_audio_count("heal", heal_before + 1)
	check(GameManager.players[2].current_hp == 4 and GameManager.find_card(2, cards.tea.instance_id).is_empty(), layout_name + ": TRÀ ĐÁ heals once and is consumed")
	check(played_audio.count("iced_tea_drink") == tea_drink_before + 1 and played_audio.count("heal") == heal_before + 1, layout_name + ": accepted TRÀ ĐÁ drink/heal audio plays once")
	check(app.table.special_presenter.banner.visible == false, layout_name + ": normal tea uses no oversized modal/banner")
	await screenshot(layout_name, "03-iced-tea-heal")
	await drain_presentation()
	var rejected_beer: int = played_audio.count("beer")
	var rejected_heal: int = played_audio.count("heal")
	var event_count := net.public_events.size()
	GameManager.resolver.play(GameManager, 2, cards.beer.instance_id, 2)
	GameManager.publish()
	await settle()
	check(not GameManager.find_card(2, cards.beer.instance_id).is_empty(), layout_name + ": rejected full-HP Beer stays in hand")
	check(net.public_events.size() == event_count and played_audio.count("beer") == rejected_beer and played_audio.count("heal") == rejected_heal, layout_name + ": rejected Beer emits no presentation/audio")

	# CỬA HÀNG order is 2 -> 3 -> 4 -> 1; local player uses real UI on final pick.
	GameManager.resolver.play(GameManager, 2, cards.store.instance_id, 2)
	GameManager.publish()
	await settle(0.08)
	check(GameManager.reactions.active.target_player_id == 2 and GameManager.flow.market.size() == 4, layout_name + ": Store opens four public cards for first picker 2")
	await screenshot(layout_name, "04-store-opened")
	var store_order: Array[int] = []
	for remote_id in [2, 3, 4]:
		store_order.append(int(GameManager.reactions.active.target_player_id))
		var selected: Dictionary = GameManager.flow.market[0]
		check(GameManager.flow.resolve({"accept":true, "cards":[selected.instance_id]}), layout_name + ": remote Store choice resolves")
		GameManager.publish()
		await settle(0.10)
	store_order.append(int(GameManager.reactions.active.target_player_id))
	check(store_order == [2, 3, 4, 1], layout_name + ": Store picker order remains 2→3→4→1")
	check(is_instance_valid(app.overlay), layout_name + ": local Store picker receives choice panel")
	check(app.match_hud.hand.visible == false, layout_name + ": choice panel hides hand instead of overlapping it")
	check_ui_bounds(layout_name + " Store choosing")
	await screenshot(layout_name, "05-store-player-choosing")
	var local_store_card: Dictionary = GameManager.flow.market[0]
	var store_button := find_card_button(str(CardData.data(local_store_card.card_data_id).name))
	check(is_instance_valid(store_button), layout_name + ": Store choice button exists with readable card name")
	if is_instance_valid(store_button): store_button.pressed.emit()
	await settle(0.25)
	check(GameManager.flow.market.is_empty() and GameManager.reactions.active.is_empty(), layout_name + ": Store finishes without stuck reaction")
	check(not is_instance_valid(app.overlay) and app.match_hud.hand.visible, layout_name + ": Store modal closes and hand/input returns")
	check(GameManager.players[2].general_store_used_this_match, layout_name + ": Store per-game limit recorded")
	verify_physical_cards(layout_name + " after Store")
	# A human Store selection lasts longer than its short accepted-card intro. Let
	# that presentation drain so the following Bách Hóa screenshot validates the
	# current state instead of an intentionally non-blocking previous animation.
	await drain_presentation()

	# BÁCH HÓA giver order is 3 -> 4 -> 1. Local final giver uses select+confirm UI.
	chat.open_chat()
	GameManager.resolver.play(GameManager, 2, cards.department.instance_id, 2)
	GameManager.publish()
	await settle(0.18)
	var wait_banner: Control = app.match_hud.get_node_or_null("CenterChoiceStatus") as Control
	check(not is_instance_valid(app.overlay), layout_name + ": non-giver Bách Hóa never receives a blocking modal")
	check(not chat.expanded and not chat.toggle_button.visible, layout_name + ": Bách Hóa auto-collapses chat for every player")
	check(is_instance_valid(wait_banner) and wait_banner.size.y <= load("res://scripts/ui/MatchLayout.gd").units(app.match_hud, 90),
		layout_name + ": non-giver Bách Hóa uses one compact wait banner")
	await screenshot(layout_name, "06a-department-non-giver-wait")
	var giver_order: Array[int] = []
	for remote_id in [3, 4]:
		giver_order.append(int(GameManager.reactions.active.target_player_id))
		var offered: Dictionary = GameManager.reactions.active.payload.cards[0]
		check(GameManager.flow.resolve({"accept":true, "cards":[offered.instance_id]}), layout_name + ": remote Bách Hóa give resolves")
		GameManager.publish()
		await settle(0.10)
	giver_order.append(int(GameManager.reactions.active.target_player_id))
	check(giver_order == [3, 4, 1], layout_name + ": Bách Hóa giver order remains 3→4→1")
	var give_panel: Control = app.match_hud.get_node_or_null("DepartmentStoreGivePanel") as Control
	check(not is_instance_valid(app.overlay) and is_instance_valid(give_panel), layout_name + ": local Bách Hóa giver receives compact non-modal panel")
	if is_instance_valid(give_panel):
		check(not give_panel.get_global_rect().intersects(app.match_hud.hand.get_global_rect()), "%s: compact Bách Hóa panel stays above the real hand panel=%s local=%s custom=%s min=%s scale=%s hand=%s" % [layout_name, give_panel.get_global_rect(), give_panel.size, give_panel.custom_minimum_size, give_panel.get_combined_minimum_size(), give_panel.scale, app.match_hud.hand.get_global_rect()])
	check_ui_bounds(layout_name + " Bách Hóa choosing")
	await screenshot(layout_name, "06-department-giver-choosing")
	var give_options: Array = GameManager.reactions.active.payload.cards
	var safe_give_options: Array = give_options.filter(func(card): return str(card.get("card_data_id", "")) != "iced_tea")
	var local_give: Dictionary = safe_give_options[0] if not safe_give_options.is_empty() else give_options[0]
	var local_give_name: String = str(CardData.data(local_give.card_data_id).name)
	var give_button: Button
	for card_view in app.match_hud.hand.cards:
		if int(card_view.get_meta("mobile_uid", -1)) == int(local_give.instance_id):
			give_button = card_view
			break
	check(is_instance_valid(give_button), layout_name + ": Bách Hóa card remains selectable in the real hand")
	if is_instance_valid(give_button): give_button.pressed.emit()
	await settle(0.05)
	give_panel = app.match_hud.get_node_or_null("DepartmentStoreGivePanel") as Control
	var confirm_give: Button = give_panel.get_node_or_null("Padding/Content/Actions/ConfirmGive") as Button if is_instance_valid(give_panel) else null
	check(is_instance_valid(confirm_give) and not confirm_give.disabled, layout_name + ": compact Bách Hóa confirmation button exists and is enabled")
	if is_instance_valid(confirm_give) and not confirm_give.disabled:
		confirm_give.pressed.emit()
	await settle(0.35)
	check(GameManager.reactions.active.is_empty() and not is_instance_valid(app.overlay) and not is_instance_valid(app.match_hud.get_node_or_null("DepartmentStoreGivePanel")), layout_name + ": Bách Hóa finishes without stuck panel/reaction")
	check(GameManager.players[2].department_store_used_this_action_turn, layout_name + ": Bách Hóa action-turn limit recorded")
	var public_transfers: Array = net.public_events.filter(func(e): return bool(e.get("department_store", false)) and e.get("kind", "") == "transfer")
	check(public_transfers.size() == 3 and public_transfers.all(func(e): return not e.has("card")), layout_name + ": public Bách Hóa transfers never leak identity")
	for giver in [3, 4, 1]:
		var exact_for_giver: Array = net.private_events.get(giver, []).filter(func(e): return e.get("kind", "") == "department_store_private")
		check(exact_for_giver.size() == 1 and exact_for_giver[0].has("card"), layout_name + ": exact card sent privately to giver %d" % giver)
	var receiver_exact: Array = net.private_events.get(2, []).filter(func(e): return e.get("kind", "") == "department_store_private")
	check(receiver_exact.size() == 3, layout_name + ": receiver privately receives exactly three identities")
	var local_private: Array = net.private_events.get(1, []).filter(func(e): return e.get("kind", "") == "department_store_private")
	if not local_private.is_empty():
		var toast_item: Dictionary = app.personal_toasts._event_item(local_private[0], 1, NetworkManager.public_state)
		check(str(toast_item.get("text", "")).contains(local_give_name) and str(toast_item.get("text", "")).contains("Cao bồi 2"), layout_name + ": personal notification names correct card and receiver")
	verify_physical_cards(layout_name + " after Bách Hóa")

	# Local dying prompt and TRÀ ĐÁ rescue.
	await drain_presentation()
	GameManager.players[1].current_hp = 1
	GameManager.damage(1, 2, 1)
	GameManager.publish()
	await settle(0.18)
	check(GameManager.reactions.active.get("reaction_type", "") == "survive", layout_name + ": lethal damage opens survive reaction")
	check(app.reaction_banner.visible and app.reaction_banner.primary_button.text.contains("TRÀ ĐÁ"), layout_name + ": dying banner exposes TRÀ ĐÁ rescue button")
	check_ui_bounds(layout_name + " dying prompt")
	await screenshot(layout_name, "07-dying-survive")
	app.reaction_banner.primary_button.pressed.emit()
	await settle(0.38)
	check(GameManager.players[1].is_alive and GameManager.players[1].current_hp == 1 and GameManager.reactions.active.is_empty(), layout_name + ": TRÀ ĐÁ rescue clears dying reaction")
	check(not app.reaction_banner.visible and not app.table.targeting.blocked, layout_name + ": rescue releases UI input")

	# Replaying the exact accepted tea event must not replay animation/audio.
	var tea_events: Array = net.public_events.filter(func(e): return e.get("kind", "") == "heal" and e.get("card_data_id", "") == "iced_tea")
	check(tea_events.size() == 2, layout_name + ": exactly normal and rescue tea heal events exist")
	if not tea_events.is_empty():
		await drain_presentation()
		# Sparse ambience is intentionally allowed to fire while this assertion is
		# running. Count only the semantic cues owned by the accepted tea event so
		# an unrelated wood creak/wind sample cannot masquerade as a duplicate.
		var tea_before_replay: int = played_audio.count("iced_tea_drink")
		var heal_before_replay: int = played_audio.count("heal")
		var seen_before: int = app.table.seen_presentation.size()
		NetworkManager.receive_table_event(tea_events[0])
		await settle(0.16)
		check(
			played_audio.count("iced_tea_drink") == tea_before_replay
			and played_audio.count("heal") == heal_before_replay
			and app.table.seen_presentation.size() == seen_before,
			layout_name + ": duplicate event replays neither audio nor animation"
		)

	# End turn, real discard phase if over hand limit, then next player's draw/action.
	GameManager.rate_limits.erase(2)
	GameManager.handle_intent(2, "end", {})
	GameManager.publish()
	await settle(0.12)
	check(GameManager.turns.phase in ["DISCARD_PHASE", "ACTION_PHASE"], layout_name + ": end intent reaches discard or next action state")
	await screenshot(layout_name, "08-end-turn")
	while GameManager.turns.current_player == 2 and GameManager.turns.phase == "DISCARD_PHASE":
		var discard_options: Array = GameManager.players[2].hand.filter(func(card): return card.instance_id != cards.panic_stolen.instance_id)
		var discard_card: Dictionary = discard_options[0] if not discard_options.is_empty() else GameManager.players[2].hand[0]
		GameManager.rate_limits.erase(2)
		GameManager.handle_intent(2, "discard", {"card":discard_card.instance_id})
	GameManager.publish()
	await settle(0.35)
	check(GameManager.turns.current_player == 3 and GameManager.turns.phase == "ACTION_PHASE", layout_name + ": next living player 3 starts normally after draw")
	check(GameManager.reactions.active.is_empty() and not is_instance_valid(app.overlay), layout_name + ": next turn has no stale reaction/modal")
	check(not GameManager.find_card(2, cards.store.instance_id).is_empty() == false, layout_name + ": played Store card is absent from hand")
	check(GameManager.players[3].weapon.get("card_data_id", "") == "winchester", layout_name + ": unrelated weapon state remains intact")
	check(GameManager.players[2].general_store_used_this_match, layout_name + ": Cửa Hàng per-game limit survives turn transition")
	check(GameManager.players[2].department_store_used_this_action_turn, layout_name + ": another player's turn does not reset Bách Hóa early")
	verify_physical_cards(layout_name + " next turn")
	check_ui_bounds(layout_name + " next turn")
	await screenshot(layout_name, "09-next-player")

	# Cycle back to A's next action turn: begin_turn is the only reset point and
	# the retained stolen Panic becomes legal again.
	GameManager.flow.jobs.clear()
	GameManager.reactions.active = {}
	GameManager.begin_turn(2)
	check(not GameManager.players[2].department_store_used_this_action_turn, layout_name + ": Bách Hóa allowance resets on player's next action turn")
	GameManager.flow.jobs.clear()
	GameManager.reactions.active = {}
	GameManager.turns.phase = "ACTION_PHASE"
	check(not GameManager.players[2].panic_used_this_action_turn, layout_name + ": next own turn resets Panic allowance")
	take_card(3, "dodge")
	GameManager.resolver.play(GameManager, 2, cards.panic_stolen.instance_id, 3)
	check(GameManager.find_card(2, cards.panic_stolen.instance_id).is_empty() and GameManager.players[2].panic_used_this_action_turn,
		layout_name + ": retained stolen Panic succeeds next own turn")
	check(GameManager.flow.resolve({"accept":true, "option":"hand"}), layout_name + ": next-turn Panic transfer resolves normally")
	verify_physical_cards(layout_name + " after next-turn Panic")

func _ready() -> void:
	capture_enabled = OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(artifact_dir))
	net = PlaytestNetwork.new()
	net.owner_test = self
	add_child(net)
	GameManager.network = net
	AudioManager.enabled = true
	AudioManager.unlocked = true
	AudioManager.muted = false
	AudioManager.sound_played.connect(func(key: String, _bus: String): played_audio.append(key))
	for layout in [
		{"name":"desktop", "size":Vector2i(1440,900)},
		{"name":"mobile-landscape", "size":Vector2i(844,390)},
		{"name":"mobile-portrait", "size":Vector2i(390,844)}
	]:
		await run_round(layout.name, layout.size)
	GameManager.clear()
	GameManager.network = NetworkManager
	var report := {
		"checks":checks, "failures":failures, "player_count":4,
		"layouts":["1440x900", "844x390", "390x844"],
		"screenshots":capture_enabled,
		"renderer":RenderingServer.get_video_adapter_name()
	}
	var file := FileAccess.open(artifact_dir + "/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	if failures.is_empty():
		print("PASS: %d complete full-round multiplayer, privacy, audio, UI and card-conservation checks" % checks)
		get_tree().quit()
	else:
		print("FAIL: %d/%d full-round checks failed" % [failures.size(), checks])
		get_tree().quit(1)
