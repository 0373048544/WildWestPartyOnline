extends Node

var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("CHARACTER ABILITY FAILED: " + message)

func setup(count: int = 4) -> void:
	GameManager.clear()
	for id in range(1, count + 1):
		GameManager.add_player(id, "Player %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()
	GameManager.selection.expire(GameManager)
	GameManager.reactions.active = {}
	GameManager.flow.jobs.clear()
	GameManager.flow.market.clear()
	for p in GameManager.players.values():
		p.ability_id = ""
		p.max_hp = 4
		p.current_hp = 4
		p.is_alive = true
		GameManager.discard_all(p)
	GameManager.deck.discard_pile.clear()
	GameManager.turns.current_player = 1
	GameManager.turns.phase = "ACTION_PHASE"
	GameManager.rate_limits.clear()

func give(id: int, kind: String, suit := "SPADE", rank: Variant = 7) -> Dictionary:
	var card := CardInstance.make(GameManager.deck.next_id, kind, suit, rank)
	GameManager.deck.next_id += 1
	GameManager.players[id].hand.append(card)
	return card

func top(kind: String, suit := "SPADE", rank: Variant = 7) -> Dictionary:
	var card := CardInstance.make(GameManager.deck.next_id, kind, suit, rank)
	GameManager.deck.next_id += 1
	GameManager.deck.draw_pile.append(card)
	return card

func test_automatic_damage() -> void:
	setup(); GameManager.players[2].ability_id = "damage_draw"
	GameManager.damage(2, 1, 2)
	check(GameManager.players[2].hand.size() == 2, "Bart draws once per HP lost")
	var before: int = GameManager.players[2].hand.size(); GameManager.heal(2, 1)
	check(GameManager.players[2].hand.size() == before, "Bart does not draw from healing")
	setup(); GameManager.players[2].ability_id = "damage_steal"; give(1, "shoot"); give(1, "dodge")
	GameManager.damage(2, 1, 2)
	check(GameManager.players[2].hand.size() == 2 and GameManager.players[1].hand.is_empty(), "El Gringo steals only source hand cards per player damage")
	before = GameManager.players[2].hand.size(); GameManager.damage(2, 0, 1)
	check(GameManager.players[2].hand.size() == before, "El Gringo ignores environmental damage")

func test_draw_abilities() -> void:
	setup(); GameManager.players[1].ability_id = "draw_reveal"; top("shoot", "HEART"); top("dodge", "SPADE")
	GameManager.flow.draw_phase.begin(GameManager, 1)
	check(GameManager.players[1].hand.size() == 3, "Black Jack red second card grants one private bonus")
	setup(); GameManager.players[1].ability_id = "draw_reveal"; top("shoot", "CLUB"); top("dodge", "SPADE")
	GameManager.flow.draw_phase.begin(GameManager, 1)
	check(GameManager.players[1].hand.size() == 2, "Black Jack black second card grants no bonus")
	setup(); GameManager.players[1].ability_id = "draw_steal"; give(2, "shoot")
	GameManager.flow.draw_phase.begin(GameManager, 1)
	check(GameManager.reactions.active.payload.choices.any(func(c): return str(c.id) == "2"), "Jesse offers an eligible opponent")
	setup(); GameManager.players[1].ability_id = "draw_steal"; GameManager.flow.draw_phase.begin(GameManager, 1)
	check(GameManager.reactions.active.payload.choices.size() == 1, "Jesse offers deck only when enemy hands are empty")
	setup(); GameManager.players[1].ability_id = "draw_choose"; GameManager.flow.draw_phase.begin(GameManager, 1)
	check(GameManager.reactions.active.reaction_type == "draw_choose" and GameManager.reactions.active.payload.cards.size() == 3, "Kit privately reserves top three")
	check(GameManager.private_snapshot(2).reaction.is_empty(), "Kit options never enter another player's private state")
	setup(); GameManager.players[1].ability_id = "draw_discard"; GameManager.flow.draw_phase.begin(GameManager, 1)
	check(GameManager.reactions.active.payload.choices.size() == 1, "Pedro cannot choose an empty discard pile")
	setup(); var discard: Dictionary = give(2, "shoot"); GameManager.consume(2, discard); GameManager.players[1].ability_id = "draw_discard"; GameManager.flow.draw_phase.begin(GameManager, 1)
	check(GameManager.reactions.active.payload.choices.any(func(c): return str(c.id) == "discard"), "Pedro may take exactly the top discard")

func test_conversion_and_combat() -> void:
	setup(); GameManager.players[2].ability_id = "convert"; var bang: Dictionary = give(2, "shoot")
	check(GameManager.abilities.response_cards(GameManager, 2, "dodge").has(bang), "Janet may use BANG as Dodge")
	GameManager.players[2].ability_id = ""
	check(not GameManager.abilities.response_cards(GameManager, 2, "dodge").has(bang), "non-Janet cannot convert response cards")
	setup(); GameManager.players[1].ability_id = "double_dodge"; var attack: Dictionary = give(1, "shoot")
	GameManager.resolver.play(GameManager, 1, attack.instance_id, 2)
	check(GameManager.reactions.active.required_count == 2, "Slab normal BANG requires two dodges")
	setup(); GameManager.players[1].ability_id = "double_dodge"; var gatling: Dictionary = give(1, "gatling")
	GameManager.resolver.play(GameManager, 1, gatling.instance_id, 1)
	check(GameManager.reactions.active.required_count == 1, "Slab does not amplify Gatling")
	setup(); GameManager.players[1].shoot_used_this_turn = true; GameManager.players[1].ability_id = "unlimited_shoot"
	check(GameManager.abilities.can_shoot(GameManager.players[1]), "Willy may keep shooting without Volcanic")
	GameManager.players[1].ability_id = ""
	check(not GameManager.abilities.can_shoot(GameManager.players[1]), "normal character remains limited to one BANG")

func test_judgement_distance_and_active() -> void:
	setup(); GameManager.players[2].ability_id = "innate_barrel"; top("shoot", "HEART"); var shot: Dictionary = give(1, "shoot")
	GameManager.resolver.play(GameManager, 1, shot.instance_id, 2)
	check(GameManager.players[2].current_hp == 4 and GameManager.reactions.active.is_empty(), "Jourdonnais innate Barrel resolves a normal BANG")
	setup(); GameManager.players[2].ability_id = "innate_barrel"; give(2, "shoot"); var indians: Dictionary = give(1, "indians"); GameManager.resolver.play(GameManager, 1, indians.instance_id, 1)
	check(GameManager.reactions.active.reaction_type == "indians", "Jourdonnais does not judge against Indians")
	setup(); GameManager.players[2].ability_id = "judge_choose"; GameManager.players[2].equipment.barrel = give(2, "barrel"); GameManager.players[2].hand.clear(); top("shoot", "SPADE"); top("shoot", "HEART"); shot = give(1, "shoot"); GameManager.resolver.play(GameManager, 1, shot.instance_id, 2)
	check(GameManager.reactions.active.reaction_type == "judge" and GameManager.reactions.active.payload.cards.size() == 2, "Lucky Duke chooses between exactly two judgements")
	setup(); GameManager.players[2].equipment.barrel = give(2, "barrel"); GameManager.players[2].hand.clear(); top("shoot", "HEART"); shot = give(1, "shoot"); GameManager.resolver.play(GameManager, 1, shot.instance_id, 2)
	check(GameManager.reactions.active.is_empty(), "normal character receives only one automatic judgement")
	setup(7); var base: int = DistanceManager.distance(GameManager.players, 1, 2); GameManager.players[2].ability_id = "distance_defense"
	check(DistanceManager.distance(GameManager.players, 1, 2) == base + 1, "Paul adds one to inbound distance")
	check(DistanceManager.distance(GameManager.players, 2, 1) == base, "Paul does not alter outbound distance")
	setup(7); base = DistanceManager.distance(GameManager.players, 1, 3); GameManager.players[1].ability_id = "distance_sight"
	check(DistanceManager.distance(GameManager.players, 1, 3) == maxi(1, base - 1), "Rose subtracts one from outbound distance")
	check(DistanceManager.distance(GameManager.players, 3, 1) == base, "Rose does not alter inbound distance")
	setup(); GameManager.players[1].ability_id = "discard_heal"; GameManager.players[1].current_hp = 3; var a: Dictionary = give(1, "shoot"); var b: Dictionary = give(1, "dodge")
	check(GameManager.abilities.heal_with_discards(GameManager, 1, [a.instance_id, b.instance_id]), "Sid heals with exactly two distinct hand cards")
	setup(); GameManager.players[1].ability_id = "discard_heal"; GameManager.players[1].current_hp = 3; a = give(1, "shoot")
	check(not GameManager.abilities.heal_with_discards(GameManager, 1, [a.instance_id, a.instance_id]), "Sid rejects a duplicate UID")

func test_empty_and_death() -> void:
	setup(); GameManager.players[2].ability_id = "empty_draw"; var last: Dictionary = give(2, "dodge"); GameManager.consume(2, last)
	check(GameManager.players[2].hand.size() == 1, "Suzy immediately refills an actually empty living hand")
	GameManager.players[2].is_alive = false; GameManager.players[2].hand.clear(); GameManager.abilities.hand_changed(GameManager, 2)
	check(GameManager.players[2].hand.is_empty(), "dead Suzy never refills")
	setup(); GameManager.players[3].ability_id = "death_collect"; give(2, "shoot"); GameManager.kill_player(2, 4)
	check(GameManager.players[3].hand.size() == 1, "Vulture collects another player's remaining cards")
	setup(); give(2, "shoot"); GameManager.kill_player(2, 4)
	check(GameManager.players[3].hand.is_empty(), "non-Vulture never receives death cards")

func _ready() -> void:
	await get_tree().process_frame
	test_automatic_damage()
	test_draw_abilities()
	test_conversion_and_combat()
	test_judgement_distance_and_active()
	test_empty_and_death()
	GameManager.clear()
	if failures.is_empty():
		print("PASS: %d focused positive/negative checks across all 16 character abilities" % checks)
		get_tree().quit()
	else:
		push_error("FAIL: %d/%d character ability checks failed" % [failures.size(), checks])
		get_tree().quit(1)
