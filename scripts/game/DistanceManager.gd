class_name DistanceManager
extends RefCounted

static func distance(players: Dictionary, attacker: int, target: int) -> int:
	var living: Array = players.values().filter(func(p): return p.is_alive)
	living.sort_custom(func(a, b): return a.seat_index < b.seat_index)
	var ids: Array = living.map(func(p): return p.player_id)
	if attacker == target or not ids.has(attacker) or not ids.has(target):
		return 999
	var gap: int = absi(ids.find(attacker) - ids.find(target))
	var base: int = mini(gap, ids.size() - gap)
	return maxi(1, base + int(players[target].equipment.has("horse"))
		+ int(players[target].ability_id == "distance_defense")
		- int(players[attacker].equipment.has("spyglass"))
		- int(players[attacker].ability_id == "distance_sight"))

static func weapon_range(player: PlayerState) -> int:
	return int(CardData.data(player.weapon.get("card_data_id", "")).get("weapon_range", 1))

static func in_range(players: Dictionary, attacker: int, target: int) -> bool:
	var reach: int = weapon_range(players[attacker])
	return distance(players, attacker, target) <= reach
