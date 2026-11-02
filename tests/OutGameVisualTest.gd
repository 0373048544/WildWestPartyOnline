extends Node

var checks: int = 0
var failures: Array[String] = []
var app: Node
var capture_enabled: bool = false
var artifact_dir := "res://tests/artifacts/out-game"

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("OUT-GAME UI FAILED: " + message)

func set_layout(size: Vector2i) -> void:
	get_window().size = size
	get_window().content_scale_size = size
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	get_viewport().set_meta("match_css_size", Vector2(size))
	get_viewport().set_meta("match_safe_insets", Vector4(10, 18, 10, 20) if size.x < 900 else Vector4.ZERO)
	await get_tree().process_frame
	app.refresh()
	await get_tree().process_frame
	await get_tree().process_frame

func capture(name: String) -> void:
	if not capture_enabled:
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [artifact_dir, name])

func require_control(node_name: String, label: String) -> Control:
	var control: Control = app.root.find_child(node_name, true, false)
	check(is_instance_valid(control), label + " exists")
	if not is_instance_valid(control):
		return null
	var viewport_rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	check(viewport_rect.intersects(control.get_global_rect()), label + " remains inside viewport")
	check(control.size.y >= 42.0, label + " has touch-safe height")
	return control

func lobby_state(count: int, all_ready: bool = false) -> Dictionary:
	var players: Array = []
	for id in range(1, count + 1):
		players.append({
			"player_id": id, "display_name": "Cao bồi %d" % id,
			"seat_index": id - 1, "ready": all_ready or id % 2 == 0,
			"is_connected": true, "is_alive": true,
			"current_hp": 4, "max_hp": 4, "hand_count": 0,
			"public_role": "", "equipment_ids": [], "equipment_cards": [],
			"weapon_id": "", "weapon_card": {}, "weapon_range": 1,
			"character_id": "", "character": {}
		})
	return {
		"started": false, "room_code": "AB7KQ2", "minimum_players": 2,
		"max_players": 7, "host_player_id": 1, "players": players,
		"debug": false, "match_id": 0, "phase": "WAITING", "server_port": 7000
	}

func show_menu(screen: String, size: Vector2i, shot: String) -> void:
	NetworkManager.public_state = {}
	NetworkManager.private_state = {}
	app.screen = screen
	app.error_text = ""
	await set_layout(size)
	if screen == "main":
		require_control("CreateRoomButton", shot + " create")
		require_control("JoinRoomButton", shot + " join")
	else:
		require_control("SubmitRoomButton", shot + " submit")
		require_control("BackButton", shot + " back")
		check(is_instance_valid(app.name_field) and app.name_field.size.y >= 42, shot + " name input is touch-safe")
		if screen == "join":
			check(is_instance_valid(app.room_field) and app.room_field.size.y >= 42, shot + " room-code input is touch-safe")
	await capture(shot)

func show_lobby(count: int, ready: bool, size: Vector2i, shot: String) -> void:
	NetworkManager.public_state = lobby_state(count, ready)
	NetworkManager.private_state = {}
	app.error_text = ""
	await set_layout(size)
	require_control("ReadyButton", shot + " ready")
	require_control("StartButton", shot + " start")
	require_control("LeaveLobbyButton", shot + " leave")
	var list: Control = app.content.get_node_or_null("PlayerList")
	check(is_instance_valid(list) and list.get_child_count() == count, shot + " renders every player card")
	var code: Label = app.content.find_child("RoomCodeValue", true, false)
	check(is_instance_valid(code) and code.text == "AB7KQ2", shot + " shows full room code")
	await capture(shot)

func _ready() -> void:
	capture_enabled = OS.get_cmdline_user_args().has("--capture")
	if capture_enabled:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(artifact_dir))
	app = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	await show_menu("main", Vector2i(1440, 900), "desktop-main")
	await show_menu("join", Vector2i(1440, 900), "desktop-join")
	app.error_text = "Không thể tham gia phòng: mã không tồn tại."
	app.refresh()
	await get_tree().process_frame
	await capture("desktop-error")
	await show_lobby(4, false, Vector2i(1440, 900), "desktop-lobby-4")
	await show_lobby(7, true, Vector2i(1440, 900), "desktop-lobby-7")
	await show_menu("main", Vector2i(390, 844), "mobile-portrait-main")
	await show_lobby(7, true, Vector2i(390, 844), "mobile-portrait-lobby-7")
	await show_menu("join", Vector2i(844, 390), "mobile-landscape-join")
	await show_lobby(7, true, Vector2i(844, 390), "mobile-landscape-lobby-7")
	NetworkManager.public_state = {}
	NetworkManager.private_state = {}
	if failures.is_empty():
		print("PASS: %d out-of-match desktop/mobile layout, controls, room-code and player-card checks" % checks)
		get_tree().quit()
	else:
		push_error("FAIL: %d/%d out-of-match UI checks failed" % [failures.size(), checks])
		get_tree().quit(1)
