extends Node

var checks := 0
var failures: Array[String] = []
var app: Node

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("V31 FAILED: " + message)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame

func set_view(size: Vector2i) -> void:
	get_window().size = size
	get_window().content_scale_size = size
	get_viewport().set_meta("match_css_size", Vector2(size))
	get_viewport().set_meta("match_safe_insets", Vector4(8, 22, 8, 18) if size.y > size.x else Vector4(20, 0, 20, 12))
	get_viewport().set_meta("match_force_mobile_device", true)
	get_viewport().set_meta("match_layout_generation", int(get_viewport().get_meta("match_layout_generation", 0)) + 1)

func player(id: int, ready: bool = true) -> Dictionary:
	return {
		"player_id": id, "display_name": "Cao bồi %d" % id,
		"seat_index": id - 1, "ready": ready, "is_connected": true
	}

func lobby(host_id: int) -> Dictionary:
	return {
		"started": false, "room_code": "V31ABC", "host_player_id": host_id,
		"minimum_players": 2, "players": [player(1), player(2)], "debug": false
	}

func publish(state: Dictionary) -> void:
	NetworkManager.public_state = state
	NetworkManager.private_state = {}
	app.refresh()
	await settle()

func _ready() -> void:
	set_view(Vector2i(360, 640))
	NetworkManager.mode = "offline"
	NetworkManager.connecting = false
	NetworkManager.connection_status = NetworkManager.CONNECTION_IDLE
	NetworkManager.public_state = {}
	app = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	await settle()

	var footer := app.root.find_child("ServerConnectionStatus", true, false) as Label
	expect(is_instance_valid(footer), "main menu has a live connection status label")
	expect("MÁY CHỦ SẴN SÀNG" not in footer.text and "CHƯA KẾT NỐI" in footer.text, "idle menu does not claim server readiness")
	NetworkManager.set_connection_status(NetworkManager.CONNECTION_CONNECTING)
	await settle()
	expect("ĐANG KẾT NỐI" in footer.text, "connecting state updates without rebuilding the menu")
	NetworkManager.set_connection_status(NetworkManager.CONNECTION_SERVER_UNAVAILABLE)
	await settle()
	expect("KHÔNG THỂ KẾT NỐI" in footer.text, "failed state is visible on the menu")

	await publish(lobby(2))
	var mounted_lobby: Control = app.content
	var mounted_id := mounted_lobby.get_instance_id()
	var player_id := mounted_lobby.get_node("PlayerList/Player1").get_instance_id()
	expect(mounted_lobby.find_children("StartButton", "Button", true, false).is_empty(), "non-host does not see Start")
	expect(mounted_lobby.find_children("WaitingForHostBadge", "PanelContainer", true, false).size() == 1, "non-host sees one waiting badge")

	await publish(lobby(1))
	expect(app.content.get_instance_id() == mounted_id, "host migration keeps the mounted lobby")
	expect(app.content.get_node("PlayerList/Player1").get_instance_id() == player_id, "host migration keeps keyed player rows")
	expect(app.content.find_children("StartButton", "Button", true, false).size() == 1, "new host receives exactly one Start button")
	expect(app.content.find_children("WaitingForHostBadge", "PanelContainer", true, false).is_empty(), "new host waiting badge is removed")
	var start := app.content.find_child("StartButton", true, false) as Button
	expect(is_instance_valid(start) and not start.disabled, "new host Start reflects ready state")

	await publish(lobby(2))
	expect(app.content.find_children("StartButton", "Button", true, false).is_empty(), "former host loses Start immediately")
	expect(app.content.find_children("WaitingForHostBadge", "PanelContainer", true, false).size() == 1, "former host gets one waiting badge without duplicates")

	NetworkManager.public_state = {}
	NetworkManager.private_state = {}
	NetworkManager.connection_status = NetworkManager.CONNECTION_IDLE
	if failures.is_empty():
		print("PASS: %d V31 menu status and host migration UI checks" % checks)
		get_tree().quit(0)
	else:
		print("FAIL: %d/%d V31 checks" % [failures.size(), checks])
		get_tree().quit(1)
