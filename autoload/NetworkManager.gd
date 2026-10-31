extends Node

signal updated
signal error_received(message: String)
signal visual_event(actor: int, kind: String, target: int)
var public_state: Dictionary = {}
var private_state: Dictionary = {}
var local_name: String = "Cao bồi"
var admission_timer: float = 0.0
var pending: Dictionary = {}
var session_port: int = 7000
var connecting: bool = false

func _ready() -> void:
	# Clients communicate only with the host; no peer relay or peer discovery needed.
	multiplayer.server_relay = false
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): register_player.rpc_id(1, local_name))
	multiplayer.connection_failed.connect(func(): leave(); error_received.emit("Connection failed. Check IP, port and firewall."))
	multiplayer.server_disconnected.connect(func(): leave(); error_received.emit("Host disconnected."))

func host_game(title: String, port: int) -> void:
	leave()
	if port < 1 or port > 65535:
		error_received.emit("Invalid port. Use a port from 1 to 65535.")
		return
	session_port = port
	local_name = clean_name(title)
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_server(port, 8)
	if result != OK:
		error_received.emit("Cannot host on that port: " + error_string(result))
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
	session_port = port
	local_name = clean_name(title)
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_client(address, port)
	if result != OK:
		error_received.emit("Connection failed: " + error_string(result))
		return
	multiplayer.multiplayer_peer = peer
	admission_timer = 12.0
	connecting = true
	updated.emit()

func leave() -> void:
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
	animate(actor, kind, target)
	for id in multiplayer.get_peers():
		if can_send(id):
			animate.rpc_id(id, actor, kind, target)

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
			return args.get("character") is String
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
