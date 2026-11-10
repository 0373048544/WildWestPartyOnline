extends Node

var checks: int = 0
var events: Array = []
var private_events: Dictionary = {}
var notices: Array = []

class CaptureNetwork:
	extends Node
	var owner_test: Node
	var session_port: int = 7000
	func is_authority() -> bool: return true
	func host_player_id() -> int: return 1
	func is_room_host(id: int) -> bool: return id == 1
	func publish_game(_game: Node) -> void: pass
	func broadcast_animation(_actor: int, _kind: String, _target: int = 0) -> void: pass
	func broadcast_table_event(event: Dictionary) -> void:
		owner_test.events.append(event.duplicate(true))
	func send_private_event(id: int, event: Dictionary) -> void:
		if not owner_test.private_events.has(id):
			owner_test.private_events[id] = []
		owner_test.private_events[id].append(event.duplicate(true))
	func send_notice(id: int, message: String) -> void:
		owner_test.notices.append({"id": id, "message": message})

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("CUSTOM CARDS FAILED: " + message)
		get_tree().quit(1)
		assert(value, message)

func setup(count: int) -> void:
	GameManager.clear()
	for id in range(1, count + 1):
		GameManager.add_player(id, "Player %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()
	GameManager.selection.expire(GameManager)
	GameManager.reactions.active = {}
	GameManager.flow.jobs.clear()
	GameManager.flow.market.clear()
	for player in GameManager.players.values():
		player.ability_id = ""
		player.max_hp = 4
		player.current_hp = 4
		GameManager.discard_all(player)
	GameManager.turns.current_player = 1
	GameManager.turns.phase = "ACTION_PHASE"
	GameManager.rate_limits.clear()
	events.clear()
	private_events.clear()
	notices.clear()

func give(id: int, card_id: String, suit: String = "CLUB", rank: String = "7") -> Dictionary:
	var card := CardInstance.make(GameManager.deck.next_id, card_id, suit, rank)
	GameManager.deck.next_id += 1
	GameManager.players[id].hand.append(card)
	return card

func _ready() -> void:
	await get_tree().process_frame
	var capture := CaptureNetwork.new()
	capture.owner_test = self
	GameManager.network = capture
	test_deck_registration()
	test_department_store_all_counts()
	test_department_store_edge_cases()
	test_department_store_validation_and_privacy()
	test_department_store_suzy_last_card()
	test_department_store_action_turn_limit()
	test_general_store_unchanged_and_limited()
	test_duplicate_card_restrictions()
	test_iced_tea_all_counts()
	test_iced_tea_survival()
	test_heal_presentation_metadata()
	test_survival_banner_choices()
	GameManager.clear()
	GameManager.network = NetworkManager
	capture.free()
	print("PASS: %d BÁCH HÓA / TRÀ ĐÁ authoritative 2–7 player checks" % checks)
	get_tree().quit()

func test_deck_registration() -> void:
	var deck := DeckManager.new()
	check(deck.reset(), "custom deck manifest validates")
	var counts: Dictionary = {}
	for card in deck.draw_pile:
		counts[card.card_data_id] = int(counts.get(card.card_data_id, 0)) + 1
	check(deck.draw_pile.size() == 86, "custom deck has 86 physical cards")
	check(int(counts.get("department_store", 0)) == 2, "deck contains exactly 2 BÁCH HÓA")
	check(int(counts.get("iced_tea", 0)) == 4, "deck contains exactly 4 TRÀ ĐÁ")

func test_department_store_all_counts() -> void:
	for count in range(2, 8):
		setup(count)
		var source := give(1, "department_store")
		var chosen: Dictionary = {}
		for id in range(2, count + 1):
			chosen[id] = give(id, "shoot", "SPADE", "8")
			give(id, "dodge", "HEART", "9")
		var before_sender: int = GameManager.players[1].hand.size()
		GameManager.resolver.play(GameManager, 1, source.instance_id, 1)
		for id in range(2, count + 1):
			check(GameManager.reactions.active.target_player_id == id,
				"BÁCH HÓA follows living turn order at %d players" % count)
			check(GameManager.flow.resolve({"accept": true, "cards": [chosen[id].instance_id]}),
				"giver %d selects their own hand card" % id)
		check(GameManager.players[1].hand.size() == before_sender - 1 + count - 1,
			"BÁCH HÓA receives one card per opponent at %d players" % count)
		for id in range(2, count + 1):
			check(GameManager.players[id].hand.size() == 1,
				"opponent %d loses exactly one hand card at %d players" % [id, count])
		var resolved: Array = events.filter(func(event): return event.get("kind", "") == "department_store_result")
		check(not resolved.is_empty() and int(resolved.back().get("count", -1)) == count - 1,
			"public BÁCH HÓA result exposes only the count at %d players" % count)
		for event in events:
			if event.get("kind", "") == "transfer" and bool(event.get("hidden", false)):
				check(not event.has("card") and not event.has("card_data_id")
					and not event.has("rank") and not event.has("suit") and not event.has("to"),
					"BÁCH HÓA never leaks a stolen hand-card identity")
				check(bool(event.get("department_store", false)),
					"BÁCH HÓA transfer is tagged for its short card-back presentation")

func test_department_store_edge_cases() -> void:
	setup(4)
	var source := give(1, "department_store")
	GameManager.players[2].is_alive = false
	# Player 3 is alive but has no hand cards. Player 4 is the only eligible victim.
	var kept_weapon := give(3, "volcanic")
	GameManager.players[3].hand.erase(kept_weapon)
	GameManager.players[3].weapon = kept_weapon
	give(4, "shoot")
	GameManager.resolver.play(GameManager, 1, source.instance_id, 1)
	check(GameManager.reactions.active.target_player_id == 4,
		"dead and empty-hand givers are skipped automatically")
	var offered_uid: int = int(GameManager.reactions.active.payload.cards[0].instance_id)
	GameManager.flow.resolve({"accept": true, "cards": [offered_uid]})
	check(GameManager.players[1].hand.size() == 1, "dead and empty-hand opponents are skipped")
	check(GameManager.players[3].weapon == kept_weapon, "BÁCH HÓA never steals weapons or equipment")
	check(GameManager.players[4].hand.is_empty(), "eligible giver loses the selected hand card")

func test_department_store_suzy_last_card() -> void:
	setup(3)
	var source := give(1, "department_store")
	GameManager.players[2].ability_id = "empty_draw"
	var last_card := give(2, "shoot")
	var third_card := give(3, "dodge")
	GameManager.resolver.play(GameManager, 1, source.instance_id, 1)
	check(GameManager.reactions.active.target_player_id == 2, "Suzy is prompted once as the first giver")
	check(GameManager.flow.resolve({"accept": true, "cards": [last_card.instance_id]}), "Suzy gives her last card")
	check(GameManager.players[2].hand.size() == 1, "Suzy draws exactly one replacement after giving her last card")
	check(GameManager.reactions.active.target_player_id == 3, "Suzy replacement card does not create a second giver obligation")
	check(GameManager.flow.resolve({"accept": true, "cards": [third_card.instance_id]}), "next giver completes normally after Suzy refill")
	check(GameManager.reactions.active.is_empty() and GameManager.players[1].hand.size() == 2,
		"BÁCH HÓA completes once with both transfers and no stuck prompt")

func test_department_store_validation_and_privacy() -> void:
	setup(3)
	var source := give(1, "department_store")
	var own := give(2, "iced_tea", "HEART", "2")
	var weapon := give(2, "volcanic")
	GameManager.players[2].hand.erase(weapon)
	GameManager.players[2].weapon = weapon
	var equipment := give(2, "barrel")
	GameManager.players[2].hand.erase(equipment)
	GameManager.players[2].equipment["barrel"] = equipment
	give(3, "dodge")
	GameManager.resolver.play(GameManager, 1, source.instance_id, 1)
	check(is_equal_approx(float(GameManager.reactions.active.timeout_seconds), 8.0),
		"BÁCH HÓA giver prompt has an 8-second server timeout")
	check(not GameManager.flow.resolve({"accept": true, "cards": [999999]}),
		"server rejects a card UID outside giver.hand")
	check(GameManager.reactions.active.target_player_id == 2,
		"invalid UID leaves the authoritative giver prompt active")
	GameManager.rate_limits.clear()
	GameManager.handle_intent(1, "reaction", {"request": GameManager.reactions.active.request_id,
		"accept": true, "cards": [own.instance_id]})
	check(GameManager.reactions.active.target_player_id == 2,
		"receiver cannot resolve the giver prompt")
	check(not GameManager.flow.resolve({"accept": true, "cards": [weapon.instance_id]}),
		"equipped weapon cannot be selected")
	check(not GameManager.flow.resolve({"accept": true, "cards": [equipment.instance_id]}),
		"equipment cannot be selected")
	check(GameManager.flow.resolve({"accept": true, "cards": [own.instance_id]}),
		"giver can submit an actual own-hand UID")
	var receiver_private: Array = private_events.get(1, [])
	var giver_private: Array = private_events.get(2, [])
	check(receiver_private.any(func(event): return event.get("card", {}).get("instance_id", -1) == own.instance_id),
		"receiver privately sees the exact received card")
	check(giver_private.any(func(event): return event.get("card", {}).get("instance_id", -1) == own.instance_id),
		"giver privately sees the exact given card")
	for event in events:
		if event.get("kind", "") == "transfer":
			check(not event.has("card") and not event.has("card_data_id")
				and not event.has("rank") and not event.has("suit"),
				"public transfer contains player IDs only")
	# Player 3 times out: authority selects one of player 3's own hand cards.
	var before_receiver: int = GameManager.players[1].hand.size()
	check(GameManager.flow.resolve({"accept": false}), "timeout auto-selects a giver hand card")
	check(GameManager.players[1].hand.size() == before_receiver + 1,
		"timeout selection transfers exactly one card and does not freeze the queue")

	setup(4)
	GameManager.players[1].role = PlayerState.Role.SHERIFF
	GameManager.players[2].role = PlayerState.Role.DEPUTY
	GameManager.players[3].role = PlayerState.Role.OUTLAW
	GameManager.players[4].role = PlayerState.Role.RENEGADE
	source = give(1, "department_store")
	for id in [2, 3, 4]:
		give(id, "shoot")
	GameManager.resolver.play(GameManager, 1, source.instance_id, 1)
	GameManager.disconnect_player(2)
	check(GameManager.reactions.active.target_player_id == 3,
		"giver disconnect is skipped and the next giver prompt continues")

func test_department_store_action_turn_limit() -> void:
	setup(2)
	var first := give(1, "department_store")
	var offered := give(2, "shoot")
	GameManager.resolver.play(GameManager, 1, first.instance_id, 1)
	GameManager.flow.resolve({"accept": true, "cards": [offered.instance_id]})
	var second := give(1, "department_store")
	check(GameManager.resolver.valid_targets(GameManager, 1, second).is_empty()
		and GameManager.resolver.disabled_reason(GameManager, 1, second) == "Bạn đã dùng BÁCH HÓA trong lượt này.",
		"same player cannot use a second BÁCH HÓA in one action turn")
	GameManager.resolver.play(GameManager, 1, second.instance_id, 1)
	check(not GameManager.find_card(1, second.instance_id).is_empty(),
		"server rejection does not consume the second BÁCH HÓA")
	GameManager.turns.current_player = 2
	GameManager.turns.phase = "ACTION_PHASE"
	var other := give(2, "department_store")
	give(1, "dodge")
	GameManager.resolver.play(GameManager, 2, other.instance_id, 2)
	check(GameManager.players[2].department_store_used_this_action_turn,
		"different player retains their independent BÁCH HÓA allowance")
	# Phase changes, snapshots and reconnect state must not create a new turn.
	GameManager.turns.phase = "REACTION"
	GameManager.publish()
	GameManager.players[2].is_connected = false
	GameManager.players[2].is_connected = true
	GameManager.turns.phase = "ACTION_PHASE"
	check(GameManager.players[2].department_store_used_this_action_turn,
		"phase changes, snapshots and reconnect do not reset BÁCH HÓA")
	# Only the authoritative next action-turn boundary resets this player's flag.
	GameManager.begin_turn(1)
	GameManager.flow.jobs.clear()
	GameManager.reactions.active = {}
	GameManager.turns.phase = "ACTION_PHASE"
	check(not GameManager.players[1].department_store_used_this_action_turn,
		"same player may use BÁCH HÓA again on their next action turn")
	check(GameManager.resolver.valid_targets(GameManager, 1, second).has(1),
		"second BÁCH HÓA becomes valid after the next action-turn boundary")
	setup(2)
	check(not GameManager.players[1].department_store_used_this_action_turn,
		"new match starts with a fresh BÁCH HÓA action-turn allowance")

func resolve_store_all() -> void:
	while not GameManager.reactions.active.is_empty():
		var cards: Array = GameManager.reactions.active.payload.get("cards", [])
		check(not cards.is_empty(), "store picker receives remaining public market")
		check(GameManager.flow.resolve({"accept": true, "cards": [cards[0].instance_id]}),
			"current store picker selects an available market UID")

func test_general_store_unchanged_and_limited() -> void:
	setup(4)
	var first := give(1, "general_store")
	GameManager.resolver.play(GameManager, 1, first.instance_id, 1)
	check(GameManager.flow.market.size() == 4, "CỬA HÀNG still reveals one card per living player")
	check(GameManager.reactions.active.target_player_id == 1,
		"CỬA HÀNG player chooses first")
	var valid_market_uid: int = GameManager.reactions.active.payload.cards[0].instance_id
	check(not GameManager.flow.resolve({"accept": true, "cards": [999999]}),
		"server rejects a store UID outside the active market")
	check(GameManager.flow.resolve({"accept": true, "cards": [valid_market_uid]}),
		"first valid store selection succeeds")
	check(GameManager.reactions.active.target_player_id == 2,
		"store selection continues in living turn order")
	resolve_store_all()
	var second := give(1, "general_store")
	check(GameManager.resolver.valid_targets(GameManager, 1, second).is_empty()
		and GameManager.resolver.disabled_reason(GameManager, 1, second) == "Bạn đã dùng CỬA HÀNG trong ván này.",
		"same player cannot use a second CỬA HÀNG in the match")
	GameManager.turns.current_player = 2
	GameManager.turns.phase = "ACTION_PHASE"
	var other := give(2, "general_store")
	GameManager.resolver.play(GameManager, 2, other.instance_id, 2)
	check(GameManager.players[2].general_store_used_this_match,
		"different player retains an independent CỬA HÀNG allowance")
	resolve_store_all()
	setup(2)
	check(not GameManager.players[1].general_store_used_this_match,
		"new match resets CỬA HÀNG per-game state")

	setup(4)
	GameManager.players[1].role = PlayerState.Role.SHERIFF
	GameManager.players[2].role = PlayerState.Role.DEPUTY
	GameManager.players[3].role = PlayerState.Role.OUTLAW
	GameManager.players[4].role = PlayerState.Role.RENEGADE
	first = give(1, "general_store")
	GameManager.resolver.play(GameManager, 1, first.instance_id, 1)
	var first_market: int = GameManager.reactions.active.payload.cards[0].instance_id
	GameManager.flow.resolve({"accept": true, "cards": [first_market]})
	GameManager.disconnect_player(2)
	check(GameManager.reactions.active.target_player_id == 3,
		"store picker disconnect does not freeze the remaining selection order")

func test_duplicate_card_restrictions() -> void:
	setup(3)
	for card_id in ["supply", "wells_fargo"]:
		var first := give(1, card_id)
		var second := give(1, card_id)
		GameManager.resolver.play(GameManager, 1, first.instance_id, 1)
		GameManager.resolver.play(GameManager, 1, second.instance_id, 1)
		check(GameManager.find_card(1, first.instance_id).is_empty()
			and GameManager.find_card(1, second.instance_id).is_empty(),
			"duplicate %s actions remain legal without a card-specific restriction" % card_id)
	GameManager.players[1].ability_id = "unlimited_shoot"
	var restricted := give(1, "department_store")
	give(2, "shoot")
	give(3, "shoot")
	GameManager.resolver.play(GameManager, 1, restricted.instance_id, 1)
	while not GameManager.reactions.active.is_empty():
		GameManager.flow.resolve({"accept": false})
	var duplicate := give(1, "department_store")
	check(GameManager.resolver.valid_targets(GameManager, 1, duplicate).is_empty(),
		"Willy-style unlimited BANG ability does not override BÁCH HÓA")
	GameManager.players[1].ability_id = ""
	GameManager.players[1].weapon = give(1, "volcanic")
	GameManager.players[1].hand.erase(GameManager.players[1].weapon)
	check(GameManager.resolver.valid_targets(GameManager, 1, duplicate).is_empty(),
		"Volcanic does not override BÁCH HÓA action-turn restriction")

	setup(3)
	GameManager.players[1].ability_id = "unlimited_shoot"
	var store := give(1, "general_store")
	GameManager.resolver.play(GameManager, 1, store.instance_id, 1)
	resolve_store_all()
	var second_store := give(1, "general_store")
	check(GameManager.resolver.valid_targets(GameManager, 1, second_store).is_empty(),
		"Willy-style unlimited BANG ability does not override CỬA HÀNG")

func test_iced_tea_all_counts() -> void:
	for count in range(2, 8):
		setup(count)
		GameManager.players[1].current_hp = 3
		var tea := give(1, "iced_tea", "HEART", "2")
		GameManager.resolver.play(GameManager, 1, tea.instance_id, 1)
		check(GameManager.players[1].current_hp == 4,
			"TRÀ ĐÁ heals 1 HP at %d players" % count)
		check(GameManager.find_card(1, tea.instance_id).is_empty(),
			"TRÀ ĐÁ is consumed at %d players" % count)
	setup(2)
	var full_hp_tea := give(1, "iced_tea")
	check(GameManager.resolver.valid_targets(GameManager, 1, full_hp_tea).is_empty(),
		"TRÀ ĐÁ cannot be played at full HP")

func test_iced_tea_survival() -> void:
	setup(2)
	GameManager.players[1].role = PlayerState.Role.DEPUTY
	GameManager.players[2].role = PlayerState.Role.OUTLAW
	GameManager.players[1].current_hp = 1
	var beer := give(1, "drink", "HEART", "6")
	var tea := give(1, "iced_tea", "HEART", "2")
	GameManager.damage(1, 2, 1)
	var prompt: Dictionary = GameManager.reactions.private_prompt(1)
	check(prompt.get("allowed_card_types", []).has(tea.instance_id),
		"TRÀ ĐÁ is offered while dying with only 2 players alive")
	check(prompt.get("allowed_card_types", []).has(beer.instance_id),
		"BIA is offered while dying with only 2 players alive")
	check(GameManager.flow.resolve({"accept": true, "card": tea.instance_id}),
		"server accepts TRÀ ĐÁ survival response")
	check(GameManager.players[1].is_alive and GameManager.players[1].current_hp == 1,
		"TRÀ ĐÁ saves a dying player in a 2-player game")

	setup(3)
	GameManager.players[1].current_hp = 1
	beer = give(1, "drink", "HEART", "6")
	tea = give(1, "iced_tea", "HEART", "2")
	GameManager.damage(1, 2, 1)
	prompt = GameManager.reactions.private_prompt(1)
	check(prompt.get("allowed_card_types", []).has(beer.instance_id)
		and prompt.get("allowed_card_types", []).has(tea.instance_id),
		"BIA and TRÀ ĐÁ are both explicit survival choices with 3+ players")
	var options: Array = prompt.get("survival_options", [])
	check(options.any(func(option): return option.get("card_data_id", "") == "drink")
		and options.any(func(option): return option.get("card_data_id", "") == "iced_tea"),
		"survival UI payload identifies both choices without exposing other hands")

func test_heal_presentation_metadata() -> void:
	setup(3)
	GameManager.players[1].current_hp = 3
	var beer := give(1, "drink", "HEART", "6")
	GameManager.resolver.play(GameManager, 1, beer.instance_id, 1)
	var heals: Array = events.filter(func(event): return event.get("kind", "") == "heal")
	check(heals.size() == 1 and heals[0].get("card_data_id", "") == "drink"
		and not bool(heals[0].get("rescued", true)),
		"successful normal BIA heal carries client-only drink presentation metadata")
	setup(2)
	GameManager.players[1].role = PlayerState.Role.DEPUTY
	GameManager.players[2].role = PlayerState.Role.OUTLAW
	GameManager.players[1].current_hp = 1
	var tea := give(1, "iced_tea", "HEART", "2")
	GameManager.damage(1, 2, 1)
	check(GameManager.flow.resolve({"accept": true, "card": tea.instance_id}),
		"TRÀ ĐÁ rescue resolves for presentation metadata test")
	heals = events.filter(func(event): return event.get("kind", "") == "heal")
	check(heals.size() == 1 and heals[0].get("card_data_id", "") == "iced_tea"
		and bool(heals[0].get("rescued", false)),
		"successful dying TRÀ ĐÁ heal is explicitly marked rescued for stronger presentation")

func test_survival_banner_choices() -> void:
	var banner: Control = load("res://scenes/ui/ReactionBanner.tscn").instantiate()
	add_child(banner)
	banner._configure_survival_actions({"survival_options": [
		{"instance_id": 101, "card_data_id": "drink"},
		{"instance_id": 102, "card_data_id": "iced_tea"}
	]})
	check(banner.primary_card == 101 and banner.primary_button.text == "DÙNG BIA",
		"survival banner keeps BIA as an explicit option when legal")
	check(banner.secondary_card == 102 and banner.secondary_button.visible
		and banner.secondary_button.text == "DÙNG TRÀ ĐÁ",
		"survival banner shows a separate TRÀ ĐÁ button when both are legal")
	banner.secondary_button.visible = false
	banner._configure_survival_actions({"survival_options": [
		{"instance_id": 103, "card_data_id": "iced_tea"}
	]})
	check(banner.primary_card == 103 and banner.primary_button.text == "DÙNG TRÀ ĐÁ"
		and not banner.secondary_button.visible,
		"two-player banner offers TRÀ ĐÁ without an invalid BIA button")
	banner.free()
