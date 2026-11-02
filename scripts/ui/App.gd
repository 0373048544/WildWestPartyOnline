extends Node

const WesternToastScript = preload("res://scripts/ui/WesternToast.gd")
const WesternStatusBadgeScript = preload("res://scripts/ui/WesternStatusBadge.gd")

signal presentation_feedback(kind: String)

var canvas: CanvasLayer
var root: Control
var content: VBoxContainer
var overlay: Control
var status: Label
var table: Node3D
var screen: String = "main"
var selected: int = -1
var seen_role: int = -1
var reaction_label: Label
var reaction_until: float = 0
var error_text: String = ""
var debug_target: int = 1
var name_field: LineEdit
var ip_field: LineEdit
var port_field: SpinBox
var room_field: LineEdit
var match_hud: Control
var menu_open: bool = false
var log_expanded: bool = false
var sid_mode: bool = false
var sid_cards: Array = []
var noticed_turn: int = -1
var turn_notice_until: int = 0
var hud_match: int = -1
var character_draft: String = ""
var layout_refresh_queued: bool = false
var personal_toasts: Control
var reaction_banner: Control

func _ready() -> void:
	set_process(false)
	add_child(load("res://scripts/ui/WebLayout.gd").new())
	var theme := SaloonTheme.create()
	canvas = CanvasLayer.new()
	add_child(canvas)
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = theme
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)
	reaction_banner = load("res://scenes/ui/ReactionBanner.tscn").instantiate()
	canvas.add_child(reaction_banner)
	personal_toasts = load("res://scripts/ui/PersonalEventToast.gd").new()
	canvas.add_child(personal_toasts)
	root.resized.connect(func():
		if not layout_refresh_queued:
			layout_refresh_queued = true
			call_deferred("refresh_layout"))
	NetworkManager.updated.connect(refresh)
	NetworkManager.error_received.connect(func(message): error_text = message; refresh())
	NetworkManager.visual_event.connect(func(a, k, t):
		if is_instance_valid(table):
			table.animate(a, k, t))
	NetworkManager.table_event.connect(func(event):
		if is_instance_valid(table):
			table.presentation(event)
		var is_local_bang: bool = str(event.get("kind", "")) == "bang" and int(event.get("target", 0)) == local_id()
		if is_instance_valid(personal_toasts) and not is_local_bang:
			personal_toasts.consume_event(event, local_id(), NetworkManager.public_state))
	refresh()
	if OS.has_feature("web") and OS.is_debug_build() and bool(JavaScriptBridge.eval("new URLSearchParams(location.search).get('e2e') === '1'")):
		var test_bridge: Node = load("res://scripts/network/BrowserTestBridge.gd").new()
		test_bridge.app = self
		add_child(test_bridge)

func _process(_delta: float) -> void:
	if is_instance_valid(reaction_label):
		var remaining: float = maxf(0, reaction_until - Time.get_ticks_msec() / 1000.0)
		reaction_label.text = "Còn %.1f giây để chọn nhân vật" % remaining if NetworkManager.public_state.get("phase", "") == "CHARACTER_SELECTION" else TextCatalog.text("Respond in %.1f seconds") % remaining

func refresh_layout() -> void:
	layout_refresh_queued = false
	if is_instance_valid(root):
		# Rebuild only responsive UI sections/modal; the table, HUD and CardViews
		# remain persistent and authoritative state is untouched.
		if is_instance_valid(match_hud):
			match_hud.top_signature = ""
			match_hud.hand_signature = ""
			match_hud.flow_signature = ""
		if is_instance_valid(overlay):
			clear_game_modal()
		refresh()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if selected >= 0 or sid_mode:
			selected = -1
			sid_mode = false
			sid_cards.clear()
		elif not NetworkManager.public_state.is_empty() and NetworkManager.public_state.get("started", false):
			menu_open = not menu_open
		refresh()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventMouseButton) or not event.pressed:
		return
	var info: Control = root.get_node_or_null("PlayerInfoCard") as Control
	if is_instance_valid(info) and not info.get_global_rect().has_point(event.position):
		root.remove_child(info)
		info.queue_free()

func label(text: String, size: int = 18, parent: Node = content) -> Label:
	var node := Label.new()
	node.text = TextCatalog.text(text)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_font_size_override("font_size", size)
	parent.add_child(node)
	return node

func button(text: String, callback: Callable, parent: Node = content, disabled: bool = false) -> Button:
	var node: Button = load("res://scripts/ui/WesternButton.gd").new()
	node.text = TextCatalog.text(text)
	node.tooltip_text = node.text
	node.disabled = disabled
	node.pressed.connect(callback)
	node.pressed.connect(func(): presentation_feedback.emit("button"); AudioManager.play_ui("button"))
	node.mouse_entered.connect(func():
		if not node.disabled:
			AudioManager.play_ui("hover")
			node.create_tween().tween_property(node, "modulate", Color("#ffe4af"), 0.12))
	node.mouse_exited.connect(func(): node.create_tween().tween_property(node, "modulate", Color.WHITE, 0.16))
	parent.add_child(node)
	return node

func western_input(placeholder: String, parent: Node = content, code: bool = false) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.custom_minimum_size.y = 52
	field.add_theme_font_size_override("font_size", 20 if code else 18)
	field.virtual_keyboard_enabled = true
	field.clear_button_enabled = true
	if code:
		field.alignment = HORIZONTAL_ALIGNMENT_CENTER
		field.add_theme_constant_override("minimum_character_width", 12)
	parent.add_child(field)
	return field

func section_header(text: String, parent: Node = content, icon: String = "✦") -> Label:
	var heading := label("%s  %s" % [icon, text], 18, parent)
	heading.add_theme_color_override("font_color", SaloonTheme.GOLD)
	heading.add_theme_color_override("font_shadow_color", Color("#1b100b"))
	heading.add_theme_constant_override("shadow_offset_y", 2)
	return heading

func show_outgame_toast(message: String, tone: String = "neutral") -> void:
	var old := root.get_node_or_null("OutGameToast")
	if old:
		old.queue_free()
	var toast := WesternToastScript.new()
	root.add_child(toast)
	var width := minf(460.0, root.size.x - 28.0)
	toast.position = Vector2((root.size.x - width) * 0.5, maxf(16.0, root.size.y * 0.06))
	toast.size = Vector2(width, 54)
	toast.show_message(message, tone)

func show_help() -> void:
	var box := modal()
	label("HƯỚNG DẪN NHANH", 28, box)
	label("1. Tạo phòng và gửi mã cho bạn bè.\n2. Mọi người nhấn SẴN SÀNG.\n3. Chủ phòng nhấn BẮT ĐẦU GAME.\n4. Trong trận, chọn bài rồi chọn mục tiêu.", 18, box)
	label("Mẹo: trên điện thoại, giữ lá bài để xem chi tiết và kéo ngang để cuộn tay bài.", 15, box)
	button("ĐÃ HIỂU", func(): clear_game_modal(); refresh(), box).set_variant("primary")

func refresh() -> void:
	var state: Dictionary = NetworkManager.public_state
	var in_game: bool = not state.is_empty() and state.get("started", false)
	# Network snapshots are frequent. Keep the table and HUD alive for the whole
	# match; MatchHUD invalidates only the sections whose input changed.
	if (
		in_game
		and is_instance_valid(table)
		and is_instance_valid(match_hud)
		and hud_match == int(state.get("match_id", -1))
	):
		build_game(state)
		return

	for child in root.get_children():
		if child.name == "PlayerInfoCard" and NetworkManager.public_state.get("started", false):
			continue
		# A host button can synchronously publish state while still emitting pressed.
		# Detach the old screen now and destroy it after signal delivery completes.
		root.remove_child(child)
		child.queue_free()
		if child == match_hud:
			match_hud = null
	reaction_label = null
	if in_game and not is_instance_valid(table):
		table = load("res://scenes/game/GameTable.tscn").instantiate()
		add_child(table)
		table.targeting.target_chosen.connect(play_selected)
		table.targeting.cancelled.connect(func(): selected = -1; refresh())
		table.character_info_requested.connect(show_character_info)
		table.targeting.world_chosen.connect(func(token):
			if is_instance_valid(match_hud):
				match_hud.world_action(token))
	elif not in_game and is_instance_valid(table):
		table.free()
		table = null
	if not in_game and is_instance_valid(reaction_banner):
		reaction_banner.hide_banner()
	var backdrop: Control
	if in_game and hud_match != int(state.match_id):
		hud_match = state.match_id
		personal_toasts.reset_for_match(hud_match)
		selected = -1
		sid_mode = false
		sid_cards.clear()
		menu_open = false
		noticed_turn = -1
		character_draft = ""
	if in_game:
		backdrop = ColorRect.new()
		backdrop.color = Color(0.035, 0.055, 0.075, 0.08)
	else:
		backdrop = load("res://scripts/ui/SaloonBackdrop.gd").new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var safe: Vector4 = load("res://scripts/ui/MatchLayout.gd").safe_insets(root)
	margin.add_theme_constant_override("margin_left", maxi(14, int(safe.x + 14)))
	margin.add_theme_constant_override("margin_right", maxi(14, int(safe.z + 14)))
	margin.add_theme_constant_override("margin_top", maxi(12, int(safe.y + 12)))
	margin.add_theme_constant_override("margin_bottom", maxi(12, int(safe.w + 12)))
	if not in_game:
		var target_width: int = 940 if not state.is_empty() else 720
		var inset: int = maxi(int(safe.x + 14), int((root.size.x - target_width) / 2))
		margin.add_theme_constant_override("margin_left", inset)
		margin.add_theme_constant_override("margin_right", maxi(int(safe.z + 14), inset))
		margin.add_theme_constant_override("margin_top", maxi(int(safe.y + 10), 10 if root.size.y < 620 else 34))
	root.add_child(margin)
	if not state.is_empty() and not in_game:
		content = load("res://scenes/menu/Lobby.tscn").instantiate()
	else:
		content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if in_game:
		margin.add_child(content)
	else:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		margin.add_child(scroll)
		var frame := PanelContainer.new()
		frame.name = "OutGameFrame"
		frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		frame.add_theme_stylebox_override("panel", SaloonTheme.wood_panel(18 if root.size.y < 520 else 28))
		scroll.add_child(frame)
		frame.add_child(content)
		frame.modulate.a = 0.0
		frame.position.y += 10
		var enter := frame.create_tween().set_parallel()
		enter.tween_property(frame, "modulate:a", 1.0, 0.18)
		enter.tween_property(frame, "position:y", frame.position.y - 10, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if state.is_empty():
		build_menu()
	elif not in_game:
		build_lobby(state)
	else:
		build_game(state)
	if not error_text.is_empty():
		var warning := PanelContainer.new()
		warning.name = "ConnectionStatus"
		warning.add_theme_stylebox_override("panel", SaloonTheme.panel(Color("#4c2e2c"), SaloonTheme.DANGER))
		content.add_child(warning)
		var notice := HBoxContainer.new()
		warning.add_child(notice)
		var message := label(TextCatalog.message(error_text), 16, notice)
		message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var dismiss := button("ĐÓNG", func(): error_text = ""; refresh(), notice)
		dismiss.set_variant("danger")

func build_menu() -> void:
	var short_landscape := root.size.y < 520.0 and root.size.x > root.size.y
	var portrait_phone := root.size.x < 600.0 and root.size.y >= root.size.x
	var ornament := label("★  QUÁN RƯỢU MIỀN TÂY  ★", 14)
	ornament.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ornament.add_theme_color_override("font_color", SaloonTheme.GOLD)
	ornament.visible = not short_landscape
	var title := label("WILD WEST\nPARTY ONLINE", 26 if short_landscape else (28 if portrait_phone else (34 if root.size.x < 900 else 44)))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", SaloonTheme.GOLD)
	title.add_theme_color_override("font_shadow_color", Color("#080f17"))
	title.add_theme_constant_override("shadow_offset_y", 4)
	if VisualSettings.decorative_motion():
		var pulse := title.create_tween().set_loops()
		pulse.tween_property(title, "modulate", Color("#f5c879"), 1.8).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(title, "modulate", Color.WHITE, 1.8).set_trans(Tween.TRANS_SINE)
	var subtitle := label("Vào phòng, gọi bạn, bắt đầu đấu súng.", 16)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.visible = not short_landscape
	content.add_child(HSeparator.new())
	if NetworkManager.connecting:
		var connecting := WesternStatusBadgeScript.new()
		connecting.configure("◆  ĐANG KẾT NỐI ĐẾN CHỦ PHÒNG…", "warning")
		content.add_child(connecting)
		button("HỦY KẾT NỐI", leave).set_variant("danger")
		return
	var space := Control.new()
	space.custom_minimum_size.y = 0 if short_landscape else 12
	content.add_child(space)
	if screen == "main":
		var create := button("★  TẠO PHÒNG", func(): screen = "host"; refresh())
		create.name = "CreateRoomButton"
		create.set_variant("primary")
		var join := button("♠  THAM GIA PHÒNG", func(): screen = "join"; refresh())
		join.name = "JoinRoomButton"
		join.set_variant("primary")
		# Stack labelled settings controls on narrow phones so none overflow.
		var secondary: Container = VBoxContainer.new() if portrait_phone else HBoxContainer.new()
		secondary.add_theme_constant_override("separation", 8)
		content.add_child(secondary)
		for spec in [["⚙  ÂM THANH", show_audio_settings], ["◇  HÌNH ẢNH", show_visual_settings], ["?  HƯỚNG DẪN", show_help]]:
			var secondary_button := button(spec[0], spec[1], secondary)
			secondary_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			secondary_button.set_variant("quiet")
		if not OS.has_feature("web"):
			button("THOÁT GAME", func(): get_tree().quit()).set_variant("danger")
		var footer := label("● Sẵn sàng kết nối  •  v0.9  •  %s" % NetworkConfig.server_url(), 12)
		footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		footer.add_theme_color_override("font_color", Color("#b9aa8f"))
		return
	section_header("TẠO PHÒNG MỚI" if screen == "host" else "THAM GIA PHÒNG", content, "★" if screen == "host" else "♠")
	var form := PanelContainer.new()
	form.add_theme_stylebox_override("panel", SaloonTheme.inset_panel(14))
	content.add_child(form)
	var form_box := VBoxContainer.new()
	form_box.add_theme_constant_override("separation", 7)
	form.add_child(form_box)
	label("TÊN CAO BỒI", 14, form_box).add_theme_color_override("font_color", SaloonTheme.GOLD)
	name_field = western_input("Nhập tên của bạn", form_box)
	name_field.text = NetworkManager.local_name
	name_field.max_length = 24
	if screen == "join":
		label("MÃ PHÒNG", 14, form_box).add_theme_color_override("font_color", SaloonTheme.GOLD)
		room_field = western_input("AB7KQ2", form_box, true)
		room_field.name = "RoomCode"
		room_field.max_length = 6
	if short_landscape:
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 10)
		content.add_child(actions)
		var submit := button("HOST" if screen == "host" else "JOIN", connect_game, actions)
		var back := button("BACK", func(): screen = "main"; refresh(), actions)
		submit.name = "SubmitRoomButton"
		back.name = "BackButton"
		submit.set_variant("primary")
		back.set_variant("quiet")
		submit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		var submit := button("TẠO PHÒNG" if screen == "host" else "THAM GIA", connect_game)
		submit.name = "SubmitRoomButton"
		submit.set_variant("primary")
		var back := button("← QUAY LẠI", func(): screen = "main"; refresh())
		back.name = "BackButton"
		back.set_variant("quiet")

func connect_game() -> void:
	error_text = ""
	var title := name_field.text
	if screen == "host":
		NetworkManager.create_room(title)
	else:
		NetworkManager.join_room(title, room_field.text)

func local_id() -> int:
	return NetworkManager.local_player_id()

func intent(action: String, args: Dictionary = {}) -> void:
	NetworkManager.send_intent(action, args)

func build_lobby(state: Dictionary) -> void:
	content.configure(self, state)

func leave() -> void:
	screen = "main"
	selected = -1
	seen_role = -1
	menu_open = false
	sid_mode = false
	sid_cards.clear()
	if is_instance_valid(personal_toasts):
		personal_toasts.reset_for_match(-1)
	if is_instance_valid(reaction_banner):
		reaction_banner.hide_banner()
	NetworkManager.leave()

func build_game(state: Dictionary) -> void:
	var own: Dictionary = NetworkManager.private_state
	if own.get("match_id", state.match_id) != state.match_id:
		own = {}
	if is_instance_valid(reaction_banner):
		reaction_banner.present(self, own.get("reaction", {}), state)
	if is_instance_valid(personal_toasts):
		var reaction_kind: String = str(own.get("reaction", {}).get("reaction_type", ""))
		# A toast that began before an urgent reaction must never cover its title or
		# buttons. Its own lifetime continues invisibly and the queue resumes after.
		personal_toasts.visible = reaction_kind not in ["dodge", "duel", "indians", "survive"] and not is_instance_valid(overlay)
	if not is_instance_valid(match_hud):
		match_hud = load("res://scripts/ui/MatchHUD.gd").new()
		root.add_child(match_hud)
	match_hud.initialize(self, state, own)
	if NetworkManager.mode == "websocket" and NetworkManager.room_client.reconnecting:
		table.targeting.blocked = true
		var box := modal()
		label("ĐANG KẾT NỐI LẠI...", 26, box)
		label("Ván chơi và vai trò được giữ trong thời gian chờ.", 18, box)

func choose_card(uid: int) -> void:
	if is_instance_valid(match_hud):
		match_hud.handle_card(uid)


func choose_card_action(uid: int) -> void:
	var state: Dictionary = NetworkManager.public_state
	if state.phase == "DISCARD_PHASE":
		intent("discard", {"card": uid})
		return
	var own: Dictionary = NetworkManager.private_state
	for card in own.get("hand", []):
		if card.instance_id == uid:
			if CardData.data(card.card_data_id).target == CardData.TargetType.SINGLE_PLAYER or (card.card_data_id == "dodge" and own.get("ability_id", "") == "convert"):
				selected = uid
				refresh()
			else:
				intent("play", {"card": uid, "target": local_id()})
			return

func play_selected(target: int) -> void:
	var uid := selected
	selected = -1
	intent("play", {"card": uid, "target": target})

func modal() -> VBoxContainer:
	clear_game_modal()
	var layout: Script = load("res://scripts/ui/MatchLayout.gd")
	overlay = ColorRect.new()
	overlay.name = "GameModal"
	overlay.color = Color(0.025, 0.03, 0.05, 0.96)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = layout.Z_MODAL_BACKDROP
	root.add_child(overlay)
	if is_instance_valid(match_hud):
		match_hud.set_modal_blocked(true)
	if is_instance_valid(personal_toasts):
		personal_toasts.visible = false
	if is_instance_valid(reaction_banner):
		reaction_banner.visible = false
	var available: Rect2 = layout.modal_rect(root)
	var responsive_width := available.size.x * (0.88 if layout.mobile_landscape(root) else (0.94 if layout.mobile_portrait(root) else 1.0))
	var frame_width: float = minf(available.size.x, minf(responsive_width, 860.0 if not layout.mobile(root) else available.size.x))
	var frame := PanelContainer.new()
	frame.name = "ModalFrame"
	frame.z_index = layout.Z_MODAL_CONTENT
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.position = Vector2(available.get_center().x - frame_width * 0.5, available.position.y)
	frame.size = Vector2(frame_width, available.size.y)
	frame.custom_minimum_size = frame.size
	frame.clip_contents = true
	frame.add_theme_stylebox_override("panel", SaloonTheme.panel(Color("#172b37"), SaloonTheme.GOLD, 18 if layout.mobile(root) else 28))
	overlay.add_child(frame)
	var padding := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		padding.add_theme_constant_override("margin_" + side, int(layout.units(root, 10.0 if layout.mobile_landscape(root) else 16.0)))
	frame.add_child(padding)
	var scroll := ScrollContainer.new()
	scroll.name = "ModalScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	padding.add_child(scroll)
	var box := VBoxContainer.new()
	box.name = "ModalContent"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10 if layout.mobile_landscape(root) else 16)
	scroll.add_child(box)
	var enter := frame.create_tween()
	frame.modulate = Color(1, 1, 1, 0.75)
	enter.tween_property(frame, "modulate", Color.WHITE, 0.18)
	return box

func clear_game_modal() -> void:
	var current: Node = root.get_node_or_null("GameModal")
	if current:
		root.remove_child(current)
		current.queue_free()
	overlay = null
	reaction_label = null
	set_process(false)
	if is_instance_valid(match_hud):
		match_hud.set_modal_blocked(false)
	if is_instance_valid(personal_toasts):
		var reaction_kind: String = str(NetworkManager.private_state.get("reaction", {}).get("reaction_type", ""))
		personal_toasts.visible = reaction_kind not in ["dodge", "duel", "indians", "survive"]

func show_role(role: String, match_number: int) -> void:
	AudioManager.play_once("role:%d" % match_number, "role")
	var box := modal()
	label("YOUR ROLE", 24, box)
	var badge := label("✦  " + TextCatalog.text(role) + "  ✦", 40, box)
	badge.add_theme_color_override("font_color", SaloonTheme.GOLD)
	var small_table: bool = NetworkManager.public_state.get("players", []).size() <= 3
	var goals := {"SHERIFF": "Eliminate every Outlaw and the Renegade.",
		"DEPUTY": "Protect the Sheriff and eliminate the enemies.",
		"OUTLAW": "Eliminate the Sheriff.", "RENEGADE": "Be the last living player."}
	if small_table:
		goals = {"DEPUTY": "Loại mọi đối thủ và là người sống sót cuối cùng.",
			"OUTLAW": "Loại mọi đối thủ và là người sống sót cuối cùng.",
			"RENEGADE": "Trở thành người sống sót cuối cùng."}
	label(goals.get(role, ""), 21, box)
	label("Không có Cảnh sát trưởng trong chế độ 2–3 người. Vai trò vẫn được giữ kín." if small_table else "The Sheriff is public. Keep your allegiance secret.", 17, box)
	button("CONTINUE", func(): seen_role = match_number; refresh(), box)

func show_reaction(request: Dictionary) -> void:
	var box := modal()
	var kind: String = request.reaction_type
	if kind in ["department_store_give", "store"]:
		overlay.color = Color(0.02, 0.025, 0.03, 0.62)
		var choice_layout: Script = load("res://scripts/ui/MatchLayout.gd")
		var available: Rect2 = choice_layout.modal_rect(root)
		var frame: PanelContainer = overlay.get_node("ModalFrame")
		var width_ratio: float = 0.90 if choice_layout.mobile_portrait(root) else (0.84 if choice_layout.mobile_landscape(root) else 0.78)
		var height_ratio: float = 0.90 if choice_layout.mobile_portrait(root) else (0.82 if choice_layout.mobile_landscape(root) else 0.78)
		var choice_size := Vector2(minf(860, available.size.x * width_ratio), available.size.y * height_ratio)
		frame.custom_minimum_size = choice_size
		frame.size = choice_size
		frame.position = available.get_center() - frame.size * 0.5
	label(request.get("title", {"dodge": "YOU ARE BEING SHOT", "survive": "USE DRINK TO SURVIVE?", "duel": "SHOWDOWN • RESPOND WITH SHOOT"}.get(kind, "CHỌN HÀNH ĐỘNG")), 25, box)
	if not str(request.get("detail", "")).is_empty():
		var detail := label(str(request.detail), 18, box)
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reaction_label = label("", 22, box)
	set_process(true)
	reaction_until = Time.get_ticks_msec() / 1000.0 + float(request.remaining)
	var request_id: int = request.request_id
	if request.has("cards"):
		var choices: Node = load("res://scripts/ui/ChoicePanel.gd").new()
		box.add_child(choices)
		choices.configure(
			self,
			request.cards,
			int(request.get("pick_count", 1)),
			func(ids): intent("reaction", {"request": request_id, "accept": true, "cards": ids}),
			str(request.get("confirm_label", "XÁC NHẬN LỰA CHỌN")),
			str(request.get("reset_label", "")),
			str(request.get("confirm_question", ""))
		)
	elif request.has("choices"):
		for choice in request.choices:
			var option: String = str(choice.id)
			button(choice.label, func(): intent("reaction", {"request": request_id, "accept": true, "option": option}), box)
	else:
		var list_scroll := ScrollContainer.new()
		list_scroll.custom_minimum_size.y = 170
		box.add_child(list_scroll)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list_scroll.add_child(list)
		for card in NetworkManager.private_state.get("hand", []):
			if request.get("allowed_card_types", []).has(card.instance_id):
				var uid: int = card.instance_id
				var title: String = "%s • %s %s" % [CardData.data(card.card_data_id).name, TextCatalog.text(card.suit), GameManager.rank_text(card.rank)]
				button(title, func(): intent("reaction", {"request": request_id, "accept": true, "card": uid}), list)
		if kind == "survive" and request.get("sid", false):
			button("KỸ NĂNG SID • BỎ 2 LÁ ĐỂ HỒI 1 MÁU", show_sid_picker, box)
		button("NO" if kind == "survive" else "NO • TAKE HIT", func(): intent("reaction", {"request": request_id, "accept": false}), box)

func show_character_selection(own: Dictionary) -> void:
	var box := modal()
	var layout: Script = load("res://scripts/ui/MatchLayout.gd")
	var landscape_phone: bool = bool(layout.mobile_landscape(root))
	var heading := label("CHỌN NHÂN VẬT", 21 if landscape_phone else 26, box)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not landscape_phone:
		label("Hai lựa chọn riêng của bạn. Chọn một thẻ rồi xác nhận. Hết giờ: máy chủ chọn một trong hai.", 15, box)
	reaction_label = label("", 14 if landscape_phone else 18, box)
	reaction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	set_process(true)
	reaction_until = Time.get_ticks_msec() / 1000.0 + float(own.get("character_remaining", 25))
	if own.get("character_chosen", false):
		label("Bạn đã chọn %s" % own.get("selected_character", {}).get("display_name", ""), 24, box)
		label("Đang chờ những người chơi còn lại...", 18, box)
		return
	var panel: Control = load("res://scripts/ui/CharacterChoicePanel.gd").new()
	box.add_child(panel)
	panel.configure(self, own.get("character_options", []))

func show_character_info(player: Dictionary) -> void:
	if is_instance_valid(overlay):
		return
	var old: Node = root.get_node_or_null("PlayerInfoCard")
	var signature := JSON.stringify(player) + str(root.size)
	if old and old.get_meta("snapshot", "") == signature:
		return
	var saved_portrait: Control
	if old and not player.is_empty() and old.get_meta("character_id", "") == player.get("character_id", ""):
		saved_portrait = old.find_child("CharacterPortrait", true, false)
		if saved_portrait:
			saved_portrait.get_parent().remove_child(saved_portrait)
	if old:
		root.remove_child(old)
		old.queue_free()
	if player.is_empty() or str(player.get("character_id", "")).is_empty():
		return
	var frame := PanelContainer.new()
	frame.name = "PlayerInfoCard"
	frame.set_meta("snapshot", signature)
	frame.set_meta("character_id", player.character_id)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(frame)
	var layout: Script = load("res://scripts/ui/MatchLayout.gd")
	var compact: bool = layout.mobile(root) or root.size.x < 1100
	var card_width: float = minf(layout.units(root, 210.0), root.size.x * 0.28) if layout.mobile_landscape(root) else (218 if compact else 250)
	var focus: Rect2 = layout.get_table_focus_rect(root)
	frame.position = Vector2(focus.position.x + layout.units(root, 8.0), focus.position.y + layout.units(root, 8.0)) if compact else Vector2(root.size.x - card_width - 18, 76)
	frame.custom_minimum_size.x = card_width
	frame.z_index = layout.Z_EQUIPMENT
	frame.add_theme_stylebox_override("panel", SaloonTheme.panel(Color("#3c3028"), Color("#b99058"), 12))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(column)
	var portrait: Control = saved_portrait if saved_portrait else load("res://scripts/ui/CharacterPortrait.gd").new()
	column.add_child(portrait)
	if not saved_portrait:
		portrait.configure(player.character_id, 88 if compact else 115)
	else:
		var portrait_height: int = 88 if compact else 115
		if portrait.custom_minimum_size.y != portrait_height:
			portrait.custom_minimum_size.y = portrait_height
			portrait.viewport.size.y = portrait_height
			portrait.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	label(player.character.display_name, 19 if compact else 22, column)
	label("%s · %d/%d máu · %d lá" % [player.display_name, player.current_hp, player.max_hp, player.hand_count], 15, column)
	var equipment: Array = player.get("equipment_ids", []).map(func(key): return CardData.data(key).name)
	label("%s · Tầm %d\n%s" % [CardData.data(player.get("weapon_id", "")).get("name", "Colt .45"), player.weapon_range, ", ".join(equipment)], 14, column)
	var role: String = str(player.get("public_role", ""))
	if int(player.player_id) == local_id():
		role = str(NetworkManager.private_state.get("role", role))
	label(TextCatalog.text(role) if not role.is_empty() else "Vai trò bí mật", 14, column)
	var ability := label(CharacterData.ability_icon(player.character.ability_id) + " " + player.character.ability_description_vi, 15, column)
	ability.custom_minimum_size.x = card_width - 28
	for child in column.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_sid_picker() -> void:
	sid_mode = true
	sid_cards.clear()
	refresh()

func build_debug(parent: Node, state: Dictionary) -> void:
	var box := VBoxContainer.new()
	parent.add_child(box)
	var picker := OptionButton.new()
	box.add_child(picker)
	for p in state.players:
		picker.add_item(p.display_name, p.player_id)
		if p.player_id == debug_target:
			picker.selected = picker.item_count - 1
	picker.item_selected.connect(func(index): debug_target = picker.get_item_id(index))
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	for operation in ["Reveal Roles", "Give Shoot", "Draw Card", "Damage Player", "Heal Player", "Next Turn", "Force Win Check"]:
		var debug_button := button(operation, func(): intent("debug", {"operation": operation, "target": debug_target}), grid)
		debug_button.add_theme_font_size_override("font_size", 15)
	if OS.is_debug_build() and NetworkManager.is_authority():
		button("KIỂM TRA BỘ BÀI", show_deck_inspector, box)

func show_deck_inspector() -> void:
	if not OS.is_debug_build() or not NetworkManager.is_authority():
		return
	var box := modal()
	label("DEBUG • BỘ BÀI / VÙNG / CHỦ SỞ HỮU", 20, box)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = minf(420, root.size.y - 200)
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for card in GameManager.debug_card_zones():
		label("#%d · %s · %s · %s · người %d" % [card.instance_id, card.card_data_id, CardInstance.corner(card), card.zone, card.owner], 14, rows)
	button("ĐÓNG", refresh, box)

func show_audio_settings() -> void:
	var box := modal()
	label("ÂM THANH", 26, box)
	var labels := {"Master": "Âm lượng tổng", "Music": "Âm nhạc", "SFX": "Hiệu ứng", "Ambient": "Môi trường", "UI": "Giao diện"}
	for bus in labels:
		var row := HBoxContainer.new()
		box.add_child(row)
		var title := label(labels[bus], 17, row)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var slider := HSlider.new()
		slider.name = "Volume" + bus
		slider.custom_minimum_size.x = 220
		slider.max_value = 1
		slider.step = 0.01
		slider.value = AudioManager.volumes[bus]
		row.add_child(slider)
		slider.value_changed.connect(func(value): AudioManager.set_volume(bus, value))
	var mute := CheckButton.new()
	mute.text = "Tắt âm"
	mute.button_pressed = AudioManager.muted
	box.add_child(mute)
	mute.toggled.connect(AudioManager.set_muted)
	if OS.is_debug_build():
		var debug := VBoxContainer.new()
		box.add_child(debug)
		button("DEBUG ÂM THANH +", func():
			if debug.get_child_count() > 1:
				return
			for cue in ["bang", "dodge", "draw", "explosion", "jail", "button"]:
				button("Thử: " + cue, func(): AudioManager.play_gameplay(cue), debug)
			label(str(AudioManager.volumes), 13, debug), debug)
	button("ĐÓNG", func(): clear_game_modal(); refresh(), box)

func show_visual_settings() -> void:
	var box := modal()
	label("CHẤT LƯỢNG HÌNH ẢNH", 24, box)
	label("Nhân vật, bài và mục tiêu luôn hiển thị đầy đủ ở mọi mức.", 16, box)
	for entry in [["LOW", "THẤP · Ít hạt, không bóng"], ["MEDIUM", "VỪA · Web / điện thoại"], ["HIGH", "CAO · Bóng cho desktop"]]:
		button(entry[1], func(): VisualSettings.set_quality(entry[0]); refresh(), box)
	label("Đang dùng: " + VisualSettings.level, 16, box)
	button("ĐÓNG", func(): clear_game_modal(); refresh(), box)
