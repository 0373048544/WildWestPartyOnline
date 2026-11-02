extends Node

var checks := 0
var last_error := ""
var events: Array = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("PANIC TURN FAILED: " + message)
		get_tree().quit(1)
		assert(value, message)

func setup() -> void:
	GameManager.clear()
	for id in range(1, 4):
		GameManager.add_player(id, "Player %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()
	GameManager.selection.expire(GameManager)
	GameManager.flow.jobs.clear()
	GameManager.flow.market.clear()
	GameManager.reactions.active = {}
	for player in GameManager.players.values():
		player.hand.clear()
		player.weapon = {}
		player.equipment.clear()
		player.ability_id = ""
		player.current_hp = 4
		player.max_hp = 4
		player.panic_used_this_action_turn = false
	GameManager.turns.current_player = 1
	GameManager.turns.phase = "ACTION_PHASE"
	GameManager.rate_limits.clear()
	last_error = ""
	events.clear()

func give(id: int, kind: String) -> Dictionary:
	var card := CardInstance.make(GameManager.deck.next_id, kind, "HEART", 8)
	GameManager.deck.next_id += 1
	GameManager.players[id].hand.append(card)
	return card

func play(id: int, card: Dictionary, target: int) -> void:
	GameManager.rate_limits.clear()
	GameManager.handle_intent(id, "play", {"card":card.instance_id, "target":target})

func choose_hand() -> void:
	check(GameManager.reactions.active.get("reaction_type", "") == "transfer", "Panic opens existing authoritative transfer chooser")
	check(GameManager.flow.resolve({"accept":true, "option":"hand"}), "Panic hand choice resolves")

func _ready() -> void:
	NetworkManager.error_received.connect(func(message): last_error = message)
	NetworkManager.table_event.connect(func(event): events.append(event.duplicate(true)))

	# Two Panic cards already owned: the second is blocked after the first resolves.
	setup()
	var first := give(1, "panic")
	var second := give(1, "panic")
	give(2, "dodge")
	play(1, first, 2)
	choose_hand()
	check(GameManager.players[1].panic_used_this_action_turn, "successful Panic sets per-player turn flag")
	var before_discard := GameManager.deck.discard_pile.size()
	var before_events := events.size()
	play(1, second, 2)
	check(last_error == "Bạn đã dùng HOẢNG LOẠN trong lượt hành động này.", "server returns exact second-Panic rejection")
	check(not GameManager.find_card(1, second.instance_id).is_empty(), "rejected second Panic remains in hand")
	check(GameManager.deck.discard_pile.size() == before_discard and events.size() == before_events and GameManager.reactions.active.is_empty(), "rejection creates no discard, event, targeting or animation")
	var private := GameManager.private_snapshot(1)
	check(private.targets[second.instance_id].is_empty() and private.disabled_reasons[second.instance_id] == last_error, "private UI disables Panic with authoritative reason")

	# Reported chain: steal Panic #2 from B, retain it, but cannot replay it now.
	setup()
	first = give(1, "panic")
	var stolen := give(2, "panic")
	play(1, first, 2)
	choose_hand()
	check(GameManager.players[1].hand.has(stolen), "Panic stolen from opponent enters attacker's hand")
	play(1, stolen, 2)
	check(not GameManager.find_card(1, stolen.instance_id).is_empty() and GameManager.reactions.active.is_empty(), "stolen Panic cannot chain in same action turn")

	# Only the owner's next turn resets it; the retained physical card is then legal.
	GameManager.begin_turn(2)
	check(GameManager.players[1].panic_used_this_action_turn and not GameManager.players[2].panic_used_this_action_turn, "another player's turn does not reset A and has its own allowance")
	GameManager.flow.jobs.clear()
	GameManager.reactions.active = {}
	give(2, "panic")
	give(1, "dodge")
	GameManager.turns.phase = "ACTION_PHASE"
	var b_panic: Dictionary = GameManager.find_kind(2, "panic")
	play(2, b_panic, 1)
	check(GameManager.find_card(2, b_panic.instance_id).is_empty(), "Panic restriction is per-player, not global")
	GameManager.flow.jobs.clear()
	GameManager.reactions.active = {}
	GameManager.begin_turn(1)
	GameManager.flow.jobs.clear()
	GameManager.reactions.active = {}
	GameManager.turns.phase = "ACTION_PHASE"
	check(not GameManager.players[1].panic_used_this_action_turn, "A's next turn lifecycle resets Panic allowance")
	give(2, "dodge")
	play(1, stolen, 2)
	check(GameManager.find_card(1, stolen.instance_id).is_empty() and GameManager.players[1].panic_used_this_action_turn, "retained stolen Panic succeeds on A's next turn")

	# Any transfer mechanism preserves the already-used flag; no UID-based bypass.
	setup()
	GameManager.players[1].panic_used_this_action_turn = true
	var transferred := give(2, "panic")
	GameManager.flow.complete_department_store_give(2, {"receiver":1, "batch":{"count":0}}, transferred.instance_id)
	check(GameManager.players[1].hand.has(transferred), "Bách Hóa can transfer a new Panic instance")
	check(GameManager.resolver.valid_targets(GameManager, 1, transferred).is_empty() and GameManager.resolver.disabled_reason(GameManager, 1, transferred).contains("đã dùng HOẢNG LOẠN"), "transferred Panic remains disabled by card type and player flag")

	# BANG-only exceptions must not override Panic.
	for exception in ["unlimited_shoot", "volcanic"]:
		setup()
		GameManager.players[1].panic_used_this_action_turn = true
		if exception == "unlimited_shoot":
			GameManager.players[1].ability_id = exception
		else:
			GameManager.players[1].weapon = give(1, "volcanic")
			GameManager.players[1].hand.erase(GameManager.players[1].weapon)
		var blocked := give(1, "panic")
		give(2, "dodge")
		play(1, blocked, 2)
		check(not GameManager.find_card(1, blocked.instance_id).is_empty(), exception + " does not override Panic limit")

	GameManager.clear()
	print("PASS: %d server-authoritative per-player Panic turn-limit and transfer regression checks" % checks)
	get_tree().quit()
