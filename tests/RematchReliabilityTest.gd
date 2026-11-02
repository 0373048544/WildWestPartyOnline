extends Node

var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("REMATCH RELIABILITY FAILED: " + message)
		get_tree().quit(1)
		assert(value, message)

func setup_game(count: int = 4) -> void:
	GameManager.clear()
	NetworkManager.mode = "offline"
	NetworkManager.begin_chat_room("SAME-ROOM")
	for id in range(1, count + 1):
		GameManager.add_player(id, "Player %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()
	GameManager.winner = "OUTLAWS WIN"
	GameManager.turns.phase = "GAME_OVER"
	GameManager.reactions.active = {}
	GameManager.flow.jobs.clear()
	GameManager.rate_limits.clear()
	for player in GameManager.players.values():
		player.ready = false

func continue_player(id: int) -> void:
	GameManager.rate_limits.erase(id)
	GameManager.handle_intent(id, "rematch", {})

func verify_fresh_match(expected_ids: Array, old_match: int, message: String) -> void:
	check(GameManager.match_id == old_match + 1, message + ": match_id increments exactly once")
	check(GameManager.winner.is_empty() and GameManager.turns.phase == "CHARACTER_SELECTION", message + ": fresh match returns to character selection")
	check(NetworkManager.chat_room == "SAME-ROOM", message + ": room identity is preserved")
	check(GameManager.players.keys().all(func(id): return expected_ids.has(id)) and GameManager.players.size() == expected_ids.size(), message + ": connected player IDs are preserved")
	check(GameManager.players.values().all(func(p): return p.is_connected and p.is_alive and not p.spectating and not p.ready), message + ": alive/spectating/ready state is reset")
	check(GameManager.players.values().all(func(p): return p.hand.is_empty() and p.weapon.is_empty() and p.equipment.is_empty() and p.dynamite.is_empty()), message + ": cards/equipment/delayed state is reset")
	var offered: Array = []
	for id in expected_ids:
		var options: Array = GameManager.selection.options.get(id, [])
		check(options.size() == 2 and options[0] != options[1], message + ": player %d receives two distinct private character choices" % id)
		offered.append_array(options)
	var unique: Dictionary = {}
	for option in offered:
		unique[option] = true
	check(unique.size() == offered.size(), message + ": character choices are dealt without replacement")

func _ready() -> void:
	setup_game(4)
	var old_match := GameManager.match_id
	for id in [1, 2, 3, 4]:
		continue_player(id)
	verify_fresh_match([1, 2, 3, 4], old_match, "all four continue")

	setup_game(4)
	old_match = GameManager.match_id
	continue_player(1)
	continue_player(2)
	continue_player(3)
	check(GameManager.match_id == old_match and GameManager.players[1].ready and GameManager.players[2].ready and GameManager.players[3].ready and not GameManager.players[4].ready, "three ready players wait for the fourth")
	GameManager.disconnect_player(4)
	verify_fresh_match([1, 2, 3], old_match, "fourth player leaves after others are ready")
	check(GameManager.players.values().all(func(p): return p.role != PlayerState.Role.SHERIFF), "three-player rematch uses the existing no-Sheriff role rules")

	setup_game(3)
	old_match = GameManager.match_id
	continue_player(1)
	check(GameManager.match_id == old_match and not GameManager.winner.is_empty(), "one ready player remains on game-over waiting state")
	check(GameManager.players[1].ready and not GameManager.players[2].ready and not GameManager.players[3].ready, "readiness remains per-player")

	setup_game(3)
	old_match = GameManager.match_id
	GameManager.players[1].is_alive = false
	GameManager.players[1].current_hp = 0
	GameManager.players[1].spectating = true
	for id in [1, 2, 3]:
		continue_player(id)
	verify_fresh_match([1, 2, 3], old_match, "dead spectator continues")
	check(GameManager.players[1].is_alive and not GameManager.players[1].spectating and GameManager.players[1].current_hp == GameManager.players[1].max_hp, "dead spectator returns alive with full normal state")

	print("PASS: %d same-room readiness, leave-after-ready, reset, role and character-rematch checks" % checks)
	get_tree().quit()
