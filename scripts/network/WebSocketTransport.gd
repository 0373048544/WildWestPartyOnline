class_name WebSocketTransport
extends NetworkTransport

var peer: WebSocketPeer
var previous_state: int = WebSocketPeer.STATE_CLOSED
var began_at: int = 0

func connect_to_server(url: String) -> Error:
	disconnect_from_server()
	peer = WebSocketPeer.new()
	peer.inbound_buffer_size = 1048576
	peer.outbound_buffer_size = 1048576
	peer.max_queued_packets = 256
	var result := peer.connect_to_url(url)
	if result != OK:
		failed.emit("Không thể kết nối máy chủ.")
		return result
	previous_state = WebSocketPeer.STATE_CONNECTING
	began_at = Time.get_ticks_msec()
	return OK

func disconnect_from_server() -> void:
	if peer:
		peer.close(1000, "leave")
	peer = null
	previous_state = WebSocketPeer.STATE_CLOSED

func send_message(message: Dictionary) -> Error:
	return peer.send_text(JSON.stringify(message)) if is_transport_connected() else ERR_UNCONFIGURED

func is_transport_connected() -> bool:
	return peer != null and peer.get_ready_state() == WebSocketPeer.STATE_OPEN

func poll() -> void:
	if peer == null:
		return
	peer.poll()
	var current := peer.get_ready_state()
	if current == WebSocketPeer.STATE_OPEN:
		if previous_state != current:
			previous_state = current
			connected.emit()
		var budget := 64
		while peer != null and peer.get_available_packet_count() > 0 and budget > 0:
			budget -= 1
			var packet := peer.get_packet()
			if packet.size() > 1048576:
				continue
			var value: Variant = JSON.parse_string(packet.get_string_from_utf8())
			if value is Dictionary:
				message_received.emit(RoomProtocol.normalize_numbers(value))
	elif current == WebSocketPeer.STATE_CLOSED and previous_state != current:
		previous_state = current
		disconnected.emit()
	elif current == WebSocketPeer.STATE_CONNECTING and Time.get_ticks_msec() - began_at > 10000:
		disconnect_from_server()
		failed.emit("Kết nối thất bại. Không nhận được phản hồi từ máy chủ.")

