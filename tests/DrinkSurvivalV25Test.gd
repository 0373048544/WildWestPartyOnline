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
	func broadcast_animation(_actor: int, _kind: String, _target: int = 0) -> void: pass
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
	respond(1, int(prompt.request_id), int(beer.instance_id))
	check(GameManager.players[1].is_alive and GameManager.players[1].current_hp == 1, "off-turn UỐNG RƯỢU rescues to 1 HP")
	check(GameManager.reactions.active.is_empty(), "survival prompt closes after reaching 1 HP")

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
	GameManager.clear()
	GameManager.network = NetworkManager
	capture.free()
	print("PASS: %d V25 authoritative UỐNG RƯỢU survival checks" % checks)
	get_tree().quit(1 if not failures.is_empty() else 0)
