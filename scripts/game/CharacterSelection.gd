class_name CharacterSelection
extends RefCounted

var options: Dictionary = {}
var chosen: Dictionary = {}
var deadline: int = 0

func begin(game: Node) -> void:
	options.clear()
	chosen.clear()
	var pool: Array = CharacterData.definitions().keys()
	pool.shuffle()
	for id in game.players:
		options[id] = [pool.pop_back(), pool.pop_back()]
	deadline = Time.get_ticks_msec() + 25000
	game.turns.phase = "CHARACTER_SELECTION"
	game.turns.current_player = 0

func choose(game: Node, id: int, character_id: String) -> bool:
	if game.turns.phase != "CHARACTER_SELECTION" or chosen.has(id) or not options.get(id, []).has(character_id):
		return false
	chosen[id] = character_id
	if chosen.size() == game.players.size():
		finish(game)
	return true

func expire(game: Node) -> void:
	for id in options:
		if not chosen.has(id):
			chosen[id] = options[id].pick_random()
	finish(game)

func finish(game: Node) -> void:
	var sheriff: int = 0
	for id in game.players:
		var player: PlayerState = game.players[id]
		var data: Dictionary = CharacterData.get_data(chosen[id])
		player.character_id = data.character_id
		player.ability_id = data.ability_id
		player.max_hp = int(data.max_hp) + int(player.role == PlayerState.Role.SHERIFF)
		player.current_hp = player.max_hp
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
