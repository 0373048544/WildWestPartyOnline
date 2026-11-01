extends Node

var server: Node
var room: Dictionary
var session_port: int = 7000
var revision: int = 0
var audio_sequence: int = 0

func stamp_audio(event: Dictionary) -> Dictionary:
	audio_sequence += 1
	var result := event.duplicate(true)
	result["audio_event_id"] = "%s:%d" % [room.room_code, audio_sequence]
	return result

func is_authority() -> bool:
	return true

func host_player_id() -> int:
	return int(room.host_player_id)

func is_room_host(id: int) -> bool:
	return id == host_player_id()

func allow_two_players() -> bool:
	return OS.is_debug_build() and server.development

func send_notice(id: int, message: String) -> void:
	server.send_player(id, "ERROR", {"message": message})

func publish_game(game: Node) -> void:
	revision += 1
	var public: Dictionary = game.public_snapshot()
	public["room_code"] = room.room_code
	public["host_player_id"] = room.host_player_id
	public["revision"] = revision
	public["debug"] = OS.is_debug_build() and server.development
	for row in public.players:
		row["is_connected"] = server.player_online(int(row.player_id))
	for id in room.members:
		if not game.players.has(id) or not server.player_online(id):
			continue
		server.send_player(id, "STATE", {"public": public, "private": game.private_snapshot(id)})

func broadcast_animation(actor: int, kind: String, target: int = 0) -> void:
	server.broadcast(room, "TABLE_EVENT", stamp_audio({"kind": "animation", "actor": actor, "animation": kind, "target": target}))

func broadcast_table_event(event: Dictionary) -> void:
	server.broadcast(room, "TABLE_EVENT", stamp_audio(event))
