class_name NetworkTransport
extends RefCounted

signal connected
signal disconnected
signal message_received(message: Dictionary)
signal failed(message: String)

func connect_to_server(_url: String) -> Error:
	return ERR_UNAVAILABLE

func disconnect_from_server() -> void:
	pass

func send_message(_message: Dictionary) -> Error:
	return ERR_UNAVAILABLE

func is_transport_connected() -> bool:
	return false

func poll() -> void:
	pass

