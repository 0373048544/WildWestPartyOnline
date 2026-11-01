extends Node

const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const MAX_PACKET := 16384
const GRACE_MS := 45000
var listener := TCPServer.new()
var connections: Dictionary = {}
var sessions: Dictionary = {} # Private tokens never appear in public room state or logs.
var players_to_tokens: Dictionary = {}
var rooms: Dictionary = {}
var next_connection: int = 1
var next_player: int = 100
var port: int = 7000
var development: bool = false
var last_cleanup: int = 0
var embedded: bool = false
var startup_error: Error = OK

func _ready() -> void:
	if not embedded:
		NetworkManager.mode = "dedicated"
		GameManager.set_process(false)
	var env_port := OS.get_environment("PORT")
	if env_port.is_valid_int():
		var parsed_port := int(env_port)
		if parsed_port > 0 and parsed_port <= 65535:
			port = parsed_port
	for arg in OS.get_cmdline_user_args():
		if arg == "--development":
			development = true
		elif arg.begins_with("--port="):
			var requested_port := arg.trim_prefix("--port=")
			if requested_port.is_valid_int():
				var parsed_port := int(requested_port)
				if parsed_port > 0 and parsed_port <= 65535:
					port = parsed_port
	var address := "127.0.0.1" if embedded else OS.get_environment("WWPO_BIND")
	if address.is_empty():
		address = "127.0.0.1" if embedded else "0.0.0.0"
	startup_error = listener.listen(port, address)
	if startup_error != OK:
		if not embedded:
			push_error("Cannot listen on game server port: " + str(startup_error))
			get_tree().quit(1)
		set_process(false)
		return
	print("ROOM SERVER READY ws://%s:%d development=%s" % [address, port, development])

func _exit_tree() -> void:
	listener.stop()
	for connection in connections.values():
		connection.peer.close(1001, "server stopped")

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var accepts := 0
	while listener.is_connection_available() and accepts < 16:
		accepts += 1
		var stream := listener.take_connection()
		if connections.size() >= 256:
			stream.disconnect_from_host()
			continue
		var peer := WebSocketPeer.new()
		peer.inbound_buffer_size = 65536
		peer.outbound_buffer_size = 1048576
		peer.max_queued_packets = 128
		if peer.accept_stream(stream) != OK:
			continue
		connections[next_connection] = {"peer": peer, "player": 0, "since": now, "window": now, "count": 0, "last_seen": now, "last_ping": now}
		next_connection += 1
	for id in connections.keys():
		if not connections.has(id):
			continue
		var conn: Dictionary = connections[id]
		var peer: WebSocketPeer = conn.peer
		peer.poll()
		if peer.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			drop_connection(id)
			continue
		if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
			if now - int(conn.since) > 10000:
				peer.close()
				drop_connection(id)
			continue
		if now - int(conn.last_ping) > 15000:
			send(id, "PING", {})
			conn.last_ping = now
		if now - int(conn.last_seen) > 60000 or (conn.player == 0 and now - int(conn.since) > 12000):
			peer.close(1000, "timeout")
			drop_connection(id)
			continue
		var budget := 32
		while connections.has(id) and peer.get_available_packet_count() > 0 and budget > 0:
			budget -= 1
			var packet := peer.get_packet()
			if packet.size() > MAX_PACKET:
				peer.close(1009, "packet too large")
				drop_connection(id)
				break
			if now - int(conn.window) >= 1000:
				conn.window = now
				conn.count = 0
			conn.count += 1
			if conn.count > 35:
				peer.close(1008, "rate limit")
				drop_connection(id)
				break
			conn.last_seen = now
			var message: Variant = JSON.parse_string(packet.get_string_from_utf8())
			if message is Dictionary:
				dispatch(id, message)
			else:
				reject(id, "ThÃ´ng Ä‘iá»‡p khÃ´ng há»£p lá»‡.", false)
	if now - last_cleanup > 1000:
		last_cleanup = now
		cleanup(now)

func send(connection_id: int, kind: String, payload: Dictionary) -> void:
	if not connections.has(connection_id):
		return
	var peer: WebSocketPeer = connections[connection_id].peer
	if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		if peer.get_current_outbound_buffered_amount() > 900000:
			peer.close(1008, "slow connection")
			return
		peer.send_text(JSON.stringify({"type": kind, "version": RoomProtocol.VERSION, "payload": payload}))

func send_player(id: int, kind: String, payload: Dictionary) -> void:
	var session: Dictionary = session_for(id)
	if not session.is_empty():
		send(int(session.connection), kind, payload)

func broadcast(room: Dictionary, kind: String, payload: Dictionary) -> void:
	for id in room.members:
		send_player(id, kind, payload)

func player_online(id: int) -> bool:
	var session := session_for(id)
	return not session.is_empty() and connections.has(int(session.connection))

func session_for(id: int) -> Dictionary:
	return sessions.get(players_to_tokens.get(id, ""), {})

func reject(id: int, reason: String, fatal: bool = true) -> void:
	send(id, "JOIN_REJECTED" if fatal else "ERROR", {"message": reason, "fatal": fatal})

func valid_name(value: Variant) -> bool:
	if not value is String:
		return false
	var title: String = value.strip_edges()
	if title.is_empty() or title.length() > 24:
		return false
	for character in title:
		if character.unicode_at(0) < 32:
			return false
	return true

func dispatch(connection_id: int, message: Dictionary) -> void:
	if not message.get("type", null) is String or not message.get("payload", null) is Dictionary or message.get("version", 0) != RoomProtocol.VERSION:
		reject(connection_id, "PhiÃªn báº£n giao thá»©c khÃ´ng há»£p lá»‡.", false)
		return
	var kind: String = message.type
	var payload: Dictionary = message.payload
	var conn: Dictionary = connections[connection_id]
	if kind == "PONG":
		return
	if int(conn.player) == 0:
		if kind == "RESUME_SESSION":
			resume(connection_id, str(payload.get("session_token", "")))
		elif kind in ["CREATE_ROOM", "JOIN_ROOM"]:
			admit(connection_id, kind, payload)
		else:
			reject(connection_id, "Báº¡n chÆ°a tham gia phÃ²ng.", false)
		return
	var session := session_for(conn.player)
	if session.is_empty() or not rooms.has(session.room):
		reject(connection_id, "PhÃ²ng khÃ´ng cÃ²n tá»“n táº¡i.")
		return
	var room: Dictionary = rooms[session.room]
	room.activity = Time.get_ticks_msec()
	if kind == "LEAVE_ROOM":
		remove_session(str(players_to_tokens.get(conn.player, "")))
		conn.player = 0
		return
	var decoded := RoomProtocol.decode(kind, payload)
	if decoded.is_empty() or not NetworkManager.valid_arguments(decoded.action, decoded.args):
		reject(connection_id, "HÃ nh Ä‘á»™ng hoáº·c dá»¯ liá»‡u khÃ´ng há»£p lá»‡.", false)
		return
	# Keep duplicate suppression on the authenticated session, including reconnect.
	if not message.has("intent_id"):
		reject(connection_id, "Thiáº¿u mÃ£ hÃ nh Ä‘á»™ng.", false)
		return
	if message.has("intent_id"):
		var intent_id: Variant = message.intent_id
		if not intent_id is String or intent_id.is_empty() or intent_id.length() > 64:
			reject(connection_id, "MÃ£ hÃ nh Ä‘á»™ng khÃ´ng há»£p lá»‡.", false)
			return
		var seen: Dictionary = session.get("seen_intents", {})
		if seen.has(intent_id):
			return
		seen[intent_id] = true
		if seen.size() > 512:
			seen.erase(seen.keys()[0])
		session["seen_intents"] = seen
	# Identity comes exclusively from this socket's authenticated room session.
	room.game.handle_intent(int(conn.player), decoded.action, decoded.args)

func make_code() -> String:
	var code := ""
	var crypto := Crypto.new()
	while code.is_empty() or rooms.has(code):
		code = ""
		for value in crypto.generate_random_bytes(6):
			code += CODE_ALPHABET[int(value) % CODE_ALPHABET.length()]
	return code

func admit(connection_id: int, kind: String, payload: Dictionary) -> void:
	if not valid_name(payload.get("player_name", null)):
		reject(connection_id, "TÃªn ngÆ°á»i chÆ¡i khÃ´ng há»£p lá»‡ (1â€“24 kÃ½ tá»±).")
		return
	var room: Dictionary
	if kind == "CREATE_ROOM":
		if rooms.size() >= 100:
			reject(connection_id, "MÃ¡y chá»§ Ä‘ang Ä‘áº§y. HÃ£y thá»­ láº¡i sau.")
			return
		var code := make_code()
		room = {"room_code": code, "host_player_id": next_player, "members": [], "created_at": Time.get_unix_time_from_system(), "activity": Time.get_ticks_msec()}
		var bridge: Node = load("res://server/RoomBridge.gd").new()
		bridge.server = self
		bridge.room = room
		bridge.session_port = port
		add_child(bridge)
		var game: Node = load("res://autoload/GameManager.gd").new()
		game.network = bridge
		bridge.add_child(game)
		room["game"] = game
		room["bridge"] = bridge
		rooms[code] = room
	else:
		var code := str(payload.get("room_code", "")).strip_edges().to_upper()
		if not rooms.has(code):
			reject(connection_id, "Mã phòng không tồn tại.")
			return
		room = rooms[code]
		if room.game.started:
			reject(connection_id, "Trận đấu đã bắt đầu.")
			return
		if room.members.size() >= 7:
			reject(connection_id, "Phòng đã đầy.")
			return
	var id := next_player
	next_player += 1
	var token := Crypto.new().generate_random_bytes(32).hex_encode()
	sessions[token] = {"player": id, "room": room.room_code, "connection": connection_id, "expires": 0}
	players_to_tokens[id] = token
	connections[connection_id].player = id
	room.members.append(id)
	room.game.add_player(id, str(payload.player_name).strip_edges())
	send(connection_id, "ROOM_CREATED" if kind == "CREATE_ROOM" else "JOIN_ACCEPTED",
		{"player_id": id, "room_code": room.room_code, "host_player_id": room.host_player_id, "session_token": token})
	room.game.publish()

func resume(connection_id: int, token: String) -> void:
	if token.length() != 64 or not sessions.has(token):
		reject(connection_id, "PhiÃªn chÆ¡i Ä‘Ã£ háº¿t háº¡n. HÃ£y tham gia láº¡i.")
		return
	var session: Dictionary = sessions[token]
	if not rooms.has(session.room) or (session.expires > 0 and Time.get_ticks_msec() > int(session.expires)):
		reject(connection_id, "PhiÃªn chÆ¡i Ä‘Ã£ háº¿t háº¡n. HÃ£y tham gia láº¡i.")
		return
	var previous: int = session.connection
	if connections.has(previous) and previous != connection_id:
		connections[previous].player = 0
		connections[previous].peer.close(1000, "session replaced")
		connections.erase(previous)
	session.connection = connection_id
	session.expires = 0
	connections[connection_id].player = session.player
	var room: Dictionary = rooms[session.room]
	room.game.players[session.player].is_connected = true
	if not player_online(room.host_player_id):
		room.host_player_id = session.player
	send(connection_id, "SESSION_RESUMED", {"player_id": session.player, "room_code": session.room, "host_player_id": room.host_player_id, "session_token": token})
	room.game.publish()

func drop_connection(connection_id: int) -> void:
	if not connections.has(connection_id):
		return
	var conn: Dictionary = connections[connection_id]
	connections.erase(connection_id)
	var session := session_for(int(conn.player))
	if session.is_empty() or int(session.connection) != connection_id:
		return
	session.connection = 0
	session.expires = Time.get_ticks_msec() + GRACE_MS
	if not rooms.has(session.room):
		return
	var room: Dictionary = rooms[session.room]
	if not room.game.started:
		room.game.players[conn.player].is_connected = false
		room.game.players[conn.player].ready = false
	reassign_host(room)
	room.game.publish()

func reassign_host(room: Dictionary) -> void:
	if player_online(int(room.host_player_id)):
		return
	for id in room.members:
		if player_online(id):
			room.host_player_id = id
			return

func remove_session(token: String) -> void:
	if not sessions.has(token):
		return
	var session: Dictionary = sessions[token]
	sessions.erase(token)
	players_to_tokens.erase(session.player)
	if connections.has(int(session.connection)):
		connections[int(session.connection)].player = 0
	if not rooms.has(session.room):
		return
	var room: Dictionary = rooms[session.room]
	room.members.erase(session.player)
	room.game.disconnect_player(session.player)
	reassign_host(room)
	if room.members.is_empty():
		destroy_room(session.room)
	else:
		room.game.publish()

func destroy_room(code: String) -> void:
	if not rooms.has(code):
		return
	var room: Dictionary = rooms[code]
	rooms.erase(code)
	room.game.clear()
	room.bridge.room = {}
	room.bridge.queue_free()

func cleanup(now: int) -> void:
	for token in sessions.keys():
		if sessions[token].expires > 0 and now >= int(sessions[token].expires):
			remove_session(token)
	for code in rooms.keys():
		var room: Dictionary = rooms[code]
		if now - int(room.activity) > 7200000:
			for id in room.members.duplicate():
				send_player(id, "ERROR", {"message": "PhÃ²ng Ä‘Ã£ háº¿t thá»i gian hoáº¡t Ä‘á»™ng.", "fatal": true})
				remove_session(str(players_to_tokens.get(id, "")))
