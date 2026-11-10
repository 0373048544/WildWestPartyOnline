extends Node

var checks := 0
var failures: Array[String] = []
var events: Array[Dictionary] = []
var notices: Array[Dictionary] = []

class CaptureNetwork:
	extends Node
	var owner_test: Node
	func is_authority() -> bool: return true
	func host_player_id() -> int: return 1
	func is_room_host(id: int) -> bool: return id == 1
	func publish_game(_game: Node) -> void: pass
	func broadcast_animation(actor: int, kind: String, target: int = 0) -> void:
		owner_test.events.append({"event_type": "ANIMATION", "player": actor, "kind": kind, "target": target})
	func broadcast_table_event(event: Dictionary) -> void:
		owner_test.events.append(event.duplicate(true))
	func send_private_event(_id: int, _event: Dictionary) -> void: pass
	func send_notice(id: int, message: String) -> void:
		owner_test.notices.append({"id": id, "message": message})

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("V25 DRINK SURVIVAL FAILED: " + message)

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
	if count == 2:
		GameManager.players[1].role = PlayerState.Role.DEPUTY
		GameManager.players[2].role = PlayerState.Role.OUTLAW
	GameManager.turns.current_player = 1
	GameManager.turns.phase = "ACTION_PHASE"
	GameManager.rate_limits.clear()
	events.clear()
	notices.clear()

func give(id: int, card_id: String) -> Dictionary:
	var card := CardInstance.make(GameManager.deck.next_id, card_id, "HEART", 6)
	GameManager.deck.next_id += 1
	GameManager.players[id].hand.append(card)
	return card

func respond(id: int, request_id: int, uid: int, accept: bool = true) -> void:
	GameManager.rate_limits.erase(id)
	GameManager.handle_intent(id, "reaction", {
		"match_id": GameManager.match_id,
		"request": request_id,
		"accept": accept,
		"card": uid
	})

func event_count(event_type: String, player_id: int = -1) -> int:
	return events.filter(func(event: Dictionary):
		return str(event.get("event_type", "")) == event_type and (player_id < 0 or int(event.get("player", -1)) == player_id)
	).size()

func animation_count(kind: String, player_id: int = -1) -> int:
	return events.filter(func(event: Dictionary):
		return str(event.get("event_type", "")) == "ANIMATION" and str(event.get("kind", "")) == kind and (player_id < 0 or int(event.get("player", -1)) == player_id)
	).size()

func use_sid(id: int, request_id: int, card_ids: Array) -> void:
	GameManager.rate_limits.erase(id)
	GameManager.handle_intent(id, "ability", {
		"match_id": GameManager.match_id,
		"request": request_id,
		"cards": card_ids
	})

func test_normal_heal_all_counts() -> void:
	for count in range(2, 8):
		setup(count)
		GameManager.players[1].current_hp = 3
		var beer := give(1, "drink")
		check(GameManager.resolver.valid_targets(GameManager, 1, beer).has(1), "UỐNG RƯỢU is legal at %d players" % count)
		GameManager.resolver.play(GameManager, 1, beer.instance_id, 1)
		check(GameManager.players[1].current_hp == 4 and GameManager.find_card(1, beer.instance_id).is_empty(), "UỐNG RƯỢU heals exactly 1 HP at %d players" % count)
	setup(2)
	var full_hp_beer := give(1, "drink")
	check(GameManager.resolver.valid_targets(GameManager, 1, full_hp_beer).is_empty(), "UỐNG RƯỢU remains illegal at full HP")
	GameManager.resolver.play(GameManager, 1, full_hp_beer.instance_id, 1)
	check(not GameManager.find_card(1, full_hp_beer.instance_id).is_empty(), "rejected full-HP UỐNG RƯỢU is not consumed")

func test_two_player_off_turn_rescue() -> void:
	setup(2)
	GameManager.turns.current_player = 2
	GameManager.players[1].current_hp = 1
	var beer := give(1, "drink")
	GameManager.damage(1, 2, 1)
	var prompt := GameManager.reactions.private_prompt(1)
	check(GameManager.players[1].is_alive and GameManager.players[1].current_hp == 0, "lethal hit does not kill before survival response")
	check(prompt.get("reaction_type", "") == "survive" and prompt.get("allowed_card_types", []).has(beer.instance_id), "two-player off-turn survival offers owned UỐNG RƯỢU")
	check(animation_count("downed", 1) == 1 and animation_count("death", 1) == 0, "HP 0 presents HẤP HỐI without a premature death animation")
	respond(1, int(prompt.request_id), int(beer.instance_id))
	check(GameManager.players[1].is_alive and GameManager.players[1].current_hp == 1, "off-turn UỐNG RƯỢU rescues to 1 HP")
	check(GameManager.reactions.active.is_empty(), "survival prompt closes after reaching 1 HP")
	check(animation_count("drink", 1) == 1 and animation_count("recover", 1) == 1 and animation_count("death", 1) == 0, "successful Beer presents drink then recovery without death")

func test_negative_hp_requires_multiple_cards() -> void:
	setup(2)
	GameManager.turns.current_player = 2
	GameManager.players[1].current_hp = 1
	var first := give(1, "drink")
	var second := give(1, "drink")
	GameManager.damage(1, 2, 2)
	var first_prompt := GameManager.reactions.private_prompt(1)
	var old_request := int(first_prompt.request_id)
	check(GameManager.players[1].current_hp == -1 and int(first_prompt.get("required_count", 0)) == 2, "HP -1 requests two points of survival healing")
	respond(1, old_request, int(first.instance_id))
	var second_prompt := GameManager.reactions.private_prompt(1)
	check(GameManager.players[1].current_hp == 0 and GameManager.players[1].is_alive, "first UỐNG RƯỢU keeps player pending at 0 HP")
	check(int(second_prompt.request_id) != old_request and int(second_prompt.get("required_count", 0)) == 1, "server issues a fresh request for the remaining heal")
	respond(1, old_request, int(second.instance_id))
	check(not GameManager.find_card(1, second.instance_id).is_empty() and int(GameManager.reactions.active.request_id) == int(second_prompt.request_id), "stale request cannot consume the second card")
	respond(1, int(second_prompt.request_id), int(second.instance_id))
	check(GameManager.players[1].current_hp == 1 and GameManager.players[1].is_alive, "two UỐNG RƯỢU rescue a player from -1 HP")

func test_authoritative_validation() -> void:
	setup(2)
	GameManager.players[1].current_hp = 1
	var own_beer := give(1, "drink")
	var opponent_beer := give(2, "drink")
	var invalid_card := give(1, "shoot")
	GameManager.damage(1, 2, 1)
	var prompt := GameManager.reactions.private_prompt(1)
	respond(1, int(prompt.request_id), int(opponent_beer.instance_id))
	check(GameManager.players[1].current_hp == 0 and not GameManager.find_card(2, opponent_beer.instance_id).is_empty(), "player cannot use an opponent's UỐNG RƯỢU")
	respond(1, int(prompt.request_id), int(invalid_card.instance_id))
	check(GameManager.players[1].current_hp == 0 and not GameManager.find_card(1, invalid_card.instance_id).is_empty(), "non-heal card is rejected by survival request")
	respond(2, int(prompt.request_id), int(opponent_beer.instance_id))
	check(int(GameManager.reactions.active.target_player_id) == 1, "non-target player cannot answer another player's survival request")
	respond(1, int(prompt.request_id), int(own_beer.instance_id))
	check(GameManager.players[1].current_hp == 1, "valid owner/request/card combination succeeds")

func test_no_rescue_and_reconnect() -> void:
	setup(2)
	GameManager.players[1].current_hp = 1
	GameManager.damage(1, 2, 1)
	check(not GameManager.players[1].is_alive and GameManager.reactions.active.is_empty(), "player dies when no valid rescue option exists")
	check(animation_count("downed", 1) == 0 and animation_count("death", 1) == 1, "no-option lethal damage presents one confirmed death and no false survival pose")

	setup(2)
	GameManager.players[1].current_hp = 1
	var beer := give(1, "drink")
	GameManager.damage(1, 2, 1)
	var request_before := int(GameManager.reactions.active.request_id)
	# DedicatedServer keeps the authoritative player/reaction during its reconnect
	# grace period; SESSION_RESUMED only restores is_connected and republishes.
	GameManager.players[1].is_connected = false
	GameManager.players[1].is_connected = true
	var resumed_prompt: Dictionary = GameManager.private_snapshot(1).get("reaction", {})
	check(int(resumed_prompt.get("request_id", -1)) == request_before and resumed_prompt.get("allowed_card_types", []).has(beer.instance_id), "reconnect republishes the same survival right")
	respond(1, request_before, int(beer.instance_id))
	check(GameManager.players[1].is_alive and GameManager.players[1].current_hp == 1, "reconnected player can complete survival")

func test_iced_tea_and_sid_survival() -> void:
	setup(2)
	GameManager.turns.current_player = 2
	GameManager.players[1].current_hp = 1
	var tea := give(1, "iced_tea")
	GameManager.damage(1, 2, 1)
	var prompt := GameManager.reactions.private_prompt(1)
	check(prompt.get("allowed_card_types", []).has(tea.instance_id), "TRÀ ĐÁ is offered as an off-turn survival card")
	respond(1, int(prompt.request_id), int(tea.instance_id))
	check(GameManager.players[1].is_alive and GameManager.players[1].current_hp == 1, "TRÀ ĐÁ rescues a player at 0 HP")

	setup(2)
	GameManager.turns.current_player = 2
	GameManager.players[1].ability_id = "discard_heal"
	GameManager.players[1].current_hp = 1
	var sid_a := give(1, "shoot")
	var sid_b := give(1, "dodge")
	GameManager.damage(1, 2, 1)
	prompt = GameManager.reactions.private_prompt(1)
	check(bool(prompt.get("sid", false)) and prompt.get("allowed_actions", []).has("sid"), "Sid Ketchum is offered during survival with two owned cards")
	use_sid(1, int(prompt.request_id) + 1, [sid_a.instance_id, sid_b.instance_id])
	check(GameManager.players[1].current_hp == 0 and GameManager.players[1].hand.size() == 2, "stale Sid request cannot discard cards or heal")
	use_sid(2, int(prompt.request_id), [sid_a.instance_id, sid_b.instance_id])
	check(GameManager.players[1].current_hp == 0 and GameManager.players[1].hand.size() == 2, "another player cannot answer Sid's survival request")
	use_sid(1, int(prompt.request_id), [sid_a.instance_id, sid_b.instance_id])
	check(GameManager.players[1].is_alive and GameManager.players[1].current_hp == 1 and GameManager.players[1].hand.is_empty(), "Sid rescues by discarding exactly two owned cards")
	use_sid(1, int(prompt.request_id), [sid_a.instance_id, sid_b.instance_id])
	check(GameManager.players[1].current_hp == 1 and GameManager.players[1].hand.is_empty(), "duplicate Sid request cannot mutate resolved survival")
	check(NetworkManager.valid_arguments("ability", {"match_id": GameManager.match_id, "request": int(prompt.request_id), "cards": [1, 2]}), "network schema accepts a typed Sid survival request")
	check(not NetworkManager.valid_arguments("ability", {"match_id": GameManager.match_id, "request": "old", "cards": [1, 2]}), "network schema rejects an untyped Sid request")

	setup(2)
	GameManager.turns.current_player = 2
	GameManager.players[1].ability_id = "discard_heal"
	GameManager.players[1].current_hp = 1
	var sid_cards: Array = [give(1, "shoot"), give(1, "dodge"), give(1, "panic"), give(1, "cat_balou")]
	GameManager.damage(1, 2, 2)
	var first_sid_prompt := GameManager.reactions.private_prompt(1)
	use_sid(1, int(first_sid_prompt.request_id), [sid_cards[0].instance_id, sid_cards[1].instance_id])
	var second_sid_prompt := GameManager.reactions.private_prompt(1)
	check(GameManager.players[1].current_hp == 0 and int(second_sid_prompt.get("request_id", -1)) != int(first_sid_prompt.request_id), "Sid at -1 HP receives a fresh second survival request")
	use_sid(1, int(second_sid_prompt.request_id), [sid_cards[2].instance_id, sid_cards[3].instance_id])
	check(GameManager.players[1].is_alive and GameManager.players[1].current_hp == 1 and GameManager.players[1].hand.is_empty(), "Sid can heal twice to rescue from -1 HP")

func test_pass_timeout_and_win_order() -> void:
	setup(2)
	GameManager.players[1].current_hp = 1
	var beer := give(1, "drink")
	GameManager.damage(1, 2, 1)
	var prompt := GameManager.reactions.private_prompt(1)
	check(GameManager.winner.is_empty() and event_count("PLAYER_DIED", 1) == 0, "match does not end before pending survival is resolved")
	respond(1, int(prompt.request_id), int(beer.instance_id), false)
	check(not GameManager.players[1].is_alive and event_count("PLAYER_DIED", 1) == 1 and GameManager.winner == "OUTLAW WINS", "passing confirms death once and only then resolves the winner")
	GameManager.kill_player(1, 2)
	check(event_count("PLAYER_DIED", 1) == 1, "repeated death resolution cannot emit a second PLAYER_DIED")

	setup(2)
	GameManager.players[1].current_hp = 1
	give(1, "drink")
	GameManager.damage(1, 2, 1)
	GameManager.reactions.active.deadline = 0
	GameManager._process(0.0)
	check(not GameManager.players[1].is_alive and GameManager.reactions.active.is_empty() and event_count("PLAYER_DIED", 1) == 1, "survival timeout confirms death exactly once")

func test_death_consequences_once() -> void:
	setup(4)
	GameManager.players[1].role = PlayerState.Role.SHERIFF
	GameManager.players[2].role = PlayerState.Role.OUTLAW
	GameManager.players[3].role = PlayerState.Role.RENEGADE
	GameManager.players[4].role = PlayerState.Role.DEPUTY
	GameManager.players[3].ability_id = "death_collect"
	var victim_hand := give(2, "shoot")
	var victim_weapon := give(2, "schofield")
	GameManager.players[2].hand.erase(victim_weapon)
	GameManager.players[2].weapon = victim_weapon
	var victim_equipment := give(2, "barrel")
	GameManager.players[2].hand.erase(victim_equipment)
	GameManager.players[2].equipment["barrel"] = victim_equipment
	var collector_before: int = GameManager.players[3].hand.size()
	var sheriff_before: int = GameManager.players[1].hand.size()
	GameManager.players[2].current_hp = 1
	GameManager.damage(2, 1, 1)
	check(GameManager.players[3].hand.size() == collector_before + 3 and GameManager.players[3].hand.has(victim_hand), "Vulture Sam receives each physical victim card once")
	check(GameManager.players[1].hand.size() == sheriff_before + 3 and event_count("REWARD", 1) == 1, "Outlaw reward draws three cards exactly once")
	var collector_after: int = GameManager.players[3].hand.size()
	var sheriff_after: int = GameManager.players[1].hand.size()
	GameManager.kill_player(2, 1)
	check(GameManager.players[3].hand.size() == collector_after and GameManager.players[1].hand.size() == sheriff_after and event_count("REWARD", 1) == 1, "duplicate death cannot repeat Vulture collection or Outlaw reward")

	setup(4)
	GameManager.players[1].role = PlayerState.Role.SHERIFF
	GameManager.players[2].role = PlayerState.Role.DEPUTY
	GameManager.players[3].role = PlayerState.Role.OUTLAW
	GameManager.players[4].role = PlayerState.Role.RENEGADE
	give(1, "shoot")
	var sheriff_weapon := give(1, "schofield")
	GameManager.players[1].hand.erase(sheriff_weapon)
	GameManager.players[1].weapon = sheriff_weapon
	var sheriff_equipment := give(1, "barrel")
	GameManager.players[1].hand.erase(sheriff_equipment)
	GameManager.players[1].equipment["barrel"] = sheriff_equipment
	GameManager.players[2].current_hp = 1
	GameManager.damage(2, 1, 1)
	check(GameManager.players[1].hand.is_empty() and GameManager.players[1].weapon.is_empty() and GameManager.players[1].equipment.is_empty() and event_count("PENALTY", 1) == 1, "Sheriff penalty discards all cards and equipment exactly once")
	GameManager.kill_player(2, 1)
	check(event_count("PENALTY", 1) == 1, "duplicate death cannot repeat Sheriff penalty")

func test_rematch_clears_survival() -> void:
	setup(2)
	GameManager.players[1].current_hp = 1
	var beer := give(1, "drink")
	GameManager.damage(1, 2, 1)
	var prompt := GameManager.reactions.private_prompt(1)
	respond(1, int(prompt.request_id), int(beer.instance_id), false)
	var old_match: int = GameManager.match_id
	for player in GameManager.players.values():
		player.ready = true
	check(GameManager.try_start_rematch(), "ready players can start a fresh rematch")
	check(GameManager.match_id == old_match + 1 and GameManager.reactions.active.is_empty() and GameManager.turns.phase == "CHARACTER_SELECTION", "rematch clears the previous survival request")

func _ready() -> void:
	await get_tree().process_frame
	var capture := CaptureNetwork.new()
	capture.owner_test = self
	GameManager.network = capture
	test_normal_heal_all_counts()
	test_two_player_off_turn_rescue()
	test_negative_hp_requires_multiple_cards()
	test_authoritative_validation()
	test_no_rescue_and_reconnect()
	test_iced_tea_and_sid_survival()
	test_pass_timeout_and_win_order()
	test_death_consequences_once()
	test_rematch_clears_survival()
	GameManager.clear()
	GameManager.network = NetworkManager
	capture.free()
	if failures.is_empty():
		print("PASS: %d V25/V26 authoritative survival and death-order checks" % checks)
		get_tree().quit(0)
	else:
		print("FAIL: %d/%d V25/V26 survival assertions failed" % [failures.size(), checks])
		get_tree().quit(1)
