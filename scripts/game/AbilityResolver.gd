class_name AbilityResolver
extends RefCounted

var refilling: bool = false
var damage_handlers: Dictionary = {"damage_draw": damage_draw, "damage_steal": damage_steal}

func can_shoot(player: PlayerState) -> bool:
	return not player.shoot_used_this_turn or player.ability_id == "unlimited_shoot" or player.weapon.get("card_data_id", "") == "volcanic"

func response_cards(game: Node, id: int, required: String) -> Array:
	var result: Array = []
	for card in game.players[id].hand:
		if card.card_data_id == required or (game.players[id].ability_id == "convert" and [required, card.card_data_id].all(func(k): return ["shoot", "dodge"].has(k))):
			result.append(card)
	return result

func hand_changed(game: Node, id: int) -> void:
	if refilling or not game.players.has(id):
		return
	var p: PlayerState = game.players[id]
	if p.is_alive and p.ability_id == "empty_draw" and p.hand.is_empty():
		refilling = true
		game.draw_cards(id, 1)
		refilling = false

func on_damage(game: Node, target: int, source: int, amount: int) -> void:
	var ability: String = game.players[target].ability_id
	if damage_handlers.has(ability):
		damage_handlers[ability].call(game, target, source, amount)

func damage_draw(game: Node, target: int, _source: int, amount: int) -> void:
	game.draw_cards(target, amount)

func damage_steal(game: Node, target: int, source: int, amount: int) -> void:
	if source == target or not game.players.has(source):
		return
	for _i in range(amount):
		if game.players[source].hand.is_empty():
			break
		var card: Dictionary = game.players[source].hand.pick_random()
		game.players[source].hand.erase(card)
		game.players[target].hand.append(card)
		hand_changed(game, source)

func heal_with_discards(game: Node, id: int, ids: Array) -> bool:
	var p: PlayerState = game.players[id]
	if p.ability_id != "discard_heal" or not p.is_alive or p.current_hp >= p.max_hp or ids.size() != 2 or ids[0] == ids[1]:
		return false
	var cards: Array = []
	for uid in ids:
		if not uid is int:
			return false
		var card: Dictionary = game.find_card(id, uid)
		if card.is_empty():
			return false
		cards.append(card)
	for card in cards:
		game.consume(id, card)
	game.heal(id, 1)
	return true

func on_death(game: Node, victim: PlayerState) -> bool:
	for p in game.players.values():
		if p.player_id != victim.player_id and p.is_alive and p.ability_id == "death_collect":
			p.hand.append_array(victim.hand)
			victim.hand.clear()
			if not victim.weapon.is_empty():
				p.hand.append(victim.weapon)
			p.hand.append_array(victim.equipment.values())
			victim.weapon = {}
			victim.equipment.clear()
			return true
	return false
