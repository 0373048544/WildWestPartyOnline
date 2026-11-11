extends Node

const LAYOUT = preload("res://scripts/ui/MatchLayout.gd")

var checks := 0
var failures: Array[String] = []
var app: Node

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("V28 FAILED: " + message)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame

func mobile_view(size: Vector2i) -> void:
	get_window().size = size
	get_window().content_scale_size = size
	get_viewport().set_meta("match_css_size", Vector2(size))
	get_viewport().set_meta("match_safe_insets", Vector4(8, 22, 8, 18) if size.y > size.x else Vector4(20, 0, 20, 12))
	get_viewport().set_meta("match_force_mobile_device", true)
	get_viewport().set_meta("match_layout_generation", int(get_viewport().get_meta("match_layout_generation", 0)) + 1)

func player(id: int, ready: bool, title: String = "") -> Dictionary:
	return {
		"player_id": id,
		"display_name": title if not title.is_empty() else "Cao bồi %d" % id,
		"seat_index": id - 1,
		"ready": ready,
		"is_connected": true
	}

func lobby_state(count: int, ready_ids: Array[int] = []) -> Dictionary:
	var players: Array = []
	for id in range(1, count + 1):
		players.append(player(id, ready_ids.has(id), "Người chơi có tên rất dài để kiểm tra cắt chữ" if id == 2 else ""))
	return {
		"started": false,
		"room_code": "V28ABC",
		"host_player_id": 1,
		"minimum_players": 2,
		"players": players,
		"debug": false
	}

func publish(state: Dictionary) -> void:
	NetworkManager.public_state = state
	NetworkManager.private_state = {}
	app.refresh()
	await settle()

func capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	var toast := app.root.get_node_or_null("OutGameToast") as Control
	if is_instance_valid(toast):
		toast.hide()
	var directory := ProjectSettings.globalize_path("res://tests/artifacts/v28")
	DirAccess.make_dir_recursive_absolute(directory)
	get_viewport().get_texture().get_image().save_png(directory.path_join(name + ".png"))

func _ready() -> void:
	mobile_view(Vector2i(390, 844))
	NetworkManager.mode = "offline"
	NetworkManager.connection_status = NetworkManager.CONNECTION_CONNECTED
	NetworkManager.public_state = lobby_state(2)
	app = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	await settle()

	var lobby: Control = app.content
	var lobby_id := lobby.get_instance_id()
	var player_one: Control = lobby.get_node("PlayerList/Player1")
	var player_one_id := player_one.get_instance_id()
	var ready_button: Button = lobby.find_child("ReadyButton", true, false)
	var ready_button_id := ready_button.get_instance_id()
	check(lobby.name == "Lobby", "lobby scene is active")
	await publish(lobby_state(2))
	check(app.content.get_instance_id() == lobby_id, "identical snapshot does not rebuild lobby")
	check(app.content.get_node("PlayerList/Player1").get_instance_id() == player_one_id, "identical snapshot keeps player row")

	await publish(lobby_state(2, [1]))
	check(app.content.get_instance_id() == lobby_id, "READY update keeps lobby node")
	check(app.content.get_node("PlayerList/Player1").get_instance_id() == player_one_id, "READY update keeps player card node")
	check(app.content.find_child("ReadyButton", true, false).get_instance_id() == ready_button_id, "READY update keeps action button")
	check("HỦY SẴN SÀNG" in ready_button.text, "READY label updates in place")

	await publish(lobby_state(7, [1, 2, 3, 4, 5, 6, 7]))
	check(app.content.get_node("PlayerList").get_child_count() == 7, "seven-player roster contains seven keyed rows")
	check(app.content.get_node("PlayerList/Player1").get_instance_id() == player_one_id, "join updates preserve existing player rows")
	check(not app.content.find_child("StartButton", true, false).disabled, "fully ready seven-player lobby enables Start")
	var copy_button: Button = app.content.find_child("CopyRoomCode", true, false)
	check(copy_button.size.x >= 90.0 and not copy_button.text.is_empty(), "mobile room-code button keeps readable text")
	var name_label: Label
	for node in app.content.get_node("PlayerList/Player2").find_children("*", "Label", true, false):
		if "Người chơi" in node.text:
			name_label = node
			break
	check(is_instance_valid(name_label) and name_label.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "long player name uses ellipsis")
	capture("lobby_portrait_390x844")
	var outer_scroll := app.content.get_parent().get_parent() as ScrollContainer
	outer_scroll.scroll_vertical = mini(40, int(outer_scroll.get_v_scroll_bar().max_value))
	var preserved_scroll := outer_scroll.scroll_vertical
	ready_button.grab_focus()
	await publish(lobby_state(7, [1, 2, 3, 4, 5, 6]))
	check(get_viewport().gui_get_focus_owner() == ready_button, "READY snapshot preserves keyboard/touch focus")
	check(abs(outer_scroll.scroll_vertical - preserved_scroll) <= 2, "READY snapshot preserves lobby scroll")
	await publish(lobby_state(7, [1, 2, 3, 4, 5, 6, 7]))

	await publish(lobby_state(2, [1, 2]))
	check(app.content.get_node("PlayerList").get_child_count() == 2, "leave update removes stale rows without rebuilding lobby")
	check(app.content.get_node("PlayerList/Player1").get_instance_id() == player_one_id, "leave update preserves remaining row")

	for viewport in [Vector2i(360, 640), Vector2i(375, 667), Vector2i(390, 844), Vector2i(393, 852), Vector2i(430, 932), Vector2i(844, 390)]:
		mobile_view(viewport)
		app.responsive_layout_changed({"profile_changed": true, "generation": get_viewport().get_meta("match_layout_generation")})
		await settle()
		var safe := LAYOUT.safe_rect(app)
		for control_name in ["ReadyButton", "StartButton", "LeaveLobbyButton"]:
			var control := app.content.find_child(control_name, true, false) as Control
			check(is_instance_valid(control) and control.get_global_rect().position.x >= safe.position.x - 1.0 and control.get_global_rect().end.x <= safe.end.x + 1.0, "%s stays horizontally safe at %dx%d" % [control_name, viewport.x, viewport.y])
		if viewport == Vector2i(844, 390):
			capture("lobby_landscape_844x390")

	# Restore a real match and validate the two-row mobile HUD contract.
	mobile_view(Vector2i(390, 844))
	GameManager.clear()
	for id in range(1, 3):
		GameManager.add_player(id, "Cao bồi %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()
	GameManager.selection.expire(GameManager)
	GameManager.flow.jobs.clear()
	GameManager.reactions.active = {}
	GameManager.turns.phase = "ACTION_PHASE"
	GameManager.publish()
	app.seen_role = GameManager.match_id
	app.refresh()
	await settle()
	var journal: Button = app.match_hud.get_node("MatchLog").find_child("ToggleHistory", true, false)
	var chat: Button = app.chat_panel.get_node("ChatToggle")
	var health: MobileSelfHealthHUD = app.match_hud.get_node("MobileSelfHealthHUD")
	check(absf(journal.get_global_rect().position.y - chat.get_global_rect().position.y) <= 2.0, "CHAT and NHẬT KÝ share the second HUD row")
	check(not journal.get_global_rect().intersects(chat.get_global_rect()), "CHAT and NHẬT KÝ do not overlap")
	check(not chat.get_global_rect().intersects(health.get_global_rect()), "CHAT does not overlap personal HP")
	capture("match_hud_portrait_390x844")
	GameManager.players[1].current_hp = 0
	GameManager.players[1].is_alive = true
	GameManager.publish()
	app.refresh()
	await settle()
	check(health.health_text() == "HẤP HỐI", "zero HP alive state is HẤP HỐI")
	GameManager.players[1].is_alive = false
	GameManager.publish()
	app.refresh()
	await settle()
	check(health.health_text() == "ĐÃ LOẠI", "dead state is ĐÃ LOẠI")

	GameManager.clear()
	NetworkManager.public_state = {}
	if failures.is_empty():
		print("PASS: %d V28 persistent lobby, responsive controls and two-row HUD checks" % checks)
		get_tree().quit(0)
	else:
		print("FAIL: %d/%d V28 checks" % [failures.size(), checks])
		get_tree().quit(1)
