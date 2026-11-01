extends Node

var app: Node
var other := WebSocketTransport.new()
var other_state: Dictionary = {}
var other_id: int = 0
var error_text: String = ""

func require(value: bool, message: String) -> void:
	if not value:
		push_error("ROOM CREATION FAILED: " + message)
		get_tree().quit(1)
		assert(value, message)

func until(condition: Callable, description: String) -> void:
	var deadline := Time.get_ticks_msec() + 15000
	while not condition.call():
		require(Time.get_ticks_msec() < deadline, "Timeout: " + description + "; " + error_text)
		await get_tree().process_frame

func _process(_delta: float) -> void:
	other.poll()

func _ready() -> void:
	OS.set_environment("WWPO_SERVER_URL", "ws://127.0.0.1:7000")
	NetworkManager.error_received.connect(func(message): error_text = message)
	app = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	app.screen = "host"
	app.refresh()
	app.name_field.text = "Chu phong"
	app.connect_game()
	await until(func(): return not NetworkManager.public_state.is_empty(), "HOST enters lobby")
	if OS.get_cmdline_user_args().has("--external"):
		require(not is_instance_valid(NetworkManager.local_room_server), "existing dedicated server is reused")
	else:
		require(is_instance_valid(NetworkManager.local_room_server), "local server automatically starts without a dedicated process")
	require(not NetworkManager.connecting and NetworkManager.mode == "websocket", "embedded service preserves client mode")
	require(app.content.name == "Lobby" and not is_instance_valid(app.table), "HOST always opens Lobby first")
	var code: String = NetworkManager.room_client.room_code
	var id: int = NetworkManager.local_player_id()
	require(code.length() == 6 and NetworkManager.host_player_id() == id, "room code and host identity")
	other.connected.connect(func(): other.send_message({"type": "JOIN_ROOM", "version": 1, "payload": {"player_name": "Khach", "room_code": code}}))
	other.message_received.connect(func(message):
		if message.type == "STATE":
			other_state = message.payload.public
		elif message.type == "JOIN_ACCEPTED":
			other_id = int(message.payload.player_id))
	other.connect_to_server("ws://127.0.0.1:7000")
	await until(func(): return other_state.get("players", []).size() == 2 and NetworkManager.public_state.players.size() == 2, "shared player list")
	NetworkManager.send_intent("ready")
	other.send_message({"type": "SET_READY", "version": 1, "payload": {}, "intent_id": "guest-ready"})
	await until(func(): return other_state.players.all(func(p): return p.ready) and NetworkManager.public_state.players.all(func(p): return p.ready), "Ready synchronizes both ways")
	other.send_message({"type": "LEAVE_ROOM", "version": 1, "payload": {}})
	await until(func(): return NetworkManager.public_state.players.size() == 1, "guest leaves")
	other.disconnect_from_server()
	NetworkManager.leave()
	NetworkManager.create_room("Phong moi")
	await until(func(): return not NetworkManager.public_state.is_empty(), "second creation reuses server")
	require(NetworkManager.room_client.room_code != code, "new room is independent")
	NetworkManager.leave()
	OS.set_environment("WWPO_SERVER_URL", "ws://127.0.0.1:17071")
	error_text = ""
	NetworkManager.create_room("Unreachable")
	await until(func(): return not error_text.is_empty(), "unavailable custom server reports error")
	require(not NetworkManager.connecting and NetworkManager.public_state.is_empty(), "failure clears connecting screen")
	OS.set_environment("WWPO_SERVER_URL", "ws://127.0.0.1:7000")
	NetworkManager.create_room("Cancel")
	NetworkManager.leave()
	await get_tree().create_timer(0.2).timeout
	require(not NetworkManager.connecting and NetworkManager.public_state.is_empty(), "cancel remains cancelled")
	print("PASS: desktop HOST auto-start -> Lobby; client Join; player/Ready sync; reuse; connection failure; cancel")
	get_tree().quit()
