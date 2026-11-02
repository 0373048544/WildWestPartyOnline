extends Node

var checks := 0
var last_error := ""

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("CAT BALOU ACTION TURN FAILED: " + message)
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
	GameManager.reactions.active = {}
	for player in GameManager.players.values():
		player.hand.clear()
		player.weapon = {}
		player.equipment.clear()
		player.ability_id = ""
		player.cat_balou_used_this_action_turn = false
	GameManager.turns.current_player = 1
	GameManager.turns.phase = "ACTION_PHASE"
	GameManager.rate_limits.clear()
	last_error = ""

func give(id: int, kind: String) -> Dictionary:
	var card := CardInstance.make(GameManager.deck.next_id, kind, "DIAMOND", 9)
	GameManager.deck.next_id += 1
	GameManager.players[id].hand.append(card)
	return card

func play(card: Dictionary, target: int = 2) -> void:
	GameManager.rate_limits.clear()
	GameManager.handle_intent(1, "play", {"card":card.instance_id, "target":target})

func resolve_hand_discard() -> void:
	check(GameManager.reactions.active.get("reaction_type", "") == "transfer", "Cat Balou opens authoritative discard chooser")
	check(GameManager.flow.resolve({"accept":true, "option":"hand"}), "discard chooser accepts hidden hand zone")

func _ready() -> void:
	NetworkManager.error_received.connect(func(message): last_error = message)
	setup()
	var first := give(1, "cat_balou")
	var second := give(1, "cat_balou")
	give(2, "dodge")
	give(2, "shoot")
	play(first)
	resolve_hand_discard()
	check(GameManager.players[1].cat_balou_used_this_action_turn, "successful Cat Balou sets action-turn flag")
	var before_discard := GameManager.deck.discard_pile.size()
	play(second)
	check(last_error == "Bạn đã dùng BỎ BÀI trong lượt hành động này.", "server returns exact action-turn rejection")
	check(not GameManager.find_card(1, second.instance_id).is_empty(), "rejected second Cat Balou stays in hand")
	check(GameManager.deck.discard_pile.size() == before_discard and GameManager.reactions.active.is_empty(), "rejection creates no discard or chooser")
	var private := GameManager.private_snapshot(1)
	check(private.targets[second.instance_id].is_empty(), "private target list disables second Cat Balou")
	check(private.disabled_reasons[second.instance_id] == last_error, "UI uses authoritative disabled reason")
	for exception in ["unlimited_shoot", "volcanic"]:
		GameManager.players[1].ability_id = exception if exception == "unlimited_shoot" else ""
		if exception == "volcanic":
			GameManager.players[1].weapon = give(1, "volcanic")
			GameManager.players[1].hand.erase(GameManager.players[1].weapon)
		play(second)
		check(not GameManager.find_card(1, second.instance_id).is_empty(), exception + " does not override Cat Balou")
	GameManager.begin_turn(2)
	check(GameManager.players[1].cat_balou_used_this_action_turn, "another player's action turn does not reset owner")
	GameManager.flow.jobs.clear()
	GameManager.reactions.active = {}
	GameManager.begin_turn(1)
	GameManager.flow.jobs.clear()
	GameManager.reactions.active = {}
	GameManager.turns.phase = "ACTION_PHASE"
	check(not GameManager.players[1].cat_balou_used_this_action_turn, "owner's next action turn resets Cat Balou")
	if GameManager.players[2].hand.is_empty():
		give(2, "dodge")
	play(second)
	check(GameManager.find_card(1, second.instance_id).is_empty() and GameManager.players[1].cat_balou_used_this_action_turn, "retained Cat Balou succeeds next action turn")
	GameManager.clear()
	print("PASS: %d server-authoritative Cat Balou action-turn checks" % checks)
	get_tree().quit()
