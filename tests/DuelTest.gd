extends Node

var checks: int = 0
var failures: Array[String] = []
var events: Array = []
var notices: Array = []
var original_network: Node
var capture_network: Node

class CaptureNetwork:
	extends Node
	var owner_test: Node
	var session_port: int = 7000
	func is_authority() -> bool: return true
	func host_player_id() -> int: return 1
	func is_room_host(id: int) -> bool: return id == 1
	func publish_game(_game: Node) -> void: pass
	func broadcast_animation(actor: int, kind: String, target: int = 0) -> void:
		broadcast_table_event({"kind": "animation", "actor": actor, "animation": kind, "target": target})
	func broadcast_table_event(event: Dictionary) -> void:
		owner_test.events.append(event.duplicate(true))
	func send_private_event(_id: int, _event: Dictionary) -> void: pass
	func send_notice(id: int, message: String) -> void:
		owner_test.notices.append({"id": id, "message": message})

class BannerApp:
	extends Node
	var calls: Array = []
	var table: Node
	func intent(action: String, args: Dictionary = {}) -> void:
		calls.append({"action": action, "args": args.duplicate(true)})

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("DUEL FAILED: " + message)

func setup(count: int = 4) -> void:
	GameManager.clear()
	events.clear()
	notices.clear()
	for id in range(1, count + 1):
		GameManager.add_player(id, "Player %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()
	GameManager.selection.expire(GameManager)
	GameManager.reactions.active = {}
	GameManager.flow.jobs.clear()
	GameManager.flow.market.clear()
	for id in GameManager.players:
		var player: PlayerState = GameManager.players[id]
		# Disable the selected character before clearing setup cards; otherwise a
		# randomly selected Suzy can refill and contaminate Duel fixtures.
		player.ability_id = ""
		GameManager.discard_all(player)
		player.max_hp = 4
		player.current_hp = 4
		player.role = PlayerState.Role.OUTLAW
		player.shoot_used_this_turn = false
	GameManager.players[1].role = PlayerState.Role.SHERIFF
	GameManager.players[count].role = PlayerState.Role.RENEGADE
	GameManager.turns.current_player = 1
	GameManager.turns.phase = "ACTION_PHASE"
	GameManager.rate_limits.clear()

func give(id: int, card_id: String, suit: String = "CLUB", rank: String = "7") -> Dictionary:
	var card := CardInstance.make(GameManager.deck.next_id, card_id, suit, rank)
	GameManager.deck.next_id += 1
	GameManager.players[id].hand.append(card)
	return card

func equip(id: int, card_id: String) -> Dictionary:
	var card := give(id, card_id)
	GameManager.players[id].hand.erase(card)
	GameManager.players[id].equipment[card_id] = card
	return card

func start_duel(source: int = 1, target: int = 2) -> Dictionary:
	var card := give(source, "showdown")
	GameManager.resolver.play(GameManager, source, card.instance_id, target)
	return card

func respond(id: int, card: Dictionary = {}, accept: bool = true) -> bool:
	if GameManager.reactions.active.is_empty():
		return false
	var args := {
		"request": int(GameManager.reactions.active.request_id),
		"accept": accept
	}
	if not card.is_empty():
		args["card"] = int(card.instance_id)
	GameManager.rate_limits.erase(id)
	GameManager.handle_intent(id, "reaction", args)
	return true

func discard_has(uid: int) -> bool:
	return GameManager.deck.discard_pile.any(func(card): return int(card.instance_id) == uid)

func test_duel_target_responds_first() -> void:
	setup()
	give(2, "shoot")
	start_duel()
	check(GameManager.reactions.active.get("reaction_type", "") == "duel", "Duel creates duel reaction")
	check(int(GameManager.reactions.active.get("target_player_id", 0)) == 2, "Duel target responds first")
	check(int(GameManager.reactions.active.get("source_player_id", 0)) == 1, "Duel prompt identifies challenger")
	check(not GameManager.reactions.private_prompt(2).is_empty() and GameManager.reactions.private_prompt(1).is_empty(), "Only current responder receives private Duel controls")

func test_duel_target_without_bang_loses_hp() -> void:
	setup()
	var dodge := give(2, "dodge")
	give(2, "iced_tea")
	start_duel()
	check(GameManager.reactions.active.is_empty(), "Target without BANG resolves immediately")
	check(GameManager.players[2].current_hp == 3 and GameManager.players[1].current_hp == 4, "Only target loses exactly one HP")
	check(GameManager.find_card(2, dodge.instance_id) == dodge, "DODGE remains unconsumed")

func test_duel_source_without_next_bang_loses_hp() -> void:
	setup()
	var bang := give(2, "shoot")
	start_duel()
	respond(2, bang)
	check(GameManager.players[1].current_hp == 3 and GameManager.players[2].current_hp == 4, "Source without return BANG loses one HP")
	check(GameManager.reactions.active.is_empty(), "Duel closes when source cannot answer")

func test_duel_multiple_bangs_alternate_correctly() -> void:
	setup()
	var a1 := give(1, "shoot")
	var a2 := give(1, "shoot")
	var b1 := give(2, "shoot")
	var b2 := give(2, "shoot")
	var b3 := give(2, "shoot")
	start_duel()
	var sequence := [[2, b1], [1, a1], [2, b2], [1, a2], [2, b3]]
	for index in range(sequence.size()):
		check(int(GameManager.reactions.active.target_player_id) == int(sequence[index][0]), "Alternating responder step %d" % (index + 1))
		respond(int(sequence[index][0]), sequence[index][1])
	check(GameManager.players[1].current_hp == 3 and GameManager.players[2].current_hp == 4, "Five-response Duel damages exhausted source")
	check(GameManager.reactions.active.is_empty(), "Five-response Duel closes")

func test_duel_dodge_not_allowed() -> void:
	setup()
	var dodge := give(2, "dodge")
	var bang := give(2, "shoot")
	start_duel()
	var allowed: Array = GameManager.reactions.active.get("allowed_card_types", [])
	check(allowed.has(bang.instance_id) and not allowed.has(dodge.instance_id), "Duel allows BANG but never DODGE")
	var request: int = GameManager.reactions.active.request_id
	GameManager.handle_intent(2, "reaction", {"request": request, "accept": true, "card": dodge.instance_id})
	check(GameManager.find_card(2, dodge.instance_id) == dodge and not GameManager.reactions.active.is_empty(), "Server rejects DODGE UID without consuming it")

func test_duel_barrel_not_triggered() -> void:
	setup()
	equip(2, "barrel")
	var draw_before: int = GameManager.deck.draw_pile.size()
	start_duel()
	check(GameManager.deck.draw_pile.size() == draw_before, "Duel performs no Barrel judgement draw")
	check(GameManager.players[2].equipment.has("barrel") and GameManager.players[2].current_hp == 3, "Barrel remains equipped and does not prevent Duel damage")
	check(not events.any(func(event): return event.get("kind", "") in ["judge", "barrel_result"]), "Duel emits no Barrel events")

func test_duel_ignores_weapon_range() -> void:
	setup(4)
	give(3, "shoot")
	var duel := give(1, "showdown")
	check(DistanceManager.distance(GameManager.players, 1, 3) > DistanceManager.weapon_range(GameManager.players[1]), "Fixture target is outside weapon range")
	check(GameManager.resolver.valid_targets(GameManager, 1, duel).has(3), "Duel may target any living opponent regardless of range")
	GameManager.resolver.play(GameManager, 1, duel.instance_id, 3)
	check(int(GameManager.reactions.active.target_player_id) == 3, "Out-of-range Duel starts normally")

func test_duel_reaction_bang_ignores_normal_bang_limit() -> void:
	setup()
	GameManager.players[2].shoot_used_this_turn = true
	var bang := give(2, "shoot")
	start_duel()
	check(GameManager.reactions.active.allowed_card_types.has(bang.instance_id), "Reaction BANG remains legal after normal BANG limit is used")
	respond(2, bang)
	check(discard_has(bang.instance_id), "Reaction consumes allowed BANG despite normal limit")

func test_duel_reaction_bang_does_not_consume_action_bang_limit() -> void:
	setup()
	var source_bang := give(1, "shoot")
	var responder_bang := give(2, "shoot")
	start_duel()
	respond(2, responder_bang)
	respond(1, source_bang)
	check(not GameManager.players[1].shoot_used_this_turn and not GameManager.players[2].shoot_used_this_turn, "Duel responses never set normal BANG flags")
	GameManager.turns.current_player = 2
	GameManager.turns.phase = "ACTION_PHASE"
	var normal := give(2, "shoot")
	check(GameManager.resolver.valid_targets(GameManager, 2, normal).has(1), "Responder can later play a normal Action BANG")

func test_duel_damage_is_exactly_one() -> void:
	setup()
	GameManager.players[2].current_hp = 4
	start_duel()
	check(GameManager.players[2].current_hp == 3, "Duel loss deals exactly one damage")
	check(events.filter(func(event): return event.get("kind", "") == "damage" and int(event.get("player", 0)) == 2).size() == 1, "Duel emits one damage event")

func test_duel_enters_survive_flow_at_zero_hp() -> void:
	setup()
	GameManager.players[2].current_hp = 1
	var beer := give(2, "drink")
	var tea := give(2, "iced_tea")
	start_duel()
	check(GameManager.players[2].current_hp == 0, "Losing Duel reaches zero HP")
	check(GameManager.reactions.active.get("reaction_type", "") == "survive", "Duel damage enters normal survive flow")
	check(GameManager.reactions.active.allowed_card_types.has(tea.instance_id), "TRÀ ĐÁ appears as survival option")
	check(GameManager.reactions.active.allowed_card_types.has(beer.instance_id), "BIA appears as survival option while more than two players live")
	respond(2, tea)
	check(GameManager.players[2].current_hp == 1 and GameManager.players[2].is_alive, "TRÀ ĐÁ rescues Duel loser")
	check(GameManager.reactions.active.is_empty(), "Survive reaction closes after rescue")

func test_duel_source_death_closes_flow() -> void:
	setup()
	GameManager.players[1].current_hp = 1
	var bang := give(2, "shoot")
	start_duel()
	respond(2, bang)
	check(not GameManager.players[1].is_alive and GameManager.players[1].current_hp == 0, "Source can die from exhausted Duel response")
	check(GameManager.reactions.active.is_empty() and GameManager.flow.jobs.is_empty(), "Source death closes Duel without prompting a dead player")

func test_duel_invalid_card_uid_rejected() -> void:
	setup()
	var bang := give(2, "shoot")
	start_duel()
	var request: int = GameManager.reactions.active.request_id
	GameManager.handle_intent(2, "reaction", {"request": request, "accept": true, "card": 999999})
	check(not GameManager.reactions.active.is_empty(), "Invalid card UID cannot consume Duel prompt")
	check(GameManager.find_card(2, bang.instance_id) == bang and GameManager.players[2].current_hp == 4, "Invalid UID mutates neither hand nor HP")

func test_duel_wrong_player_cannot_respond() -> void:
	setup()
	var bang := give(2, "shoot")
	start_duel()
	var request: int = GameManager.reactions.active.request_id
	GameManager.handle_intent(3, "reaction", {"request": request, "accept": false})
	check(int(GameManager.reactions.active.target_player_id) == 2, "Wrong player cannot pass another player's Duel prompt")
	check(GameManager.find_card(2, bang.instance_id) == bang and GameManager.players[2].current_hp == 4, "Wrong player request causes no mutation")

func test_duel_timeout_does_not_freeze_flow() -> void:
	setup()
	give(2, "shoot")
	start_duel()
	GameManager.reactions.active.deadline = 0
	GameManager._process(0.0)
	check(GameManager.reactions.active.is_empty(), "Expired Duel prompt is cleared")
	check(GameManager.players[2].current_hp == 3, "Duel timeout is treated as pass and deals one damage")
	check(GameManager.flow.jobs.is_empty(), "Duel timeout leaves no stuck flow job")

func test_duel_pass_disconnect_conversion_and_special_cases() -> void:
	setup()
	var bang := give(2, "shoot")
	start_duel()
	respond(2, {}, false)
	check(GameManager.players[2].current_hp == 3 and GameManager.find_card(2, bang.instance_id) == bang, "Voluntary pass deals damage without auto-using BANG")
	setup()
	GameManager.players[2].ability_id = "convert"
	var janet_dodge := give(2, "dodge")
	start_duel()
	check(GameManager.reactions.active.allowed_card_types.has(janet_dodge.instance_id), "Janet conversion is honored through response_cards")
	respond(2, janet_dodge)
	check(discard_has(janet_dodge.instance_id), "Converted DODGE consumes exactly one physical card")
	setup()
	GameManager.players[2].ability_id = "unlimited_shoot"
	var willy_bang := give(2, "shoot")
	start_duel()
	respond(2, willy_bang)
	check(GameManager.players[2].hand.filter(func(card): return card.card_data_id == "shoot").is_empty(), "Willy still consumes only the selected single response")
	check(GameManager.reactions.active.is_empty(), "Willy does not bypass alternating Duel flow when source is empty")
	setup()
	var volcanic := give(2, "volcanic")
	GameManager.players[2].hand.erase(volcanic)
	GameManager.players[2].weapon = volcanic
	var v1 := give(2, "shoot")
	var v2 := give(2, "shoot")
	start_duel()
	respond(2, v1)
	check(GameManager.find_card(2, v2.instance_id) == v2, "Volcanic does not auto-spend a second Duel BANG")
	setup()
	give(2, "shoot")
	start_duel()
	GameManager.disconnect_player(2)
	check(GameManager.reactions.active.is_empty() and GameManager.flow.jobs.is_empty(), "Responder disconnect cannot freeze Duel")
	setup()
	var source_response := give(1, "shoot")
	var target_response := give(2, "shoot")
	start_duel()
	respond(2, target_response)
	check(int(GameManager.reactions.active.target_player_id) == 1 and GameManager.find_card(1, source_response.instance_id) == source_response, "Fixture reaches source response before disconnect")
	GameManager.disconnect_player(2)
	check(GameManager.reactions.active.is_empty() and GameManager.flow.jobs.is_empty(), "Duel challenger disconnect cannot freeze source prompt")

func test_duel_hand_consumption_and_full_playtest() -> void:
	setup()
	var a1 := give(1, "shoot")
	var a2 := give(1, "shoot")
	var b1 := give(2, "shoot")
	var b2 := give(2, "shoot")
	var b3 := give(2, "shoot")
	var showdown := start_duel()
	var sequence := [[2, b1], [1, a1], [2, b2], [1, a2], [2, b3]]
	for step in sequence:
		respond(int(step[0]), step[1])
	for card in [showdown, a1, a2, b1, b2, b3]:
		check(discard_has(card.instance_id), "Full Duel discards physical card %d exactly once" % card.instance_id)
		check(GameManager.deck.discard_pile.count(card) == 1, "Full Duel has no duplicated discard %d" % card.instance_id)
	check(GameManager.players[1].hand.is_empty() and GameManager.players[2].hand.is_empty(), "All five response BANG cards consumed")
	check(GameManager.players[1].current_hp == 3 and GameManager.players[2].current_hp == 4, "Full Duel final HP is A=3, B=4")
	check(GameManager.reactions.active.is_empty() and GameManager.flow.jobs.is_empty(), "Full Duel closes reaction and flow state")
	check(GameManager.turns.current_player == 1 and GameManager.turns.phase == "ACTION_PHASE", "Full Duel returns to A Action Phase")
	check(not GameManager.players[1].shoot_used_this_turn and not GameManager.players[2].shoot_used_this_turn, "Full Duel leaves normal BANG allowances untouched")
	check(GameManager.log_lines.any(func(line): return "Player 2 dùng BẮN" in line), "Log records Duel BANG response")
	check(GameManager.log_lines.any(func(line): return "Player 1 không thể đáp trả" in line), "Log records exhausted loser")
	var follow_up := give(1, "supply")
	GameManager.resolver.play(GameManager, 1, follow_up.instance_id, 1)
	check(GameManager.find_card(1, follow_up.instance_id).is_empty() and GameManager.turns.phase == "ACTION_PHASE", "A can continue playing a legal Action card after Duel")

func test_duel_reaction_banner() -> void:
	var app := BannerApp.new()
	add_child(app)
	var banner: Control = load("res://scenes/ui/ReactionBanner.tscn").instantiate()
	add_child(banner)
	banner.present(app, {
		"request_id": 77, "reaction_type": "duel", "source_player_id": 1,
		"remaining": 8.0, "allowed_card_types": [123]
	}, {"players": [{"player_id": 1, "display_name": "Alice"}]})
	check(banner.visible, "Duel uses compact ReactionBanner")
	check("Alice" in banner.title_label.text and "ĐẤU SÚNG" in banner.title_label.text, "Duel banner identifies challenger and Duel")
	check("BẮN" in banner.detail_label.text and "1 sát thương" in banner.detail_label.text, "Duel banner explains BANG or one damage")
	check("BẮN" in banner.primary_button.text and "BỎ QUA" in banner.skip_button.text, "Duel banner exposes BANG and pass buttons")
	check(banner.primary_card == 123 and not banner.primary_button.disabled, "Duel banner binds only server-allowed response UID")
	banner.skip_button.pressed.emit()
	check(app.calls.size() == 1 and not app.calls[0].args.accept, "Duel banner pass sends authoritative reaction intent")
	banner.queue_free()
	app.queue_free()

func _ready() -> void:
	await get_tree().process_frame
	original_network = GameManager.network
	capture_network = CaptureNetwork.new()
	capture_network.owner_test = self
	add_child(capture_network)
	GameManager.network = capture_network
	test_duel_target_responds_first()
	test_duel_target_without_bang_loses_hp()
	test_duel_source_without_next_bang_loses_hp()
	test_duel_multiple_bangs_alternate_correctly()
	test_duel_dodge_not_allowed()
	test_duel_barrel_not_triggered()
	test_duel_ignores_weapon_range()
	test_duel_reaction_bang_ignores_normal_bang_limit()
	test_duel_reaction_bang_does_not_consume_action_bang_limit()
	test_duel_damage_is_exactly_one()
	test_duel_enters_survive_flow_at_zero_hp()
	test_duel_source_death_closes_flow()
	test_duel_invalid_card_uid_rejected()
	test_duel_wrong_player_cannot_respond()
	test_duel_timeout_does_not_freeze_flow()
	test_duel_pass_disconnect_conversion_and_special_cases()
	test_duel_hand_consumption_and_full_playtest()
	test_duel_reaction_banner()
	GameManager.clear()
	GameManager.network = original_network
	if failures.is_empty():
		print("PASS: %d Duel authority, alternation, response, damage, survival, UI and full-playtest checks" % checks)
		get_tree().quit()
	else:
		push_error("FAIL: %d/%d Duel checks failed" % [failures.size(), checks])
		get_tree().quit(1)
