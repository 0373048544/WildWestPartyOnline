extends Node

signal updated
signal error_received(message: String)
signal visual_event(actor: int, kind: String, target: int)
signal table_event(event: Dictionary)
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

func stamp_audio(event: Dictionary) -> Dictionary:
	audio_sequence += 1
	var result := event.duplicate(true)
	result["audio_event_id"] = "enet:%d:%d" % [GameManager.match_id, audio_sequence]
	return result

func _ready() -> void:
	# Clients communicate only with the host; no peer relay or peer discovery needed.
	multiplayer.server_relay = false
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): register_player.rpc_id(1, local_name))
	multiplayer.connection_failed.connect(func(): leave(); error_received.emit("Connection failed. Check IP, port and firewall."))
	multiplayer.server_disconnected.connect(func(): leave(); error_received.emit("Host disconnected."))
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
	return OS.is_debug_build()

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
	var peer := ENetTransport.server(port)
	if peer == null:
		error_received.emit("Cannot host on that port: unavailable")
		return
	multiplayer.multiplayer_peer = peer
	GameManager.add_player(1, local_name)
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
	GameManager.clear()
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

@rpc("authority", "call_remote", "reliable")
func rejected(reason: String) -> void:
	leave()
	error_received.emit(reason)

func send_intent(action: String, args: Dictionary = {}) -> void:
	if action == "character":
		args = args.duplicate(true)
		args["match_id"] = int(public_state.get("match_id", 0))
	if mode == "websocket":
		room_client.send_intent(action, args)
		return
	if multiplayer.is_server():
		GameManager.handle_intent(1, action, args)
	else:
		request.rpc_id(1, action, args)

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
	if args.size() > 5:
		return false
	match action:
		"ready", "start", "restart", "lobby", "end":
			return args.is_empty()
		"play":
			return args.get("card") is int and args.get("target") is int
		"discard":
			return args.get("card") is int
		"reaction":
			return args.get("request") is int and args.get("accept") is bool and args.get("cards", []) is Array and args.get("cards", []).size() <= 2 and args.get("option", "") is String and args.get("card", 0) is int
		"character":
			return args.get("character") is String and args.get("match_id") is int
		"ability":
			return args.get("cards") is Array and args.cards.size() == 2 and args.cards.all(func(id): return id is int)
		"debug":
			return args.get("operation") is String and args.get("target", 1) is int
	return false

@rpc("authority", "call_remote", "reliable")
func receive_public(snapshot: Dictionary) -> void:
	if snapshot.get("match_id", 0) != public_state.get("match_id", 0):
		private_state = {}
	public_state = snapshot
	admission_timer = 0.0
	connecting = false
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
