extends Node

const MATCH_LAYOUT = preload("res://scripts/ui/MatchLayout.gd")

var checks := 0
var next_uid := 91000

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("SPECTATOR/REMATCH/QUICK EQUIP FAILED: " + message)
		get_tree().quit(1)
		assert(value, message)

func setup(count: int = 4) -> void:
	GameManager.clear()
	NetworkManager.mode = "offline"
	for id in range(1, count + 1):
		GameManager.add_player(id, "Player %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()
	GameManager.selection.expire(GameManager)
	GameManager.flow.jobs.clear()
	GameManager.flow.market.clear()
	GameManager.reactions.active = {}
	GameManager.winner = ""
	GameManager.turns.current_player = 1
	GameManager.turns.phase = "ACTION_PHASE"
	GameManager.rate_limits.clear()
	for player in GameManager.players.values():
		player.ability_id = ""
		player.hand.clear()
		player.weapon = {}
		player.equipment.clear()
		player.dynamite = {}
		player.spectating = false
		player.is_alive = true
		player.is_connected = true
		player.current_hp = player.max_hp

func give(id: int, card_id: String, suit: String = "CLUB", rank: Variant = 7) -> Dictionary:
	next_uid += 1
	var card := CardInstance.make(next_uid, card_id, suit, rank)
	GameManager.players[id].hand.append(card)
	return card

func intent(id: int, action: String, args: Dictionary = {}) -> void:
	GameManager.rate_limits.erase(id)
	GameManager.handle_intent(id, action, args)

func test_quick_equipment() -> void:
	setup(3)
	check(CardData.is_quick_equipment("horse") and CardData.is_quick_equipment("barrel") and CardData.is_quick_equipment("spyglass"), "central helper contains exactly the three shipped quick-equipment IDs")
	check(not CardData.is_quick_equipment("remington") and not CardData.is_quick_equipment("dynamite"), "weapon and delayed cards are not quick equipment")
	GameManager.players[1].shoot_used_this_action_turn = true
	GameManager.players[1].panic_used_this_action_turn = true
	GameManager.players[1].cat_balou_used_this_action_turn = true
	var mustang := give(2, "horse")
	check(GameManager.resolver.valid_targets(GameManager, 2, mustang) == [2], "Mustang is self-playable outside its owner's action turn")
	intent(2, "play", {"card": mustang.instance_id, "target": 2})
	check(not GameManager.players[2].hand.has(mustang) and GameManager.players[2].equipment.get("horse", {}) == mustang, "Mustang moves directly from B hand to B equipment")
	check(GameManager.turns.current_player == 1 and GameManager.turns.phase == "ACTION_PHASE", "Mustang quick equip preserves A current turn and phase")
	check(GameManager.players[1].shoot_used_this_action_turn and GameManager.players[1].panic_used_this_action_turn and GameManager.players[1].cat_balou_used_this_action_turn, "quick equip does not reset current-player usage flags")

	setup(3)
	var barrel := give(2, "barrel")
	intent(2, "play", {"card": barrel.instance_id, "target": 2})
	check(GameManager.players[2].equipment.get("barrel", {}) == barrel, "Barrel equips outside turn")
	var hp_before: int = GameManager.players[2].current_hp
	GameManager.deck.draw_pile.append(CardInstance.make(next_uid + 1, "supply", "HEART", 4))
	var shot := give(1, "shoot")
	intent(1, "play", {"card": shot.instance_id, "target": 2})
	check(GameManager.players[2].current_hp == hp_before and GameManager.reactions.active.is_empty(), "quick-equipped Barrel participates in the existing BANG judgement flow")

	setup(4)
	var before_distance: int = DistanceManager.distance(GameManager.players, 2, 4)
	var scope := give(2, "spyglass")
	intent(2, "play", {"card": scope.instance_id, "target": 2})
	check(GameManager.players[2].equipment.get("spyglass", {}) == scope, "Spyglass equips outside turn")
	check(DistanceManager.distance(GameManager.players, 2, 4) == maxi(1, before_distance - 1), "Spyglass distance modifier activates immediately")
	check(GameManager.turns.current_player == 1 and GameManager.turns.phase == "ACTION_PHASE", "Spyglass does not start targeting or consume a turn")

func test_quick_equipment_rejections() -> void:
	setup(3)
	for card_id in ["shoot", "panic", "cat_balou"]:
		var card := give(2, card_id)
		intent(2, "play", {"card": card.instance_id, "target": 1})
		check(GameManager.players[2].hand.has(card), "%s remains server-rejected outside B action turn" % card_id)
	check(GameManager.turns.current_player == 1 and GameManager.turns.phase == "ACTION_PHASE", "invalid out-of-turn cards leave A flow unchanged")

	setup(3)
	var parallel_scope := give(2, "spyglass")
	GameManager.flow.prompt(1, "draw_choose", {}, {"cards": [], "pick_count": 1})
	var prompt_id: int = int(GameManager.reactions.active.get("request_id", 0))
	intent(2, "play", {"card": parallel_scope.instance_id, "target": 2})
	check(GameManager.players[2].equipment.get("spyglass", {}) == parallel_scope, "quick equip remains legal when a different player owns the blocking prompt")
	check(GameManager.turns.current_player == 1 and GameManager.turns.phase == "REACTION" and int(GameManager.reactions.active.get("request_id", 0)) == prompt_id, "quick equip never clears or rewrites another player's active reaction")

	setup(3)
	var blocked_mustang := give(2, "horse")
	GameManager.flow.prompt(2, "dodge", {"source": 1}, {"allowed_cards": [], "allowed_actions": ["pass"]})
	intent(2, "play", {"card": blocked_mustang.instance_id, "target": 2})
	check(GameManager.players[2].hand.has(blocked_mustang) and GameManager.reactions.active.get("reaction_type", "") == "dodge", "mandatory Dodge prompt blocks Mustang without clearing the reaction")

	setup(3)
	var blocked_barrel := give(2, "barrel")
	GameManager.flow.prompt(2, "department_store_give", {"receiver": 1}, {"cards": [blocked_barrel], "pick_count": 1})
	intent(2, "play", {"card": blocked_barrel.instance_id, "target": 2})
	check(GameManager.players[2].hand.has(blocked_barrel) and not GameManager.reactions.active.is_empty(), "Bách Hóa giver must finish the mandatory choice before quick equip")

	setup(3)
	var equipped := give(2, "horse")
	GameManager.players[2].hand.erase(equipped)
	GameManager.players[2].equipment["horse"] = equipped
	var duplicate := give(2, "horse")
	intent(2, "play", {"card": duplicate.instance_id, "target": 2})
	check(GameManager.players[2].hand.has(duplicate) and GameManager.players[2].equipment.horse == equipped, "duplicate Mustang is rejected without consuming either physical card")

	setup(3)
	GameManager.players[2].is_alive = false
	GameManager.players[2].current_hp = 0
	var dead_scope := give(2, "spyglass")
	intent(2, "play", {"card": dead_scope.instance_id, "target": 2})
	check(GameManager.players[2].hand.has(dead_scope) and not GameManager.players[2].equipment.has("spyglass"), "dead spectator cannot quick equip")

func test_death_and_spectator_ui() -> void:
	setup(4)
	GameManager.players[1].role = PlayerState.Role.OUTLAW
	GameManager.players[2].role = PlayerState.Role.SHERIFF
	GameManager.players[3].role = PlayerState.Role.OUTLAW
	GameManager.players[4].role = PlayerState.Role.RENEGADE
	GameManager.kill_player(1, 2)
	check(GameManager.players.has(1) and not GameManager.players[1].is_alive and GameManager.players[1].is_connected, "death keeps player in room and public table roster")
	var dead_row: Dictionary = GameManager.public_snapshot().players.filter(func(row): return int(row.player_id) == 1)[0]
	check(not dead_row.is_alive and not str(dead_row.public_role).is_empty(), "corpse snapshot reveals the existing death role and remains public")
	var forged := give(1, "horse")
	intent(1, "play", {"card": forged.instance_id, "target": 1})
	check(GameManager.players[1].hand.has(forged) and not GameManager.players[1].equipment.has("horse"), "dead player gameplay intent is rejected server-side")
	GameManager.publish()
	var app: Node = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	app.seen_role = GameManager.match_id
	app.refresh()
	await get_tree().process_frame
	check(is_instance_valid(app.root.find_child("SpectateButton", true, false)), "death panel offers XEM TIẾP")
	check(is_instance_valid(app.root.find_child("DeathLeaveButton", true, false)), "death panel offers RỜI PHÒNG")
	check(app.table.avatars.has(1) and app.table.avatars[1].dead, "corpse avatar stays at its seat in death pose")
	check("☠" in str(app.table.nameplates[1].label.text), "corpse nameplate visibly marks the dead player")
	intent(1, "spectate")
	await get_tree().process_frame
	check(GameManager.players[1].spectating and GameManager.private_snapshot(1).spectating, "XEM TIẾP enters authoritative spectator state")
	check(is_instance_valid(app.match_hud.get_node_or_null("SpectatorBar")), "spectator HUD replaces gameplay hand controls")
	check(not is_instance_valid(app.match_hud.get_node_or_null("HandActions")) and not app.match_hud.get_children().any(func(node): return node is Button and node.name == "EndTurn"), "spectator has no End Turn or gameplay action bar")
	check(is_instance_valid(app.chat_panel) and not app.chat_panel.blocked, "dead spectator keeps room chat available")
	app.queue_free()
	await get_tree().process_frame

func force_game_over() -> void:
	GameManager.winner = "OUTLAWS WIN"
	GameManager.turns.phase = "GAME_OVER"
	for player in GameManager.players.values():
		player.ready = false
	GameManager.reactions.active = {}
	GameManager.flow.jobs.clear()

func test_result_ui() -> void:
	setup(4)
	force_game_over()
	GameManager.publish()
	var app: Node = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	app.seen_role = GameManager.match_id
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	for css in [Vector2i(390, 844), Vector2i(844, 390)]:
		get_window().size = css
		get_viewport().set_meta("match_css_size", Vector2(css))
		var logical := Vector2i(600, int(600.0 * css.y / css.x)) if css.y >= css.x else Vector2i(960, int(960.0 * css.y / css.x))
		get_window().content_scale_size = logical
		get_viewport().set_meta("match_safe_insets", Vector4(10, 24, 10, 20))
		app.match_hud.flow_signature = ""
		app.refresh()
		await get_tree().process_frame
		var frame: Control = app.root.get_node_or_null("GameModal/ModalFrame")
		var safe_rect: Rect2 = MATCH_LAYOUT.modal_rect(app.root)
		check(is_instance_valid(frame) and safe_rect.encloses(frame.get_global_rect()), "result panel stays inside mobile safe viewport %s" % css)
		var continue_button: Button = frame.find_child("RematchReadyButton", true, false)
		var leave_button: Button = frame.find_child("ResultLeaveButton", true, false)
		check(is_instance_valid(continue_button) and is_instance_valid(leave_button), "mobile result exposes TIẾP TỤC and RỜI PHÒNG %s" % css)
		check(continue_button.custom_minimum_size.y >= 44.0 and leave_button.custom_minimum_size.y >= 44.0, "mobile result actions retain touch-sized height %s" % css)
	intent(1, "rematch")
	await get_tree().process_frame
	check(GameManager.players[1].ready and not is_instance_valid(app.root.find_child("RematchReadyButton", true, false)), "TIẾP TỤC becomes a persistent ready/waiting state for only that player")
	check(is_instance_valid(app.root.find_child("ResultLeaveButton", true, false)), "ready player can still leave while waiting for rematch")
	app.queue_free()
	await get_tree().process_frame

func test_rematch() -> void:
	setup(4)
	var legacy_match: int = GameManager.match_id
	force_game_over()
	intent(1, "restart")
	check(GameManager.match_id == legacy_match and GameManager.players[1].ready and GameManager.players.values().filter(func(player): return player.ready).size() == 1, "legacy host restart cannot bypass per-player rematch readiness")
	intent(1, "lobby")
	check(GameManager.started and not GameManager.winner.is_empty(), "legacy host return-to-lobby cannot remove other players from the result flow")

	setup(4)
	var previous_match: int = GameManager.match_id
	var old_player: PlayerState = GameManager.players[1]
	NetworkManager.begin_chat_room("REMATCH-ROOM")
	force_game_over()
	GameManager.players[4].is_connected = false
	intent(1, "rematch")
	intent(2, "rematch")
	check(GameManager.match_id == previous_match and GameManager.players[1].ready and GameManager.players[2].ready, "continue is per-player readiness and does not reconnect or start early")
	intent(3, "rematch")
	check(GameManager.match_id == previous_match + 1 and GameManager.winner.is_empty() and GameManager.turns.phase == "CHARACTER_SELECTION", "remaining three ready players start a fresh 3-player match in the same room")
	check(GameManager.players.size() == 3 and NetworkManager.chat_room == "REMATCH-ROOM", "departed player is removed from rematch roster while room/chat identity remains")
	check(GameManager.players[1] != old_player and GameManager.players.values().all(func(player): return player.is_alive and not player.spectating and player.hand.is_empty() and player.weapon.is_empty() and player.equipment.is_empty() and player.dynamite.is_empty()), "rematch reconstructs player match state and clears corpse/cards/equipment")
	var offered: Array = []
	for id in GameManager.players:
		var options: Array = GameManager.selection.options.get(id, [])
		check(options.size() == 2 and options[0] != options[1], "rematch deals exactly two distinct private character choices to player %d" % id)
		offered.append_array(options)
	var unique_options: Dictionary = {}
	for option in offered:
		unique_options[option] = true
	check(unique_options.size() == offered.size(), "rematch character options are dealt without replacement")

	setup(4)
	previous_match = GameManager.match_id
	force_game_over()
	for id in [1, 2, 3, 4]:
		intent(id, "rematch")
	check(GameManager.match_id == previous_match + 1 and GameManager.players.size() == 4 and GameManager.players.values().all(func(player): return player.is_alive), "all connected players continue without reconnecting and return alive")

func _ready() -> void:
	test_quick_equipment()
	test_quick_equipment_rejections()
	await test_death_and_spectator_ui()
	await test_result_ui()
	test_rematch()
	print("PASS: %d spectator, corpse, rematch reset and authoritative quick-equipment checks" % checks)
	get_tree().quit()
