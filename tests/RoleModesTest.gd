extends Node

var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("FAILED: " + message)
		get_tree().quit(1)
		assert(value, message)

func prepare(count: int) -> void:
	GameManager.clear()
	for id in range(1, count + 1):
		GameManager.add_player(id, "Người %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()

func choose_all() -> void:
	for id in GameManager.players:
		var choices: Array = GameManager.selection.options.get(id, [])
		if not choices.is_empty():
			GameManager.selection.choose(GameManager, id, choices[0])

func sorted_roles() -> Array:
	var result: Array = GameManager.players.values().map(func(p): return p.role)
	result.sort()
	return result

func _ready() -> void:
	await get_tree().process_frame
	test_distributions_and_character_choice()
	test_small_table_starter_and_hp()
	test_host_and_rematch_shuffle()
	test_small_table_winners()
	test_base_table_sheriff_rules()
	GameManager.clear()
	print("PASS: %d production 2–7 role, starter, HP, character and winner checks" % checks)
	get_tree().quit()

func test_distributions_and_character_choice() -> void:
	var expected := {
		2: [PlayerState.Role.DEPUTY, PlayerState.Role.OUTLAW],
		3: [PlayerState.Role.DEPUTY, PlayerState.Role.OUTLAW, PlayerState.Role.RENEGADE],
		4: [PlayerState.Role.SHERIFF, PlayerState.Role.OUTLAW, PlayerState.Role.OUTLAW, PlayerState.Role.RENEGADE],
		5: [PlayerState.Role.SHERIFF, PlayerState.Role.DEPUTY, PlayerState.Role.OUTLAW, PlayerState.Role.OUTLAW, PlayerState.Role.RENEGADE],
		6: [PlayerState.Role.SHERIFF, PlayerState.Role.DEPUTY, PlayerState.Role.OUTLAW, PlayerState.Role.OUTLAW, PlayerState.Role.OUTLAW, PlayerState.Role.RENEGADE],
		7: [PlayerState.Role.SHERIFF, PlayerState.Role.DEPUTY, PlayerState.Role.DEPUTY, PlayerState.Role.OUTLAW, PlayerState.Role.OUTLAW, PlayerState.Role.OUTLAW, PlayerState.Role.RENEGADE]
	}
	for count in range(2, 8):
		prepare(count)
		check(GameManager.started, "%d players can start in production rules" % count)
		check(sorted_roles() == expected[count], "%d-player role distribution" % count)
		var all_options: Array = []
		for id in GameManager.players:
			var private_options: Array = GameManager.private_snapshot(id).character_options
			check(private_options.size() == 2, "player %d receives exactly two private options at %d players" % [id, count])
			all_options.append_array(GameManager.selection.options[id])
		check(all_options.size() == count * 2, "%d-player round offers exactly two per player" % count)
		var unique: Dictionary = {}
		for character_id in all_options:
			unique[character_id] = true
		check(unique.size() == all_options.size(), "%d-player character offers have no replacement" % count)
		check(not GameManager.public_snapshot().has("character_options"), "private choices are never public")

func test_small_table_starter_and_hp() -> void:
	for count in [2, 3]:
		prepare(count)
		check(GameManager.players.values().all(func(p): return p.role != PlayerState.Role.SHERIFF), "%d players have no Sheriff" % count)
		check(GameManager.public_snapshot().players.all(func(row): return row.public_role.is_empty()), "%d-player roles remain private" % count)
		choose_all()
		check(GameManager.players.has(GameManager.turns.current_player), "%d-player starter is selected from players" % count)
		for p in GameManager.players.values():
			var base_hp := int(CharacterData.get_data(p.character_id).max_hp)
			check(p.max_hp == base_hp, "%d-player mode applies no Sheriff HP bonus" % count)

func test_host_and_rematch_shuffle() -> void:
	for count in range(2, 8):
		var host_roles: Dictionary = {}
		var assignments: Dictionary = {}
		for trial in range(80):
			prepare(count)
			host_roles[GameManager.players[1].role] = true
			assignments[str(GameManager.players.values().map(func(p): return p.role))] = true
		check(host_roles.size() > 1, "host is not locked to one role at %d players" % count)
		check(assignments.size() > 1, "roles reshuffle between %d-player matches" % count)

func winner_with_survivor(count: int, role: int) -> String:
	prepare(count)
	var survivor_id := 1
	for id in GameManager.players:
		GameManager.players[id].role = PlayerState.Role.OUTLAW
		GameManager.players[id].is_alive = id == survivor_id
	GameManager.players[survivor_id].role = role
	GameManager.winner = ""
	return GameManager.check_win()

func test_small_table_winners() -> void:
	check(winner_with_survivor(2, PlayerState.Role.DEPUTY) == "DEPUTY WINS", "2-player Deputy wins after Outlaw elimination")
	check(winner_with_survivor(2, PlayerState.Role.OUTLAW) == "OUTLAW WINS", "2-player Outlaw wins after Deputy elimination")
	check(winner_with_survivor(3, PlayerState.Role.DEPUTY) == "DEPUTY WINS", "3-player Deputy wins as last survivor")
	check(winner_with_survivor(3, PlayerState.Role.OUTLAW) == "OUTLAW WINS", "3-player Outlaw wins as last survivor")
	check(winner_with_survivor(3, PlayerState.Role.RENEGADE) == "RENEGADE WINS", "3-player Renegade wins as last survivor")
	prepare(3)
	GameManager.players[1].role = PlayerState.Role.DEPUTY
	GameManager.players[2].role = PlayerState.Role.OUTLAW
	GameManager.players[3].role = PlayerState.Role.RENEGADE
	GameManager.players[1].is_alive = false
	check(GameManager.check_win().is_empty(), "3-player mode does not use Sheriff-dependent early victory")

func test_base_table_sheriff_rules() -> void:
	for count in range(4, 8):
		prepare(count)
		var sheriff: PlayerState
		for p in GameManager.players.values():
			if p.role == PlayerState.Role.SHERIFF:
				sheriff = p
		check(sheriff != null, "%d-player mode has one Sheriff" % count)
		check(GameManager.public_snapshot().players.any(func(row): return row.public_role == "SHERIFF"), "%d-player Sheriff is public" % count)
		check(GameManager.public_snapshot().players.filter(func(row): return row.public_role == "SHERIFF").size() == 1 and GameManager.public_snapshot().players.filter(func(row): return not row.public_role.is_empty()).size() == 1, "%d-player non-Sheriff roles stay private" % count)
		choose_all()
		check(GameManager.turns.current_player == sheriff.player_id, "%d-player Sheriff starts" % count)
		check(sheriff.max_hp == int(CharacterData.get_data(sheriff.character_id).max_hp) + 1, "%d-player Sheriff gets +1 HP" % count)
