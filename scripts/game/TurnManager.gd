class_name TurnManager
extends RefCounted

enum Phase { WAITING, GAME_STARTING, TURN_START, DRAW_PHASE, ACTION_PHASE, DISCARD_PHASE, TURN_END, REACTION, GAME_OVER }
var phase: String = "WAITING"
var current_player: int = 0
var round_number: int = 0

func next_living(players: Dictionary) -> int:
	var ordered: Array = players.values()
	ordered.sort_custom(func(a, b): return a.seat_index < b.seat_index)
	var ids: Array = ordered.map(func(p): return p.player_id)
	var start: int = ids.find(current_player)
	for offset in range(1, ids.size() + 1):
		var id: int = ids[(start + offset) % ids.size()]
		if players[id].is_alive and players[id].is_connected:
			return id
	return 0
