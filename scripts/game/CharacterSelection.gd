class_name CharacterSelection
extends RefCounted

var options: Dictionary = {}
var chosen: Dictionary = {}
var deadline: int = 0

func begin(game: Node) -> bool:
	if not game.network.is_authority():
		return false
	var pool: Array = CharacterData.definitions().keys()
	if pool.size() != 16 or game.players.size() > 7 or game.players.size() < 2:
		push_error("Character selection requires all 16 base characters and 2–7 players.")
		return false
	options.clear()
	chosen.clear()
	pool.shuffle()
	for id in game.players:
		options[id] = [pool.pop_back(), pool.pop_back()]
	deadline = Time.get_ticks_msec() + 25000
	game.turns.phase = "CHARACTER_SELECTION"
	game.turns.current_player = 0
	return true

func choose(game: Node, id: int, character_id: String) -> bool:
	if not game.network.is_authority() or not game.started or game.turns.phase != "CHARACTER_SELECTION" or not game.living(id) or chosen.has(id) or not options.get(id, []).has(character_id):
		return false
	chosen[id] = character_id
	apply_character(game.players[id], character_id)
	if chosen.size() == game.players.size():
		finish(game)
	return true

func expire(game: Node) -> void:
	if not game.network.is_authority() or game.turns.phase != "CHARACTER_SELECTION":
		return
	for id in options:
		if not chosen.has(id):
			chosen[id] = options[id].pick_random()
			apply_character(game.players[id], chosen[id])
	finish(game)

func apply_character(player: PlayerState, character_id: String) -> void:
	var data: Dictionary = CharacterData.get_data(character_id)
	player.character_id = data.character_id
	player.ability_id = data.ability_id
	player.max_hp = int(data.max_hp) + int(player.role == PlayerState.Role.SHERIFF)
	player.current_hp = player.max_hp if player.is_alive else 0

func finish(game: Node) -> void:
	if not game.network.is_authority() or game.turns.phase != "CHARACTER_SELECTION" or chosen.size() != game.players.size():
		return
	var sheriff: int = 0
	for id in game.players:
		var player: PlayerState = game.players[id]
		apply_character(player, chosen[id])
		if player.is_alive and player.is_connected:
			game.draw_cards(id, player.max_hp)
		if player.role == PlayerState.Role.SHERIFF:
			sheriff = id
	options.clear()
	chosen.clear()
	game.begin_turn(sheriff)

func private_options(id: int) -> Array:
	if chosen.has(id):
		return []
	var result: Array = []
	for key in options.get(id, []):
		result.append(CharacterData.get_data(key).duplicate(true))
	return result
