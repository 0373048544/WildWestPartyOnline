extends VBoxContainer

const WesternStatusBadgeScript = preload("res://scripts/ui/WesternStatusBadge.gd")
const WesternPlayerCardScript = preload("res://scripts/ui/WesternPlayerCard.gd")

# Presentation only. Every gameplay-affecting button still submits the original
# intention to the authoritative room host.
func configure(app: Node, state: Dictionary) -> void:
	var viewport_size := get_viewport_rect().size
	var compact := viewport_size.y < 520.0 and viewport_size.x > viewport_size.y
	var portrait := viewport_size.y > viewport_size.x
	add_theme_constant_override("separation", 8 if compact else 12)

	var header: Container = VBoxContainer.new() if portrait else HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	add_child(header)
	var heading: Label = app.label("★  PHÒNG CHỜ", 23 if compact else 32, header)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_color_override("font_color", SaloonTheme.GOLD)
	var connection := WesternStatusBadgeScript.new()
	connection.configure("● ĐÃ KẾT NỐI", "success")
	header.add_child(connection)

	var code: String = str(state.get("room_code", ""))
	var room_panel := PanelContainer.new()
	room_panel.name = "RoomCodePanel"
	room_panel.add_theme_stylebox_override("panel", SaloonTheme.parchment_panel(10 if compact else 16))
	add_child(room_panel)
	var room_row: Container = VBoxContainer.new() if portrait else HBoxContainer.new()
	room_row.add_theme_constant_override("separation", 12)
	room_panel.add_child(room_row)
	var room_text := VBoxContainer.new()
	room_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room_text.add_theme_constant_override("separation", 0)
	room_row.add_child(room_text)
	var room_caption: Label = app.label("MÃ PHÒNG", 12 if compact else 14, room_text)
	room_caption.add_theme_color_override("font_color", Color("#6c4a2d"))
	var room_code: Label = app.label(code if not code.is_empty() else "PHÒNG DESKTOP", 25 if compact else 34, room_text)
	room_code.name = "RoomCodeValue"
	room_code.add_theme_color_override("font_color", Color("#35241b"))
	if not code.is_empty():
		var copy: Button = app.button("⧉  SAO CHÉP", func():
			DisplayServer.clipboard_set(code)
			app.show_outgame_toast("Đã sao chép mã phòng " + code, "success"), room_row)
		copy.name = "CopyRoomCode"
		copy.set_variant("primary")
		if not portrait:
			var invite: Button = app.button("✦  MỜI BẠN", func():
				DisplayServer.clipboard_set(code)
				app.show_outgame_toast("Đã sao chép mã để gửi bạn bè", "success"), room_row)
			invite.set_variant("quiet")

	var host_name := ""
	for player in state.players:
		if int(player.player_id) == int(state.get("host_player_id", 1)):
			host_name = str(player.display_name)
			break
	var summary: Label = app.label("2–7 người  •  %d/7 trong phòng  •  Chủ phòng: %s" % [state.players.size(), host_name], 14 if compact else 16)
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_color_override("font_color", Color("#d8c7a6"))

	var list_title: Label = app.section_header("DANH SÁCH CAO BỒI", self, "♠")
	list_title.add_theme_font_size_override("font_size", 15 if compact else 18)
	var list := GridContainer.new()
	list.name = "PlayerList"
	list.columns = 2 if (compact or viewport_size.x >= 760.0) else 1
	list.add_theme_constant_override("h_separation", 8)
	list.add_theme_constant_override("v_separation", 7)
	add_child(list)
	var own_ready := false
	for player in state.players:
		var card: PanelContainer = WesternPlayerCardScript.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_child(card)
		card.configure(player, int(state.get("host_player_id", 1)), app.local_id(), compact or portrait)
		if int(player.player_id) == app.local_id():
			own_ready = bool(player.ready)
	for _slot in range(maxi(0, int(state.minimum_players) - state.players.size())):
		var empty := PanelContainer.new()
		empty.add_theme_stylebox_override("panel", SaloonTheme.inset_panel(10))
		empty.custom_minimum_size.y = 44 if compact else 54
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_child(empty)
		var waiting: Label = app.label("◇  Đang chờ một cao bồi…", 14, empty)
		waiting.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		waiting.add_theme_color_override("font_color", Color("#968d80"))

	var note := PanelContainer.new()
	note.add_theme_stylebox_override("panel", SaloonTheme.inset_panel(9))
	add_child(note)
	var note_label: Label = app.label("Mọi người nhấn SẴN SÀNG. Chủ phòng sẽ bắt đầu khi đủ người.", 13 if compact else 15, note)
	note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.visible = not compact

	# A three-button row is too wide for a 390 px phone and can push the leave
	# action completely beyond the right edge. Stack the same controls in
	# portrait; landscape/desktop keep the compact horizontal action bar.
	var actions: Container = VBoxContainer.new() if portrait else HBoxContainer.new()
	actions.name = "LobbyActions"
	actions.add_theme_constant_override("separation", 8)
	add_child(actions)
	var ready: Button = app.button("HỦY SẴN SÀNG" if own_ready else "✓  SẴN SÀNG", func(): app.intent("ready"), actions)
	ready.name = "ReadyButton"
	ready.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ready.set_variant("secondary" if own_ready else "primary")
	var can_start: bool = state.players.size() >= 2 and state.players.size() <= 7 and state.players.all(func(p): return p.ready and p.is_connected)
	if app.local_id() == int(state.get("host_player_id", 1)):
		var start: Button = app.button("★  BẮT ĐẦU GAME", func(): app.intent("start"), actions, not can_start)
		start.name = "StartButton"
		start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		start.set_variant("primary")
		if can_start and VisualSettings.decorative_motion():
			var pulse := start.create_tween().set_loops()
			pulse.tween_property(start, "modulate", Color("#fff0c5"), 0.75).set_trans(Tween.TRANS_SINE)
			pulse.tween_property(start, "modulate", Color.WHITE, 0.75).set_trans(Tween.TRANS_SINE)
	else:
		var waiting_host := WesternStatusBadgeScript.new()
		waiting_host.configure("CHỜ CHỦ PHÒNG", "warning")
		waiting_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(waiting_host)
	var leave: Button = app.button("RỜI PHÒNG", app.leave, actions)
	leave.name = "LeaveLobbyButton"
	leave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leave.set_variant("danger")
	if compact or portrait:
		# Primary room controls stay above the scrollable player roster and browser
		# toolbar area; the full roster can continue below without hiding Start.
		move_child(actions, 3)

	if OS.is_debug_build() and bool(state.debug) and NetworkManager.mode != "websocket" and app.local_id() == int(state.get("host_player_id", 1)):
		var debug_button: Button = app.button("DEBUG • BẮT ĐẦU ÉP BUỘC", func(): app.intent("debug", {"operation": "Force Start"}), self, state.players.size() < int(state.minimum_players))
		debug_button.set_variant("quiet")
