class_name ChatRoomState
extends RefCounted

const MAX_LENGTH := 160
const HISTORY_LIMIT := 30
const RATE_COUNT := 4
const RATE_WINDOW_MS := 5000

var room_code: String
var sequence: int = 0
var history: Array[Dictionary] = []
var rate_windows: Dictionary = {}

func _init(code: String = "ROOM") -> void:
	room_code = code

static func sanitize_text(value: Variant) -> String:
	if not value is String:
		return ""
	var cleaned := ""
	for character in str(value):
		var code := character.unicode_at(0)
		cleaned += " " if code < 32 or code == 127 else character
	cleaned = " ".join(cleaned.strip_edges().split(" ", false))
	return cleaned.substr(0, MAX_LENGTH).strip_edges()

func accept(player_id: int, player_name: String, dead: bool, payload: Dictionary, now_ms: int, timestamp: int) -> Dictionary:
	var text := sanitize_text(payload.get("text", null))
	if text.is_empty():
		return {"ok": false, "reason": "Tin nhắn không được để trống."}
	var recent: Array = rate_windows.get(player_id, [])
	recent = recent.filter(func(value): return now_ms - int(value) < RATE_WINDOW_MS)
	if recent.size() >= RATE_COUNT:
		rate_windows[player_id] = recent
		return {"ok": false, "reason": "Bạn gửi tin quá nhanh."}
	recent.append(now_ms)
	rate_windows[player_id] = recent
	sequence += 1
	var message: Dictionary = {
		"message_id": "%s:%d" % [room_code, sequence],
		"sender_id": player_id,
		"sender_name": player_name,
		"text": text,
		"timestamp": timestamp,
		"dead": dead,
	}
	history.append(message)
	while history.size() > HISTORY_LIMIT:
		history.pop_front()
	return {"ok": true, "message": message}

func recent_history() -> Array:
	return history.duplicate(true)

func forget_player(player_id: int) -> void:
	rate_windows.erase(player_id)
