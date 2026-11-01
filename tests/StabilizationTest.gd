extends Node

var checks: int = 0
var events: Array = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("STABILIZATION FAILED: " + message)
		get_tree().quit(1)
		assert(value, message)

func setup(select: bool = true) -> void:
	GameManager.clear()
	for id in range(1, 5):
		GameManager.add_player(id, "QA %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()
	for id in GameManager.players:
		GameManager.players[id].role = [PlayerState.Role.SHERIFF, PlayerState.Role.OUTLAW, PlayerState.Role.OUTLAW, PlayerState.Role.RENEGADE][id - 1]
	if select:
		GameManager.selection.expire(GameManager)
		for _index in range(8):
			if GameManager.reactions.active.is_empty():
				break
			GameManager.flow.resolve({"accept": false})
		GameManager.reactions.active = {}
		GameManager.flow.jobs.clear()
		# Resolve setup choices before clearing so reserved cards remain accounted for.
		for p in GameManager.players.values():
			p.ability_id = ""
			GameManager.discard_all(p)
		GameManager.turns.current_player = 1
		GameManager.turns.phase = "ACTION_PHASE"
	events.clear()

func take(id: int, kind: String) -> Dictionary:
	for zone in [GameManager.deck.draw_pile, GameManager.deck.discard_pile]:
		for card in zone:
			if card.card_data_id == kind:
				zone.erase(card)
				GameManager.players[id].hand.append(card)
				return card
	check(false, "required canonical card exists " + kind)
	return {}

func conserved() -> void:
	var cards: Array = GameManager.debug_card_zones()
	var ids: Dictionary = {}
	for card in cards:
		ids[card.instance_id] = true
	check(cards.size() == 80 and ids.size() == 80, "80 physical instances conserved")

func _ready() -> void:
	await get_tree().process_frame
	NetworkManager.table_event.connect(func(e): events.append(e.duplicate(true)))
	setup()
	var store := take(1, "general_store")
	GameManager.resolver.play(GameManager, 1, store.instance_id, 1)
	GameManager.disconnect_player(2)
	for _index in range(4):
		if GameManager.reactions.active.is_empty():
			break
		GameManager.flow.resolve({"accept": false})
	check(GameManager.flow.market.is_empty(), "Store leftovers discarded after chooser disconnect")
	check(events.any(func(e): return e.get("from_zone", "") == "market"), "leftover movement announced")
	conserved()
	store = take(1, "general_store")
	GameManager.resolver.play(GameManager, 1, store.instance_id, 1)
	for _index in range(4):
		if GameManager.reactions.active.is_empty():
			break
		GameManager.flow.resolve({"accept": false})
	conserved()
	setup()
	GameManager.players[2].ability_id = "judge_choose"
	GameManager.flow.judge(2, "barrel", {"kind": "attack", "source": 1, "target": 2, "required": 1, "total_required": 1, "checks": 1})
	var reserved: Array = GameManager.reactions.active.context.cards.duplicate()
	GameManager.kill_player(1, 3)
	check(GameManager.winner == "OUTLAWS WIN", "disconnect/death can end match during private choice")
	check(reserved.all(func(c): return GameManager.deck.discard_pile.has(c)), "game-over returns all reserved judgement cards")
	check(events.filter(func(e): return e.get("kind") == "judgement_discard").size() == 2, "both Lucky Duke results visibly go to discard")
	conserved()
	setup(false)
	var selected: String = GameManager.selection.options[2][0]
	GameManager.selection.choose(GameManager, 2, selected)
	GameManager.disconnect_player(2)
	check(GameManager.selection.chosen[2] == selected, "disconnect cannot replace confirmed choice")
	for id in [1, 3, 4]:
		GameManager.selection.choose(GameManager, id, GameManager.selection.options[id][0])
	check(not GameManager.players[2].is_alive and GameManager.players[2].current_hp == 0, "finishing selection cannot refill an eliminated player's HP")
	# Resolve any legitimate Sheriff draw choice before checking reserved zones.
	for _index in range(8):
		if GameManager.reactions.active.is_empty():
			break
		GameManager.flow.resolve({"accept": false})
	conserved()
	var app: Node = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	GameManager.publish()
	app.table.show_context(3)
	var portrait: Node = app.root.get_node("PlayerInfoCard").find_child("CharacterPortrait", true, false)
	var portrait_id: int = portrait.get_instance_id()
	GameManager.publish()
	check(app.root.get_node("PlayerInfoCard").find_child("CharacterPortrait", true, false).get_instance_id() == portrait_id, "same snapshot reuses portrait")
	GameManager.players[3].current_hp -= 1
	GameManager.publish()
	check(app.root.get_node("PlayerInfoCard").find_child("CharacterPortrait", true, false).get_instance_id() == portrait_id, "HP/text update reuses portrait renderer")
	app.table.presentation_queue.clear()
	var event := {"kind": "animation", "actor": 1, "animation": "shoot", "target": 3, "audio_event_id": "qa:duplicate"}
	app.table.presentation(event)
	app.table.presentation(event)
	check(app.table.presentation_queue.size() == 1, "duplicate network event cannot replay animation")
	GameManager.clear()
	print("PASS: %d disconnect, reserved-card conservation, remnant Store, portrait reuse and duplicate presentation checks" % checks)
	get_tree().quit()
