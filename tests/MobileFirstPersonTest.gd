extends Node

const LAYOUT = preload("res://scripts/ui/MatchLayout.gd")

var app: Node
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		push_error("MOBILE FIRST PERSON FAILED: " + message)
		get_tree().quit(1)
		assert(ok, message)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().create_timer(0.08).timeout

func build_match(player_count: int) -> void:
	GameManager.clear()
	for id in range(1, player_count + 1):
		GameManager.add_player(id, "Cao boi %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()
	GameManager.selection.expire(GameManager)
	GameManager.flow.jobs.clear()
	GameManager.reactions.active = {}
	GameManager.turns.current_player = 1
	GameManager.turns.phase = "ACTION_PHASE"
	for player in GameManager.players.values():
		player.current_hp = player.max_hp
	GameManager.publish()
	app.seen_role = GameManager.match_id
	app.refresh()
	await settle()

func screen_touch(index: int, position: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	return event

func test_seat_count(player_count: int) -> void:
	await build_match(player_count)
	var table: Node3D = app.table
	var mobile_camera: Node = table.mobile_camera
	check(mobile_camera.enabled, "%d players enables phone first-person camera" % player_count)
	check(table.avatars.size() == player_count, "%d players creates every avatar" % player_count)
	check(not table.avatars[1].visible and not table.nameplates[1].visible,
		"local model and nameplate do not obstruct the seated view")
	var visible_world_players := 0
	var unique_positions: Dictionary = {}
	for id in table.avatars:
		if id != 1 and table.avatars[id].visible:
			visible_world_players += 1
		unique_positions[str(table.avatars[id].position.snapped(Vector3(0.001, 0.001, 0.001)))] = true
	check(visible_world_players == player_count - 1, "%d players keeps every opponent rendered" % player_count)
	check(unique_positions.size() == player_count, "%d players retains distinct seats" % player_count)
	check(absf(table.camera.position.y - 2.30) < 0.02, "camera uses the raised seated eye height")
	check(absf(Vector2(table.camera.position.x, table.camera.position.z).length() - 3.52) < 0.03,
		"camera remains inside the local seat instead of using an overhead view")
	mobile_camera.reset_toward_table()
	check(not table.camera.is_position_behind(Vector3(0.0, 0.86, 0.0)), "reset points down toward the visible table center")

	# Exercise every possible local seat, not just the host seat. This changes only
	# the local presentation input passed to TableView; authoritative seat order is
	# untouched and must remain identical in the snapshot.
	var snapshot: Dictionary = NetworkManager.public_state
	for local_id in range(1, player_count + 1):
		table.state_signature = ""
		table.update_state(snapshot, local_id, [])
		var expected_seat: int = int(snapshot.players[local_id - 1].seat_index)
		var expected_angle: float = TAU * float(expected_seat) / player_count
		var expected_eye := Vector3(sin(expected_angle) * 3.52, 2.30, cos(expected_angle) * 3.52)
		check(table.camera.position.distance_to(expected_eye) < 0.04,
			"%d players local seat %d places camera at its own chair" % [player_count, expected_seat])
		check(not table.avatars[local_id].visible, "local seat %d hides only its own avatar" % expected_seat)
	table.state_signature = ""
	table.update_state(snapshot, 1, [])
	mobile_camera.reset_toward_table()

	# Every opponent can be brought in front of the same camera without moving
	# the authoritative table or changing any seat data.
	for id in table.avatars:
		if id == 1:
			continue
		var head: Vector3 = table.avatars[id].global_position + Vector3.UP * 1.6
		table.camera.look_at(head, Vector3.UP)
		mobile_camera.yaw = table.camera.rotation.y
		mobile_camera.pitch = clampf(table.camera.rotation.x, mobile_camera.MIN_PITCH, mobile_camera.MAX_PITCH)
		mobile_camera.apply_camera()
		table.plate_layout_key = ""
		table.layout_nameplates()
		check(not table.camera.is_position_behind(head), "player %d can be viewed by swiping" % id)
		check(table.nameplates[id].visible, "player %d nameplate appears only when in view" % id)
	mobile_camera.reset_toward_table()

func test_touch_ownership() -> void:
	var table: Node3D = app.table
	var controller: Node = table.mobile_camera
	var hand_before: Rect2 = app.match_hud.hand.get_global_rect()
	var table_zone: Rect2 = LAYOUT.get_table_focus_rect(table)
	var start := table_zone.get_center()
	var yaw_before: float = controller.yaw
	controller._unhandled_input(screen_touch(7, start, true))
	var drag := InputEventScreenDrag.new()
	drag.index = 7
	drag.position = start + Vector2(90.0, -9000.0)
	drag.relative = Vector2(90.0, -9000.0)
	controller._unhandled_input(drag)
	controller._unhandled_input(screen_touch(7, drag.position, false))
	check(not is_equal_approx(controller.yaw, yaw_before), "horizontal table swipe rotates the view")
	check(controller.pitch >= controller.MIN_PITCH and controller.pitch <= controller.MAX_PITCH,
		"vertical look is clamped to a comfortable range")
	check(app.match_hud.hand.get_global_rect().is_equal_approx(hand_before),
		"camera rotation never moves or scales the fixed 2D hand")

	var hand_point: Vector2 = LAYOUT.hand_rect(table).get_center()
	yaw_before = controller.yaw
	controller._unhandled_input(screen_touch(8, hand_point, true))
	drag.index = 8
	drag.position = hand_point + Vector2(120.0, 0.0)
	drag.relative = Vector2(120.0, 0.0)
	controller._unhandled_input(drag)
	controller._unhandled_input(screen_touch(8, drag.position, false))
	check(is_equal_approx(controller.yaw, yaw_before) and controller.touch_index == -1,
		"hand swipe is never captured by the camera")

	var action_point: Vector2 = LAYOUT.action_rect(table).get_center()
	controller._unhandled_input(screen_touch(9, action_point, true))
	check(controller.touch_index == -1, "action HUD touch is never captured by the camera")

	table.targeting.blocked = true
	yaw_before = controller.yaw
	controller._unhandled_input(screen_touch(10, start, true))
	check(controller.touch_index == -1 and is_equal_approx(controller.yaw, yaw_before),
		"blocking modal/reaction state owns input before the camera")
	table.targeting.blocked = false

func test_orientation_reflow() -> void:
	var table: Node3D = app.table
	var table_instance: int = table.get_instance_id()
	var camera_instance: int = table.camera.get_instance_id()
	table.mobile_camera.yaw += deg_to_rad(11.0)
	table.mobile_camera.pitch = clampf(table.mobile_camera.pitch - deg_to_rad(4.0), table.mobile_camera.MIN_PITCH, table.mobile_camera.MAX_PITCH)
	table.mobile_camera.apply_camera()
	var yaw_before: float = table.mobile_camera.yaw
	var pitch_before: float = table.mobile_camera.pitch
	get_window().size = Vector2i(844, 390)
	get_window().content_scale_size = Vector2i(960, 444)
	get_viewport().set_meta("match_css_size", Vector2(844, 390))
	table.state_signature = ""
	table.update_state(NetworkManager.public_state, 1, [])
	await settle()
	check(LAYOUT.mobile_landscape(table) and table.mobile_camera.enabled, "orientation change keeps first-person enabled")
	check(is_equal_approx(table.camera.fov, 72.0), "landscape uses the wider first-person projection")
	check(table.get_instance_id() == table_instance and table.camera.get_instance_id() == camera_instance,
		"orientation change reuses the match and camera nodes")
	check(is_equal_approx(table.mobile_camera.yaw, yaw_before) and is_equal_approx(table.mobile_camera.pitch, pitch_before),
		"orientation change preserves first-person yaw and pitch")
	get_window().size = Vector2i(390, 844)
	get_window().content_scale_size = Vector2i(600, 1298)
	get_viewport().set_meta("match_css_size", Vector2(390, 844))
	table.state_signature = ""
	table.update_state(NetworkManager.public_state, 1, [])
	await settle()
	check(LAYOUT.mobile_portrait(table) and is_equal_approx(table.camera.fov, 68.0),
		"portrait projection restores without rebuilding the match")
	check(is_equal_approx(table.mobile_camera.yaw, yaw_before) and is_equal_approx(table.mobile_camera.pitch, pitch_before),
		"returning to portrait does not reset camera orientation")

func test_touch_targeting() -> void:
	await build_match(2)
	var table: Node3D = app.table
	var target_id := 2
	var chosen := [0]
	table.targeting.target_chosen.connect(func(id: int): chosen[0] = id, CONNECT_ONE_SHOT)
	table.targeting.begin_targeting(99001, 1, [target_id], {target_id: {"distance": 1, "range": 1}}, "BANG")
	var target_point: Vector2 = table.camera.unproject_position(table.avatars[target_id].global_position + Vector3.UP * 1.6)
	check(LAYOUT.get_table_focus_rect(table).has_point(target_point), "opponent is inside the touchable table region")
	for index in [20, 21]:
		table.mobile_camera._unhandled_input(screen_touch(index, target_point, true))
		table.mobile_camera._unhandled_input(screen_touch(index, target_point, false))
	check(chosen[0] == target_id, "two clear taps select and confirm the authoritative target")
	check(table.targeting.selected_card < 0, "confirmed target leaves no stuck targeting state")

	# Repeat in the short landscape geometry used by the real browser E2E test.
	get_window().size = Vector2i(844, 390)
	get_window().content_scale_size = Vector2i(960, 444)
	get_viewport().set_meta("match_css_size", Vector2(844, 390))
	table.state_signature = ""
	table.update_state(NetworkManager.public_state, 1, [])
	await settle()
	chosen[0] = 0
	table.targeting.target_chosen.connect(func(id: int): chosen[0] = id, CONNECT_ONE_SHOT)
	table.targeting.begin_targeting(99002, 1, [target_id], {target_id: {"distance": 1, "range": 1}}, "BANG")
	target_point = table.camera.unproject_position(table.avatars[target_id].global_position + Vector3.UP * 1.6)
	table.mobile_camera._unhandled_input(screen_touch(22, target_point, true))
	table.mobile_camera._unhandled_input(screen_touch(22, target_point, false))
	table.mobile_camera._unhandled_input(screen_touch(23, target_point, true))
	table.mobile_camera._unhandled_input(screen_touch(23, target_point, false))
	check(chosen[0] == target_id, "landscape raised camera keeps two-tap target confirmation reliable")
	get_window().size = Vector2i(390, 844)
	get_window().content_scale_size = Vector2i(600, 1298)
	get_viewport().set_meta("match_css_size", Vector2(390, 844))

func test_desktop_unchanged() -> void:
	get_viewport().set_meta("match_force_mobile_device", false)
	app.table.state_signature = ""
	app.table.update_state(NetworkManager.public_state, app.local_id(), [])
	await settle()
	check(not app.table.mobile_camera.enabled, "narrow desktop viewport does not enable phone camera")
	check(app.table.avatars[1].visible and app.table.nameplates[1].visible,
		"desktop keeps the existing local avatar and nameplate")
	check(app.table.camera_goal.y > 7.0, "desktop retains the established overhead camera goal")

func _ready() -> void:
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	get_window().size = Vector2i(390, 844)
	get_window().content_scale_size = Vector2i(600, 1298)
	get_viewport().set_meta("match_css_size", Vector2(390, 844))
	get_viewport().set_meta("match_safe_insets", Vector4(0, 24, 0, 18))
	get_viewport().set_meta("match_force_mobile_device", true)
	NetworkManager.mode = "offline"
	app = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	for player_count in [2, 4, 7]:
		await test_seat_count(player_count)
	await test_touch_ownership()
	await test_orientation_reflow()
	await test_touch_targeting()
	await test_desktop_unchanged()
	print("MOBILE FIRST PERSON PASS: %d checks" % checks)
	get_tree().quit(0)
