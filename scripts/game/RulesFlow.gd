class_name RulesFlow
extends RefCounted

# A bounded event pump. No network request, animation or player choice blocks a loop.
var game: Node
var jobs: Array = []
var pumping: bool = false
var market: Array = []
var handlers: Dictionary = {}
var draw_phase := DrawPhaseResolver.new()

func _init(owner_game: Node = null) -> void:
	game = owner_game
	handlers = {"attack": attack, "duel": duel, "indians": indians, "damage": damage_job,
		"judged": judged, "dynamite": dynamite, "jail": jail, "draw": draw_job,
		"action": action_job, "store_pick": store_pick, "transfer": transfer}

func push(job: Dictionary, front: bool = false) -> void:
	if front:
		jobs.push_front(job)
	else:
		jobs.append(job)

func run() -> void:
	if pumping:
		return
	pumping = true
	var budget: int = 64
	while budget > 0 and not jobs.is_empty() and game.reactions.active.is_empty() and game.winner.is_empty():
		budget -= 1
		var job: Dictionary = jobs.pop_front()
		if handlers.has(job.kind):
			handlers[job.kind].call(job)
	pumping = false
	if not game.winner.is_empty():
		jobs.clear()
		market.clear()
	elif jobs.is_empty() and game.reactions.active.is_empty():
		game.finish_resolution()

func prompt(id: int, kind: String, context: Dictionary, payload: Dictionary) -> void:
	game.reactions.create(id, kind, context, payload)
	game.turns.phase = "REACTION"

func attack(job: Dictionary) -> void:
	var target: int = job.target
	if not game.living(target):
		return
	var required: int = job.get("required", 1)
	job["total_required"] = int(job.get("total_required", required))
	if required <= 0:
		game.network.broadcast_animation(target, "dodge", job.source)
		game.record(game.players[target].display_name + " đã Né.")
		return
	var checks: int = job.get("checks", -1)
	if checks < 0:
		checks = int(game.players[target].equipment.has("barrel")) + int(game.players[target].ability_id == "innate_barrel")
	job["checks"] = checks
	if checks > 0:
		judge(target, "barrel", job)
		return
	var cards: Array = game.abilities.response_cards(game, target, "dodge")
	if cards.is_empty():
		push({"kind": "damage", "target": target, "source": job.source, "amount": 1}, true)
		return
	prompt(target, "dodge", job, {"title": "BẠN ĐANG BỊ BẮN! • NÉ %d/%d" % [int(job.total_required) - required, int(job.total_required)],
		"allowed_cards": cards.map(func(c): return c.instance_id), "allowed_actions": ["card", "pass"]})

func duel(job: Dictionary) -> void:
	if not game.living(job.target) or not game.living(job.source):
		return
	response(job, "duel", "ĐẤU SÚNG • DÙNG LÁ BẮN ĐỂ ĐÁP TRẢ")

func indians(job: Dictionary) -> void:
	if game.living(job.target):
		response(job, "indians", "THỔ DÂN TẤN CÔNG! • DÙNG BẮN HOẶC CHỊU 1 SÁT THƯƠNG")

func response(job: Dictionary, kind: String, title: String) -> void:
	var cards: Array = game.abilities.response_cards(game, job.target, "shoot")
	if cards.is_empty():
		push({"kind": "damage", "target": job.target, "source": job.source, "amount": 1}, true)
	else:
		prompt(job.target, kind, job, {"title": title, "allowed_cards": cards.map(func(c): return c.instance_id), "allowed_actions": ["card", "pass"]})

func damage_job(job: Dictionary) -> void:
	game.damage(job.target, job.source, job.get("amount", 1))

func judge(id: int, purpose: String, context: Dictionary) -> void:
	var cards: Array = []
	for _i in range(2 if game.players[id].ability_id == "judge_choose" else 1):
		var card: Dictionary = game.deck.draw()
		if not card.is_empty():
			cards.append(card)
			game.record("%s lật phán định: %s." % [game.players[id].display_name, game.card_text(card)])
			game.emit_event("JUDGEMENT_REVEALED", id, {"kind": "judge", "card": card.duplicate(), "purpose": purpose})
	if cards.size() > 1:
		prompt(id, "judge", {"source": id, "purpose": purpose, "continuation": context, "cards": cards},
			{"cards": cards.duplicate(true), "pick_count": 1, "title": "LUCKY DUKE • CHỌN KẾT QUẢ PHÁN ĐỊNH"})
	else:
		var card: Dictionary = cards[0] if not cards.is_empty() else {}
		game.deck.discard(card)
		push({"kind": "judged", "target": id, "purpose": purpose, "card": card, "continuation": context}, true)

func judged(job: Dictionary) -> void:
	var id: int = job.target
	if not game.living(id):
		return
	var card: Dictionary = job.card
	match job.purpose:
		"barrel":
			var attack_context: Dictionary = job.continuation
			attack_context.checks -= 1
			if card.get("suit", "") == "HEART":
				attack_context.required -= 1
			var success: bool = card.get("suit", "") == "HEART"
			game.record("%s: %s" % ["THÙNG / JOURDONNAIS", "NÉ THÀNH CÔNG" if success else "PHÁN ĐỊNH THẤT BẠI"])
			game.emit_event("JUDGEMENT_RESOLVED", id, {"kind": "barrel_result", "success": success, "resolved": int(attack_context.total_required) - int(attack_context.required), "required": attack_context.total_required})
			push(attack_context, true)
		"jail":
			game.deck.discard(game.players[id].equipment.get("jail", {}))
			game.emit_event("CARD_DISCARDED", id, {"kind": "discard", "card": game.players[id].equipment.get("jail", {}).duplicate(), "from_zone": "equipment"})
			game.players[id].equipment.erase("jail")
			if card.get("suit", "") != "HEART":
				game.record(game.players[id].display_name + " bị giam, mất lượt.")
				game.network.broadcast_table_event({"kind": "jail_result", "player": id, "escaped": false})
				jobs.clear()
				game.advance_turn()
			else:
				game.record(game.players[id].display_name + " thoát khỏi Nhà giam.")
				game.network.broadcast_table_event({"kind": "jail_result", "player": id, "escaped": true})
		"dynamite":
			var explosive: Dictionary = game.players[id].equipment.get("dynamite", {})
			game.players[id].equipment.erase("dynamite")
			if card.get("suit", "") == "SPADE" and int(card.get("rank", 0)) >= 2 and int(card.get("rank", 0)) <= 9:
				game.deck.discard(explosive)
				game.emit_event("CARD_DISCARDED", id, {"kind": "discard", "card": explosive.duplicate(), "from_zone": "equipment"})
				game.record("Thuốc nổ phát nổ! Mất 3 máu.")
				game.damage(id, 0, 3)
			else:
				var passed := false
				for next in game.living_order(id, false):
					if not game.players[next].equipment.has("dynamite"):
						game.players[next].equipment.dynamite = explosive
						game.record("Thuốc nổ chuyển sang " + game.players[next].display_name + ".")
						game.emit_event("CARD_MOVED", id, {"kind": "dynamite_pass", "to": next, "card": explosive.duplicate()})
						passed = true
						break
				if not passed:
					game.deck.discard(explosive)

func dynamite(job: Dictionary) -> void:
	if game.living(job.target) and game.players[job.target].equipment.has("dynamite"):
		judge(job.target, "dynamite", {})

func jail(job: Dictionary) -> void:
	if game.living(job.target) and game.players[job.target].equipment.has("jail"):
		judge(job.target, "jail", {})

func draw_job(job: Dictionary) -> void:
	if game.living(job.target):
		draw_phase.begin(game, job.target)

func action_job(job: Dictionary) -> void:
	if game.living(job.target):
		game.turns.phase = "ACTION_PHASE"
	else:
		game.advance_turn()

func start_store(source: int) -> void:
	market.clear()
	var order: Array = game.living_order(source, true)
	for _id in order:
		var card: Dictionary = game.deck.draw()
		if not card.is_empty():
			market.append(card)
	for id in order:
		push({"kind": "store_pick", "source": source, "target": id})

func store_pick(job: Dictionary) -> void:
	if not game.living(job.target) or market.is_empty():
		return
	prompt(job.target, "store", {"source": job.source}, {"cards": market.duplicate(true),
		"pick_count": 1, "title": "CỬA HÀNG • CHỌN 1 LÁ BÀI"})

func transfer(job: Dictionary) -> void:
	if not game.living(job.target) or not game.living(job.source):
		return
	var victim: PlayerState = game.players[job.target]
	var choices: Array = []
	if not victim.hand.is_empty():
		choices.append({"id": "hand", "label": "Một lá ngẫu nhiên trên tay"})
	if not victim.weapon.is_empty():
		choices.append({"id": "weapon", "instance_id": victim.weapon.instance_id, "label": CardData.data(victim.weapon.card_data_id).name})
	for key in victim.equipment:
		choices.append({"id": key, "instance_id": victim.equipment[key].instance_id, "label": CardData.data(key).name})
	if choices.is_empty():
		return
	prompt(job.source, "transfer", job, {"choices": choices, "title": "CHỌN LÁ BÀI CỦA " + victim.display_name})

func resolve(args: Dictionary) -> bool:
	if game.reactions.active.is_empty():
		return false
	var r: Dictionary = game.reactions.active
	var id: int = r.target_player_id
	var context: Dictionary = r.context
	var kind: String = r.reaction_type
	var accept: bool = bool(args.get("accept", false))
	var selected: Array = args.get("cards", [])
	var option: String = str(args.get("option", ""))
	var payload: Dictionary = r.payload
	var card: Dictionary = {}
	if ["dodge", "duel", "indians", "survive"].has(kind) and accept:
		var required: String = "dodge" if kind == "dodge" else ("drink" if kind == "survive" else "shoot")
		var allowed: Array = game.abilities.response_cards(game, id, required)
		var uid: int = int(args.get("card", allowed[0].instance_id if not allowed.is_empty() else -1))
		card = game.find_card(id, uid)
		if card.is_empty() or not allowed.has(card):
			return false
	if payload.has("choices"):
		var choices: Array = payload.choices
		if option.is_empty() and not accept:
			option = str(choices[0].id)
		if not choices.any(func(c): return str(c.id) == option):
			return false
		if kind == "transfer":
			if not game.living(id) or not game.living(int(context.target)):
				return false
			var victim: PlayerState = game.players[context.target]
			if option == "hand":
				# Never accept a hand instance from the actor; authority chooses randomly.
				if victim.hand.is_empty() or int(args.get("card", 0)) != 0:
					return false
			else:
				var offered: Dictionary = choices.filter(func(c): return str(c.id) == option)[0]
				var physical: Dictionary = victim.weapon if option == "weapon" else victim.equipment.get(option, {})
				var expected: int = int(offered.get("instance_id", -1))
				if physical.is_empty() or physical.get("instance_id", -1) != expected or int(args.get("card", expected)) != expected:
					return false
	if payload.has("cards"):
		var cards: Array = payload.cards
		var count: int = int(payload.get("pick_count", 1))
		if selected.is_empty() and not accept:
			selected = cards.slice(0, count).map(func(c): return c.instance_id)
		if selected.size() != count:
			return false
		var seen: Dictionary = {}
		for uid in selected:
			if not uid is int or seen.has(uid) or not cards.any(func(c): return c.instance_id == uid):
				return false
			seen[uid] = true
	# All validation finishes before consuming the request or mutating any cards.
	game.reactions.active = {}
	match kind:
		"dodge":
			if accept:
				game.consume(id, card)
				game.emit_event("MISSED_USED", id, {"kind": "missed", "resolved": int(context.total_required) - int(context.required) + 1, "required": context.total_required})
				context.required -= 1
				context["resolved"] = int(context.get("resolved", 0)) + 1
				push(context, true)
			else:
				push({"kind": "damage", "target": id, "source": context.source, "amount": 1}, true)
		"duel", "indians":
			if accept:
				game.consume(id, card)
				if kind == "duel":
					game.network.broadcast_animation(id, "shoot", context.source)
					push({"kind": "duel", "target": context.source, "source": id}, true)
			else:
				push({"kind": "damage", "target": id, "source": context.source, "amount": 1}, true)
		"survive":
			if accept and game.beer_enabled():
				game.consume(id, card)
				game.heal(id, 1)
				if game.players[id].current_hp <= 0:
					game.offer_survival(id, context.source)
			else:
				game.kill_player(id, context.source)
		"draw_steal":
			var victim: int = int(option) if option.is_valid_int() else 0
			if game.living(victim) and victim != id and not game.players[victim].hand.is_empty():
				var stolen: Dictionary = game.players[victim].hand.pick_random()
				game.players[victim].hand.erase(stolen)
				game.players[id].hand.append(stolen)
				game.emit_event("CARD_STOLEN", victim, {"kind": "transfer", "to": id, "steal": true, "hidden": true, "from_zone": "hand"})
				game.abilities.hand_changed(game, victim)
			else:
				game.draw_cards(id, 1)
			game.draw_cards(id, 1)
		"draw_discard":
			if option == "discard" and not game.deck.discard_pile.is_empty():
				var reclaimed: Dictionary = game.deck.discard_pile.pop_back()
				game.players[id].hand.append(reclaimed)
				game.emit_event("CARD_DRAWN", id, {"kind": "reclaim", "card": reclaimed.duplicate(), "from_zone": "discard", "to_zone": "hand"})
			else:
				game.draw_cards(id, 1)
			game.draw_cards(id, 1)
		"draw_choose":
			for reserved in context.cards:
				if selected.has(reserved.instance_id):
					game.players[id].hand.append(reserved)
				else:
					game.deck.draw_pile.append(reserved)
			game.emit_event("CARD_DRAWN", id, {"kind": "draw", "count": selected.size(), "from_zone": "deck", "to_zone": "hand"})
		"judge":
			var result: Dictionary = {}
			for judged_card in context.cards:
				game.deck.discard(judged_card)
				if selected.has(judged_card.instance_id):
					result = judged_card
			push({"kind": "judged", "target": id, "purpose": context.purpose, "card": result, "continuation": context.continuation}, true)
		"store":
			for offered in market.duplicate():
				if selected.has(offered.instance_id):
					market.erase(offered)
					game.players[id].hand.append(offered)
					game.network.broadcast_table_event({"kind": "store_pick", "player": id, "card": offered.duplicate()})
		"transfer":
			complete_transfer(id, context, option)
	run()
	return true

func complete_transfer(id: int, context: Dictionary, option: String) -> void:
	var target: int = context.target
	if not game.living(target):
		return
	var victim: PlayerState = game.players[target]
	var taken: Dictionary = {}
	if option == "hand" and not victim.hand.is_empty():
		taken = victim.hand.pick_random()
		victim.hand.erase(taken)
	elif option == "weapon":
		taken = victim.weapon
		victim.weapon = {}
	elif victim.equipment.has(option):
		taken = victim.equipment[option]
		victim.equipment.erase(option)
	if not taken.is_empty():
		if context.steal:
			game.players[id].hand.append(taken)
		else:
			game.deck.discard(taken)
		game.abilities.hand_changed(game, target)
		var event := {"kind": "transfer", "to": id, "steal": context.steal, "hidden": option == "hand", "from_zone": option, "to_zone": "hand" if context.steal else "discard"}
		# A stolen hand card stays private. A discarded card becomes public at destination.
		if option != "hand" or not context.steal:
			event["card"] = taken.duplicate()
		game.emit_event("CARD_STOLEN" if context.steal else "CARD_DISCARDED", target, event)
		game.record("%s %s 1 lá %s %s." % [game.players[id].display_name, "lấy" if context.steal else "bỏ", "từ tay" if option == "hand" else "đang đặt trước", victim.display_name])

func cancel_for_disconnect(id: int) -> void:
	if game.reactions.active.is_empty():
		return
	var r: Dictionary = game.reactions.active
	if r.target_player_id == id:
		if ["dodge", "duel", "indians", "survive"].has(r.reaction_type):
			game.reactions.active = {}
		else:
			# Return private reserved cards safely; do not strand the queue.
			for card in r.context.get("cards", []):
				game.deck.discard(card)
			game.reactions.active = {}
	elif r.reaction_type == "duel" and r.context.get("source", 0) == id:
		game.reactions.active = {}

