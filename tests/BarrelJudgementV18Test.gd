extends Node

var checks := 0
var failures: Array[String] = []
var events: Array[Dictionary] = []
var table: Node = null

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("BARREL V18 FAILED: " + message)

func setup(attacker_ability := "", target_ability := "") -> void:
	GameManager.clear()
	for id in range(1, 5):
		GameManager.add_player(id, "Player %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()
	GameManager.selection.expire(GameManager)
	GameManager.flow.jobs.clear()
	GameManager.reactions.active = {}
	for player in GameManager.players.values():
		player.hand.clear()
		player.weapon = {}
		player.equipment.clear()
		player.ability_id = ""
		player.current_hp = 4
		player.max_hp = 4
	GameManager.players[1].ability_id = attacker_ability
	GameManager.players[2].ability_id = target_ability
	GameManager.turns.current_player = 1
	GameManager.turns.phase = "ACTION_PHASE"
	GameManager.rate_limits.clear()
	events.clear()

func give(id: int, card_id: String) -> Dictionary:
	var card := CardInstance.make(GameManager.deck.next_id, card_id, "CLUB", 8)
	GameManager.deck.next_id += 1
	GameManager.players[id].hand.append(card)
	return card

func top(suit: String, rank := 7) -> Dictionary:
	var card := CardInstance.make(GameManager.deck.next_id, "shoot", suit, rank)
	GameManager.deck.next_id += 1
	GameManager.deck.draw_pile.append(card)
	return card

func shoot() -> void:
	var card := give(1, "shoot")
	GameManager.resolver.play(GameManager, 1, card.instance_id, 2)

func equip_barrel() -> void:
	GameManager.players[2].equipment["barrel"] = CardInstance.make(GameManager.deck.next_id, "barrel", "CLUB", 7)
	GameManager.deck.next_id += 1

func event_index(event_type: String) -> int:
	for index in range(events.size()):
		if str(events[index].get("event_type", "")) == event_type:
			return index
	return -1

func test_normal_suits() -> void:
	setup(); equip_barrel(); var dodge := give(2, "dodge"); top("HEART"); shoot()
	expect(GameManager.reactions.active.is_empty(), "HEART resolves the normal BANG before a Dodge prompt")
	expect(GameManager.players[2].hand.has(dodge), "HEART judgement consumes no Dodge card")
	expect(GameManager.players[2].current_hp == 4, "HEART judgement prevents damage")
	expect(event_index("JUDGEMENT_REVEALED") >= 0 and event_index("JUDGEMENT_REVEALED") < event_index("JUDGEMENT_RESOLVED"), "revealed event precedes resolved event")

	setup(); equip_barrel(); dodge = give(2, "dodge"); top("SPADE"); shoot()
	expect(str(GameManager.reactions.active.get("reaction_type", "")) == "dodge", "SPADE creates Dodge prompt only after judgement")
	expect(GameManager.reactions.active.payload.get("judgement", {}).get("success", true) == false, "failed judgement is carried into authoritative prompt")
	expect(event_index("JUDGEMENT_RESOLVED") >= 0 and event_index("JUDGEMENT_RESOLVED") == events.size() - 1, "Dodge state exists after the resolved event")
	GameManager.flow.resolve({"accept": true, "card": dodge.instance_id})
	expect(GameManager.players[2].current_hp == 4 and not GameManager.players[2].hand.has(dodge), "valid Dodge after SPADE prevents damage exactly once")

	setup(); equip_barrel(); top("DIAMOND"); shoot()
	expect(GameManager.reactions.active.payload.get("allowed_cards", []).is_empty(), "DIAMOND without Dodge still gives a skippable prompt")
	GameManager.flow.resolve({"accept": false})
	expect(GameManager.players[2].current_hp == 3, "DIAMOND without Dodge deals exactly one damage")

	setup(); equip_barrel(); give(2, "dodge"); top("CLUB"); shoot(); GameManager.flow.resolve({"accept": false})
	expect(GameManager.players[2].current_hp == 3, "passing after CLUB deals exactly one damage")

	setup(); give(2, "dodge"); var deck_before := GameManager.deck.draw_pile.size(); top("HEART"); shoot()
	expect(event_index("JUDGEMENT_REVEALED") < 0 and GameManager.deck.draw_pile.size() == deck_before + 1, "no Barrel performs no judgement draw")

func test_character_interactions() -> void:
	setup("double_dodge"); equip_barrel(); top("HEART"); shoot()
	expect(str(GameManager.reactions.active.get("reaction_type", "")) == "dodge" and int(GameManager.reactions.active.get("resolved_count", -1)) == 1, "Slab + HEART contributes exactly one of two Dodges")
	GameManager.flow.resolve({"accept": false})
	expect(GameManager.players[2].current_hp == 3, "Slab partial Barrel success then pass deals one damage")

	setup("double_dodge"); equip_barrel(); var dodge := give(2, "dodge"); top("HEART"); shoot()
	GameManager.flow.resolve({"accept": true, "card": dodge.instance_id})
	expect(GameManager.players[2].current_hp == 4 and GameManager.reactions.active.is_empty(), "Slab HEART plus one Dodge avoids the shot")

	setup("double_dodge", "innate_barrel"); equip_barrel(); top("HEART"); top("HEART"); shoot()
	expect(GameManager.players[2].current_hp == 4 and GameManager.reactions.active.is_empty(), "Jourdonnais plus Barrel can supply two independent HEART results")
	expect(events.filter(func(event): return event.get("event_type", "") == "JUDGEMENT_RESOLVED").size() == 2, "two physical judgement results are emitted once each")

	setup("", "judge_choose"); equip_barrel(); var heart := top("HEART"); top("SPADE"); shoot()
	expect(str(GameManager.reactions.active.get("reaction_type", "")) == "judge", "Lucky Duke chooses before any Dodge prompt")
	GameManager.flow.resolve({"accept": true, "cards": [heart.instance_id]})
	expect(GameManager.players[2].current_hp == 4 and GameManager.reactions.active.is_empty(), "Lucky Duke choosing HEART resolves Barrel")

	setup("", "convert"); equip_barrel(); var bang := give(2, "shoot"); top("CLUB"); shoot()
	expect(GameManager.reactions.active.payload.get("allowed_cards", []).has(bang.instance_id), "Janet may use BANG only after failed judgement")
	GameManager.flow.resolve({"accept": true, "card": bang.instance_id})
	expect(GameManager.players[2].current_hp == 4, "Janet BANG as Dodge prevents damage")

func test_timeout_and_reconnect_idempotence() -> void:
	setup(); equip_barrel(); top("SPADE"); shoot()
	var event_count := events.size()
	var discard_count := GameManager.deck.discard_pile.size()
	GameManager.public_snapshot(); GameManager.private_snapshot(2); GameManager.public_snapshot()
	expect(events.size() == event_count and GameManager.deck.discard_pile.size() == discard_count, "repeated snapshots do not repeat judgement or discard")
	GameManager.reactions.active.deadline = 0
	GameManager._process(0.0)
	expect(GameManager.players[2].current_hp == 3 and GameManager.reactions.active.is_empty(), "timeout after failed judgement deals one damage and closes reaction")
	var damage_events := events.filter(func(event): return event.get("kind", "") == "damage" and int(event.get("player", 0)) == 2)
	expect(damage_events.size() == 1, "timeout cannot emit duplicate damage")

func _ready() -> void:
	NetworkManager.table_event.connect(func(event): events.append(event.duplicate(true)))
	await get_tree().process_frame
	test_normal_suits()
	test_character_interactions()
	test_timeout_and_reconnect_idempotence()
	setup(); equip_barrel(); var dodge := give(2, "dodge"); top("SPADE"); shoot()
	var banner: Control = load("res://scenes/ui/ReactionBanner.tscn").instantiate()
	add_child(banner)
	await get_tree().process_frame
	banner.present(self, GameManager.private_snapshot(2).reaction, GameManager.public_snapshot())
	expect("THÙNG" in banner.detail_label.text and "♠" in banner.detail_label.text,
		"compact reaction banner shows the revealed Barrel result before Dodge copy")
	expect(not banner.primary_button.disabled and banner.primary_card == dodge.instance_id,
		"Dodge button appears only in the post-judgement authoritative prompt")
	banner.queue_free()
	GameManager.clear()
	if failures.is_empty():
		print("PASS: %d Barrel judgement order, suit, character and reconnect checks" % checks)
		get_tree().quit(0)
	else:
		print("FAIL: %d/%d Barrel V18 checks" % [failures.size(), checks])
		get_tree().quit(1)
