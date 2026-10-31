extends VBoxContainer

# Presentation only. Every button submits an intention to the authoritative host.
func configure(app: Node, state: Dictionary) -> void:
	app.label("THE SALOON • LOBBY", 36, self)
	var code: String = str(state.get("room_code", ""))
	app.label("MÃ PHÒNG: " + code if not code.is_empty() else "PHÒNG KIỂM THỬ DESKTOP", 24, self)
	if not code.is_empty():
		app.button("SAO CHÉP MÃ", func(): DisplayServer.clipboard_set(code), self)
	var minimum: int = state.minimum_players
	app.label("Cần 4–7 người và tất cả sẵn sàng." + (" Kiểm thử: cho phép đúng 2 người." if state.debug else ""), 18, self)
	app.label("Người chơi: %d / 7" % state.players.size(), 21, self)
	var list := VBoxContainer.new()
	list.name = "PlayerList"
	add_child(list)
	var own_ready := false
	for player in state.players:
		var row: Label = app.label("%s  %s  •  %s" % [
			player.display_name, TextCatalog.text("[HOST]") if player.player_id == state.get("host_player_id", 1) else "",
			"ĐANG KẾT NỐI LẠI" if not player.is_connected else TextCatalog.text("READY" if player.ready else "NOT READY")], 24, list)
		row.name = "Player%d" % player.player_id
		row.add_theme_font_size_override("font_size", 20)
		row.add_theme_color_override("font_color", Color("#a5d8b0") if player.ready else SaloonTheme.CREAM)
		row.add_theme_stylebox_override("normal", SaloonTheme.panel(Color("#263b43"), SaloonTheme.SEATS[int(player.seat_index) % SaloonTheme.SEATS.size()]))
		row.custom_minimum_size.y = 38 if state.players.size() > 4 else 54
		if player.player_id == app.local_id():
			own_ready = player.ready
	for _slot in range(maxi(0, int(state.minimum_players) - state.players.size())):
		var empty: Label = app.label("Waiting for a cowboy…", 18, list)
		empty.custom_minimum_size.y = 44
		empty.add_theme_color_override("font_color", Color("#9aa6aa"))
	var ready: Button = app.button("NOT READY • Click to ready" if not own_ready else "READY • Click to unready",
		func(): app.intent("ready"), self)
	ready.name = "ReadyButton"
	if app.local_id() == state.get("host_player_id", 1):
		var can_start: bool = (state.players.size() >= 4 or (state.debug and state.players.size() == 2)) and state.players.all(func(p): return p.ready and p.is_connected)
		var start: Button = app.button("START GAME", func(): app.intent("start"), self, not can_start)
		start.name = "StartButton"
		if not can_start:
			app.label("Waiting for enough players and everyone to be ready.", 17, self)
		if OS.is_debug_build() and state.debug and NetworkManager.mode != "websocket":
			app.button("DEBUG • Force Start (2+ players)", func(): app.intent("debug", {"operation": "Force Start"}), self,
				state.players.size() < minimum)
	else:
		app.label("Waiting for host...", 17, self)
	app.button("LEAVE LOBBY", app.leave, self)
