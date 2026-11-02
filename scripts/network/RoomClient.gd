extends Node

var manager: Node
var transport: WebSocketTransport
var player_id: int = 0
var room_code: String = ""
var host_id: int = 0
var session_token: String = ""
var pending: Dictionary = {}
var reconnecting: bool = false
var retry_at: int = 0
var retries: int = 0
var response_deadline: int = 0
var leaving: bool = false
var local_start_attempted: bool = false

func restore() -> void:
	if not OS.has_feature("web"):
		return
	var saved: Variant = JSON.parse_string(str(JavaScriptBridge.eval("sessionStorage.getItem('wwpo_session') || '{}'")))
	if saved is Dictionary and not str(saved.get("token", "")).is_empty():
		session_token = saved.token
		room_code = str(saved.get("room", ""))
		manager.mode = "websocket"
		reconnecting = true
		connect_socket()

func request_room(kind: String, title: String, code: String = "") -> void:
	manager.leave()
	manager.mode = "websocket"
	manager.local_name = title.strip_edges()
	pending = {"type": kind, "payload": {"player_name": title.strip_edges(), "room_code": code.strip_edges().to_upper()}, "version": RoomProtocol.VERSION}
	connect_socket()

func connect_socket() -> void:
	if transport:
		transport.disconnect_from_server()
	transport = WebSocketTransport.new()
	transport.connected.connect(socket_open)
	transport.disconnected.connect(socket_lost)
	transport.failed.connect(func(_message): socket_lost())
	transport.message_received.connect(receive)
	manager.connecting = true
	response_deadline = Time.get_ticks_msec() + 12000
	transport.connect_to_server(NetworkConfig.server_url())
	manager.updated.emit()

func socket_open() -> void:
	retry_at = 0
	if not session_token.is_empty():
		transport.send_message({"type": "RESUME_SESSION", "version": RoomProtocol.VERSION, "payload": {"session_token": session_token}})
	else:
		transport.send_message(pending)

func socket_lost() -> void:
	if leaving or manager.mode != "websocket":
		return
	if retry_at > 0:
		return
	if session_token.is_empty() and pending.get("type", "") == "CREATE_ROOM" and not local_start_attempted:
		local_start_attempted = true
		if manager.start_local_room_server():
			# Retry after the old transport callback has finished polling.
			response_deadline = 0
			retry_at = Time.get_ticks_msec() + 1
			return
	if not session_token.is_empty() and retries < 8:
		reconnecting = true
		manager.connecting = true
		retries += 1
		retry_at = Time.get_ticks_msec() + mini(5000, retries * 500)
		response_deadline = 0
	else:
		manager.leave()
		manager.error_received.emit("Không kết nối được máy chủ tại %s. Hãy kiểm tra máy chủ và cổng kết nối." % NetworkConfig.server_url())
	manager.updated.emit()

func _process(_delta: float) -> void:
	if manager.mode != "websocket":
		return
	if transport:
		transport.poll()
	if retry_at > 0 and Time.get_ticks_msec() >= retry_at:
		retry_at = 0
		connect_socket()
	elif response_deadline > 0 and Time.get_ticks_msec() >= response_deadline:
		response_deadline = 0
		socket_lost()

func send_intent(action: String, args: Dictionary) -> void:
	if transport == null or not transport.is_transport_connected() or reconnecting:
		return
	var message := RoomProtocol.encode(action, args)
	if not message.is_empty():
		message["intent_id"] = Crypto.new().generate_random_bytes(16).hex_encode()
		transport.send_message(message)

func send_chat(text: String) -> void:
	if transport == null or not transport.is_transport_connected() or reconnecting:
		return
	transport.send_message(RoomProtocol.encode_chat(text))

func leave() -> void:
	leaving = true
	if transport:
		if transport.is_transport_connected() and not session_token.is_empty():
			transport.send_message({"type": "LEAVE_ROOM", "version": RoomProtocol.VERSION, "payload": {}})
		transport.disconnect_from_server()
	transport = null
	session_token = ""
	player_id = 0
	host_id = 0
	room_code = ""
	reconnecting = false
	retry_at = 0
	retries = 0
	response_deadline = 0
	pending = {}
	local_start_attempted = false
	if OS.has_feature("web"):
		JavaScriptBridge.eval("sessionStorage.removeItem('wwpo_session')")
	leaving = false

func receive(message: Dictionary) -> void:
	if not message.get("payload", {}) is Dictionary:
		return
	var payload: Dictionary = message.get("payload", {})
	match str(message.get("type", "")):
		"ROOM_CREATED", "JOIN_ACCEPTED", "SESSION_RESUMED":
			player_id = int(payload.player_id)
			room_code = str(payload.room_code)
			host_id = int(payload.host_player_id)
			session_token = str(payload.session_token)
			manager.connecting = false
			reconnecting = false
			retries = 0
			response_deadline = 0
			manager.begin_chat_room(room_code)
			if OS.has_feature("web"):
				var saved := JSON.stringify({"token": session_token, "room": room_code})
				JavaScriptBridge.eval("sessionStorage.setItem('wwpo_session', " + JSON.stringify(saved) + ")")
		"STATE":
			# Public/private snapshots from the same revision commit atomically.
			manager.private_state = RoomProtocol.normalize_private(payload.private)
			host_id = int(payload.public.get("host_player_id", host_id))
			manager.public_state = payload.public
		"VISUAL_EVENT":
			manager.visual_event.emit(int(payload.actor), str(payload.kind), int(payload.get("target", 0)))
		"TABLE_EVENT":
			manager.table_event.emit(payload)
		"CHAT_MESSAGE":
			manager.receive_chat_message(payload)
		"CHAT_HISTORY":
			manager.receive_chat_history(payload.get("messages", []))
		"CHAT_REJECTED":
			manager.chat_error.emit(str(payload.get("message", "Không gửi được tin nhắn.")))
		"ERROR", "JOIN_REJECTED":
			var reason := str(payload.get("message", "Yêu cầu không hợp lệ."))
			if bool(payload.get("fatal", false)):
				manager.leave()
			manager.error_received.emit(reason)
		"PING":
			transport.send_message({"type": "PONG", "version": RoomProtocol.VERSION, "payload": {}})
	if str(message.get("type", "")) in ["ROOM_CREATED", "JOIN_ACCEPTED", "SESSION_RESUMED", "STATE"]:
		manager.updated.emit()

