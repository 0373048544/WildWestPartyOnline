extends Node

var checks := 0
var log_expanded := false


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("MULTIPLAYER EXPERIENCE V2 FAILED: " + message)
		get_tree().quit(1)
		assert(value, message)


func test_authoritative_history() -> void:
	GameManager.clear()
	GameManager.match_id = 77
	for index in range(155):
		GameManager.record("Hành động %d" % index)
	var history: Array = GameManager.public_snapshot().get("history", [])
	check(history.size() == 150, "server history is capped at 150 events")
	var ids: Dictionary = {}
	for event in history:
		ids[str(event.get("event_id", ""))] = true
		check(int(event.get("match_id", -1)) == 77, "history event belongs to the current match")
	check(ids.size() == history.size(), "server history IDs are unique")
	check(str(history.front().get("text", "")) == "Hành động 5", "history evicts only the oldest event")
	GameManager.record("Bách Hóa: An đã nhận một lá úp.")
	var public_text := str(GameManager.history_events.back().get("text", ""))
	check("uid" not in public_text.to_lower() and "card_data_id" not in public_text.to_lower(), "public history contains no private card identifier")


func test_history_panel_dedup_and_layout() -> void:
	var panel = load("res://scripts/ui/ActionHistoryPanel.gd").new()
	add_child(panel)
	panel.setup(self)
	var events := [
		{"event_id": "history:1:1", "match_id": 1, "text": "An đã dùng BẮN."},
		{"event_id": "history:1:2", "match_id": 1, "text": "Bình đã dùng NÉ."}
	]
	panel.sync(events, 1)
	panel.sync(events, 1)
	check(panel.cached_events.size() == 2 and panel.seen.size() == 2, "repeated snapshots do not duplicate history")
	check(panel.rows.get_child_count() == 0, "collapsed history renders no message rows")
	panel.set_expanded(true)
	await get_tree().process_frame
	check(panel.rows.get_child_count() == 2, "expanding renders each cached event once")
	panel.sync([events[1], {"event_id": "history:1:3", "match_id": 1, "text": "An kết thúc lượt hành động."}], 1)
	await get_tree().process_frame
	check(panel.cached_events.size() == 3 and panel.rows.get_child_count() == 3, "expanded history appends only the new event")
	for viewport_size in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(430, 932), Vector2i(844, 390), Vector2i(1366, 768), Vector2i(1920, 1080)]:
		get_window().size = viewport_size
		get_window().content_scale_size = viewport_size
		get_viewport().set_meta("match_css_size", Vector2(viewport_size))
		panel._apply_layout()
		await get_tree().process_frame
		var rect: Rect2 = panel.get_global_rect()
		check(rect.position.x >= 0.0 and rect.position.y >= 0.0, "history starts inside viewport at %s" % viewport_size)
		var visible_size: Vector2 = get_viewport().get_visible_rect().size
		check(rect.end.x <= visible_size.x + 1.0 and rect.end.y <= visible_size.y + 1.0, "history stays inside viewport at %s (rect=%s visible=%s)" % [viewport_size, rect, visible_size])
	panel.sync([{"event_id": "history:2:1", "match_id": 2, "text": "Ván mới."}], 2)
	await get_tree().process_frame
	check(panel.cached_events.size() == 1 and panel.seen.has("history:2:1"), "new match clears the previous match history")
	panel.queue_free()


func test_connection_status_and_banner() -> void:
	var original_mode: String = NetworkManager.mode
	NetworkManager.mode = "websocket"
	NetworkManager.public_state = {"room_code": "TEST"}
	NetworkManager.set_connection_status(NetworkManager.CONNECTION_RECONNECTING)
	check(not NetworkManager.can_submit_intents(), "gameplay intents are blocked while reconnecting")
	var banner = load("res://scripts/ui/ConnectionStatusBanner.gd").new()
	add_child(banner)
	banner.setup(self)
	await get_tree().process_frame
	check(banner.visible and "KẾT NỐI LẠI" in banner.message.text, "reconnecting banner is visible in Vietnamese")
	NetworkManager.set_connection_status(NetworkManager.CONNECTION_SESSION_EXPIRED)
	check(banner.visible and banner.action.visible, "expired session offers an explicit home action")
	NetworkManager.set_connection_status(NetworkManager.CONNECTION_CONNECTED)
	check(not banner.visible, "a terminal error does not pretend it recovered")
	NetworkManager.mode = "offline"
	NetworkManager.set_connection_status(NetworkManager.CONNECTION_IDLE)
	check(NetworkManager.can_submit_intents(), "offline test mode remains usable")
	NetworkManager.mode = original_mode
	banner.queue_free()


func _ready() -> void:
	await get_tree().process_frame
	test_authoritative_history()
	await test_history_panel_dedup_and_layout()
	test_connection_status_and_banner()
	print("PASS: %d connection-state, history dedup/privacy/cap and responsive panel checks" % checks)
	get_tree().quit()
