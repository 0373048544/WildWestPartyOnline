extends Node

var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("CHAT TEST FAILED: " + message)

func _ready() -> void:
	policy_tests()
	await ui_tests()
	if failures.is_empty():
		print("PASS: %d authoritative chat, privacy, spam, history and responsive mobile checks" % checks)
		get_tree().quit()
	else:
		print("FAIL: %d/%d chat checks failed" % [failures.size(), checks])
		get_tree().quit(1)

func policy_tests() -> void:
	var room_a := ChatRoomState.new("ROOMA")
	var room_b := ChatRoomState.new("ROOMB")
	var forged := room_a.accept(11, "Alice", false, {
		"text": "  xin chào 😂  ", "sender_id": 22, "sender_name": "Bob", "role": "SHERIFF"
	}, 1000, 123)
	check(forged.ok, "valid Vietnamese/emoji message accepted")
	check(forged.message.sender_id == 11 and forged.message.sender_name == "Alice", "server identity overrides forged sender fields")
	check(forged.message.text == "xin chào 😂" and not forged.message.has("role"), "text trimmed and forged role omitted")
	check(forged.message.timestamp == 123 and forged.message.message_id == "ROOMA:1", "server owns timestamp and message ID")
	var markup := room_a.accept(12, "Bob", false, {"text":"<script>alert(1)</script> [bbcode]"}, 1000, 124)
	check(markup.ok and markup.message.text.contains("<script>"), "markup remains inert plain text instead of being interpreted")
	var long_text := "x".repeat(240)
	var long_result := room_a.accept(13, "Long Name Cowboy", true, {"text":long_text}, 1000, 125)
	check(long_result.ok and long_result.message.text.length() == 160 and long_result.message.dead, "long text capped at 160 and dead marker is public status only")
	check(not room_a.accept(14, "Empty", false, {"text":" \n\r\t "}, 1000, 126).ok, "blank/control-only message rejected")
	for index in range(4):
		check(room_a.accept(20, "Spammer", false, {"text":"m%d" % index}, 2000 + index, 130 + index).ok, "first four messages in rate window accepted")
	check(not room_a.accept(20, "Spammer", false, {"text":"blocked"}, 2005, 140).ok, "fifth message inside five seconds rejected")
	check(room_a.accept(20, "Spammer", false, {"text":"later"}, 8001, 141).ok, "rate window recovers")
	room_b.accept(30, "Other", false, {"text":"private room"}, 1000, 200)
	check(room_b.history.size() == 1 and room_a.history.all(func(m): return not str(m.message_id).begins_with("ROOMB")), "room histories are isolated")
	for index in range(40):
		room_b.accept(100 + index, "P%d" % index, false, {"text":"history %d" % index}, 1000, 300 + index)
	check(room_b.history.size() == 30 and room_b.history[0].text == "history 10", "room history retains only newest 30 messages")

func ui_tests() -> void:
	var chat: ChatPanel = load("res://scenes/ui/ChatPanel.tscn").instantiate()
	add_child(chat)
	chat.setup(self)
	var state := {"started":true, "room_code":"UITEST", "phase":"ACTION_PHASE"}
	var layouts := [
		{"name":"portrait", "size":Vector2i(390,844)},
		{"name":"small-portrait", "size":Vector2i(360,740)},
		{"name":"landscape", "size":Vector2i(844,390)},
		{"name":"small-landscape", "size":Vector2i(740,360)},
		{"name":"desktop", "size":Vector2i(1440,900)},
	]
	for spec in layouts:
		get_window().size = spec.size
		get_window().content_scale_size = spec.size
		get_viewport().set_meta("match_css_size", Vector2(spec.size))
		get_viewport().set_meta("match_safe_insets", Vector4(8, 18, 8, 22))
		chat.sync_state(state, {}, false)
		await get_tree().process_frame
		var layout: Script = load("res://scripts/ui/MatchLayout.gd")
		var safe: Rect2 = layout.safe_rect(chat)
		check(chat.toggle_button.visible and safe.encloses(chat.toggle_button.get_global_rect()), spec.name + ": collapsed button inside safe viewport")
		check(chat.toggle_button.size.x >= 44 and chat.toggle_button.size.y >= 44, spec.name + ": collapsed button has >=44px touch target")
		chat.open_chat()
		await get_tree().process_frame
		var panel_rect := chat.panel.get_global_rect()
		check(safe.encloses(panel_rect), spec.name + ": panel remains inside safe viewport")
		check(panel_rect.end.y <= layout.action_rect(chat).position.y + 1, "%s: panel stays above action and hand zones (panel=%.1f action=%.1f min=%s desired=%s)" % [spec.name, panel_rect.end.y, layout.action_rect(chat).position.y, chat.panel.get_combined_minimum_size(), layout.chat_panel_rect(chat)])
		check(panel_rect.size.x < safe.size.x * 0.96 and panel_rect.size.y < safe.size.y * 0.70, spec.name + ": panel is compact, never fullscreen")
		check(chat.input.custom_minimum_size.y >= 44 and chat.send_button.custom_minimum_size.y >= 44 and chat.close_button.custom_minimum_size.y >= 44, spec.name + ": input/send/close targets are touch-safe")
		chat.close_chat()
	for index in range(10):
		chat.append_message({"message_id":"ui:%d" % index, "sender_id":2, "sender_name":"Cao Bồi Không Bao Giờ Ngủ", "text":"Tin nhắn dài kiểm tra cuộn và wrap %d" % index, "timestamp":index}, true)
	check(chat.message_list.get_child_count() == 10, "messages append incrementally without rebuilding history")
	check(chat.message_list.get_child(0).autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "long name/message wraps without horizontal overflow")
	chat.open_chat()
	chat.sync_state(state, {"reaction":{"reaction_type":"dodge"}}, false)
	check(not chat.expanded and not chat.panel.visible and not chat.toggle_button.visible, "urgent BANG reaction auto-collapses and hides chat below ReactionBanner")
	chat.sync_state(state, {"reaction":{"reaction_type":"store"}}, true)
	check(not chat.expanded and not chat.toggle_button.visible, "Store/Bách Hóa true chooser keeps chat out of the way")
	chat.sync_state(state, {}, false)
	check(chat.toggle_button.visible and chat.message_list.get_child_count() == 10, "chat returns collapsed without losing history")
	chat.queue_free()
