class_name EffectResolver
extends RefCounted

var handlers: Dictionary = {
	CardData.EffectType.ATTACK: attack, CardData.EffectType.HEAL: heal,
	CardData.EffectType.DRAW: supply, CardData.EffectType.EQUIP_WEAPON: weapon,
	CardData.EffectType.EQUIP_PASSIVE: passive, CardData.EffectType.DUEL: duel,
	CardData.EffectType.STEAL: steal, CardData.EffectType.DISCARD: discard_target,
	CardData.EffectType.GROUP_HEAL: saloon, CardData.EffectType.STORE: store,
	CardData.EffectType.GATLING: gatling, CardData.EffectType.INDIANS: indians,
	CardData.EffectType.JAIL: jail, CardData.EffectType.DYNAMITE: passive,
	CardData.EffectType.DEPARTMENT_STORE: department_store
}

func effective_effect(game: Node, sender: int, card: Dictionary) -> int:
	var effect: int = CardData.data(card.card_data_id).effect
	if effect == CardData.EffectType.DODGE and game.players[sender].ability_id == "convert":
		return CardData.EffectType.ATTACK
	return effect

func valid_targets(game: Node, sender: int, card: Dictionary) -> Array:
	var definition: Dictionary = CardData.data(card.get("card_data_id", ""))
	var result: Array = []
	if definition.is_empty() or not game.living(sender) or not game.reactions.active.is_empty() or game.turns.phase != "ACTION_PHASE" or game.turns.current_player != sender:
		return result
	var effect: int = effective_effect(game, sender, card)
	var p: PlayerState = game.players[sender]
	if effect == CardData.EffectType.DODGE:
		return result
	if effect == CardData.EffectType.ATTACK and not game.abilities.can_shoot(p):
		return result
	if effect == CardData.EffectType.HEAL and (p.current_hp >= p.max_hp or (card.card_data_id == "drink" and not game.beer_enabled())):
		return result
	if effect == CardData.EffectType.DEPARTMENT_STORE and p.department_store_used_this_match:
		return result
	if effect == CardData.EffectType.STORE and p.general_store_used_this_match:
		return result
	if card.get("card_data_id", "") == "panic" and p.panic_used_this_action_turn:
		return result
	if card.get("card_data_id", "") == "cat_balou" and p.cat_balou_used_this_action_turn:
		return result
	if effect == CardData.EffectType.DYNAMITE and not p.dynamite.is_empty():
		return result
	if effect == CardData.EffectType.EQUIP_PASSIVE and p.equipment.has(card.card_data_id):
		return result
	var targeted: bool = definition.target == CardData.TargetType.SINGLE_PLAYER or effect == CardData.EffectType.ATTACK
	if targeted:
		for id in game.players:
			var target: PlayerState = game.players[id]
			if id == sender or not game.living(id):
				continue
			if effect == CardData.EffectType.ATTACK and not DistanceManager.in_range(game.players, sender, id):
				continue
			if effect == CardData.EffectType.STEAL and DistanceManager.distance(game.players, sender, id) > 1:
				continue
			if [CardData.EffectType.STEAL, CardData.EffectType.DISCARD].has(effect) and target.hand.is_empty() and target.weapon.is_empty() and target.equipment.is_empty():
				continue
			if effect == CardData.EffectType.JAIL and (target.role == PlayerState.Role.SHERIFF or target.equipment.has("jail")):
				continue
			result.append(id)
	else:
		result.append(sender)
	return result

func play(game: Node, sender: int, uid: int, target: int) -> void:
	var card: Dictionary = game.find_card(sender, uid)
	if card.is_empty():
		game.fail(sender, "Lá bài không còn trên tay bạn.")
		return
	var effect: int = effective_effect(game, sender, card)
	if effect == CardData.EffectType.ATTACK and game.turns.phase == "ACTION_PHASE" and game.turns.current_player == sender and not game.abilities.can_shoot(game.players[sender]):
		game.fail(sender, "Bạn đã dùng BẮN trong lượt hành động này.")
		return
	if card.get("card_data_id", "") == "panic" and game.turns.phase == "ACTION_PHASE" and game.turns.current_player == sender and game.players[sender].panic_used_this_action_turn:
		game.fail(sender, "Bạn đã dùng HOẢNG LOẠN trong lượt hành động này.")
		return
	if card.get("card_data_id", "") == "cat_balou" and game.turns.phase == "ACTION_PHASE" and game.turns.current_player == sender and game.players[sender].cat_balou_used_this_action_turn:
		game.fail(sender, "Bạn đã dùng BỎ BÀI trong lượt hành động này.")
		return
	if not valid_targets(game, sender, card).has(target):
		var reason: String = disabled_reason(game,sender,card)
		if game.players.has(target) and [CardData.EffectType.STEAL, CardData.EffectType.DISCARD].has(effect):
			var victim: PlayerState = game.players[target]
			if not victim.dynamite.is_empty() and victim.hand.is_empty() and victim.weapon.is_empty() and victim.equipment.is_empty():
				reason = "THUỐC NỔ không thể bị lấy hoặc hủy."
		if effect == CardData.EffectType.ATTACK and game.living(target) and game.turns.current_player == sender and game.turns.phase == "ACTION_PHASE" and not DistanceManager.in_range(game.players,sender,target):
			reason = "Mục tiêu ngoài tầm bắn."
		game.fail(sender, reason if not reason.is_empty() else "Lá bài, mục tiêu hoặc tầm hiện tại không hợp lệ.")
		return
	var definition: Dictionary = CardData.data(card.card_data_id)
	if not handlers.has(effect):
		return
	game.players[sender].hand.erase(card)
	if definition.type != CardData.CardType.WEAPON and definition.type != CardData.CardType.EQUIPMENT:
		game.deck.discard(card)
		game.emit_event("CARD_PLAYED", sender, {"kind": "discard", "card": card.duplicate(), "from_zone": "hand", "to_zone": "discard"})
	game.abilities.hand_changed(game, sender)
	game.record("%s dùng %s%s." % [game.players[sender].display_name, definition.name,
		" vào " + game.players[target].display_name if target != sender else ""])
	if card.get("card_data_id", "") == "panic":
		game.players[sender].panic_used_this_action_turn = true
	elif card.get("card_data_id", "") == "cat_balou":
		game.players[sender].cat_balou_used_this_action_turn = true
	handlers[effect].call(game, sender, target, card)
	game.flow.run()

func disabled_reason(game: Node, sender: int, card: Dictionary) -> String:
	if not game.living(sender):
		return "Bạn đã bị loại."
	if not game.reactions.active.is_empty():
		var prompt: Dictionary = game.reactions.private_prompt(sender)
		return "" if prompt.get("allowed_card_types", []).has(card.instance_id) else "Đang chờ đáp trả hoặc lựa chọn hợp lệ."
	if game.turns.current_player != sender:
		return "Không phải lượt hành động của bạn."
	if game.turns.phase == "DISCARD_PHASE":
		return "Chọn lá bài để bỏ xuống chồng bỏ."
	if game.turns.phase != "ACTION_PHASE":
		return "Không thể dùng bài trong giai đoạn này."
	var p: PlayerState = game.players[sender]
	var effect := effective_effect(game, sender, card)
	if effect == CardData.EffectType.ATTACK and not game.abilities.can_shoot(p):
		return "Bạn đã dùng BẮN trong lượt hành động này."
	if effect == CardData.EffectType.HEAL:
		if card.card_data_id == "drink" and not game.beer_enabled():
			return "Bia không có tác dụng khi chỉ còn 2 người chơi."
		if p.current_hp >= p.max_hp:
			return "Bạn đã đầy máu."
	if effect == CardData.EffectType.DEPARTMENT_STORE and p.department_store_used_this_match:
		return "Bạn đã dùng BÁCH HÓA trong ván này."
	if effect == CardData.EffectType.STORE and p.general_store_used_this_match:
		return "Bạn đã dùng CỬA HÀNG trong ván này."
	if card.get("card_data_id", "") == "panic" and p.panic_used_this_action_turn:
		return "Bạn đã dùng HOẢNG LOẠN trong lượt hành động này."
	if card.get("card_data_id", "") == "cat_balou" and p.cat_balou_used_this_action_turn:
		return "Bạn đã dùng BỎ BÀI trong lượt hành động này."
	if effect == CardData.EffectType.DODGE:
		return "Chỉ dùng lá Né khi đáp trả hiệu ứng Bắn."
	if effect == CardData.EffectType.DYNAMITE and not p.dynamite.is_empty():
		return "Bạn đã có THUỐC NỔ trước mặt."
	if effect == CardData.EffectType.EQUIP_PASSIVE and p.equipment.has(card.card_data_id):
		return "Bạn đã có %s trên bàn." % CardData.data(card.card_data_id).name
	return "Không có mục tiêu hợp lệ trong tầm." if valid_targets(game, sender, card).is_empty() else ""

func attack(game: Node, sender: int, target: int, _card: Dictionary) -> void:
	game.players[sender].shoot_used_this_action_turn = true
	game.emit_event("BANG_FIRED", sender, {"kind": "bang", "target": target, "card_data_id": "shoot", "amount": 1, "result": "pending"})
	game.network.broadcast_animation(sender, "shoot", target)
	game.flow.push({"kind": "attack", "source": sender, "target": target, "required": 2 if game.players[sender].ability_id == "double_dodge" else 1})

func heal(game: Node, sender: int, _target: int, card: Dictionary) -> void:
	# The optional card id is presentation metadata only. Healing remains entirely
	# authoritative and keeps the same amount and validation path.
	game.heal(sender, 1, str(card.get("card_data_id", "")))

func supply(game: Node, sender: int, _target: int, card: Dictionary) -> void:
	game.draw_cards(sender, CardData.data(card.card_data_id).amount)

func weapon(game: Node, sender: int, _target: int, card: Dictionary) -> void:
	var previous: Dictionary = game.players[sender].weapon
	game.deck.discard(previous)
	if not previous.is_empty():
		game.emit_event("CARD_DISCARDED", sender, {"kind": "discard", "card": previous.duplicate(), "from_zone": "weapon", "to_zone": "discard"})
	game.players[sender].weapon = card
	game.emit_event("CARD_EQUIPPED", sender, {"kind": "equip", "card": card.duplicate(), "from_zone": "hand", "to_zone": "weapon"})

func passive(game: Node, sender: int, _target: int, card: Dictionary) -> void:
	if card.get("card_data_id", "") == "dynamite":
		game.players[sender].dynamite = card
		game.emit_event("CARD_EQUIPPED", sender, {"kind": "dynamite_placed", "card": card.duplicate(), "from_zone": "hand", "to_zone": "delayed"})
	else:
		game.players[sender].equipment[card.card_data_id] = card
		game.emit_event("CARD_EQUIPPED", sender, {"kind": "equip", "card": card.duplicate(), "from_zone": "hand", "to_zone": "equipment"})

func jail(game: Node, _sender: int, target: int, card: Dictionary) -> void:
	game.players[target].equipment.jail = card
	game.emit_event("CARD_EQUIPPED", target, {"kind": "equip", "card": card.duplicate(), "from_player": _sender, "from_zone": "hand", "to_zone": "equipment"})

func duel(game: Node, sender: int, target: int, _card: Dictionary) -> void:
	game.network.broadcast_table_event({"kind": "duel", "player": sender, "target": target})
	game.flow.push({"kind": "duel", "source": sender, "target": target})

func steal(game: Node, sender: int, target: int, _card: Dictionary) -> void:
	game.flow.push({"kind": "transfer", "source": sender, "target": target, "steal": true})

func discard_target(game: Node, sender: int, target: int, _card: Dictionary) -> void:
	game.flow.push({"kind": "transfer", "source": sender, "target": target, "steal": false})

func saloon(game: Node, _sender: int, _target: int, _card: Dictionary) -> void:
	for id in game.players:
		if game.living(id):
			game.heal(id, 1)

func store(game: Node, sender: int, _target: int, _card: Dictionary) -> void:
	game.players[sender].general_store_used_this_match = true
	game.emit_event("GENERAL_STORE_STARTED", sender, {
		"kind": "store_started", "message": "Mỗi người lần lượt chọn 1 lá."
	})
	game.flow.start_store(sender)

func gatling(game: Node, sender: int, _target: int, _card: Dictionary) -> void:
	game.network.broadcast_animation(sender, "gatling", 0)
	for id in game.living_order(sender, false):
		game.flow.push({"kind": "attack", "source": sender, "target": id, "required": 1})

func indians(game: Node, sender: int, _target: int, _card: Dictionary) -> void:
	for id in game.living_order(sender, false):
		game.flow.push({"kind": "indians", "source": sender, "target": id})

func department_store(game: Node, sender: int, _target: int, _card: Dictionary) -> void:
	game.players[sender].department_store_used_this_match = true
	var batch := {"receiver": sender, "count": 0}
	game.emit_event("DEPARTMENT_STORE_STARTED", sender, {
		"kind": "department_store", "receiver": sender,
		"message": "%s yêu cầu mỗi người đưa 1 lá." % game.players[sender].display_name
	})
	for giver in game.living_order(sender, false):
		game.flow.push({"kind": "department_store_give", "giver": giver,
			"receiver": sender, "batch": batch})
	game.flow.push({"kind": "department_store_finish", "receiver": sender, "batch": batch})


