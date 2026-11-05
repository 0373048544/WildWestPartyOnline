extends Node

var checks := 0
var failures: Array[String] = []

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("SAFARI LAYOUT FAILED: " + message)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame

func _ready() -> void:
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	get_window().size = Vector2i(390, 844)
	get_window().content_scale_size = Vector2i(600, 1298)
	get_viewport().set_meta("match_css_size", Vector2(390, 844))
	get_viewport().set_meta("match_safe_insets", Vector4(0, 24, 0, 18))
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
	for index in range(10):
		GameManager.players[1].hand.append(CardInstance.make(18000 + index, "shoot" if index % 2 == 0 else "dodge", "HEART", 7))
	GameManager.publish()
	var app: Node = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	app.seen_role = GameManager.match_id
	app.refresh()
	await settle()
	var table_id: int = app.table.get_instance_id()
	var camera_id: int = app.table.camera.get_instance_id()
	var hud_id: int = app.match_hud.get_instance_id()
	var hand: Control = app.match_hud.hand
	var hand_id := hand.get_instance_id()
	hand.scroll_offset = minf(80.0, maxf(0.0, hand.content_width() - hand.size.x))
	hand.arrange()
	var scroll_before: float = hand.scroll_offset
	var yaw_before: float = app.table.mobile_camera.yaw
	var pitch_before: float = app.table.mobile_camera.pitch
	var modal_content: Control = app.modal()
	var overlay_id: int = app.overlay.get_instance_id()
	modal_content.add_child(Label.new())

	# Simulate Safari showing browser chrome: width/profile remain stable while
	# visual height and safe bottom inset change.
	get_window().content_scale_size = Vector2i(600, 1169)
	get_viewport().set_meta("match_css_size", Vector2(390, 760))
	get_viewport().set_meta("match_safe_insets", Vector4(0, 24, 0, 30))
	get_viewport().set_meta("match_layout_generation", 1)
	app.responsive_layout_changed({"generation": 1, "height_only": true})
	await settle()
	expect(app.table.get_instance_id() == table_id and app.table.camera.get_instance_id() == camera_id,
		"height-only toolbar change reuses table and camera")
	expect(app.match_hud.get_instance_id() == hud_id and app.match_hud.hand.get_instance_id() == hand_id,
		"height-only toolbar change reuses HUD and HandFan")
	expect(is_equal_approx(app.match_hud.hand.scroll_offset, scroll_before),
		"height-only toolbar change preserves hand scroll")
	expect(is_instance_valid(app.overlay) and app.overlay.get_instance_id() == overlay_id,
		"height-only toolbar change does not close/recreate blocking modal")
	expect(load("res://scripts/ui/MatchLayout.gd").mobile_portrait(app),
		"Safari height change stays in the same portrait profile")
	expect(is_equal_approx(app.table.mobile_camera.yaw, yaw_before) and is_equal_approx(app.table.mobile_camera.pitch, pitch_before),
		"Safari toolbar height change preserves camera yaw and pitch")

	# Orientation is a real profile transition, but persistent match objects still
	# survive and all hit geometry is rebuilt in the new logical viewport.
	app.clear_game_modal()
	get_window().size = Vector2i(844, 390)
	get_window().content_scale_size = Vector2i(960, 444)
	get_viewport().set_meta("match_css_size", Vector2(844, 390))
	get_viewport().set_meta("match_safe_insets", Vector4(20, 0, 20, 12))
	get_viewport().set_meta("match_layout_generation", 2)
	app.responsive_layout_changed({"generation": 2, "height_only": false, "profile_changed": true})
	await settle()
	expect(app.table.get_instance_id() == table_id and app.table.camera.get_instance_id() == camera_id,
		"orientation reflow reuses table and camera")
	expect(app.match_hud.hand.get_instance_id() == hand_id,
		"orientation reflow reuses pooled hand cards")
	expect(load("res://scripts/ui/MatchLayout.gd").mobile_landscape(app),
		"orientation reflow selects mobile landscape profile")
	var hand_rect: Rect2 = app.match_hud.hand.get_global_rect()
	var safe_rect: Rect2 = load("res://scripts/ui/MatchLayout.gd").safe_rect(app)
	expect(hand_rect.position.x >= safe_rect.position.x - 1.0 and hand_rect.end.x <= safe_rect.end.x + 1.0,
		"landscape hand hitbox remains inside safe width")

	GameManager.clear()
	if failures.is_empty():
		print("PASS: %d Safari height-only and orientation persistence checks" % checks)
		get_tree().quit(0)
	else:
		print("FAIL: %d/%d Safari layout checks" % [failures.size(), checks])
		get_tree().quit(1)
