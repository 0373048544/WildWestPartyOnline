extends Control

var app: Node
var state: Dictionary
var own: Dictionary
var request: Dictionary
var hand: Control
var preview: Control
var timer_label: Label
var deadline: float = 0

func initialize(owner_app: Node, snapshot: Dictionary, private: Dictionary) -> void:
	app = owner_app
	state = snapshot
	own = private
	request = own.get("reaction", {})
	if app.sid_mode:
		app.sid_cards = app.sid_cards.filter(func(uid): return own.get("hand", []).any(func(c): return c.instance_id == uid))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name = "MatchHUD"
	app.table.targeting.blocked = false
	var targets: Array = own.get("targets", {}).get(app.selected, [])
	if app.selected >= 0 and targets.is_empty():
		app.selected = -1
	app.table.update_state(state, app.local_id(), targets)
	app.table.objects.sync(state, app.local_id(), request)
	if app.selected >= 0:
		var selected_cards: Array = own.get("hand", []).filter(func(c): return c.instance_id == app.selected)
		var style: String = "GENERIC"
		if not selected_cards.is_empty():
			style = {"shoot": "BANG", "dodge": "BANG", "showdown": "DUEL", "panic": "STEAL", "cat_balou": "DISCARD", "jail": "JAIL"}.get(selected_cards[0].card_data_id, "GENERIC")
		app.table.targeting.begin_targeting(app.selected, app.local_id(), targets, own.get("target_info", {}), style)
	else:
		app.table.targeting.cancel_targeting(false)
	build_top()
	build_log()
	if state.phase == "CHARACTER_SELECTION":
		app.table.targeting.blocked = true
		app.show_character_selection(own)
		return
	if not state.winner.is_empty():
		build_result()
		return
	build_hand()
	if app.menu_open:
		build_pause()
	elif own.has("role") and app.seen_role != int(state.match_id):
		app.table.targeting.blocked = true
		app.show_role(own.role, state.match_id)
	elif not request.is_empty() and not ["dodge", "survive", "duel", "indians", "transfer", "store", "draw_steal", "draw_discard"].has(request.reaction_type):
		app.table.targeting.blocked = true
		app.show_reaction(request)

func text(value: String, font_size: int = 16, parent: Node = self) -> Label:
	var item: Label = app.label(value, font_size, parent)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return item

func action(value: String, callback: Callable, parent: Node, disabled: bool = false) -> Button:
	var item: Button = app.button(value, callback, parent, disabled)
	item.add_theme_font_size_override("font_size", 14)
	item.custom_minimum_size.y = 42
	return item

func build_top() -> void:
	var bar := Control.new()
	bar.name = "TopBar"
	add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 52
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var owner := ""
	for player in state.players:
		if player.player_id == state.current_player:
			owner = player.display_name
	var title := "LƯỢT CỦA BẠN" if state.current_player == app.local_id() else "LƯỢT CỦA " + owner
	var phase: String = TextCatalog.text(state.phase)
	var strip: Control = load("res://scripts/ui/HUDMatchStrip.gd").new()
	bar.add_child(strip)
	var strip_width: float = minf(570,size.x-260)
	strip.position = Vector2((size.x-strip_width)/2,8)
	strip.custom_minimum_size = Vector2(strip_width,34)
	strip.configure(title,phase,float(request.get("remaining",0)))
	var menu := action("MENU", func(): app.menu_open = true; app.refresh(), bar)
	menu.position = Vector2(size.x-86,8)
	menu.size = Vector2(74,42)
	menu.name = "PauseButton"
	menu.tooltip_text = "Menu · Luật chơi · Rời trận"

func build_log() -> void:
	var holder := VBoxContainer.new()
	add_child(holder)
	holder.position = Vector2(12, 8)
	holder.size.x = minf(320, size.x * 0.28) if app.log_expanded else 105
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var toggle := action("NHẬT KÝ  +" if not app.log_expanded else "NHẬT KÝ  −",
		func(): app.log_expanded = not app.log_expanded; app.refresh(), holder)
	toggle.custom_minimum_size.y = 30
	toggle.add_theme_font_size_override("font_size", 12)
	if not app.log_expanded:
		return
	var entries: Array = state.log.slice(-2)
	if app.log_expanded:
		entries = state.log
	var scroller := ScrollContainer.new()
	holder.add_child(scroller)
	scroller.custom_minimum_size = Vector2(0, 180 if app.log_expanded else 72)
	scroller.mouse_filter = Control.MOUSE_FILTER_PASS if app.log_expanded else Control.MOUSE_FILTER_IGNORE
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroller.add_child(rows)
	for entry in entries:
		text(entry, 12, rows)

func build_hand() -> void:
	var local: Dictionary = {}
	for player in state.players:
		if player.player_id == app.local_id():
			local = player
	var footer := HBoxContainer.new()
	add_child(footer)
	footer.name = "HandActions"
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_left = 18
	footer.offset_right = -18
	footer.offset_top = -224
	footer.offset_bottom = -182
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var message := "BÀI CỦA BẠN"
	if not local.get("is_alive", false):
		message = "BẠN ĐÃ BỊ LOẠI · ĐANG THEO DÕI"
	elif app.sid_mode:
		message = "SID · CHỌN 2 LÁ ĐỂ BỎ (%d/2)" % app.sid_cards.size()
	elif not request.is_empty():
		message = str(request.get("title", "CHỌN TRÊN BÀN"))
		if request.reaction_type == "transfer":
			message = "CHẠM VÙNG TAY KÍN / TRANG BỊ ĐƯỢC ĐÁNH DẤU"
		elif request.reaction_type == "store":
			message = "CỬA HÀNG · CHẠM LÁ BÀI TRÊN BÀN"
	elif state.phase == "DISCARD_PHASE" and state.current_player == app.local_id():
		message = "BỎ %d LÁ · CHẠM BÀI ĐỂ BỎ" % maxi(0, own.get("hand", []).size() - int(local.get("current_hp", 0)))
	elif app.selected >= 0:
		message = "CHẠM CAO BỒI ĐƯỢC ĐÁNH DẤU"
	var prompt := text(message, 14, footer)
	prompt.name = "HandPrompt"
	prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prompt.add_theme_color_override("font_color", SaloonTheme.GOLD)
	var character: Dictionary = local.get("character", {})
	prompt.tooltip_text = "%s · %s\n%s" % [character.get("display_name", ""), TextCatalog.text(own.get("role", "")), character.get("ability_description_vi", "")]
	if not request.is_empty():
		deadline = Time.get_ticks_msec() / 1000.0 + float(request.get("remaining", 0))
	if app.sid_mode:
		action("HỒI 1 MÁU", func(): app.intent("ability", {"cards": app.sid_cards.duplicate()}); app.sid_mode = false; app.sid_cards.clear(); app.refresh(),
			footer, app.sid_cards.size() != 2).name = "SidConfirm"
		action("HỦY", cancel_selection, footer)
	elif not request.is_empty():
		if ["dodge", "duel", "indians", "survive"].has(request.reaction_type):
			action("CHỊU ĐÒN" if request.reaction_type != "survive" else "KHÔNG CỨU",
				func(): app.intent("reaction", {"request": request.request_id, "accept": false}), footer).name = "TakeHit"
		if request.reaction_type == "draw_steal" or request.reaction_type == "draw_discard":
			# Deck/discard also accept the same choices directly through their table zones.
			prompt.text = "CHỌN CHỒNG RÚT / CHỒNG BỎ" if request.reaction_type == "draw_discard" else "CHỌN CHỒNG RÚT HOẶC TAY BÀI ĐỐI THỦ"
	elif app.selected >= 0:
		action("× HỦY", cancel_selection, footer).name = "CancelSelection"
	elif state.current_player == app.local_id() and state.phase == "ACTION_PHASE":
		action("END TURN", func(): app.intent("end"), footer).name = "EndTurn"
	# Own identity/ability is small and sits with the hand, never in a permanent toolbar.
	if local.get("is_alive", false) and own.get("ability_id", "") == "discard_heal" and int(local.get("current_hp", 0)) < int(local.get("max_hp", 4)):
		var sid := action("+", func(): app.sid_mode = not app.sid_mode; app.sid_cards.clear(); app.refresh(), footer)
		sid.name = "SidAbility"
		sid.tooltip_text = "Sid Ketchum · Chọn bỏ 2 lá để hồi 1 máu"
	var selected_ids: Array = app.sid_cards.duplicate() if app.sid_mode else [app.selected]
	var usable: Array = []
	var reacting: bool = not request.is_empty() and ["dodge", "duel", "indians", "survive"].has(request.reaction_type)
	for card in own.get("hand", []):
		if app.sid_mode or (state.phase == "DISCARD_PHASE" and state.current_player == app.local_id()) or (reacting and request.get("allowed_card_types", []).has(card.instance_id)) or (request.is_empty() and not own.get("targets", {}).get(card.instance_id, []).is_empty()):
			usable.append(card.instance_id)
	hand = load("res://scripts/ui/HandFan.gd").new()
	hand.name = "HandFan"
	add_child(hand)
	hand.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hand.offset_left = 18
	hand.offset_right = -18
	hand.offset_top = -182
	hand.offset_bottom = -4
	hand.configure(own.get("hand", []), usable, selected_ids, reacting, own.get("disabled_reasons", {}))
	hand.card_clicked.connect(handle_card)
	hand.preview_requested.connect(show_preview)
	hand.preview_closed.connect(close_preview)

func _process(_delta: float) -> void:
	if is_instance_valid(timer_label):
		timer_label.text = "%.1f s" % maxf(0, deadline - Time.get_ticks_msec() / 1000.0)

func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
		close_preview()

func handle_card(uid: int) -> void:
	AudioManager.play_card("select")
	if app.menu_open:
		return
	if app.sid_mode:
		if app.sid_cards.has(uid):
			app.sid_cards.erase(uid)
		elif app.sid_cards.size() < 2:
			app.sid_cards.append(uid)
		app.refresh()
		return
	if not request.is_empty():
		if request.get("allowed_card_types", []).has(uid):
			app.intent("reaction", {"request": request.request_id, "accept": true, "card": uid})
		return
	if app.selected == uid:
		cancel_selection()
		return
	app.choose_card_action(uid)

func cancel_selection() -> void:
	AudioManager.play_card("release")
	app.selected = -1
	app.sid_mode = false
	app.sid_cards.clear()
	app.refresh()

func world_action(token: Dictionary) -> void:
	if app.menu_open or request.is_empty():
		return
	var args := {"request": request.request_id, "accept": true}
	match token.get("kind", ""):
		"market": args["cards"] = [token.card]
		"zone":
			args["option"] = str(token.player) if request.reaction_type == "draw_steal" else str(token.zone)
			if request.reaction_type == "transfer" and str(token.zone) != "hand":
				args["card"] = int(token.get("card", 0))
		"deck": args["option"] = "deck"
		"discard": args["option"] = "discard"
		_: return
	app.intent("reaction", args)

func show_preview(card: Dictionary) -> void:
	close_preview()
	preview = PanelContainer.new()
	preview.name = "CardPreview"
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(preview)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(column)
	var data: Dictionary = CardData.data(card.card_data_id)
	text(data.name, 19, column).add_theme_color_override("font_color", SaloonTheme.GOLD)
	text(CardInstance.corner(card), 22, column).add_theme_color_override("font_color", SaloonTheme.CREAM)
	var description := text(data.description, 16, column)
	description.custom_minimum_size.x = 260
	var reason: String = str(own.get("disabled_reasons", {}).get(card.instance_id, ""))
	if not reason.is_empty():
		text(reason, 15, column).add_theme_color_override("font_color", Color("#ffb995"))
	preview.position = Vector2(clampf(get_viewport().get_mouse_position().x - 130, 12, size.x - 304), size.y - 370)
	preview.size.x = 290

func close_preview() -> void:
	if is_instance_valid(preview):
		preview.queue_free()
		preview = null

func build_pause() -> void:
	app.table.targeting.blocked = true
	var box: VBoxContainer = app.modal()
	text("TẠM DỪNG GIAO DIỆN", 25, box)
	text("Trận online và đồng hồ phản ứng vẫn tiếp tục.", 16, box)
	action("TIẾP TỤC", func(): app.menu_open = false; app.refresh(), box)
	action("LUẬT CHƠI", func(): show_rules(), box)
	action("ÂM THANH", app.show_audio_settings, box)
	action("HÌNH ẢNH", app.show_visual_settings, box)
	action("RỜI TRẬN", app.leave, box)
	if app.local_id() == state.get("host_player_id", 1) and OS.is_debug_build() and state.debug and NetworkManager.mode != "websocket":
		var fold := VBoxContainer.new()
		box.add_child(fold)
		action("DEBUG ▾", func(): toggle_debug(fold), fold)

func toggle_debug(fold: VBoxContainer) -> void:
	if fold.get_child_count() == 1:
		app.build_debug(fold, state)
	else:
		for node in fold.get_children().slice(1):
			node.queue_free()

func show_rules() -> void:
	var box: VBoxContainer = app.modal()
	text("LUẬT CHƠI", 26, box)
	text("Chọn bài → chạm cao bồi. Mỗi lượt bình thường dùng 1 lá Bắn. Tầm súng và khoảng cách được máy chủ kiểm tra.\nKhi bị tấn công, chạm lá phản ứng sáng trên tay hoặc chịu đòn.\nKết thúc lượt: bỏ bớt bài để số bài không quá máu.\nChạm trang bị/tay kín khi Hoảng loạn hoặc Cat Balou yêu cầu. Chạm bài giữa bàn để chọn trong Cửa hàng.\nEsc, chuột phải, nút Hủy hoặc chạm lại lá đã chọn để hủy nhắm mục tiêu.", 18, box)
	action("TIẾP TỤC", func(): app.menu_open = false; app.refresh(), box)

func build_result() -> void:
	app.table.targeting.blocked = true
	var box: VBoxContainer = app.modal()
	text("✦ AI CÒN MŨ, NGƯỜI ĐÓ THẮNG! ✦", 21, box)
	text(TextCatalog.text(state.winner), 30, box)
	for player in state.players:
		text("%s · %s" % [player.display_name, TextCatalog.text(player.public_role)], 17, box)
	if app.local_id() == state.get("host_player_id", 1):
		action("PLAY AGAIN", func(): app.intent("restart"), box)
		action("RETURN TO LOBBY", func(): app.intent("lobby"), box)
	else:
		text("Đang chờ chủ phòng...", 17, box)
	action("RỜI TRẬN", app.leave, box)
