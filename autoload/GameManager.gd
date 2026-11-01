extends Node

var network: Node
var players: Dictionary = {}
var started: bool = false
var match_id: int = 0
var winner: String = ""
var log_lines: Array[String] = []
var deck := DeckManager.new()
var turns := TurnManager.new()
var reactions := ReactionManager.new()
var resolver := EffectResolver.new()
var abilities := AbilityResolver.new()
var selection := CharacterSelection.new()
var flow: RulesFlow
var rate_limits: Dictionary = {}
var log_role_assignments: bool = false

func _ready() -> void:
	if network == null:
		network = NetworkManager
	flow = RulesFlow.new(self)

func clear() -> void:
	players.clear()
	started = false
	winner = ""
	log_lines.clear()
	reactions.active = {}
	turns = TurnManager.new()
	rate_limits.clear()
	selection = CharacterSelection.new()
	flow = RulesFlow.new(self)

func add_player(id: int, title: String) -> void:
	if not players.has(id):
		players[id] = PlayerState.new(id, title, players.size())

func _process(_delta: float) -> void:
	if not network.is_authority() or not started or not winner.is_empty():
		return
	if turns.phase == "CHARACTER_SELECTION" and Time.get_ticks_msec() >= selection.deadline:
		selection.expire(self)
		publish()
	elif reactions.expired():
		flow.resolve({"accept": false})
		publish()
	elif not flow.jobs.is_empty() and reactions.active.is_empty():
		flow.run()
		publish()

func role_distribution(count: int) -> Array:
	return RoleData.pool(count)

func start_match(force: bool = false) -> void:
	if not network.is_authority():
		return
	var connected: Array = players.values().filter(func(p): return p.is_connected)
	var valid_count: bool = connected.size() >= 2 and connected.size() <= 7
	if not valid_count or (not force and connected.any(func(p): return not p.ready)):
		fail(network.host_player_id(), "Cần 2–7 người và tất cả phải sẵn sàng.")
		return
	if started and winner.is_empty():
		return
	if not deck.reset():
		fail(network.host_player_id(), "Dữ liệu bộ bài không hợp lệ. Không thể bắt đầu ván.")
		return
	var fresh: Dictionary = {}
	for p in connected:
		fresh[p.player_id] = PlayerState.new(p.player_id, p.display_name, fresh.size())
	players = fresh
	RoleData.assign(players)
	match_id += 1
	# IDs do not get reused across rematches; late card intentions cannot hit new cards.
	for card in deck.draw_pile:
		card.instance_id += match_id * 1000
	deck.next_id += match_id * 1000
	turns = TurnManager.new()
	flow = RulesFlow.new(self)
	reactions.active = {}
	rate_limits.clear()
	log_lines.clear()
	winner = ""
	started = true
	if OS.is_debug_build() and log_role_assignments:
		for p in players.values():
			print("Match role assignment: Peer %d -> %s" % [p.player_id, PlayerState.ROLE_NAMES[p.role]])
	if not selection.begin(self):
		started = false
		fail(network.host_player_id(), "Không thể chia nhân vật: cần đủ bộ 16 nhân vật gốc.")

func living(id: int) -> bool:
	return players.has(id) and players[id].is_alive and players[id].is_connected

func living_order(first: int, include_first: bool) -> Array:
	var ordered: Array = players.values().filter(func(p): return p.is_alive)
	ordered.sort_custom(func(a, b): return a.seat_index < b.seat_index)
	var ids: Array = ordered.map(func(p): return p.player_id)
	var start: int = ids.find(first)
	var result: Array = []
	if ids.is_empty():
		return result
	for offset in range(0 if include_first else 1, ids.size() if include_first else ids.size() + 1):
		var id: int = ids[posmod(start + offset, ids.size())]
		if include_first or id != first:
			result.append(id)
	return result

func draw_cards(id: int, amount: int) -> Array:
	var drawn: Array = []
	if not players.has(id):
		return drawn
	for _i in range(amount):
		var card := deck.draw()
		if not card.is_empty():
			players[id].hand.append(card)
			drawn.append(card)
	if not drawn.is_empty():
		emit_event("CARD_DRAWN", id, {"kind": "draw", "count": drawn.size(), "from_zone": "deck", "to_zone": "hand"})
	return drawn

func begin_turn(id: int) -> void:
	if not winner.is_empty():
		return
	if id == 0:
		check_win()
		return
	turns.current_player = id
	turns.round_number += 1
	turns.phase = "TURN_START"
	players[id].shoot_used_this_turn = false
	flow.push({"kind": "dynamite", "target": id})
	flow.push({"kind": "jail", "target": id})
	flow.push({"kind": "draw", "target": id})
	flow.push({"kind": "action", "target": id})
	flow.run()

func advance_turn() -> void:
	turns.phase = "TURN_END"
	begin_turn(turns.next_living(players))

func handle_intent(sender: int, action: String, args: Dictionary) -> void:
	if not network.is_authority() or not players.has(sender):
		return
	var now := Time.get_ticks_msec()
	if now - int(rate_limits.get(sender, -1000)) < 80:
		return
	rate_limits[sender] = now
	if action == "ready" and not started:
		players[sender].ready = not players[sender].ready
	elif action == "start" and network.is_room_host(sender) and not started:
		start_match()
	elif action == "restart" and network.is_room_host(sender) and not winner.is_empty():
		for p in players.values():
			p.ready = true
		start_match()
	elif action == "lobby" and network.is_room_host(sender) and not winner.is_empty():
		started = false
		winner = ""
		reactions.active = {}
		flow.jobs.clear()
		flow.market.clear()
		turns.phase = "WAITING"
		for id in players.keys():
			if not players[id].is_connected:
				players.erase(id)
			else:
				players[id].ready = false
	elif action == "character" and started and winner.is_empty():
		if args.get("match_id", -1) == match_id:
			selection.choose(self, sender, str(args.get("character", "")))
	elif action == "debug" and network.is_room_host(sender) and OS.is_debug_build():
		debug_action(args)
	elif started and winner.is_empty() and players[sender].is_alive and turns.phase != "CHARACTER_SELECTION":
		match action:
			"play":
				resolver.play(self, sender, int(args.get("card", -1)), int(args.get("target", sender)))
			"end":
				if turns.current_player == sender and turns.phase == "ACTION_PHASE":
					if players[sender].hand.size() > players[sender].current_hp:
						turns.phase = "DISCARD_PHASE"
					else:
						advance_turn()
			"discard":
				if turns.current_player == sender and turns.phase == "DISCARD_PHASE":
					var card := find_card(sender, int(args.get("card", -1)))
					if not card.is_empty():
						consume(sender, card)
					if players[sender].hand.size() <= players[sender].current_hp:
						advance_turn()
			"reaction":
				if not reactions.active.is_empty() and reactions.active.target_player_id == sender and reactions.active.request_id == int(args.get("request", -1)):
					flow.resolve(args)
			"ability":
				var survival_source: int = int(reactions.active.get("context", {}).get("source", 0))
				if abilities.heal_with_discards(self, sender, args.get("cards", [])):
					if not reactions.active.is_empty() and reactions.active.target_player_id == sender and reactions.active.reaction_type == "survive":
						if players[sender].current_hp > 0:
							reactions.active = {}
							flow.run()
						else:
							reactions.active = {}
							offer_survival(sender, survival_source)
	flow.run()
	if started and winner.is_empty() and turns.phase == "DISCARD_PHASE" and reactions.active.is_empty() and players.has(turns.current_player) and players[turns.current_player].hand.size() <= players[turns.current_player].current_hp:
		advance_turn()
	publish()

func emit_event(event_type: String, id: int, details: Dictionary = {}) -> void:
	var event: Dictionary = details.duplicate(true)
	event["event_type"] = event_type
	event["player"] = id
	event["target_player_id"] = int(event.get("target_player_id", event.get("target", id)))
	var source_fallback: int = id if event_type in ["BANG_FIRED", "CARD_PLAYED"] else int(event.get("source", event.get("to", 0)))
	event["source_player_id"] = int(event.get("source_player_id", source_fallback))
	event["match_id"] = match_id
	network.broadcast_table_event(event)

func find_card(id: int, uid: int) -> Dictionary:
	if players.has(id):
		for card in players[id].hand:
			if card.instance_id == uid:
				return card
	return {}

func find_kind(id: int, kind: String) -> Dictionary:
	if players.has(id):
		for card in players[id].hand:
			if CardData.canonical_id(card.card_data_id) == CardData.canonical_id(kind):
				return card
	return {}

func consume(id: int, card: Dictionary) -> void:
	players[id].hand.erase(card)
	deck.discard(card)
	emit_event("CARD_DISCARDED", id, {"kind": "discard", "card": card.duplicate(), "from_zone": "hand", "to_zone": "discard"})
	abilities.hand_changed(self, id)

func beer_enabled() -> bool:
	return players.values().filter(func(p): return p.is_alive).size() > 2

func offer_survival(id: int, source: int) -> void:
	var p: PlayerState = players[id]
	var beer: Array = abilities.response_cards(self, id, "drink") if beer_enabled() else []
	var sid: bool = p.ability_id == "discard_heal" and p.hand.size() >= 2
	if beer.is_empty() and not sid:
		kill_player(id, source)
		return
	flow.prompt(id, "survive", {"source": source, "required": 1 - p.current_hp}, {
		"title": "HẤP HỐI • CẦN HỒI %d MÁU ĐỂ SỐNG SÓT" % (1 - p.current_hp),
		"allowed_cards": beer.map(func(c): return c.instance_id),
		"allowed_actions": ["beer", "sid", "pass"] if sid else ["beer", "pass"], "sid": sid})

func resolve_reaction(accept: bool) -> void:
	flow.resolve({"accept": accept})

func damage(target: int, source: int, amount: int = 1) -> void:
	if not living(target) or amount <= 0:
		return
	players[target].current_hp -= amount
	emit_event("DAMAGE", target, {"kind": "damage", "amount": amount, "source": source})
	network.broadcast_animation(target, "hit", source)
	record("%s mất %d máu." % [players[target].display_name, amount])
	abilities.on_damage(self, target, source, amount)
	if players[target].current_hp <= 0:
		offer_survival(target, source)

func heal(id: int, amount: int) -> void:
	var before: int = players[id].current_hp
	players[id].current_hp = mini(players[id].max_hp, before + amount)
	if players[id].current_hp > before:
		emit_event("HEAL", id, {"kind": "heal", "amount": players[id].current_hp - before})
		network.broadcast_animation(id, "drink", id)

func discard_all(p: PlayerState) -> void:
	for card in p.hand:
		deck.discard(card)
		emit_event("CARD_DISCARDED", p.player_id, {"kind": "discard", "card": card.duplicate(), "from_zone": "hand", "to_zone": "discard"})
	p.hand.clear()
	deck.discard(p.weapon)
	if not p.weapon.is_empty():
		emit_event("CARD_DISCARDED", p.player_id, {"kind": "discard", "card": p.weapon.duplicate(), "from_zone": "weapon", "to_zone": "discard"})
	p.weapon = {}
	for card in p.equipment.values():
		deck.discard(card)
		emit_event("CARD_DISCARDED", p.player_id, {"kind": "discard", "card": card.duplicate(), "from_zone": "equipment", "to_zone": "discard"})
	p.equipment.clear()
	abilities.hand_changed(self, p.player_id)

func kill_player(id: int, source: int) -> void:
	if not players.has(id) or not players[id].is_alive:
		return
	var p: PlayerState = players[id]
	p.is_alive = false
	p.current_hp = 0
	emit_event("PLAYER_DIED", id, {"kind": "death", "source": source})
	emit_event("ROLE_REVEALED", id, {"kind": "role", "role": PlayerState.ROLE_NAMES[p.role]})
	abilities.on_death(self, p)
	discard_all(p)
	record(TextCatalog.text("%s fell: %s") % [p.display_name, TextCatalog.text(PlayerState.ROLE_NAMES[p.role])])
	network.broadcast_animation(id, "death", source)
	if players.has(source) and players[source].is_alive and source != id:
		if p.role == PlayerState.Role.OUTLAW:
			emit_event("REWARD", source, {"kind": "reward"})
			draw_cards(source, 3)
			record(players[source].display_name + " được thưởng 3 lá vì hạ Tội phạm.")
		elif p.role == PlayerState.Role.DEPUTY and players[source].role == PlayerState.Role.SHERIFF:
			emit_event("PENALTY", source, {"kind": "penalty"})
			discard_all(players[source])
			record("Cảnh sát trưởng hạ Phó cảnh sát: bỏ toàn bộ bài và trang bị.")
	check_win()

func check_win() -> String:
	if not started:
		return ""
	var survivors: Array = players.values().filter(func(p): return p.is_alive)
	if players.size() <= 3:
		# The small-table variant has no Sheriff. It ends only with one survivor,
		# making every role outcome deterministic and independent of Sheriff rules.
		if survivors.size() == 1:
			winner = {PlayerState.Role.DEPUTY: "DEPUTY WINS", PlayerState.Role.OUTLAW: "OUTLAW WINS",
				PlayerState.Role.RENEGADE: "RENEGADE WINS"}.get(survivors[0].role, "")
	else:
		var sheriff_alive: bool = survivors.any(func(p): return p.role == PlayerState.Role.SHERIFF)
		if not sheriff_alive:
			winner = "RENEGADE WINS" if survivors.size() == 1 and survivors[0].role == PlayerState.Role.RENEGADE else "OUTLAWS WIN"
		elif not survivors.any(func(p): return p.role == PlayerState.Role.OUTLAW or p.role == PlayerState.Role.RENEGADE):
			winner = "SHERIFF TEAM WINS"
	if not winner.is_empty():
		turns.phase = "GAME_OVER"
		for reserved in reactions.active.get("context", {}).get("cards", []):
			deck.discard(reserved)
			emit_event("CARD_DISCARDED", int(reactions.active.get("target_player_id", 0)), {"kind": "judgement_discard" if reactions.active.get("reaction_type", "") == "judge" else "discard", "card": reserved.duplicate(), "from_zone": "reserved"})
		reactions.active = {}
		flow.jobs.clear()
		for card in flow.market:
			deck.discard(card)
		flow.market.clear()
	return winner

func finish_resolution() -> void:
	if not started or not winner.is_empty() or not reactions.active.is_empty() or not flow.jobs.is_empty() or turns.phase == "CHARACTER_SELECTION":
		return
	if not living(turns.current_player):
		advance_turn()
	elif turns.phase != "DISCARD_PHASE":
		turns.phase = "ACTION_PHASE"

func disconnect_player(id: int) -> void:
	if not players.has(id):
		return
	if not started:
		players.erase(id)
		var seat := 0
		for p in players.values():
			p.seat_index = seat
			seat += 1
	else:
		players[id].is_connected = false
		if turns.phase == "CHARACTER_SELECTION" and selection.options.has(id) and not selection.chosen.has(id):
			selection.chosen[id] = selection.options[id].pick_random()
		flow.cancel_for_disconnect(id)
		if players[id].is_alive and winner.is_empty():
			kill_player(id, 0)
		if turns.phase == "CHARACTER_SELECTION" and selection.chosen.size() == players.size() and winner.is_empty():
			selection.finish(self)
		flow.run()
	publish()

func card_text(card: Dictionary) -> String:
	return "%s (%s)" % [CardData.data(card.card_data_id).name, CardInstance.corner(card)]

func rank_text(rank: Variant) -> String:
	return CardInstance.rank_label(rank)

func record(message: String) -> void:
	log_lines.append(message)
	if log_lines.size() > 12:
		log_lines.pop_front()

func fail(id: int, message: String) -> void:
	network.send_notice(id, message)

func public_snapshot() -> Dictionary:
	var rows: Array = []
	for p in players.values():
		rows.append(p.public_snapshot(not winner.is_empty(), not p.character_id.is_empty()))
	return {"players": rows, "started": started, "match_id": match_id, "winner": winner,
		"server_port": network.session_port, "host_player_id": network.host_player_id(), "minimum_players": 2, "max_players": 7,
		"current_player": turns.current_player, "phase": turns.phase, "round": turns.round_number,
		"draw_count": deck.draw_pile.size(), "discard_count": deck.discard_pile.size(),
		"discard_top": deck.discard_pile.back() if not deck.discard_pile.is_empty() else {},
		"market": flow.market.duplicate(true), "choice_player": reactions.active.get("target_player_id", 0),
		"log": log_lines.duplicate(), "debug": OS.is_debug_build()}

func private_snapshot(id: int) -> Dictionary:
	var result: Dictionary = players[id].private_snapshot() if started else {}
	result["match_id"] = match_id
	result["character_options"] = selection.private_options(id)
	result["character_remaining"] = maxf(0, (selection.deadline - Time.get_ticks_msec()) / 1000.0)
	result["character_chosen"] = selection.chosen.has(id)
	result["selected_character"] = CharacterData.get_data(str(selection.chosen.get(id, ""))).duplicate(true)
	result["reaction"] = reactions.private_prompt(id)
	result["ability_id"] = players[id].ability_id
	var targets: Dictionary = {}
	var target_info: Dictionary = {}
	var disabled_reasons: Dictionary = {}
	if started and winner.is_empty() and living(id):
		for card in players[id].hand:
			targets[card.instance_id] = resolver.valid_targets(self, id, card)
			disabled_reasons[card.instance_id] = resolver.disabled_reason(self, id, card)
		for other in players:
			if other != id and living(other):
				target_info[other] = {"distance": DistanceManager.distance(players, id, other), "range": DistanceManager.weapon_range(players[id])}
	result["targets"] = targets
	result["target_info"] = target_info
	result["disabled_reasons"] = disabled_reasons
	return result

func publish() -> void:
	if network.is_authority():
		network.publish_game(self)

func debug_action(args: Dictionary) -> void:
	var operation: String = str(args.get("operation", ""))
	var target: int = int(args.get("target", 1))
	if operation == "Force Start":
		start_match(true)
		return
	if not started or not winner.is_empty() or not players.has(target) or turns.phase == "CHARACTER_SELECTION":
		return
	match operation:
		"Reveal Roles":
			var roles: Array = []
			for p in players.values():
				roles.append(p.display_name + ": " + TextCatalog.text(PlayerState.ROLE_NAMES[p.role]))
			fail(network.host_player_id(), " | ".join(roles))
		"Give Shoot":
			if living(target):
				players[target].hand.append(CardInstance.make(deck.next_id, "shoot", "SPADE", 7))
				deck.next_id += 1
		"Draw Card":
			if living(target):
				draw_cards(target, 1)
		"Damage Player":
			if reactions.active.is_empty() and living(target):
				damage(target, 1)
				flow.run()
		"Heal Player":
			if living(target):
				heal(target, 1)
		"Next Turn":
			if reactions.active.is_empty():
				advance_turn()
		"Force Win Check":
			check_win()

func debug_card_zones() -> Array:
	# Never serialize this into public/private player snapshots.
	if not OS.is_debug_build() or not network.is_authority():
		return []
	var result: Array = []
	var zones: Array = [{"zone": "deck", "owner": 0, "cards": deck.draw_pile},
		{"zone": "discard", "owner": 0, "cards": deck.discard_pile},
		{"zone": "market", "owner": 0, "cards": flow.market}]
	for p in players.values():
		zones.append({"zone": "hand", "owner": p.player_id, "cards": p.hand})
		zones.append({"zone": "weapon", "owner": p.player_id, "cards": [] if p.weapon.is_empty() else [p.weapon]})
		zones.append({"zone": "equipment", "owner": p.player_id, "cards": p.equipment.values()})
	if not reactions.active.is_empty():
		zones.append({"zone": "reserved", "owner": reactions.active.target_player_id, "cards": reactions.active.context.get("cards", [])})
	for zone in zones:
		for card in zone.cards:
			var entry: Dictionary = card.duplicate(true)
			entry["zone"] = zone.zone
			entry["owner"] = zone.owner
			result.append(entry)
	return result


