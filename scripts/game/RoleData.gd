class_name RoleData
extends RefCounted

static func pool(count: int) -> Array:
	match count:
		2: return [0, 2] # Development duel only.
		4: return [0, 2, 2, 3]
		5: return [0, 1, 2, 2, 3]
		6: return [0, 1, 2, 2, 2, 3]
		7: return [0, 1, 1, 2, 2, 2, 3]
	return []

static func assign(players: Dictionary) -> void:
	var roles := pool(players.size())
	roles.shuffle()
	for player in players.values():
		player.role = roles.pop_back()
