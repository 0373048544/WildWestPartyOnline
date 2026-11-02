extends Node

var checks: int = 0
var last_error: String = ""

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("FAILED: " + message)
		get_tree().quit(1)
		assert(value, message)

func setup(count: int = 4) -> void:
	GameManager.clear()
	for id in range(1, count + 1):
		GameManager.add_player(id, "Người %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()
	choose_all()
	GameManager.reactions.active = {}
	GameManager.flow.jobs.clear()
	GameManager.flow.market.clear()
	for p in GameManager.players.values():
		p.ability_id = ""
		p.max_hp = 4
		p.current_hp = 4
		p.role = PlayerState.Role.OUTLAW
		GameManager.discard_all(p)
	GameManager.players[1].role = PlayerState.Role.SHERIFF
	if count > 2:
		GameManager.players[count].role = PlayerState.Role.RENEGADE
	GameManager.turns.current_player = 1
	GameManager.turns.phase = "ACTION_PHASE"
	GameManager.rate_limits.clear()

func choose_all() -> void:
	for id in GameManager.players:
		if GameManager.selection.options.has(id) and not GameManager.selection.chosen.has(id):
			GameManager.selection.choose(GameManager, id, GameManager.selection.options[id][0])
	for _i in range(20):
		if GameManager.reactions.active.is_empty():
			break
		GameManager.resolve_reaction(false)

func give(id: int, kind: String, suit: String = "SPADE", rank: int = 7) -> Dictionary:
	var card := CardInstance.make(GameManager.deck.next_id, kind, suit, rank)
	GameManager.deck.next_id += 1
	GameManager.players[id].hand.append(card)
	return card

func top(kind: String, suit: String, rank: int = 7) -> Dictionary:
	var card := CardInstance.make(GameManager.deck.next_id, kind, suit, rank)
	GameManager.deck.next_id += 1
	GameManager.deck.draw_pile.append(card)
	return card

func play(id: int, kind: String, target: int = 1) -> Dictionary:
	var card := give(id, kind)
	GameManager.resolver.play(GameManager, id, card.instance_id, target)
	return card

func respond(accept: bool = true, extra: Dictionary = {}) -> void:
	var args: Dictionary = {"accept": accept}
	args.merge(extra, true)
	check(GameManager.flow.resolve(args), "reaction accepted")

func _ready() -> void:
	await get_tree().process_frame
	NetworkManager.error_received.connect(func(message): last_error = message)
	test_deck()
	test_randomization()
	test_distance()
	test_shoot()
	test_characters()
	test_cards()
	test_death_and_privacy()
	GameManager.clear()
	print("PASS: %d base rules, randomization and privacy checks" % checks)
	get_tree().quit()

func test_deck() -> void:
	var deck := DeckManager.new()
	deck.reset()
	check(deck.draw_pile.size() == 86, "86-card deck including custom cards")
	var counts: Dictionary = {}
	var ids: Dictionary = {}
	var fixed: Dictionary = {}
	while not deck.draw_pile.is_empty():
		var card := deck.draw()
		check(not ids.has(card.instance_id), "unique card instance")
		ids[card.instance_id] = true
		counts[card.card_data_id] = int(counts.get(card.card_data_id, 0)) + 1
		fixed[card.instance_id] = [card.card_data_id, card.suit, card.rank]
		deck.discard(card)
	for key in CardData.definitions():
		check(counts.get(key, 0) == CardData.data(key).count, "base quantity " + key)
	check(not deck.draw().is_empty() and deck.draw_pile.size() == 85, "reshuffle")
	deck.reset()
	for card in deck.draw_pile:
		check(fixed[card.instance_id] == [card.card_data_id, card.suit, card.rank], "fixed configured suit/rank")
	deck.draw_pile.clear()
	deck.discard_pile.clear()
	check(deck.draw().is_empty(), "empty deck safe")
	check(CharacterData.definitions().size() == 16, "16 base characters")

func test_randomization() -> void:
	for count in [4, 5, 6, 7]:
		var host_roles: Dictionary = {}
		var character_pairs: Dictionary = {}
		for trial in range(100):
			GameManager.clear()
			for id in range(1, count + 1):
				GameManager.add_player(id, "Player%d" % id)
				GameManager.players[id].ready = true
			GameManager.start_match()
			var actual: Array = GameManager.players.values().map(func(p): return p.role)
			actual.sort()
			var expected := RoleData.pool(count)
			expected.sort()
			check(actual == expected, "role pool %d trial %d" % [count, trial])
			host_roles[GameManager.players[1].role] = true
			character_pairs[str(GameManager.selection.options[1])] = true
			var offered: Array = []
			for id in GameManager.players:
				offered.append_array(GameManager.selection.options[id])
			check(offered.size() == count * 2 and offered.size() == Array(set_unique(offered)).size(), "unique private character offers")
			var public: Dictionary = GameManager.public_snapshot()
			check(public.players.all(func(p): return p.character_id.is_empty()), "character selections not published early")
			check(not public.has("character_options") and not public.has("roles"), "selection/role privacy")
		check(host_roles.has(0) and host_roles.has(2) and host_roles.has(3), "host can be Sheriff, Outlaw and Renegade")
		check(character_pairs.size() > 1, "fresh character options each match")
		choose_all()
		var sheriff: int = 0
		for p in GameManager.players.values():
			if p.role == PlayerState.Role.SHERIFF:
				sheriff = p.player_id
		check(GameManager.turns.current_player == sheriff, "random Sheriff starts")
		var previous_ids: Array = GameManager.players[1].hand.map(func(c): return c.instance_id)
		GameManager.winner = "OUTLAWS WIN"
		for p in GameManager.players.values():
			p.ready = true
		GameManager.start_match()
		check(GameManager.turns.phase == "CHARACTER_SELECTION" and GameManager.players[1].hand.is_empty(), "rematch resets character/hand/turn")
		choose_all()
		check(GameManager.players[1].hand.all(func(c): return not previous_ids.has(c.instance_id)), "old card intentions cannot affect rematch")
	setup()
	var options: Array = GameManager.selection.options.keys()
	GameManager.winner = "OUTLAWS WIN"
	for p in GameManager.players.values():
		p.ready = true
	GameManager.start_match()
	check(not GameManager.selection.choose(GameManager, 1, "forged_character"), "reject unoffered character")
	var private: Dictionary = GameManager.private_snapshot(1)
	check(private.character_options.size() == 2, "exactly two private options")
	GameManager.selection.deadline = 0
	GameManager._process(0)
	check(GameManager.turns.phase != "CHARACTER_SELECTION", "selection timeout picks offered characters")

func set_unique(values: Array) -> Array:
	var unique: Dictionary = {}
	for value in values:
		unique[value] = true
	return unique.keys()

func test_distance() -> void:
	setup(7)
	var p: Dictionary = GameManager.players
	check(DistanceManager.distance(p, 1, 2) == 1 and DistanceManager.distance(p, 1, 7) == 1, "circular adjacent")
	check(DistanceManager.distance(p, 1, 4) == 3, "circular farther")
	p[2].is_alive = false
	check(DistanceManager.distance(p, 1, 3) == 1, "dead seats ignored")
	check(GameManager.turns.next_living(p) == 3, "turn skips dead")
	p[2].is_alive = true
	p[2].equipment.horse = give(2, "horse")
	p[2].ability_id = "distance_defense"
	check(DistanceManager.distance(p, 1, 2) == 3, "Paul + Mustang stack")
	p[1].equipment.spyglass = give(1, "spyglass")
	p[1].ability_id = "distance_sight"
	check(DistanceManager.distance(p, 1, 2) == 1, "Rose + Scope stack")
	check(DistanceManager.distance(p, 1, 3) == 1, "minimum one")
	p[1].ability_id = ""
	p[1].equipment.clear()
	for weapon in ["volcanic", "schofield", "remington", "carabine", "winchester"]:
		p[1].weapon = give(1, weapon)
		check(DistanceManager.weapon_range(p[1]) == CardData.data(weapon).amount, "weapon range " + weapon)
		check(DistanceManager.distance(p, 1, 4) == 3, "weapon never changes distance")
	p[1].weapon = {}
	check(DistanceManager.weapon_range(p[1]) == 1, "implicit Colt .45")

func test_shoot() -> void:
	setup()
	var p: Dictionary = GameManager.players
	var invalid := play(1, "shoot", 3)
	check(p[1].hand.has(invalid) and not p[1].shoot_used_this_action_turn, "invalid range consumes neither card nor Shoot")
	give(2, "dodge")
	GameManager.resolver.play(GameManager, 1, invalid.instance_id, 2)
	check(GameManager.reactions.active.reaction_type == "dodge", "Dodge prompt")
	var request: int = GameManager.reactions.active.request_id
	GameManager.handle_intent(3, "reaction", {"request": request, "accept": true})
	check(GameManager.reactions.active.request_id == request, "cannot respond for another peer")
	GameManager.rate_limits.clear()
	GameManager.handle_intent(2, "reaction", {"request": request - 1, "accept": true})
	check(GameManager.reactions.active.request_id == request, "stale reaction ignored")
	respond()
	check(p[2].current_hp == 4 and p[1].shoot_used_this_action_turn, "Dodge prevents hit but keeps Shoot limit")
	var again := play(1, "shoot", 2)
	check(p[1].hand.has(again) and last_error == "Bạn đã dùng BẮN trong lượt hành động này.", "second Shoot rejected with Vietnamese message")
	GameManager.begin_turn(1)
	for _i in range(20):
		if GameManager.reactions.active.is_empty():
			break
		respond(false)
	check(not p[1].shoot_used_this_action_turn, "new action turn resets Shoot")
	GameManager.resolver.play(GameManager, 1, again.instance_id, 2)
	check(GameManager.reactions.active.reaction_type == "dodge" and GameManager.reactions.active.payload.allowed_cards.is_empty(), "Shoot without Dodge still offers skippable reaction")
	respond(false)
	check(p[2].current_hp == 3, "Shoot deals one")
	for exception in ["volcanic", "unlimited_shoot"]:
		setup()
		if exception == "volcanic":
			GameManager.players[1].weapon = give(1, "volcanic")
		else:
			GameManager.players[1].ability_id = exception
		play(1, "shoot", 2)
		respond(false)
		play(1, "shoot", 2)
		respond(false)
		check(GameManager.players[2].current_hp == 2, exception + " unlimited Shoot")
	setup()
	GameManager.players[1].ability_id = "convert"
	var janet := play(1, "dodge", 2)
	check(not GameManager.players[1].hand.has(janet) and GameManager.players[1].shoot_used_this_action_turn, "Janet Dodge as Shoot counts")
	give(1, "dodge")
	check(GameManager.resolver.valid_targets(GameManager, 1, GameManager.players[1].hand.back()).is_empty(), "Janet second attack rejected")
	setup()
	GameManager.players[2].ability_id = "convert"
	give(2, "shoot")
	play(1, "shoot", 2)
	respond()
	check(GameManager.players[2].current_hp == 4, "Janet Shoot as Dodge")
	setup()
	GameManager.players[1].ability_id = "double_dodge"
	give(2, "dodge")
	give(2, "dodge")
	play(1, "shoot", 2)
	check(GameManager.reactions.active.required_count == 2, "Slab requires two")
	respond()
	check(GameManager.reactions.active.required_count == 1, "first Dodge is only partial")
	respond()
	check(GameManager.players[2].current_hp == 4, "two Dodge defend Slab")
	setup()
	GameManager.players[2].ability_id = "innate_barrel"
	GameManager.players[2].equipment.barrel = give(2, "barrel")
	GameManager.players[1].ability_id = "double_dodge"
	top("shoot", "HEART")
	top("shoot", "HEART")
	play(1, "shoot", 2)
	check(GameManager.players[2].current_hp == 4 and GameManager.reactions.active.is_empty(), "Jourdonnais + Barrel each cancel one Slab Dodge")
	setup()
	GameManager.players[2].ability_id = "judge_choose"
	GameManager.players[2].equipment.barrel = give(2, "barrel")
	var heart := top("dodge", "HEART")
	top("dodge", "SPADE")
	play(1, "shoot", 2)
	check(GameManager.reactions.active.reaction_type == "judge" and GameManager.reactions.active.payload.cards.size() == 2, "Lucky Duke choice")
	respond(true, {"cards": [heart.instance_id]})
	check(GameManager.players[2].current_hp == 4 and GameManager.reactions.active.is_empty(), "Lucky Duke chooses Heart")
	setup()
	give(2, "dodge")
	play(1, "shoot", 2)
	GameManager.reactions.active.deadline = 0
	GameManager._process(0)
	check(GameManager.players[2].current_hp == 3, "Dodge timeout takes hit")

func test_characters() -> void:
	setup()
	GameManager.players[2].ability_id = "damage_draw"
	GameManager.damage(2, 1, 3)
	check(GameManager.players[2].hand.size() == 3, "Bart draws per HP lost")
	setup()
	GameManager.players[2].ability_id = "damage_steal"
	for _i in range(3):
		give(1, "shoot")
	GameManager.damage(2, 1, 2)
	check(GameManager.players[2].hand.size() == 2 and GameManager.players[1].hand.size() == 1, "El Gringo random steal per damage")
	GameManager.damage(2, 0, 1)
	check(GameManager.players[2].hand.size() == 2, "Dynamite has no attacker")
	setup()
	GameManager.players[1].ability_id = "draw_reveal"
	top("dodge", "DIAMOND")
	top("shoot", "SPADE")
	GameManager.flow.draw_phase.begin(GameManager, 1)
	check(GameManager.players[1].hand.size() == 3, "Black Jack bonus for red second card")
	check(GameManager.log_lines.back().contains("NÉ"), "Black Jack reveals second only")
	setup()
	GameManager.players[1].ability_id = "draw_steal"
	var stolen := give(3, "winchester")
	GameManager.flow.draw_phase.begin(GameManager, 1)
	respond(true, {"option": "3"})
	check(GameManager.players[1].hand.has(stolen) and GameManager.players[1].hand.size() == 2, "Jesse first draw steals then draws")
	setup()
	GameManager.players[1].ability_id = "draw_discard"
	var discarded := give(2, "horse")
	GameManager.consume(2, discarded)
	GameManager.flow.draw_phase.begin(GameManager, 1)
	respond(true, {"option": "discard"})
	check(GameManager.players[1].hand.has(discarded) and GameManager.players[1].hand.size() == 2, "Pedro takes discard then deck")
	setup()
	GameManager.players[1].ability_id = "draw_choose"
	GameManager.flow.draw_phase.begin(GameManager, 1)
	var offered: Array = GameManager.reactions.active.payload.cards
	check(GameManager.private_snapshot(2).reaction.is_empty(), "Kit choice private to owner")
	respond(true, {"cards": [offered[0].instance_id, offered[2].instance_id]})
	check(GameManager.players[1].hand.size() == 2 and GameManager.deck.draw_pile.back() == offered[1], "Kit keeps two, returns third on top")
	setup()
	GameManager.players[1].ability_id = "discard_heal"
	GameManager.players[1].current_hp = 2
	var a := give(1, "shoot")
	var b := give(1, "dodge")
	check(not GameManager.abilities.heal_with_discards(GameManager, 1, [a.instance_id, a.instance_id]), "Sid must choose two distinct owned cards")
	check(GameManager.abilities.heal_with_discards(GameManager, 1, [a.instance_id, b.instance_id]) and GameManager.players[1].current_hp == 3, "Sid heals by discarding exactly two")
	setup()
	GameManager.players[1].ability_id = "discard_heal"
	GameManager.players[1].current_hp = 2
	for _i in range(4):
		give(1, "dodge")
	GameManager.handle_intent(1, "end", {})
	GameManager.rate_limits.clear()
	var sid_ids: Array = GameManager.players[1].hand.slice(0, 2).map(func(c): return c.instance_id)
	GameManager.handle_intent(1, "ability", {"cards": sid_ids})
	check(GameManager.turns.current_player == 2, "Sid healing/discard in Discard Phase cannot strand a zero-excess turn")
	setup()
	GameManager.players[2].ability_id = "empty_draw"
	a = give(2, "dodge")
	GameManager.consume(2, a)
	check(GameManager.players[2].hand.size() == 1, "Suzy refills outside her turn")
	GameManager.deck.draw_pile.clear()
	GameManager.deck.discard_pile.clear()
	GameManager.players[2].hand.clear()
	GameManager.abilities.hand_changed(GameManager, 2)
	check(GameManager.players[2].hand.is_empty(), "Suzy empty-deck guard")
	setup()
	GameManager.players[3].ability_id = "death_collect"
	give(2, "shoot")
	GameManager.players[2].weapon = give(2, "schofield")
	GameManager.players[2].hand.erase(GameManager.players[2].weapon)
	GameManager.players[2].equipment.horse = give(2, "horse")
	GameManager.players[2].hand.erase(GameManager.players[2].equipment.horse)
	GameManager.kill_player(2, 4)
	check(GameManager.players[3].hand.size() == 3, "Vulture receives hand, weapon and equipment")
	check(GameManager.players[4].hand.size() == 3, "Outlaw reward applies after Vulture")

func test_cards() -> void:
	setup()
	GameManager.players[2].current_hp = 2
	give(2, "drink")
	give(2, "drink")
	GameManager.damage(2, 0, 3)
	check(GameManager.reactions.active.required_count == 2, "multi-damage lethal Beer needs two")
	respond()
	check(GameManager.players[2].current_hp == 0 and not GameManager.reactions.active.is_empty(), "one Beer is insufficient")
	respond()
	check(GameManager.players[2].current_hp == 1 and GameManager.players[2].is_alive, "two Beer save at one")
	setup(2)
	GameManager.players[1].current_hp = 2
	var beer := play(1, "drink", 1)
	check(GameManager.players[1].current_hp == 2 and GameManager.players[1].hand.has(beer), "Beer disabled at two living players")
	GameManager.players[1].current_hp = 1
	GameManager.damage(1, 2)
	check(not GameManager.players[1].is_alive, "two-player Beer cannot save lethal damage")
	setup()
	for p in GameManager.players.values():
		p.current_hp = 2
	play(1, "saloon")
	check(GameManager.players.values().all(func(p): return p.current_hp == 3), "Saloon heals everyone")
	for kind in ["supply", "wells_fargo"]:
		setup()
		play(1, kind)
		check(GameManager.players[1].hand.size() == CardData.data(kind).amount, "draw card " + kind)
	setup()
	GameManager.players[1].weapon = give(1, "winchester")
	GameManager.players[1].hand.clear()
	give(3, "dodge")
	var panic := play(1, "panic", 3)
	check(GameManager.players[1].hand.has(panic), "Panic range ignores Winchester")
	GameManager.players[1].equipment.spyglass = give(1, "spyglass")
	GameManager.resolver.play(GameManager, 1, panic.instance_id, 3)
	respond(true, {"option": "hand"})
	check(GameManager.find_kind(1, "dodge").size() > 0, "Panic steals random hand card")
	setup()
	GameManager.players[3].weapon = give(3, "winchester")
	GameManager.players[3].hand.clear()
	play(1, "cat_balou", 3)
	respond(true, {"option": "weapon"})
	check(GameManager.players[3].weapon.is_empty() and DistanceManager.weapon_range(GameManager.players[3]) == 1, "Cat Balou removes visible weapon at any range")
	setup()
	play(1, "general_store")
	check(GameManager.flow.market.size() == 4, "Store exposes one card per living player")
	for id in range(1, 5):
		check(GameManager.reactions.active.target_player_id == id, "Store clockwise chooser")
		var uid: int = GameManager.flow.market[0].instance_id
		respond(true, {"cards": [uid]})
		check(GameManager.players[id].hand.size() == 1, "Store chosen card to owner")
	check(GameManager.flow.market.is_empty(), "Store finishes")
	setup()
	GameManager.players[1].ability_id = "double_dodge"
	give(2, "dodge")
	play(1, "gatling")
	check(GameManager.reactions.active.required_count == 1, "Slab does not amplify Gatling")
	respond()
	respond(false)
	check(not GameManager.players[1].shoot_used_this_action_turn and GameManager.players[3].current_hp == 3, "Gatling hits all others without Shoot limit")
	setup()
	GameManager.players[2].ability_id = "convert"
	give(2, "dodge")
	play(1, "indians")
	check(GameManager.reactions.active.reaction_type == "indians", "Indians demands Shoot response")
	respond()
	check(GameManager.players[2].current_hp == 4 and GameManager.players[3].current_hp == 3 and not GameManager.players[2].shoot_used_this_action_turn, "Janet conversion against Indians; no Shoot limit")
	setup()
	give(1, "shoot")
	give(2, "shoot")
	play(1, "showdown", 2)
	check(GameManager.reactions.active.target_player_id == 2, "Duel target responds first")
	respond()
	check(GameManager.reactions.active.target_player_id == 1, "Duel alternates")
	respond()
	check(GameManager.players[2].current_hp == 3 and not GameManager.players[1].shoot_used_this_action_turn and not GameManager.players[2].shoot_used_this_action_turn, "Duel discards never consume Shoot limit")
	setup()
	var illegal_jail := play(2, "jail", 1)
	check(GameManager.players[2].hand.has(illegal_jail), "Jail cannot target Sheriff")
	play(1, "jail", 3)
	check(GameManager.players[3].equipment.has("jail"), "Jail placed at any distance")
	top("shoot", "SPADE")
	GameManager.begin_turn(3)
	check(GameManager.turns.current_player == 4 and not GameManager.players[3].equipment.has("jail"), "failed Jail skips entire turn")
	setup()
	GameManager.players[2].dynamite = give(2, "dynamite")
	GameManager.players[2].equipment.jail = give(2, "jail")
	GameManager.players[2].hand.clear()
	top("dodge", "HEART")
	top("shoot", "SPADE", 2)
	GameManager.begin_turn(2)
	check(GameManager.players[2].current_hp == 1 and not GameManager.players[2].equipment.has("jail"), "Dynamite resolves before Jail")
	check(GameManager.turns.current_player == 2 and GameManager.turns.phase == "ACTION_PHASE", "survive Dynamite then escape Jail")
	setup()
	GameManager.players[1].dynamite = give(1, "dynamite")
	top("dodge", "HEART")
	GameManager.begin_turn(1)
	check(not GameManager.players[2].dynamite.is_empty() and GameManager.players[1].dynamite.is_empty(), "nonexploding Dynamite passes clockwise")
	setup()
	for _i in range(6):
		give(1, "dodge")
	GameManager.handle_intent(1, "end", {})
	check(GameManager.turns.phase == "DISCARD_PHASE", "hand limit uses current HP")
	for _i in range(2):
		GameManager.rate_limits.clear()
		GameManager.handle_intent(1, "discard", {"card": GameManager.players[1].hand[0].instance_id})
	check(GameManager.turns.current_player == 2, "discard choice advances turn")

func test_death_and_privacy() -> void:
	setup()
	GameManager.players[2].role = PlayerState.Role.DEPUTY
	give(1, "shoot")
	GameManager.players[1].weapon = give(1, "winchester")
	GameManager.players[1].equipment.horse = give(1, "horse")
	GameManager.kill_player(2, 1)
	check(GameManager.players[1].hand.is_empty() and GameManager.players[1].weapon.is_empty() and GameManager.players[1].equipment.is_empty(), "Sheriff kills Deputy penalty")
	setup()
	var public: Dictionary = GameManager.public_snapshot()
	for p in public.players:
		check(not p.has("hand") and not p.has("role") and not p.has("character_options"), "public excludes secrets")
		if p.player_id != 1:
			check(p.public_role.is_empty(), "hidden roles")
	check(not public.has("draw_pile") and not public.has("character_options"), "deck and private options not broadcast")
	GameManager.kill_player(2, 1)
	check(GameManager.players[2].public_snapshot().public_role == "OUTLAW", "dead role revealed")
	GameManager.kill_player(3, 1)
	GameManager.kill_player(4, 1)
	check(GameManager.winner == "SHERIFF TEAM WINS", "Sheriff team victory")
	setup()
	GameManager.kill_player(1, 2)
	check(GameManager.winner == "OUTLAWS WIN", "Outlaws win on Sheriff death")
	setup()
	GameManager.kill_player(2, 4)
	GameManager.kill_player(3, 4)
	GameManager.kill_player(1, 4)
	check(GameManager.winner == "RENEGADE WINS", "Renegade sole survivor")
	setup()
	GameManager.turns.current_player = 2
	GameManager.disconnect_player(2)
	check(not GameManager.players[2].is_alive and GameManager.turns.current_player == 3, "disconnect turn owner safely advances")
	check(not NetworkManager.valid_arguments("reaction", {"request": 1, "accept": true, "cards": [1,2,3]}), "malformed selection rejected")
	check(not NetworkManager.valid_arguments("ability", {"cards": ["fake", 1]}), "ability card types rejected")

