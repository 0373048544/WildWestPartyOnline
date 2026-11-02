extends Node

var checks := 0
var last_error := ""
var events: Array = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("DYNAMITE RULE FAILED: " + message)
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
	GameManager.flow.jobs.clear()
	GameManager.reactions.active = {}
	for player in GameManager.players.values():
		player.hand.clear()
		player.weapon = {}
		player.equipment.clear()
		player.dynamite = {}
		player.current_hp = 4
		player.max_hp = 4
		player.ability_id = ""
		player.role = PlayerState.Role.OUTLAW
	GameManager.players[1].role = PlayerState.Role.SHERIFF
	GameManager.players[4].role = PlayerState.Role.RENEGADE
	GameManager.turns.current_player = 1
	GameManager.turns.phase = "ACTION_PHASE"
	GameManager.rate_limits.clear()
	last_error = ""
	events.clear()

func make_card(kind: String, suit: String = "HEART", rank: int = 7) -> Dictionary:
	var card := CardInstance.make(GameManager.deck.next_id, kind, suit, rank)
	GameManager.deck.next_id += 1
	return card

func give(id: int, kind: String, suit: String = "HEART", rank: int = 7) -> Dictionary:
	var card := make_card(kind, suit, rank)
	GameManager.players[id].hand.append(card)
	return card

func top(kind: String, suit: String, rank: int) -> Dictionary:
	var card := make_card(kind, suit, rank)
	GameManager.deck.draw_pile.append(card)
	return card

func put_dynamite(id: int) -> Dictionary:
	var card := make_card("dynamite", "HEART", 7)
	GameManager.players[id].dynamite = card
	return card

func resolve_dynamite(id: int, suit: String, rank: int) -> void:
	top("dodge", suit, rank)
	GameManager.flow.push({"kind":"dynamite", "target":id})
	GameManager.flow.run()

func play(actor: int, kind: String, target: int) -> Dictionary:
	var card := give(actor, kind)
	GameManager.rate_limits.clear()
	GameManager.handle_intent(actor, "play", {"card":card.instance_id, "target":target})
	return card

func _ready() -> void:
	NetworkManager.error_received.connect(func(message): last_error = message)
	NetworkManager.table_event.connect(func(event): events.append(event.duplicate(true)))

	# A/B: delayed Dynamite is not an ordinary transfer/discard target.
	for effect in ["panic", "cat_balou"]:
		setup()
		var protected := put_dynamite(2)
		var action := play(1, effect, 2)
		check(not GameManager.find_card(1, action.instance_id).is_empty(), effect + " is rejected when Dynamite is the only table card")
		check(last_error == "THUỐC NỔ không thể bị lấy hoặc hủy.", effect + " receives exact protected-card message")
		check(GameManager.players[2].dynamite == protected and GameManager.reactions.active.is_empty(), effect + " cannot move delayed Dynamite")
		var barrel := make_card("barrel")
		GameManager.players[2].equipment.barrel = barrel
		last_error = ""
		play(1, effect, 2)
		var choices: Array = GameManager.private_snapshot(1).reaction.get("choices", [])
		check(choices.any(func(choice): return str(choice.get("id", "")) == "barrel") and not choices.any(func(choice): return str(choice.get("id", "")) == "dynamite"), effect + " chooser excludes Dynamite but keeps ordinary equipment")
		check(not GameManager.flow.resolve({"accept":true, "option":"dynamite", "card":protected.instance_id}), effect + " forged Dynamite option is rejected")
		check(last_error == "THUỐC NỔ không thể bị lấy hoặc hủy." and GameManager.players[2].dynamite == protected, effect + " forged UID cannot bypass server")

	# C: 5 of Spades explodes for exactly three and discards the physical card.
	setup()
	var explosive := put_dynamite(1)
	resolve_dynamite(1, "SPADE", 5)
	check(GameManager.players[1].current_hp == 1, "5 Spades deals exactly three HP")
	check(GameManager.players[1].dynamite.is_empty() and GameManager.deck.discard_pile.has(explosive), "exploded Dynamite enters discard and does not pass")

	# D/E: 10 of Spades is safe; the same UID can circulate indefinitely.
	setup()
	var circulating := put_dynamite(1)
	resolve_dynamite(1, "SPADE", 10)
	check(GameManager.players[2].dynamite == circulating, "10 Spades passes to next living player")
	var expected_holders := [3, 4, 1, 2, 3, 4, 1]
	var holder := 2
	for expected in expected_holders:
		resolve_dynamite(holder, "HEART", 10)
		holder = expected
		check(GameManager.players[holder].dynamite.get("instance_id", 0) == circulating.instance_id, "same Dynamite passes to holder %d" % holder)
		var copies := GameManager.players.values().filter(func(player): return player.dynamite.get("instance_id", 0) == circulating.instance_id).size()
		check(copies == 1, "circulating Dynamite remains unique")

	# F: death/disconnect passes before Vulture collection and ordinary discard-all.
	setup()
	var death_dynamite := put_dynamite(2)
	give(2, "dodge")
	GameManager.players[3].ability_id = "death_collect"
	GameManager.kill_player(2, 1)
	check(GameManager.players[3].dynamite == death_dynamite, "dead holder passes Dynamite to next living player")
	check(not GameManager.players[3].hand.has(death_dynamite), "Vulture Sam never receives Dynamite in hand")
	GameManager.discard_all(GameManager.players[3])
	check(GameManager.players[3].dynamite == death_dynamite and not GameManager.deck.discard_pile.has(death_dynamite), "ordinary discard_all preserves delayed Dynamite")
	GameManager.disconnect_player(3)
	check(GameManager.players[4].dynamite == death_dynamite, "disconnect/death policy passes Dynamite without freezing")

	# G: Lucky Duke's selected card, not the other reveal, decides explosion.
	setup()
	var lucky_dynamite := put_dynamite(2)
	GameManager.players[2].ability_id = "judge_choose"
	var safe := top("dodge", "HEART", 10)
	var boom := top("shoot", "SPADE", 5)
	GameManager.flow.push({"kind":"dynamite", "target":2})
	GameManager.flow.run()
	check(GameManager.reactions.active.get("reaction_type", "") == "judge" and GameManager.reactions.active.payload.cards.size() == 2, "Lucky Duke receives two private judgement options")
	check(GameManager.flow.resolve({"accept":true, "cards":[boom.instance_id]}), "Lucky Duke can select one judgement")
	check(GameManager.players[2].current_hp == 1 and GameManager.players[2].dynamite.is_empty(), "selected 5 Spades explodes despite safe alternative")
	check(GameManager.deck.discard_pile.has(safe) and GameManager.deck.discard_pile.has(boom) and GameManager.deck.discard_pile.has(lucky_dynamite), "both judgements and exploded Dynamite conserve physical cards")

	# H: begin_action_turn queues Dynamite before Jail, then draw/action.
	setup()
	put_dynamite(2)
	GameManager.players[2].equipment.jail = make_card("jail")
	# Stack order: Dynamite safe first, then Jail Heart succeeds, then draw cards.
	top("dodge", "HEART", 4)
	top("shoot", "HEART", 8)
	GameManager.begin_turn(2)
	var kinds: Array = events.map(func(event): return str(event.get("kind", "")))
	check(kinds.has("dynamite_pass") and kinds.has("jail_result"), "both delayed effects resolve at action-turn start")
	check(kinds.find("dynamite_pass") < kinds.find("jail_result"), "Dynamite resolves before Jail")
	check(GameManager.turns.current_player == 2 and GameManager.turns.phase == "ACTION_PHASE", "safe Dynamite and successful Jail proceed through draw to action phase")

	GameManager.clear()
	print("PASS: %d delayed Dynamite authority, protection, circulation, death and judgement checks" % checks)
	get_tree().quit()
