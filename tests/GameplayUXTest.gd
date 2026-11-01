extends Node

var app: Node
var checks: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("GAMEPLAY UX FAILED: " + message)
		get_tree().quit(1)
		assert(value, message)

func settle() -> void:
	await get_tree().create_timer(0.12).timeout
	await get_tree().physics_frame

func setup() -> void:
	GameManager.clear()
	for id in range(1, 5):
		GameManager.add_player(id, "Cao bồi %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()
	for id in GameManager.players:
		GameManager.selection.choose(GameManager, id, GameManager.selection.options[id][0])
	GameManager.flow.jobs.clear()
	GameManager.reactions.active = {}
	for p in GameManager.players.values():
		p.ability_id = ""
		p.character_id = "bart_cassidy"
		p.hand.clear()
		p.role = PlayerState.Role.OUTLAW
		p.max_hp = 4
		p.current_hp = 4
	GameManager.players[1].role = PlayerState.Role.SHERIFF
	GameManager.players[4].role = PlayerState.Role.RENEGADE
	GameManager.turns.current_player = 1
	GameManager.turns.phase = "ACTION_PHASE"
	GameManager.rate_limits.clear()
	GameManager.publish()
	app.seen_role = GameManager.match_id
	app.menu_open = false
	app.sid_mode = false
	app.refresh()

func give(id: int, key: String) -> Dictionary:
	var card := CardInstance.make(GameManager.deck.next_id, key, "HEART", 7)
	GameManager.deck.next_id += 1
	GameManager.players[id].hand.append(card)
	return card

func world_tap(item: Node3D) -> void:
	var at: Vector2 = app.table.camera.unproject_position(item.global_position + Vector3.UP * 0.12)
	var event := InputEventScreenTouch.new()
	event.position = at
	event.index = 0
	event.pressed = true
	Input.parse_input_event(event)
	await settle()

func click_hand(uid: int) -> void:
	var hand: Control = app.match_hud.hand
	var index: int = -1
	for i in range(NetworkManager.private_state.hand.size()):
		if NetworkManager.private_state.hand[i].instance_id == uid:
			index = i
	var card: Button = hand.cards[index]
	var at: Vector2 = card.global_position + Vector2(40, 72)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await get_tree().process_frame
	await settle()

func touch_hand(index: int) -> void:
	var card: Button = app.match_hud.hand.cards[index]
	var at: Vector2 = card.global_position + Vector2(40, 72)
	for down in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = at
		event.index = 0
		event.pressed = down
		Input.parse_input_event(event)
		await get_tree().process_frame
	await settle()

func buttons(node: Node) -> Array:
	var result: Array = []
	if node is Button:
		result.append(node)
	for child in node.get_children():
		result.append_array(buttons(child))
	return result

func capture(label: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts/ux")
	var ignore := FileAccess.open("res://tests/artifacts/.gdignore", FileAccess.WRITE)
	ignore.close()
	get_viewport().get_texture().get_image().save_png("res://tests/artifacts/ux/" + label + ".png")

func _ready() -> void:
	get_window().size = Vector2i(1440, 900)
	get_window().content_scale_size = Vector2i(1440, 900)
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	app = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	setup()
	var shot := give(1, "shoot")
	var spare := give(1, "dodge")
	GameManager.publish()
	await settle()
	var persistent_hud: Control = app.match_hud
	var persistent_hand: Control = app.match_hud.hand
	var persistent_card: Button = persistent_hand.cards[0]
	app.refresh()
	check(app.match_hud == persistent_hud and app.match_hud.hand == persistent_hand, "duplicate network refresh keeps HUD and hand nodes")
	app.sid_mode = true
	app.refresh()
	check(app.match_hud.hand.cards[0] == persistent_card, "hand state update reuses CardView instance")
	app.sid_mode = false
	app.refresh()
	var refresh_started := Time.get_ticks_usec()
	for _index in range(100):
		app.refresh()
	var refresh_average_us := (Time.get_ticks_usec() - refresh_started) / 100.0
	print("PROFILE: unchanged in-match refresh average %.1f usec; HUD/card identity preserved" % refresh_average_us)
	check(buttons(app.match_hud).filter(func(b): return b.disabled and b.text.contains("Cao bồi")).is_empty(), "no permanent player button panels")
	check(not buttons(app.match_hud).any(func(b): return b.text in ["RỜI BÀN", "HỦY CHỌN MỤC TIÊU", "Hiện tất cả vai trò"]), "no leave/cancel/debug toolbar")
	check(app.match_hud.has_node("HandActions/EndTurn"), "End Turn accessible near hand")
	await click_hand(shot.instance_id)
	check(app.selected == shot.instance_id, "real hand click selects Shoot")
	check(not app.table.targeting.targeting_arrow.visible and app.table.targeting.hovered_target == 0, "target mode never auto-locks first player")
	await click_hand(shot.instance_id)
	check(app.selected == -1, "click selected card again cancels")
	app.choose_card(shot.instance_id)
	app.match_hud.get_node("HandActions/CancelSelection").pressed.emit()
	check(app.selected == -1, "tap cancel is available")
	await touch_hand(0)
	check(app.selected == shot.instance_id, "touch selects hand card")
	await touch_hand(0)
	check(app.selected == -1, "touch selected hand card cancels")
	await capture("tabletop")
	# React through exactly the same physical hand, including Janet conversion.
	setup()
	GameManager.players[1].ability_id = "convert"
	var converted := give(1, "shoot")
	spare = give(1, "horse")
	GameManager.turns.current_player = 2
	var attack := give(2, "shoot")
	GameManager.resolver.play(GameManager, 2, attack.instance_id, 1)
	GameManager.publish()
	await settle()
	check(not is_instance_valid(app.overlay) or not app.overlay.is_inside_tree(), "Shoot reaction opens no modal")
	check(app.match_hud.hand.cards[0].disabled == false and app.match_hud.hand.cards[1].disabled, "valid Janet response lit, unrelated card disabled")
	check(app.reaction_banner.visible and app.reaction_banner.get_node("Banner/Content/Actions/Primary").text == "DÙNG NÉ", "compact reaction banner offers Dodge")
	check(app.reaction_banner.get_node("Banner/Content/Actions/Skip").text == "BỎ QUA", "compact reaction banner offers Skip")
	check(app.table.reaction_source == 2 and app.table.reaction_target == 1, "incoming attack highlights its source and local target")
	check(app.table.rings[1].visible and app.table.rings[2].visible, "reaction focus rings stay visible around both affected players")
	await capture("reaction")
	await click_hand(converted.instance_id)
	check(GameManager.reactions.active.is_empty() and GameManager.players[1].current_hp == 4, "actual hand card resolves reaction")
	check(not GameManager.players[1].shoot_used_this_turn, "reaction keeps normal Shoot limit")
	# Without a Dodge the same banner remains actionable, but its primary button is disabled.
	setup()
	GameManager.turns.current_player = 2
	attack = give(2, "shoot")
	GameManager.resolver.play(GameManager, 2, attack.instance_id, 1)
	GameManager.publish()
	await settle()
	check(app.reaction_banner.visible and app.reaction_banner.get_node("Banner/Content/Actions/Primary").disabled, "no Dodge disables primary reaction")
	check(not app.reaction_banner.get_node("Banner/Content/Actions/Skip").disabled, "Skip remains enabled without Dodge")
	app.reaction_banner.get_node("Banner/Content/Actions/Skip").pressed.emit()
	check(GameManager.players[1].current_hp == 3, "Skip resolves authoritative one damage")
	# Long-press previews a card without accidentally playing it.
	setup()
	var held := give(1, "shoot")
	GameManager.publish()
	await settle()
	var held_view: Button = app.match_hud.hand.cards[0]
	held_view.button_down.emit()
	await get_tree().create_timer(0.5).timeout
	check(held_view.block_activation and is_instance_valid(app.match_hud.preview), "long press opens card preview")
	held_view.button_up.emit()
	held_view.pressed.emit()
	check(not GameManager.find_card(1, held.instance_id).is_empty() and app.selected == -1, "long press release does not play")
	setup()
	GameManager.players[1].ability_id = "discard_heal"
	GameManager.players[1].current_hp = 2
	var first := give(1, "dodge")
	var second := give(1, "shoot")
	GameManager.publish()
	await settle()
	app.match_hud.get_node("HandActions/SidAbility").pressed.emit()
	await click_hand(first.instance_id)
	check(app.sid_cards == [first.instance_id], "Sid selects actual hand card")
	await click_hand(first.instance_id)
	check(app.sid_cards.is_empty(), "Sid deselects actual hand card")
	await click_hand(first.instance_id)
	await click_hand(second.instance_id)
	check(not app.match_hud.get_node("HandActions/SidConfirm").disabled, "exactly two enables compact heal")
	app.match_hud.get_node("HandActions/SidConfirm").pressed.emit()
	await settle()
	check(GameManager.players[1].current_hp == 3 and GameManager.players[1].hand.is_empty(), "Sid validated two-card heal")
	setup()
	var hidden := give(2, "dodge")
	var panic := give(1, "panic")
	GameManager.resolver.play(GameManager, 1, panic.instance_id, 2)
	GameManager.publish()
	await settle()
	check(NetworkManager.private_state.reaction.zone_player_id == 2, "transfer carries public target ID only")
	check(app.table.objects.objects["2:hand"].enabled, "opponent hand zone selectable")
	check(is_instance_valid(app.match_hud.target_picker) and app.match_hud.target_picker.visible, "compact target card picker opens near victim")
	check(app.match_hud.target_picker.hand_row.get_child_count() == 1, "picker mirrors hidden hand count without identities")
	check(not app.table.objects.objects["2:hand"].title.text.contains("NÉ"), "opponent hand identity stays hidden")
	await capture("panic-zones")
	app.match_hud.target_picker.hand_row.get_child(0).pressed.emit()
	await settle()
	check(GameManager.players[1].hand.has(hidden) and GameManager.reactions.active.is_empty(), "tap hidden hand steals server-random card")
	setup()
	GameManager.players[2].weapon = give(2, "winchester")
	GameManager.players[2].hand.clear()
	var cat := give(1, "cat_balou")
	GameManager.resolver.play(GameManager, 1, cat.instance_id, 2)
	GameManager.publish()
	await settle()
	check(app.match_hud.target_picker.table_row.get_child_count() == 1, "picker exposes exact public weapon only")
	app.match_hud.target_picker.table_row.get_child(0).pressed.emit()
	await settle()
	check(GameManager.players[2].weapon.is_empty() and GameManager.reactions.active.is_empty(), "tap visible weapon discards exact equipment")
	setup()
	var store := give(1, "general_store")
	GameManager.resolver.play(GameManager, 1, store.instance_id, 1)
	GameManager.publish()
	await settle()
	var chosen: Dictionary = GameManager.flow.market[0]
	check(app.table.objects.objects.has("market:%d" % chosen.instance_id), "Store cards physically on table")
	check(app.table.objects.objects["market:%d" % chosen.instance_id].attention, "Store row stays visibly emphasized while a chooser is active")
	await capture("store")
	await world_tap(app.table.objects.objects["market:%d" % chosen.instance_id])
	check(GameManager.players[1].hand.has(chosen) and GameManager.reactions.active.target_player_id == 2, "tap Store card advances chooser server-side")
	GameManager.publish()
	await settle()
	check(not app.table.objects.token_allowed({"kind": "market", "card": GameManager.flow.market[0].instance_id}), "other player's store pick cannot be clicked")
	check(is_instance_valid(app.match_hud.loadout_panel) and not app.match_hud.loadout_panel.visible, "empty equipment HUD stays hidden")
	setup()
	give(1, "shoot")
	GameManager.players[2].equipment.jail = give(2, "jail")
	GameManager.players[2].hand.clear()
	GameManager.publish()
	await settle()
	check(app.table.objects.objects.has("2:jail"), "physical Jail bars")
	var info_position: Vector2 = app.table.camera.unproject_position(app.table.avatars[2].global_position + Vector3.UP * 1.65)
	var tap := InputEventScreenTouch.new()
	tap.position = info_position
	tap.pressed = true
	Input.parse_input_event(tap)
	await settle()
	check(app.table.context_player == 2 and app.table.context_label.text.contains("Bart Cassidy"), "tap avatar opens contextual character info")
	check(app.table.context_label.text.contains("Vai trò bí mật") and not app.table.context_label.text.contains("TỘI PHẠM"), "context preserves role privacy")
	app.match_hud.get_node("TopBar/PauseButton").pressed.emit()
	await settle()
	check(app.menu_open and app.table.targeting.blocked, "pause blocks world input")
	check(buttons(app.root).any(func(b): return b.text == "RỜI TRẬN"), "leave lives in pause")
	check(not buttons(app.root).any(func(b): return b.text == "Hiện tất cả vai trò"), "debug initially collapsed")
	app.menu_open = false
	app.refresh()
	await settle()
	check(not app.table.targeting.blocked, "resume restores tabletop interaction")
	check(app.match_hud.hand.position.y > 650, "hand leaves table center unobstructed")
	# Physical deck choice for draw abilities uses the same server reaction request.
	setup()
	GameManager.players[1].ability_id = "draw_discard"
	GameManager.flow.draw_phase.begin(GameManager, 1)
	GameManager.publish()
	await settle()
	check(app.table.objects.objects.deck.enabled, "Pedro deck is interactive")
	await world_tap(app.table.objects.objects.deck)
	check(GameManager.players[1].hand.size() == 2 and GameManager.reactions.active.is_empty(), "tap deck resolves first-draw choice")
	# Outside choice contexts, table objects cannot submit stale intentions.
	check(not app.table.objects.token_allowed({"kind": "deck"}), "normal automatic draw has no draw button/intent")
	GameManager.clear()
	print("PASS: %d tabletop UX and server-backed interaction checks" % checks)
	get_tree().quit()
