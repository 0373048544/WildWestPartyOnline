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
			zones.append({"zone": "weapon", "kind": "weapon", "name": CardData.data(p.weapon_id).name, "card": p.get("weapon_card", {})})
		for key in p.equipment_ids:
			var physical: Array = p.get("equipment_cards", []).filter(func(c): return c.card_data_id == key)
			zones.append({"zone": key, "kind": key, "name": CardData.data(key).name, "card": physical[0] if not physical.is_empty() else {}})
		for delayed in p.get("delayed_cards", []):
			zones.append({"zone": "delayed_dynamite", "kind": "dynamite", "name": CardData.data("dynamite").name, "card": delayed})
		var radial: Vector3 = table.avatars[p.player_id].position.normalized()
		var tangent := Vector3(radial.z, 0, -radial.x)
		for index in range(zones.size()):
			var zone: Dictionary = zones[index]
			var key: String = "%d:%s" % [p.player_id, zone.zone]
			present[key] = true
			if objects.has(key) and zone.kind == "weapon" and objects[key].weapon_id != str(zone.get("card",{}).get("card_data_id","")):
				objects[key].play_remove()
				objects.erase(key)
			if not objects.has(key):
				var item := TableObject.new()
				add_child(item)
				item.configure(zone.kind, {"name": zone.name,"card_data_id":zone.get("card",{}).get("card_data_id","")}, {"kind": "zone", "player": p.player_id, "zone": zone.zone})
				item.weapon_id = str(zone.get("card",{}).get("card_data_id",""))
				item.position = radial * 2.55 + tangent * ((index - (zones.size() - 1) / 2.0) * 0.7) + Vector3.UP * 1.43
				item.rotation.y = atan2(radial.x, radial.z)
				item.scale = Vector3.ONE * 0.82
				objects[key] = item
				item.play_spawn()
			# Four compact public cards per row stay readable without stretching the
			# equipment strip across the neighbouring player's nameplate.
			var column: int = index % 4
			var row: int = index / 4
			var columns: int = mini(4, zones.size() - row * 4)
			var slot: Vector3 = radial * (2.55 + row * 0.68) + tangent * ((column - (columns - 1) / 2.0) * 0.62) + Vector3.UP * 1.43
			objects[key].position.x = slot.x
			objects[key].position.z = slot.z
			var local_first_person: bool = table.mobile_camera.enabled and int(p.player_id) == local_id
			# At the seated phone camera, the normal local radius puts public cards
			# centimetres from the lens. Keep them physically visible, but arrange a
			# smaller strip farther toward table center. Only the redundant secret
			# hand proxy remains hidden from its owner.
			if local_first_person and str(zone.zone) != "hand":
				var has_hand_proxy: int = 1 if not zones.is_empty() and str(zones[0].zone) == "hand" else 0
				var public_index: int = index - has_hand_proxy
				var public_count: int = zones.size() - has_hand_proxy
				var public_column: int = public_index % 4
				var public_row: int = public_index / 4
				var public_columns: int = mini(4, public_count - public_row * 4)
				var compact_slot := radial * (1.55 + public_row * 0.46) + tangent * ((public_column - (public_columns - 1) / 2.0) * 0.42) + Vector3.UP * 1.43
				objects[key].position.x = compact_slot.x
				objects[key].position.z = compact_slot.z
			objects[key].visible = not (local_first_person and str(zone.zone) == "hand")
			objects[key].scale = Vector3.ONE * (0.48 if local_first_person else (0.64 if int(p.player_id) == local_id else 0.82))
			objects[key].title.text = zone.name
			objects[key].token["card"] = int(zone.get("card", {}).get("instance_id", 0))
			if not zone.get("card", {}).is_empty():
				objects[key].title.text += "\n" + CardInstance.corner(zone.card)
				objects[key].set_face(zone.card)
			var selectable: bool = choice.get("reaction_type", "") == "transfer" and int(choice.get("zone_player_id", 0)) == int(p.player_id) and choice.get("choices", []).any(func(c): return str(c.id) == str(zone.zone) and (zone.zone == "hand" or int(c.get("instance_id", -1)) == int(zone.get("card", {}).get("instance_id", 0))))
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
			item.play_spawn(index * 0.08)
		objects[key].highlight(choice.get("reaction_type", "") == "store")
		objects[key].set_attention(int(state.get("choice_player", 0)) > 0)
	for key in objects.keys():
		if not present.has(key):
			objects[key].play_remove()
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
		if pile == "discard":
			var top: Dictionary = state.get("discard_top", {})
			objects[pile].title.text = "CHỒNG BỎ" if top.is_empty() else "%s\n%s" % [CardData.data(top.card_data_id).name, CardInstance.corner(top)]
			objects[pile].set_face(top)
		else:
			objects[pile].title.text = "CHỒNG RÚT\n%d lá" % state.get("draw_count", 0)

func token_allowed(token: Dictionary) -> bool:
	if token.get("kind", "") == "market":
		return choice.get("reaction_type", "") == "store" and state.get("market", []).any(func(c): return c.instance_id == token.card)
	if token.get("kind", "") == "zone":
		var key: String = "%d:%s" % [token.player, token.zone]
		return objects.has(key) and objects[key].enabled and int(objects[key].token.get("card", 0)) == int(token.get("card", 0))
	if token.get("kind", "") in ["deck", "discard"]:
		return objects.has(token.kind) and objects[token.kind].enabled
	return false
