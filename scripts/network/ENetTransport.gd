class_name ENetTransport
extends RefCounted

# Desktop/debug high-level RPC compatibility. Browser builds never instantiate this.
static func server(port: int) -> ENetMultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	return peer if peer.create_server(port, 8) == OK else null

static func client(address: String, port: int) -> ENetMultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	return peer if peer.create_client(address, port) == OK else null
