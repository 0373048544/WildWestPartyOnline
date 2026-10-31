extends Node

var received: String = ""

func _ready() -> void:
	NetworkManager.error_received.connect(func(message): received = message)
	NetworkManager.join_game("Test", "not-an-ip", 7000)
	if not received.begins_with("Invalid IP"):
		fail("Invalid IP was not rejected")
		return
	NetworkManager.join_game("Test", "127.0.0.1", 0)
	if not received.begins_with("Invalid port"):
		fail("Invalid port was not rejected")
		return
	received = ""
	# The lobby suite uses 7000; this unhosted local port tests failure/timeout.
	NetworkManager.join_game("Test", "127.0.0.1", 17071)
	var deadline := Time.get_ticks_msec() + 15000
	while received.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not received.begins_with("Connection failed"):
		fail("Unreachable host did not produce Connection failed")
		return
	if NetworkManager.connecting or not NetworkManager.public_state.is_empty():
		fail("Connection failure did not clean up the session")
		return
	print("PASS: invalid IP, invalid port, real ENet connection failure/timeout and session cleanup")
	get_tree().quit()

func fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
