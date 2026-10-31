extends Node3D

var table: Node3D
var objects: Dictionary = {}
var state: Dictionary = {}
var choice: Dictionary = {}
var local_id: int = 1

func clear() -> void:
	for node in objects.values():
		node.free()
	objects.clear()

func sync(snapshot: Dictionary, owner: int, request: Dictionary) -> void:
	state = snapshot
	local_id = owner
	choice = request
	var present: Dictionary = {"deck": true, "discard": true}
	for p in state.players:
		if not p.is_alive or not table.avatars.has(p.player_id):
			continue
		var zones: Array = []
		if p.hand_count > 0:
			zones.append({"zone": "hand", "kind": "hand", "name": "TAY KÍN · %d" % p.hand_count})
		if not p.weapon_id.is_empty():
			zones.append({"zone": "weapon", "kind": "weapon", "name": CardData.data(p.weapon_id).name})
		for key in p.equipment_ids:
			zones.append({"zone": key, "kind": key, "name": CardData.data(key).name})
		var radial: Vector3 = table.avatars[p.player_id].position.normalized()
		var tangent := Vector3(radial.z, 0, -radial.x)
		for index in range(zones.size()):
			var zone: Dictionary = zones[index]
			var key: String = "%d:%s" % [p.player_id, zone.zone]
			present[key] = true
			if not objects.has(key):
				var item := TableObject.new()
				add_child(item)
				item.configure(zone.kind, {"name": zone.name}, {"kind": "zone", "player": p.player_id, "zone": zone.zone})
				item.position = radial * 2.55 + tangent * ((index - (zones.size() - 1) / 2.0) * 0.7) + Vector3.UP * 1.43
				item.rotation.y = atan2(radial.x, radial.z)
				item.scale = Vector3.ONE * 0.82
				objects[key] = item
			objects[key].title.text = zone.name
			var selectable: bool = choice.get("reaction_type", "") == "transfer" and int(choice.get("zone_player_id", 0)) == int(p.player_id) and choice.get("choices", []).any(func(c): return str(c.id) == str(zone.zone))
			if choice.get("reaction_type", "") == "draw_steal":
				selectable = zone.zone == "hand" and choice.get("choices", []).any(func(c): return str(c.id) == str(p.player_id))
			objects[key].highlight(selectable)
	var market: Array = state.get("market", [])
	for index in range(market.size()):
		var card: Dictionary = market[index]
		var key: String = "market:%d" % card.instance_id
		present[key] = true
		if not objects.has(key):
			var item := TableObject.new()
			add_child(item)
			var data: Dictionary = CardData.data(card.card_data_id).duplicate()
			data["suit"] = card.suit
			data["rank_label"] = GameManager.rank_text(card.rank)
			item.configure("card", data, {"kind": "market", "card": card.instance_id})
			var column: int = index % 4
			var row: int = index / 4
			item.position = Vector3((column - minf(3, market.size() - 1) / 2) * 0.79, 1.49, -0.95 + row * 1.9)
			objects[key] = item
		objects[key].highlight(choice.get("reaction_type", "") == "store")
	for key in objects.keys():
		if not present.has(key):
			objects[key].free()
			objects.erase(key)
	# These are transparent pick zones over the physical piles in SaloonRoom.
	for pile in ["deck", "discard"]:
		if not objects.has(pile):
			var zone := TableObject.new()
			add_child(zone)
			zone.configure("card", {"name": "RÚT BÀI" if pile == "deck" else "BỎ BÀI"}, {"kind": pile})
			zone.position = Vector3(-0.45 if pile == "deck" else 0.45, 1.58, 0)
			zone.scale = Vector3.ONE * 0.75
			objects[pile] = zone
		var allowed: bool = choice.get("reaction_type", "") in ["draw_steal", "draw_discard"] and choice.get("choices", []).any(func(c): return c.id == pile)
		objects[pile].highlight(allowed)

func token_allowed(token: Dictionary) -> bool:
	if token.get("kind", "") == "market":
		return choice.get("reaction_type", "") == "store" and state.get("market", []).any(func(c): return c.instance_id == token.card)
	if token.get("kind", "") == "zone":
		var key: String = "%d:%s" % [token.player, token.zone]
		return objects.has(key) and objects[key].enabled
	if token.get("kind", "") in ["deck", "discard"]:
		return objects.has(token.kind) and objects[token.kind].enabled
	return false
