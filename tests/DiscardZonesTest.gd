extends Node

var checks: int = 0
var events: Array = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("DISCARD ZONES FAILED: " + message)
		get_tree().quit(1)
		assert(value, message)

func setup() -> void:
	GameManager.clear()
	for id in range(1, 5):
		GameManager.add_player(id, "Player %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()
	for id in GameManager.players:
		GameManager.selection.choose(GameManager, id, GameManager.selection.options[id][0])
	GameManager.reactions.active = {}
	GameManager.flow.jobs.clear()
	for p in GameManager.players.values():
		p.ability_id = ""
		p.current_hp = 4
		p.max_hp = 4
		p.role = PlayerState.Role.OUTLAW
		GameManager.discard_all(p)
	GameManager.players[1].role = PlayerState.Role.SHERIFF
	GameManager.players[4].role = PlayerState.Role.RENEGADE
	GameManager.turns.current_player = 1
	GameManager.turns.phase = "ACTION_PHASE"
	GameManager.rate_limits.clear()
	events.clear()

func give(id: int, kind: String) -> Dictionary:
	var card := CardInstance.make(GameManager.deck.next_id, kind, "HEART", "7")
	GameManager.deck.next_id += 1
	GameManager.players[id].hand.append(card)
	return card

func equip(kind: String) -> Dictionary:
	var card := give(2, kind)
	GameManager.players[2].hand.erase(card)
	if kind == "winchester":
		GameManager.players[2].weapon = card
	else:
		GameManager.players[2].equipment[kind] = card
	return card

func begin_discard() -> void:
	var cat := give(1, "cat_balou")
	GameManager.resolver.play(GameManager, 1, cat.instance_id, 2)
	check(GameManager.reactions.active.get("reaction_type", "") == "transfer", "Cat Balou opens zone selection even with empty victim hand")

func remove(kind: String, card: Dictionary) -> void:
	check(GameManager.flow.resolve({"accept": true, "option": "weapon" if kind == "winchester" else kind, "card": card.instance_id}), "specific physical card accepted")
	check(GameManager.deck.discard_pile.back() == card, "exact physical instance moves to discard")
	check(GameManager.public_snapshot().discard_top.instance_id == card.instance_id, "discard identity public")

func _ready() -> void:
	await get_tree().process_frame
	NetworkManager.table_event.connect(func(event): events.append(event.duplicate(true)))
	for kind in ["winchester", "horse", "spyglass", "barrel", "jail"]:
		setup()
		var physical := equip(kind)
		begin_discard()
		var request: Dictionary = GameManager.reactions.active.duplicate(true)
		check(not GameManager.flow.resolve({"accept": true, "option": "weapon" if kind == "winchester" else kind, "card": physical.instance_id + 100}), "forged/stale instance rejected")
		check(GameManager.reactions.active == request, "invalid selection preserves live request")
		remove(kind, physical)
		check(GameManager.players[2].weapon.is_empty() if kind == "winchester" else not GameManager.players[2].equipment.has(kind), "slot effect removed immediately")
		if kind == "winchester":
			check(DistanceManager.weapon_range(GameManager.players[2]) == 1, "implicit Colt .45 range immediately restored")
		elif kind == "horse":
			check(DistanceManager.distance(GameManager.players, 1, 2) == 1, "physical defensive modifier removed")
		elif kind == "spyglass":
			check(DistanceManager.distance(GameManager.players, 2, 4) == 2, "physical offensive modifier removed")
		elif kind == "barrel":
			var shot := give(1, "shoot")
			GameManager.resolver.play(GameManager, 1, shot.instance_id, 2)
			check(not events.any(func(e): return e.get("kind") == "judge"), "removed physical Barrel never judges")
			check(GameManager.reactions.active.get("reaction_type", "") == "dodge" and GameManager.reactions.active.get("allowed_card_types", []).is_empty(), "undefended BANG still exposes the compact skip reaction")
			GameManager.resolve_reaction(false)
			check(GameManager.players[2].current_hp == 3, "undefended BANG hits")
		else:
			events.clear()
			GameManager.begin_turn(2)
			check(not events.any(func(e): return e.get("kind") in ["judge", "jail_result"]), "removed Jail has no future judgement")
			check(GameManager.turns.current_player == 2 and GameManager.players[2].current_hp == 4, "no skipped turn or explosive damage")
	for pair in [["horse", "distance_defense"], ["spyglass", "distance_sight"], ["barrel", "innate_barrel"]]:
		setup()
		GameManager.players[2].ability_id = pair[1]
		var card := equip(pair[0])
		begin_discard()
		remove(pair[0], card)
		check(GameManager.players[2].ability_id == pair[1], "innate character ability survives physical discard")
		if pair[0] == "horse":
			check(DistanceManager.distance(GameManager.players, 1, 2) == 2, "Paul retains innate +1")
		elif pair[0] == "spyglass":
			check(DistanceManager.distance(GameManager.players, 2, 4) == 1, "Rose retains innate -1")
		else:
			events.clear()
			var shot := give(1, "shoot")
			GameManager.resolver.play(GameManager, 1, shot.instance_id, 2)
			check(events.filter(func(e): return e.get("kind") == "judge").size() == 1, "Jourdonnais retains exactly one innate check")
	setup()
	for kind in ["shoot", "dodge", "drink"]:
		give(2, kind)
	var before: Array = GameManager.players[2].hand.duplicate(true)
	begin_discard()
	var prompt: Dictionary = GameManager.private_snapshot(1).reaction
	check(prompt.choices.size() == 1 and not prompt.choices[0].has("instance_id"), "hand choice contains no hidden card identity")
	check(not GameManager.flow.resolve({"accept": true, "option": "hand", "card": before[0].instance_id}), "actor cannot choose hidden hand instance")
	check(GameManager.flow.resolve({"accept": true, "option": "hand"}), "server-random hand discard accepted")
	var top: Dictionary = GameManager.deck.discard_pile.back()
	check(before.has(top) and GameManager.players[2].hand.size() == 2, "random exactly one owned physical hand card removed")
	check(events.back().get("card", {}).get("instance_id") == top.instance_id and events.back().hidden, "hidden flight reveals actual card only at discard destination")
	# Replacing the same equipment type cannot make an old prompt select the new copy.
	setup()
	var old := equip("horse")
	begin_discard()
	GameManager.deck.discard(old)
	var replacement := equip("horse")
	check(not GameManager.flow.resolve({"accept": true, "option": "horse", "card": old.instance_id}), "same-name replacement rejects old physical selection")
	check(GameManager.players[2].equipment.horse == replacement, "stale request never removes replacement")
	GameManager.clear()
	print("PASS: %d Cat Balou hand/weapon/all blue zones, physical ID safety, immediate modifiers and innate ability checks" % checks)
	get_tree().quit()
