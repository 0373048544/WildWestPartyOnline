extends Node

var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("MULTIPLAYER STABILITY FAILED: " + message)
		get_tree().quit(1)
		assert(value, message)

func setup_game(count: int = 3) -> void:
	GameManager.clear()
	NetworkManager.mode = "offline"
	for id in range(1, count + 1):
		GameManager.add_player(id, "Player %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()
	GameManager.selection.expire(GameManager)
	for _step in range(16):
		if GameManager.reactions.active.is_empty():
			break
		GameManager.flow.resolve({"accept": false})
	GameManager.reactions.active = {}
	GameManager.flow.jobs.clear()
	for player in GameManager.players.values():
		player.ability_id = ""
		player.equipment.clear()
		player.dynamite = {}
	GameManager.turns.current_player = 1
	GameManager.turns.phase = "ACTION_PHASE"
	GameManager.turns.action_deadline = Time.get_ticks_msec() + TurnManager.ACTION_TIMEOUT_MS
	GameManager.rate_limits.clear()

func trim_to_hp(id: int) -> void:
	while GameManager.players[id].hand.size() > GameManager.players[id].current_hp:
		GameManager.consume(id, GameManager.players[id].hand.back())

func test_stale_match_intent() -> void:
	setup_game()
	trim_to_hp(1)
	var match_before: int = GameManager.match_id
	var hand_before: Array = GameManager.players[1].hand.duplicate(true)
	GameManager.handle_intent(1, "end", {"match_id": match_before - 1})
	check(GameManager.turns.current_player == 1 and GameManager.turns.phase == "ACTION_PHASE", "late previous-match END_TURN cannot advance the new match")
	check(GameManager.players[1].hand == hand_before and GameManager.match_id == match_before, "rejected stale intent mutates no cards or match state")
	GameManager.handle_intent(1, "end", {"match_id": match_before})
	check(GameManager.turns.current_player != 1, "same-match END_TURN remains valid")

func test_action_afk_timeout() -> void:
	setup_game()
	var player: PlayerState = GameManager.players[1]
	player.current_hp = 1
	var excess: int = maxi(0, player.hand.size() - player.current_hp)
	var discard_before: int = GameManager.deck.discard_pile.size()
	GameManager.turns.action_deadline = 1
	GameManager._process(0.0)
	check(excess > 0, "AFK fixture starts above the discard limit")
	check(player.hand.size() == player.current_hp, "server discards only the AFK player's required excess")
	check(GameManager.deck.discard_pile.size() == discard_before + excess, "AFK cleanup conserves every discarded physical card")
	check(GameManager.turns.current_player == 2 and GameManager.turns.phase == "ACTION_PHASE", "AFK action timeout advances to the next living player")
	var turn_after: int = GameManager.turns.action_turn_number
	GameManager._process(0.0)
	check(GameManager.turns.action_turn_number == turn_after, "expired AFK deadline resolves exactly once")

func test_disconnect_reaction_progress() -> void:
	setup_game()
	GameManager.reactions.create(2, "dodge", {"source": 1, "target": 2, "required": 1}, {"allowed_cards": []})
	GameManager.disconnect_player(2)
	check(GameManager.reactions.active.is_empty(), "disconnect clears the target's pending reaction")
	check(not GameManager.players[2].is_alive and not GameManager.players[2].is_connected, "expired session removes the disconnected player from gameplay")
	check(GameManager.turns.current_player != 2 and GameManager.living(GameManager.turns.current_player), "disconnect cannot strand the turn on a dead player")

func _ready() -> void:
	await get_tree().process_frame
	test_stale_match_intent()
	test_action_afk_timeout()
	test_disconnect_reaction_progress()
	print("PASS: %d stale-intent, AFK timeout and disconnect-reaction checks" % checks)
	get_tree().quit()
