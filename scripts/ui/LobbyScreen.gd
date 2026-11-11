extends VBoxContainer

const WesternStatusBadgeScript = preload("res://scripts/ui/WesternStatusBadge.gd")
const WesternPlayerCardScript = preload("res://scripts/ui/WesternPlayerCard.gd")

var _built := false
var _app: Node
var _layout_signature := ""
var _state_signature := ""

func configure(app: Node, state: Dictionary) -> void:
	_app = app
	var viewport_size := get_viewport_rect().size
	_sync_outer_margin(viewport_size)
	var next_layout := "%s:%s:%s" % [
		viewport_size.x < 600.0,
		viewport_size.y >= viewport_size.x,
		viewport_size.y < 520.0 and viewport_size.x > viewport_size.y
	]
	var next_state := JSON.stringify([
		state.get("room_code", ""), state.get("host_player_id", 1),
		state.get("minimum_players", 2), state.get("players", []),
		NetworkManager.connection_status
	])
	if not _built or next_layout != _layout_signature:
		# Responsive profile changes are rare and legitimately need a geometry
		# rebuild. Ordinary multiplayer snapshots take the keyed sync path below.
		_layout_signature = next_layout
		_built = true
		_state_signature = next_state
		for child in get_children():
			remove_child(child)
			child.queue_free()
		_build_lobby(app, state)
		return
	if next_state == _state_signature:
		return
	_state_signature = next_state
	_sync_lobby(state)

func _sync_outer_margin(viewport_size: Vector2) -> void:
	var ancestor: Node = get_parent()
	while is_instance_valid(ancestor) and not ancestor is MarginContainer:
		ancestor = ancestor.get_parent()
	if not ancestor is MarginContainer:
		return
	var margin := ancestor as MarginContainer
	var safe: Vector4 = load("res://scripts/ui/MatchLayout.gd").safe_insets(self)
	var inset := maxi(int(safe.x + 14), int((viewport_size.x - 940.0) / 2.0))
	margin.add_theme_constant_override("margin_left", inset)
	margin.add_theme_constant_override("margin_right", maxi(int(safe.z + 14), inset))
	margin.add_theme_constant_override("margin_top", maxi(int(safe.y + 10), 10 if viewport_size.y < 620.0 else 34))
	margin.add_theme_constant_override("margin_bottom", maxi(12, int(safe.w + 12)))

# Presentation only. Every gameplay-affecting button still submits the original
# intention to the authoritative room host.
func _build_lobby(app: Node, state: Dictionary) -> void:
	var viewport_size := get_viewport_rect().size
	var compact := viewport_size.y < 520.0 and viewport_size.x > viewport_size.y
	var portrait := viewport_size.y > viewport_size.x
	var phone := viewport_size.x < 600.0
	add_theme_constant_override("separation", 6 if (compact or phone) else 12)

	var header: Container = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	add_child(header)
	var heading: Label = app.label("PHÒNG CHỜ", 22 if (compact or phone) else 32, header)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_color_override("font_color", SaloonTheme.GOLD)
	var connection := WesternStatusBadgeScript.new()
	connection.name = "ConnectionBadge"
	var local_status := NetworkManager.connection_status
	connection.configure(
		"ĐANG KẾT NỐI LẠI" if local_status == NetworkManager.CONNECTION_RECONNECTING else "ĐÃ KẾT NỐI",
		"warning" if local_status == NetworkManager.CONNECTION_RECONNECTING else "success"
	)
	header.add_child(connection)

	var code: String = str(state.get("room_code", ""))
	var room_panel := PanelContainer.new()
	room_panel.name = "RoomCodePanel"
	room_panel.add_theme_stylebox_override("panel", SaloonTheme.parchment_panel(10 if compact else 16))
	add_child(room_panel)
	var room_row: Container = HBoxContainer.new()
	room_row.add_theme_constant_override("separation", 12)
	room_panel.add_child(room_row)
	var room_text := VBoxContainer.new()
	room_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room_text.add_theme_constant_override("separation", 0)
	room_row.add_child(room_text)
	var room_caption: Label = app.label("MÃ PHÒNG", 12 if compact else 14, room_text)
	room_caption.add_theme_color_override("font_color", Color("#6c4a2d"))
	var room_code: Label = app.label(code if not code.is_empty() else "PHÒNG DESKTOP", 24 if (compact or phone) else 34, room_text)
	room_code.name = "RoomCodeValue"
	room_code.add_theme_color_override("font_color", Color("#35241b"))
	if not code.is_empty():
		var copy: Button = app.button("CHÉP MÃ" if phone or compact else "SAO CHÉP", func(): _copy_room_code(app, code), room_row)
		copy.name = "CopyRoomCode"
		copy.set_variant("primary")
		if phone or compact:
			copy.custom_minimum_size = Vector2(94, 46)
		if not portrait and not compact:
			var invite: Button = app.button("✦  MỜI BẠN", func(): _copy_room_code(app, code), room_row)
			invite.set_variant("quiet")

	var host_name := ""
	for player in state.players:
		if int(player.player_id) == int(state.get("host_player_id", 1)):
			host_name = str(player.display_name)
			break
	var summary_text := "%d/7 CAO BỒI  •  CHỦ PHÒNG: %s" % [state.players.size(), host_name] if phone else "2–7 người  •  %d/7 trong phòng  •  Chủ phòng: %s" % [state.players.size(), host_name]
	var summary: Label = app.label(summary_text, 13 if (compact or phone) else 16)
	summary.name = "LobbySummary"
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_color_override("font_color", Color("#d8c7a6"))

	var list_title: Label = app.section_header("DANH SÁCH CAO BỒI", self, "♠")
	list_title.add_theme_font_size_override("font_size", 15 if compact else 18)
	var list := GridContainer.new()
	list.name = "PlayerList"
	list.columns = 2 if compact or not phone else 1
	list.add_theme_constant_override("h_separation", 8)
	list.add_theme_constant_override("v_separation", 7)
	# The lobby itself is already inside App's vertical ScrollContainer. Keeping
	# the keyed roster as its direct child preserves stable node paths and lets a
	# seven-player list scroll without introducing nested touch scroll areas.
	add_child(list)
	var own_ready := false
	var connected_count := 0
	var ready_count := 0
	for player in state.players:
		var card: PanelContainer = WesternPlayerCardScript.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_child(card)
		card.configure(player, int(state.get("host_player_id", 1)), app.local_id(), compact or phone)
		if int(player.player_id) == app.local_id():
			own_ready = bool(player.ready)
		if bool(player.get("is_connected", true)):
			connected_count += 1
			ready_count += int(bool(player.ready))
	for _slot in range(maxi(0, int(state.minimum_players) - state.players.size())):
		var empty := PanelContainer.new()
		empty.name = "EmptySlot"
		empty.add_theme_stylebox_override("panel", SaloonTheme.inset_panel(10))
		empty.custom_minimum_size.y = 44 if compact else 54
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_child(empty)
		var waiting: Label = app.label("◇  Đang chờ một cao bồi…", 14, empty)
		waiting.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		waiting.add_theme_color_override("font_color", Color("#968d80"))

	var note := PanelContainer.new()
	note.name = "LobbyNote"
	note.add_theme_stylebox_override("panel", SaloonTheme.inset_panel(9))
	add_child(note)
	var waiting_reason := "Mọi người đã sẵn sàng."
	if connected_count < 2:
		waiting_reason = "Cần ít nhất 2 người chơi."
	elif connected_count < state.players.size():
		waiting_reason = "Đang chờ người chơi mất kết nối quay lại."
	elif ready_count < connected_count:
		waiting_reason = "Đang chờ người chơi sẵn sàng (%d/%d)." % [ready_count, connected_count]
	var note_label: Label = app.label(waiting_reason, 13 if compact else 15, note)
	note_label.name = "LobbyNoteText"
	note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.visible = not compact and not phone

	# A three-button row is too wide for a 390 px phone and can push the leave
	# action completely beyond the right edge. Stack the same controls in
	# portrait; landscape/desktop keep the compact horizontal action bar.
	var actions: Container = VBoxContainer.new() if portrait else HBoxContainer.new()
	actions.name = "LobbyActions"
	actions.add_theme_constant_override("separation", 6 if phone else 8)
	add_child(actions)
	var primary_actions: Container = HBoxContainer.new() if portrait else actions
	if portrait:
		primary_actions.add_theme_constant_override("separation", 6)
		actions.add_child(primary_actions)
	var ready_text := "HỦY SẴN SÀNG" if own_ready else "SẴN SÀNG"
	var ready: Button = app.button(ready_text, func(): app.intent("ready"), primary_actions)
	ready.name = "ReadyButton"
	ready.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ready.set_variant("secondary" if own_ready else "primary")
	var can_start: bool = state.players.size() >= 2 and state.players.size() <= 7 and state.players.all(func(p): return p.ready and p.is_connected)
	if app.local_id() == int(state.get("host_player_id", 1)):
		var start: Button = app.button("BẮT ĐẦU" if phone else "BẮT ĐẦU GAME", func(): app.intent("start"), primary_actions, not can_start)
		start.name = "StartButton"
		start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		start.set_variant("primary")
	else:
		var waiting_host := WesternStatusBadgeScript.new()
		waiting_host.configure("CHỜ CHỦ PHÒNG", "warning")
		waiting_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		primary_actions.add_child(waiting_host)
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

func _sync_lobby(state: Dictionary) -> void:
	var list := get_node_or_null("PlayerList") as GridContainer
	if not is_instance_valid(list):
		return
	var host_id := int(state.get("host_player_id", 1))
	var host_name := ""
	var own_ready := false
	var connected_count := 0
	var ready_count := 0
	var present: Dictionary = {}
	for raw in state.get("players", []):
		var player: Dictionary = raw
		var id := int(player.get("player_id", 0))
		present[id] = true
		if id == host_id:
			host_name = str(player.get("display_name", ""))
		if id == _app.local_id():
			own_ready = bool(player.get("ready", false))
		if bool(player.get("is_connected", true)):
			connected_count += 1
			ready_count += int(bool(player.get("ready", false)))
		var card := list.get_node_or_null("Player%d" % id) as PanelContainer
		if not is_instance_valid(card):
			card = WesternPlayerCardScript.new()
			list.add_child(card)
		card.configure(player, host_id, _app.local_id(), get_viewport_rect().size.x < 600.0)
	for child in list.get_children():
		if child is WesternPlayerCard:
			var id := int(String(child.name).trim_prefix("Player"))
			if not present.has(id):
				list.remove_child(child)
				child.queue_free()
	var ordered: Array = state.get("players", []).duplicate()
	ordered.sort_custom(func(a, b): return int(a.get("seat_index", 0)) < int(b.get("seat_index", 0)))
	for index in range(ordered.size()):
		var card := list.get_node_or_null("Player%d" % int(ordered[index].get("player_id", 0)))
		if is_instance_valid(card):
			list.move_child(card, index)
	_sync_empty_slots(list, maxi(0, int(state.get("minimum_players", 2)) - ordered.size()))
	var summary := get_node_or_null("LobbySummary") as Label
	if is_instance_valid(summary):
		summary.text = "%d/7 CAO BỒI · CHỦ PHÒNG: %s" % [ordered.size(), host_name]
	var room_code := find_child("RoomCodeValue", true, false) as Label
	var code := str(state.get("room_code", ""))
	if is_instance_valid(room_code):
		room_code.text = code if not code.is_empty() else "PHÒNG CỤC BỘ"
	var copy := find_child("CopyRoomCode", true, false) as Button
	if is_instance_valid(copy):
		copy.visible = not code.is_empty()
	var connection := find_child("ConnectionBadge", true, false) as PanelContainer
	if is_instance_valid(connection):
		var reconnecting := NetworkManager.connection_status == NetworkManager.CONNECTION_RECONNECTING
		connection.configure("ĐANG KẾT NỐI LẠI" if reconnecting else "ĐÃ KẾT NỐI", "warning" if reconnecting else "success")
	var ready := find_child("ReadyButton", true, false) as Button
	if is_instance_valid(ready):
		ready.text = "HỦY SẴN SÀNG" if own_ready else "SẴN SÀNG"
		ready.set_variant("secondary" if own_ready else "primary")
	var can_start := ordered.size() >= 2 and ordered.size() <= 7 and ordered.all(func(p): return bool(p.get("ready", false)) and bool(p.get("is_connected", true)))
	var start := find_child("StartButton", true, false) as Button
	if is_instance_valid(start):
		start.disabled = not can_start
	var note_text := get_node_or_null("LobbyNote/LobbyNoteText") as Label
	if is_instance_valid(note_text):
		if connected_count < 2:
			note_text.text = "Cần ít nhất 2 người chơi."
		elif connected_count < ordered.size():
			note_text.text = "Đang chờ người chơi kết nối lại."
		elif ready_count < connected_count:
			note_text.text = "Đang chờ sẵn sàng (%d/%d)." % [ready_count, connected_count]
		else:
			note_text.text = "Mọi người đã sẵn sàng."

func _sync_empty_slots(list: GridContainer, count: int) -> void:
	var slots: Array[Node] = []
	for child in list.get_children():
		if child.name == "EmptySlot":
			slots.append(child)
	while slots.size() < count:
		var empty := PanelContainer.new()
		empty.name = "EmptySlot"
		empty.add_theme_stylebox_override("panel", SaloonTheme.inset_panel(10))
		empty.custom_minimum_size.y = 48
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var waiting: Label = _app.label("Đang chờ cao bồi…", 13, empty)
		waiting.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		waiting.add_theme_color_override("font_color", Color("#968d80"))
		list.add_child(empty)
		slots.append(empty)
	while slots.size() > count:
		var old: Node = slots.pop_back()
		list.remove_child(old)
		old.queue_free()
	for slot in slots:
		list.move_child(slot, list.get_child_count() - 1)

func _copy_room_code(app: Node, code: String) -> void:
	DisplayServer.clipboard_set(code)
	if DisplayServer.clipboard_get() == code:
		app.show_outgame_toast("ĐÃ SAO CHÉP MÃ PHÒNG", "success")
	else:
		app.show_outgame_toast("KHÔNG THỂ SAO CHÉP MÃ PHÒNG", "danger")
