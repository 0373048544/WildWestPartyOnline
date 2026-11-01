extends Node

# Independent oracle: printed rank/suit list, not reconstructed from runtime manifest.
const EXPECTED := {
	"barrel": "QS KS", "dynamite": "2H", "jail": "JS 4H 10S", "horse": "8H 9H",
	"remington": "KC", "carabine": "AC", "schofield": "JC QC KS", "spyglass": "AS",
	"volcanic": "10S 10C", "winchester": "8S",
	"shoot": "AS 2D 3D 4D 5D 6D 7D 8D 9D 10D JD QD KD AD 2C 3C 4C 5C 6C 7C 8C 9C QH KH AH",
	"drink": "6H 7H 8H 9H 10H JH", "cat_balou": "KH 9D 10D JD", "showdown": "QD JS 8C",
	"gatling": "10H", "general_store": "9C QS", "indians": "KD AD",
	"dodge": "10C JC QC KC AC 2S 3S 4S 5S 6S 7S 8S", "panic": "JH QH AH 8D",
	"saloon": "5H", "supply": "9S 9S", "wells_fargo": "3H"
}
var checks: int = 0
var public_events: Array = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("BASE CORRECTION FAILED: " + message)
		get_tree().quit(1)
		assert(value, message)

func _ready() -> void:
	await get_tree().process_frame
	NetworkManager.table_event.connect(func(event): public_events.append(event.duplicate(true)))
	var deck := DeckManager.new()
	check(deck.reset(), "canonical manifest validates")
	var actual: Dictionary = {}
	var ids: Dictionary = {}
	for card in deck.draw_pile:
		check(card.rank is String and CardInstance.RANKS.has(card.rank), "rank stored as real poker string")
		check(not ids.has(card.instance_id), "unique physical instance IDs")
		ids[card.instance_id] = true
		if not actual.has(card.card_data_id):
			actual[card.card_data_id] = []
		actual[card.card_data_id].append(card.rank + card.suit.left(1))
	for id in EXPECTED:
		var expected: Array = Array(EXPECTED[id].split(" "))
		expected.sort()
		actual[id].sort()
		check(actual[id] == expected, "every physical tuple exactly matches official list: " + id)
	check(actual.size() == EXPECTED.size() and deck.draw_pile.size() == 80, "exactly 22 card names and 80 physical cards")
	var definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/cards/base_deck.json"))
	for field in ["rank", "suit", "card_data_id"]:
		var wrong := definition.duplicate(true)
		wrong.cards[0][field] = {"rank": "2", "suit": "HEART", "card_data_id": "shoot"}[field]
		check(not deck.validate_definition(wrong).is_empty(), "reject corrupt " + field)
	var missing := definition.duplicate(true)
	missing.cards.pop_back()
	check(not deck.validate_definition(missing).is_empty(), "reject 79-card manifest")
	var duplicate := definition.duplicate(true)
	duplicate.cards[0] = duplicate.cards[1].duplicate()
	check(not deck.validate_definition(duplicate).is_empty(), "reject duplicate tuple quantity")
	for sample in [["A", "SPADE", "A♠"], ["10", "CLUB", "10♣"], ["Q", "HEART", "Q♥"], ["8", "DIAMOND", "8♦"]]:
		var view: Button = load("res://scenes/ui/CardUI.tscn").instantiate()
		add_child(view)
		var physical := CardInstance.make(900, "schofield", sample[1], sample[0])
		view.configure(physical, CardData.data("schofield"), false, false, "Không phải lượt của bạn.")
		var corner: Label = view.visual.get_node("RankSuitCorner")
		check(corner.text == sample[2], "real card UI corner " + sample[2])
		check(corner.get_theme_color("font_color") == CardInstance.suit_color(sample[1]), "red/dark suit rendering")
		check(view.tooltip_text.is_empty() and str(view.get_meta("disabled_reason", "")).contains("Không phải lượt") and CardData.data("schofield").weapon_range == 2, "custom preview owns disabled inspection; weapon range separate from rank")
		view.free()
	# Full legal matches, with all 80 physical cards conserved at every server step.
	seed(20261101)
	for count in [4, 5, 6, 7]:
		for trial in range(4):
			play_match(count)
	for event in public_events:
		if event.get("kind", "") == "draw":
			check(not event.has("card") and not event.has("cards"), "normal draws contain no private identity")
		if event.get("kind", "") == "transfer" and event.get("hidden", false) and event.get("steal", false):
			check(not event.has("card") and not event.has("rank") and not event.has("suit"), "hidden hand transfer has no identity/rank/suit")
	GameManager.clear()
	print("PASS: %d canonical deck, corruption rejection, card UI, full-match conservation and event privacy checks; 16 complete 4–7 player matches" % checks)
	get_tree().quit()

func play_match(count: int) -> void:
	GameManager.clear()
	for id in range(1, count + 1):
		GameManager.add_player(id, "Bot %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()
	for id in GameManager.players:
		GameManager.selection.choose(GameManager, id, GameManager.selection.options[id].pick_random())
	for step in range(6000):
		conserved()
		if not GameManager.winner.is_empty():
			return
		if not GameManager.reactions.active.is_empty():
			var r: Dictionary = GameManager.reactions.active
			var args := {"accept": true}
			if r.payload.has("cards"):
				args["cards"] = r.payload.cards.slice(0, int(r.payload.get("pick_count", 1))).map(func(c): return c.instance_id)
			elif r.payload.has("choices"):
				args["option"] = str(r.payload.choices[0].id)
			elif not r.allowed_card_types.is_empty():
				args["card"] = int(r.allowed_card_types[0])
			else:
				args.accept = false
			check(GameManager.flow.resolve(args), "legal bot reaction resolves")
			continue
		if not GameManager.flow.jobs.is_empty():
			GameManager.flow.run()
			continue
		var id: int = GameManager.turns.current_player
		GameManager.rate_limits.clear()
		if GameManager.turns.phase == "DISCARD_PHASE":
			GameManager.handle_intent(id, "discard", {"card": GameManager.players[id].hand[0].instance_id})
		elif GameManager.turns.phase == "ACTION_PHASE":
			var own: Dictionary = GameManager.private_snapshot(id)
			var used: bool = false
			for card in own.hand:
				var targets: Array = own.targets.get(card.instance_id, [])
				if not targets.is_empty():
					GameManager.handle_intent(id, "play", {"card": card.instance_id, "target": targets.pick_random()})
					used = true
					break
			if not used:
				GameManager.handle_intent(id, "end", {})
		else:
			check(false, "unexpected stalled phase: " + GameManager.turns.phase)
	check(false, "full match must finish within bounded legal actions")

func conserved() -> void:
	var all_cards: Array = GameManager.deck.draw_pile.duplicate()
	all_cards.append_array(GameManager.deck.discard_pile)
	all_cards.append_array(GameManager.flow.market)
	for p in GameManager.players.values():
		all_cards.append_array(p.hand)
		if not p.weapon.is_empty():
			all_cards.append(p.weapon)
		all_cards.append_array(p.equipment.values())
	if not GameManager.reactions.active.is_empty():
		all_cards.append_array(GameManager.reactions.active.context.get("cards", []))
	var ids: Dictionary = {}
	for card in all_cards:
		ids[card.instance_id] = true
	check(all_cards.size() == 80 and ids.size() == 80, "80 unique cards across deck/discard/hands/in-play/market/reserved choices")
