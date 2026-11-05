extends Node

const LAYOUT = preload("res://scripts/ui/MatchLayout.gd")

var checks := 0
var failures: Array[String] = []

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("V20 MOBILE UX FAILED: " + message)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame

func _ready() -> void:
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	get_window().size = Vector2i(390, 844)
	get_window().content_scale_size = Vector2i(600, 1298)
	get_viewport().set_meta("match_css_size", Vector2(390, 844))
	get_viewport().set_meta("match_safe_insets", Vector4(8, 24, 8, 18))
	get_viewport().set_meta("match_force_mobile_device", true)
	NetworkManager.mode = "offline"
	GameManager.clear()
	for id in range(1, 5):
		GameManager.add_player(id, "Cao bồi %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()
	GameManager.selection.expire(GameManager)
	GameManager.flow.jobs.clear()
	GameManager.reactions.active = {}
	GameManager.turns.current_player = 1
	GameManager.turns.phase = "ACTION_PHASE"
	GameManager.players[1].hand.clear()
	var ids := ["shoot", "dodge", "drink", "panic", "cat_balou", "iced_tea", "jail", "barrel", "general_store", "department_store"]
	for index in range(10):
		GameManager.players[1].hand.append(CardInstance.make(22000 + index, ids[index], "HEART", 7))
	GameManager.players[1].equipment["barrel"] = CardInstance.make(22100, "barrel", "HEART", 12)
	GameManager.publish()
	var app: Node = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	app.seen_role = GameManager.match_id
	app.refresh()
	await settle()

	var unit := LAYOUT.units(app, 1.0)
	var hand_height_css := LAYOUT.hand_height(app) / unit
	var card_width_css := LAYOUT.touch_card_width(app) / unit
	expect(hand_height_css >= 110.0 and hand_height_css <= 125.0, "portrait hand zone stays within 110-125 CSS px")
	expect(card_width_css >= 90.0 and card_width_css <= 105.0, "mobile card width stays within 90-105 CSS px")
	var hand: Control = app.match_hud.hand
	expect(hand.cards.size() == 10 and hand.content_width() > hand.size.x, "ten-card hand uses horizontal scrolling")
	var first_card: Button = hand.cards[0]
	var card_node_id := first_card.get_instance_id()
	var card_name: Label = first_card.visual.find_child("CardName", true, false)
	var artwork: Control = first_card.visual.find_child("ArtworkFrame", true, false)
	expect(card_name.visible and not Rect2(card_name.position, card_name.size).intersects(Rect2(artwork.position, artwork.size)),
		"card title occupies a fixed header above artwork")

	var yaw_before: float = app.table.mobile_camera.yaw
	var selected_before: int = app.selected
	var down := InputEventScreenTouch.new()
	down.index = 41
	down.pressed = true
	down.position = hand.get_global_rect().get_center()
	hand._input(down)
	var drag := InputEventScreenDrag.new()
	drag.index = 41
	drag.position = down.position + Vector2(-90, 0)
	drag.relative = Vector2(-90, 0)
	hand._input(drag)
	down.pressed = false
	down.position = drag.position
	hand._input(down)
	await get_tree().process_frame
	expect(is_equal_approx(app.table.mobile_camera.yaw, yaw_before), "hand drag never rotates first-person camera")
	expect(app.selected == selected_before, "hand drag never plays/selects a card")

	var dodge_uid: int = int(GameManager.players[1].hand[1].instance_id)
	app.reaction_banner.present(app, {
		"request_id": 2020, "reaction_type": "dodge", "source_player_id": 2,
		"allowed_card_types": [dodge_uid], "remaining": 8.0
	}, NetworkManager.public_state)
	app.match_hud.show_preview(NetworkManager.private_state.hand[0])
	await settle()
	expect(is_instance_valid(app.match_hud.preview) and app.match_hud.preview.z_index < app.reaction_banner.z_index,
		"reaction banner renders above compact card preview")
	expect(app.reaction_banner.visible, "preview does not hide an active reaction")
	app.match_hud.close_preview()
	app.reaction_banner.hide_banner()

	var action_rect: Rect2 = LAYOUT.action_rect(app)
	var hand_rect: Rect2 = LAYOUT.hand_rect(app)
	var loadout_rect: Rect2 = app.match_hud.loadout_panel.get_global_rect()
	expect(not loadout_rect.intersects(action_rect), "compact equipment panel does not cover action controls")
	expect(not loadout_rect.intersects(hand_rect), "compact equipment panel does not cover hand")

	var focus_rect: Rect2 = LAYOUT.get_table_focus_rect(app)
	for kind in ["deck", "discard"]:
		var found := false
		for object in app.table.objects.objects.values():
			if str(object.token.get("kind", "")) == kind:
				found = true
				var screen_point: Vector2 = app.table.camera.unproject_position(object.global_position + Vector3.UP * 0.12)
				expect(focus_rect.has_point(screen_point), "%s pile remains visible inside the table focus region" % kind)
		expect(found, "%s pile presentation exists" % kind)

	app.refresh()
	await settle()
	expect(app.match_hud.hand.cards[0].get_instance_id() == card_node_id, "unchanged snapshot reuses CardView nodes")

	get_viewport().set_meta("match_force_mobile_device", false)
	app.table.state_signature = ""
	app.table.update_state(NetworkManager.public_state, 1, [])
	await settle()
	expect(not app.table.mobile_camera.enabled and app.table.camera_goal.y > 7.0, "desktop camera remains the established overhead camera")

	GameManager.clear()
	if failures.is_empty():
		print("PASS: %d V20 mobile card-game UX checks" % checks)
		get_tree().quit(0)
	else:
		print("FAIL: %d/%d V20 mobile UX checks" % [failures.size(), checks])
		get_tree().quit(1)
