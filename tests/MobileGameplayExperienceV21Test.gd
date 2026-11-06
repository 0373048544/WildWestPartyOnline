extends Node

const LAYOUT = preload("res://scripts/ui/MatchLayout.gd")

var checks := 0
var failures: Array[String] = []
var app: Node

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("V21 MOBILE EXPERIENCE FAILED: " + message)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame

func touch(index: int, position: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	return event

func give(player_id: int, card_id: String, suit: String = "CLUB") -> Dictionary:
	var card := CardInstance.make(GameManager.deck.next_id, card_id, suit, 7)
	GameManager.deck.next_id += 1
	GameManager.players[player_id].hand.append(card)
	return card

func setup_match() -> void:
	GameManager.clear()
	for id in range(1, 5):
		GameManager.add_player(id, "Cao bồi %d" % id)
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
	GameManager.turns.current_player = 1
	GameManager.turns.phase = "ACTION_PHASE"
	GameManager.rate_limits.clear()
	GameManager.players[1].weapon = CardInstance.make(GameManager.deck.next_id, "winchester", "SPADE", 8)
	GameManager.deck.next_id += 1
	GameManager.players[1].equipment["barrel"] = CardInstance.make(GameManager.deck.next_id, "barrel", "HEART", 9)
	GameManager.deck.next_id += 1
	for card_id in ["shoot", "dodge", "drink", "panic", "cat_balou", "iced_tea", "jail", "horse", "general_store", "department_store"]:
		give(1, card_id)
	GameManager.publish()

func test_mobile_ui_and_targeting() -> void:
	var table: Node3D = app.table
	var controller: TargetingController = table.targeting
	var chosen: Array[int] = []
	controller.target_chosen.connect(func(id: int): chosen.append(id))

	# A real selected card keeps the compact picker and Cancel action available.
	# If two visible nameplates compete for the same touch, no target signal may
	# be emitted: the player must make the explicit compact-list choice instead.
	var shoot_uid := -1
	for card in NetworkManager.private_state.get("hand", []):
		if str(card.get("card_data_id", "")) == "shoot":
			shoot_uid = int(card.get("instance_id", -1))
			break
	expect(shoot_uid > 0, "fixture exposes a Shoot card for the real mobile selection flow")
	app.choose_card_action(shoot_uid)
	await settle()
	var compact_picker: Node = app.match_hud.find_child("MobileTargetPicker", true, false)
	var cancel_button: Node = app.match_hud.find_child("CancelSelection", true, false)
	expect(is_instance_valid(compact_picker) and compact_picker.visible, "mobile targeting exposes a compact explicit target picker")
	expect(is_instance_valid(cancel_button) and cancel_button.visible, "mobile targeting keeps the Cancel action visible")
	var old_plate_2: Rect2 = table.nameplates[2].screen_rect
	var old_plate_3: Rect2 = table.nameplates[3].screen_rect
	var overlap := Rect2(Vector2(145, 250), Vector2(100, 64))
	table.nameplates[2].screen_rect = overlap
	table.nameplates[3].screen_rect = overlap
	controller.handle_mobile_table_tap(overlap.get_center())
	expect(chosen.is_empty() and controller.selected_card == shoot_uid, "overlapping target hitboxes never auto-submit a play intent")
	expect(controller.ambiguous_target_ids.has(2) and controller.ambiguous_target_ids.has(3), "ambiguous touch records every competing opponent")
	expect(controller.tooltip.visible and controller.tooltip.text.contains("CH\u1eccN M\u1ee4C TI\u00caU"), "ambiguous touch directs the player to the compact target picker")
	table.nameplates[2].screen_rect = old_plate_2
	table.nameplates[3].screen_rect = old_plate_3
	controller.cancel_targeting(false)
	app.selected = -1
	app.refresh()
	await settle()

	table.state_signature = ""
	table.update_state(NetworkManager.public_state, 1, [2])
	controller.begin_targeting(99101, 1, [2], {2: {"distance": 1, "range": 1}, 3: {"distance": 2, "range": 1}}, "BANG")
	expect(table.rings[2].visible and table.rings[2].scale.x > 1.0, "valid mobile target has a readable lightweight table marker")
	expect(not table.rings[3].visible, "invalid opponent receives no valid-target marker")
	var invalid_point: Vector2 = table.camera.unproject_position(table.avatars[3].global_position + Vector3.UP * 1.6)
	controller.handle_mobile_table_tap(invalid_point)
	expect(chosen.is_empty() and controller.selected_card == 99101, "invalid touch target is blocked without cancelling the card")
	expect(controller.hovered_target == 3 and controller.tooltip.visible, "invalid visible target receives readable feedback")
	var valid_point: Vector2 = table.camera.unproject_position(table.avatars[2].global_position + Vector3.UP * 1.6)
	controller.handle_mobile_table_tap(valid_point)
	expect(chosen == [2] and controller.selected_card < 0, "one valid touch confirms exactly one target")
	controller.handle_mobile_table_tap(valid_point)
	expect(chosen.size() == 1, "synthetic follow-up tap cannot emit a duplicate target intent")

	var yaw_before: float = table.mobile_camera.yaw
	var hand: Control = app.match_hud.hand
	var down := touch(31, hand.get_global_rect().get_center(), true)
	hand._input(down)
	var drag := InputEventScreenDrag.new()
	drag.index = 31
	drag.position = down.position + Vector2(-86, 0)
	drag.relative = Vector2(-86, 0)
	hand._input(drag)
	hand._input(touch(31, drag.position, false))
	expect(is_equal_approx(table.mobile_camera.yaw, yaw_before), "hand drag never rotates the seated camera")

	controller.begin_targeting(99102, 1, [2], {2: {"distance": 1, "range": 1}}, "BANG")
	controller.blocked = true
	table.mobile_camera._unhandled_input(touch(32, valid_point, true))
	table.mobile_camera._unhandled_input(touch(32, valid_point, false))
	expect(chosen.size() == 1 and controller.selected_card == 99102, "reaction/input lock has priority over table targeting")
	controller.blocked = false
	controller.cancel_targeting(false)

	var dodge_uid: int = int(GameManager.players[1].hand[1].instance_id)
	app.reaction_banner.present(app, {
		"request_id": 2101, "reaction_type": "dodge", "source_player_id": 2,
		"required_count": 2, "resolved_count": 1,
		"allowed_card_types": [dodge_uid], "remaining": 8.0
	}, NetworkManager.public_state)
	expect(app.reaction_banner.visible and app.reaction_banner.detail_label.text.contains("1/2"), "Slab progress 1/2 remains an active reaction")
	expect(app.reaction_banner.z_index > LAYOUT.Z_PREVIEW and app.reaction_banner.z_index > LAYOUT.Z_CHAT, "reaction controls stay above preview and chat")
	app.reaction_banner.hide_banner()

	var old_yaw: float = table.mobile_camera.yaw + 0.19
	var old_pitch: float = table.mobile_camera.pitch - 0.07
	table.mobile_camera.yaw = old_yaw
	table.mobile_camera.pitch = old_pitch
	table.mobile_camera.apply_camera()
	table.state_signature = ""
	table.update_state(NetworkManager.public_state, 1, [])
	await settle()
	expect(is_equal_approx(table.mobile_camera.yaw, old_yaw) and is_equal_approx(table.mobile_camera.pitch, old_pitch), "height-only/keyboard-style refresh preserves camera orientation")

	var public_barrel_visible := false
	for key in table.objects.objects:
		if str(key).ends_with(":barrel"):
			public_barrel_visible = bool(table.objects.objects[key].visible)
	expect(public_barrel_visible and app.match_hud.loadout_panel.visible, "public equipment is visible without hover")
	var action_rect: Rect2 = LAYOUT.action_rect(app)
	expect(not app.match_hud.loadout_panel.get_global_rect().intersects(action_rect), "equipment panel does not cover the action bar")
	expect(not app.chat_panel.toggle_button.get_global_rect().intersects(action_rect), "chat control does not cover the action bar")

	app.selected = int(GameManager.players[1].hand[0].instance_id)
	GameManager.match_id += 1
	GameManager.publish()
	app.refresh()
	await settle()
	expect(app.selected == -1 and app.table.targeting.selected_card == -1, "new match/rematch clears stale card and target selection")

	get_viewport().set_meta("match_force_mobile_device", false)
	app.table.state_signature = ""
	app.table.update_state(NetworkManager.public_state, 1, [])
	await settle()
	expect(not app.table.mobile_camera.enabled and app.table.camera_goal.y > 7.0, "desktop keeps the existing overhead camera")

func test_authoritative_reaction_rules() -> void:
	setup_match()
	GameManager.players[1].ability_id = "double_dodge"
	var dodge := give(2, "dodge")
	var shot := give(1, "shoot")
	GameManager.resolver.play(GameManager, 1, shot.instance_id, 2)
	expect(int(GameManager.reactions.active.get("required_count", 0)) == 2, "Slab requires two authoritative Dodge results")
	GameManager.flow.resolve({"accept": true, "card": dodge.instance_id})
	expect(int(GameManager.reactions.active.get("resolved_count", 0)) == 1 and GameManager.players[2].current_hp == 4, "Slab 1/2 is not announced or resolved as a successful dodge")
	GameManager.flow.resolve({"accept": false})

	setup_match()
	var deck_before: int = GameManager.deck.draw_pile.size()
	GameManager.deck.draw_pile.append(CardInstance.make(GameManager.deck.next_id, "shoot", "HEART", 7))
	GameManager.deck.next_id += 1
	shot = give(1, "shoot")
	GameManager.resolver.play(GameManager, 1, shot.instance_id, 2)
	expect(GameManager.deck.draw_pile.size() == deck_before + 1, "ordinary target performs no Barrel judgement")
	GameManager.reactions.active = {}
	GameManager.flow.jobs.clear()
	GameManager.players[1].shoot_used_this_action_turn = false
	GameManager.players[2].equipment["barrel"] = CardInstance.make(GameManager.deck.next_id, "barrel", "CLUB", 7)
	GameManager.deck.next_id += 1
	GameManager.deck.draw_pile.append(CardInstance.make(GameManager.deck.next_id, "shoot", "HEART", 7))
	GameManager.deck.next_id += 1
	shot = give(1, "shoot")
	GameManager.resolver.play(GameManager, 1, shot.instance_id, 2)
	expect(GameManager.reactions.active.is_empty() and GameManager.players[2].current_hp == 4, "equipped Barrel HEART judgement avoids the shot")

func _ready() -> void:
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	get_window().size = Vector2i(390, 844)
	get_window().content_scale_size = Vector2i(600, 1298)
	get_viewport().set_meta("match_css_size", Vector2(390, 844))
	get_viewport().set_meta("match_safe_insets", Vector4(8, 24, 8, 18))
	get_viewport().set_meta("match_force_mobile_device", true)
	NetworkManager.mode = "offline"
	setup_match()
	app = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	app.seen_role = GameManager.match_id
	app.refresh()
	await settle()
	await test_mobile_ui_and_targeting()
	test_authoritative_reaction_rules()
	GameManager.clear()
	if failures.is_empty():
		print("PASS: %d V21 one-touch targeting, reaction, camera, equipment and authority checks" % checks)
		get_tree().quit(0)
	else:
		print("FAIL: %d/%d V21 checks" % [failures.size(), checks])
		get_tree().quit(1)
