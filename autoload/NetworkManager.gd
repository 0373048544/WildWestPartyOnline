extends Node

signal updated
signal error_received(message: String)
signal visual_event(actor: int, kind: String, target: int)
signal table_event(event: Dictionary)
signal chat_message(message: Dictionary)
signal chat_history(messages: Array)
signal chat_error(message: String)
signal connection_status_changed(status: String)

const CONNECTION_IDLE := "IDLE"
const CONNECTION_CONNECTED := "CONNECTED"
const CONNECTION_RECONNECTING := "RECONNECTING"
const CONNECTION_DISCONNECTED := "DISCONNECTED"
const CONNECTION_SESSION_EXPIRED := "SESSION_EXPIRED"
const CONNECTION_SERVER_UNAVAILABLE := "SERVER_UNAVAILABLE"
var public_state: Dictionary = {}
var private_state: Dictionary = {}
var local_name: String = "Cao bồi"
var admission_timer: float = 0.0
var pending: Dictionary = {}
var session_port: int = 7000
var connecting: bool = false
var mode: String = "offline"
var room_client: Node
var local_room_server: Node
var audio_sequence: int = 0
var chat_room: String = ""
var chat_messages: Array[Dictionary] = []
var seen_chat_messages: Dictionary = {}
var enet_chat := ChatRoomState.new("ENET")
var connection_status: String = CONNECTION_IDLE

func stamp_audio(event: Dictionary) -> Dictionary:
	audio_sequence += 1
	var result := event.duplicate(true)
	var event_match: int = int(result.get("match_id", GameManager.match_id))
	var id := "enet:%d:%d" % [event_match, audio_sequence]
	result["match_id"] = event_match
	result["audio_event_id"] = id
	result["event_id"] = id
	return result

func _ready() -> void:
	# Clients communicate only with the host; no peer relay or peer discovery needed.
	multiplayer.server_relay = false
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): register_player.rpc_id(1, local_name))
	multiplayer.connection_failed.connect(func():
		leave()
		set_connection_status(CONNECTION_SERVER_UNAVAILABLE)
		error_received.emit("Không thể liên lạc với máy chủ. Hãy kiểm tra địa chỉ, cổng và tường lửa."))
	multiplayer.server_disconnected.connect(func():
		leave()
		set_connection_status(CONNECTION_SERVER_UNAVAILABLE)
		error_received.emit("Máy chủ đã đóng kết nối."))
	room_client = load("res://scripts/network/RoomClient.gd").new()
	room_client.manager = self
	add_child(room_client)
	room_client.restore()

func is_authority() -> bool:
	return mode in ["offline", "enet"] and multiplayer.is_server()

func host_player_id() -> int:
	return room_client.host_id if mode == "websocket" else 1

func is_room_host(id: int) -> bool:
	return id == host_player_id()

func allow_two_players() -> bool:
	return true

func set_connection_status(next_status: String) -> void:
	if connection_status == next_status:
		return
	connection_status = next_status
	connection_status_changed.emit(connection_status)
	updated.emit()

func can_submit_intents() -> bool:
	if mode == "websocket":
		return (
			connection_status == CONNECTION_CONNECTED
			and is_instance_valid(room_client)
			and room_client.can_send_gameplay()
			and not public_state.is_empty()
		)
	if mode == "enet":
		return multiplayer.is_server() or (not connecting and multiplayer.has_multiplayer_peer())
	return mode == "offline"

func local_player_id() -> int:
	return room_client.player_id if mode == "websocket" else multiplayer.get_unique_id()

func create_room(title: String) -> void:
	room_client.request_room("CREATE_ROOM", title)

func start_local_room_server() -> bool:
	# F5 hosting uses the same authoritative WebSocket service as dedicated mode.
	if OS.has_feature("web") or NetworkConfig.server_url() not in ["ws://127.0.0.1:7000", "ws://localhost:7000"]:
		return false
	if is_instance_valid(local_room_server):
		return local_room_server.startup_error == OK
	local_room_server = load("res://server/DedicatedServer.gd").new()
	local_room_server.embedded = true
	local_room_server.development = OS.is_debug_build()
	add_child(local_room_server)
	if local_room_server.startup_error != OK:
		local_room_server.queue_free()
		local_room_server = null
		return false
	return true

func join_room(title: String, code: String) -> void:
	room_client.request_room("JOIN_ROOM", title, code)

func publish_game(game: Node) -> void:
	if not is_authority():
		return
	var snapshot: Dictionary = game.public_snapshot()
	receive_public(snapshot)
	for id in game.players:
		if not game.players[id].is_connected:
			continue
		if id == 1:
			receive_private(game.private_snapshot(id))
		elif can_send(id):
			receive_public.rpc_id(id, snapshot)
			receive_private.rpc_id(id, game.private_snapshot(id))

func send_notice(id: int, message: String) -> void:
	if id == 1:
		notice(message)
	elif can_send(id):
		notice.rpc_id(id, message)

func host_game(title: String, port: int) -> void:
	leave()
	mode = "enet"
	if port < 1 or port > 65535:
		error_received.emit("Invalid port. Use a port from 1 to 65535.")
		return
	session_port = port
	local_name = clean_name(title)
	enet_chat = ChatRoomState.new("ENET")
	var peer := ENetTransport.server(port)
	if peer == null:
		error_received.emit("Cannot host on that port: unavailable")
		return
	multiplayer.multiplayer_peer = peer
	GameManager.add_player(1, local_name)
	begin_chat_room("ENET")
	GameManager.publish()

func join_game(title: String, address: String, port: int) -> void:
	if not address.is_valid_ip_address():
		error_received.emit("Invalid IP. Enter an IPv4 or IPv6 address.")
		return
	if port < 1 or port > 65535:
		error_received.emit("Invalid port. Use a port from 1 to 65535.")
		return
	leave()
	mode = "enet"
	session_port = port
	local_name = clean_name(title)
	begin_chat_room("ENET")
	var peer := ENetTransport.client(address, port)
	if peer == null:
		error_received.emit("Connection failed: unavailable")
		return
	multiplayer.multiplayer_peer = peer
	admission_timer = 12.0
	connecting = true
	updated.emit()

func leave() -> void:
	if room_client:
		room_client.leave()
	mode = "offline"
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	pending.clear()
	admission_timer = 0.0
	connecting = false
	public_state = {}
	private_state = {}
	clear_chat()
	GameManager.clear()
	set_connection_status(CONNECTION_IDLE)
	updated.emit()

func clean_name(title: String) -> String:
	var value := title.strip_edges().substr(0, 24).replace("\n", " ").replace("\r", " ")
	return value if not value.is_empty() else TextCatalog.text("Cowboy")

func _process(delta: float) -> void:
	if admission_timer > 0.0:
		admission_timer -= delta
		if admission_timer <= 0.0:
			leave()
			error_received.emit("Connection failed: server did not admit this player.")
	if multiplayer.is_server():
		for id in pending.keys():
			if Time.get_ticks_msec() > pending[id]:
				pending.erase(id)
				if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
					multiplayer.multiplayer_peer.disconnect_peer(id)

func _peer_connected(id: int) -> void:
	if multiplayer.is_server():
		pending[id] = Time.get_ticks_msec() + 5000

func _peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		pending.erase(id)
		GameManager.disconnect_player(id)

@rpc("any_peer", "call_remote", "reliable")
func register_player(title: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not pending.has(sender):
		return
	pending.erase(sender)
	var reason := ""
	if GameManager.started:
		reason = "Game already started."
	elif GameManager.players.size() >= 7:
		reason = "Server full."
	if not reason.is_empty():
		rejected.rpc_id(sender, reason)
		pending[sender] = Time.get_ticks_msec() + 1000
		return
	GameManager.add_player(sender, clean_name(title))
	GameManager.publish()
	if can_send(sender):
		receive_chat_history_rpc.rpc_id(sender, enet_chat.recent_history())

@rpc("authority", "call_remote", "reliable")
func rejected(reason: String) -> void:
	leave()
	error_received.emit(reason)

func send_intent(action: String, args: Dictionary = {}) -> bool:
	if not can_submit_intents():
		return false
	args = args.duplicate(true)
	args["match_id"] = int(public_state.get("match_id", GameManager.match_id))
	if mode == "websocket":
		return room_client.send_intent(action, args)
	if multiplayer.is_server():
		GameManager.handle_intent(1, action, args)
	else:
		request.rpc_id(1, action, args)
	return true

func begin_chat_room(code: String) -> void:
	if chat_room == code:
		return
	chat_room = code
	chat_messages.clear()
	seen_chat_messages.clear()
	chat_history.emit(chat_messages)

func clear_chat() -> void:
	chat_room = ""
	chat_messages.clear()
	seen_chat_messages.clear()
	chat_history.emit(chat_messages)

func receive_chat_history(messages: Variant) -> void:
	if not messages is Array:
		return
	for message in messages:
		if message is Dictionary:
			receive_chat_message(message)
	chat_history.emit(chat_messages.duplicate(true))

func receive_chat_message(message: Dictionary) -> void:
	var message_id := str(message.get("message_id", ""))
	if message_id.is_empty() or seen_chat_messages.has(message_id):
		return
	seen_chat_messages[message_id] = true
	chat_messages.append(message.duplicate(true))
	while chat_messages.size() > 50:
		var removed: Dictionary = chat_messages.pop_front()
		seen_chat_messages.erase(str(removed.get("message_id", "")))
	chat_message.emit(message.duplicate(true))

func send_chat(text: String) -> void:
	if mode == "websocket":
		room_client.send_chat(text)
	elif mode == "enet":
		if multiplayer.is_server():
			accept_enet_chat(1, {"text": text})
		else:
			request_chat.rpc_id(1, text)

func accept_enet_chat(sender: int, payload: Dictionary) -> void:
	if not multiplayer.is_server() or not GameManager.players.has(sender):
		return
	var player: PlayerState = GameManager.players[sender]
	var result := enet_chat.accept(sender, player.display_name, not player.is_alive, payload, Time.get_ticks_msec(), int(Time.get_unix_time_from_system()))
	if not bool(result.get("ok", false)):
		if sender == 1:
			chat_error.emit(str(result.get("reason", "Không gửi được tin nhắn.")))
		elif can_send(sender):
			receive_chat_rejected.rpc_id(sender, str(result.get("reason", "Không gửi được tin nhắn.")))
		return
	receive_chat_message(result.message)
	for id in multiplayer.get_peers():
		if can_send(id):
			receive_chat.rpc_id(id, result.message)

@rpc("any_peer", "call_remote", "reliable")
func request_chat(text: String) -> void:
	if multiplayer.is_server():
		accept_enet_chat(multiplayer.get_remote_sender_id(), {"text": text})

@rpc("authority", "call_remote", "reliable")
func receive_chat(message: Dictionary) -> void:
	receive_chat_message(message)

@rpc("authority", "call_remote", "reliable")
func receive_chat_rejected(message: String) -> void:
	chat_error.emit(message)

@rpc("authority", "call_remote", "reliable")
func receive_chat_history_rpc(messages: Array) -> void:
	receive_chat_history(messages)

func can_send(id: int) -> bool:
	if not multiplayer.get_peers().has(id) or not multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		return false
	var peer: ENetPacketPeer = multiplayer.multiplayer_peer.get_peer(id)
	return peer != null and peer.get_state() == ENetPacketPeer.STATE_CONNECTED

func broadcast_animation(actor: int, kind: String, target: int = 0) -> void:
	broadcast_table_event({"kind": "animation", "actor": actor, "animation": kind, "target": target})

func broadcast_table_event(event: Dictionary) -> void:
	# Cosmetic payloads only: counts, public player IDs and already-revealed cards.
	if not multiplayer.is_server():
		return
	var stamped := stamp_audio(event)
	receive_table_event(stamped)
	for id in multiplayer.get_peers():
		if can_send(id):
			receive_table_event.rpc_id(id, stamped)

func send_private_event(id: int, event: Dictionary) -> void:
	# Full hidden-card data is sent only to the intended participant.
	var stamped := stamp_audio(event)
	if id == 1:
		receive_table_event(stamped)
	elif can_send(id):
		receive_table_event.rpc_id(id, stamped)

@rpc("authority", "call_remote", "reliable")
func receive_table_event(event: Dictionary) -> void:
	table_event.emit(event)

@rpc("any_peer", "call_remote", "reliable")
func request(action: String, args: Dictionary) -> void:
	if multiplayer.is_server() and valid_arguments(action, args):
		var sender := multiplayer.get_remote_sender_id()
		if GameManager.players.has(sender):
			GameManager.handle_intent(sender, action, args)

func valid_arguments(action: String, args: Dictionary) -> bool:
	if args.size() > 6 or not args.get("match_id", 0) is int:
		return false
	var payload := args.duplicate(true)
	payload.erase("match_id")
	match action:
		"ready", "start", "spectate", "rematch", "restart", "lobby", "end":
			return payload.is_empty()
		"play":
			return payload.get("card") is int and payload.get("target") is int
		"discard":
			return payload.get("card") is int
		"reaction":
			return payload.get("request") is int and payload.get("accept") is bool and payload.get("cards", []) is Array and payload.get("cards", []).size() <= 2 and payload.get("option", "") is String and payload.get("card", 0) is int
		"character":
			return payload.get("character") is String and args.get("match_id") is int
		"ability":
			return (
				payload.keys().all(func(key): return key in ["cards", "request"])
				and payload.get("cards") is Array
				and payload.cards.size() == 2
				and payload.cards.all(func(id): return id is int)
				and (not payload.has("request") or payload.request is int)
			)
		"debug":
			return payload.get("operation") is String and payload.get("target", 1) is int
	return false

@rpc("authority", "call_remote", "reliable")
func receive_public(snapshot: Dictionary) -> void:
	if snapshot.get("match_id", 0) != public_state.get("match_id", 0):
		private_state = {}
	public_state = snapshot
	admission_timer = 0.0
	connecting = false
	set_connection_status(CONNECTION_CONNECTED)
	session_port = int(snapshot.get("server_port", session_port))
	updated.emit()

@rpc("authority", "call_remote", "reliable")
func receive_private(snapshot: Dictionary) -> void:
	private_state = snapshot
	updated.emit()

@rpc("authority", "call_remote", "reliable")
func notice(message: String) -> void:
	error_received.emit(message)

@rpc("authority", "call_local", "reliable")
func animate(actor: int, kind: String, target: int = 0) -> void:
	visual_event.emit(actor, kind, target)
