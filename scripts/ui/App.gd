extends Node

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

func _ready() -> void:
	add_child(load("res://scripts/ui/WebLayout.gd").new())
	var theme := SaloonTheme.create()
	canvas = CanvasLayer.new()
	add_child(canvas)
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = theme
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)
	NetworkManager.updated.connect(refresh)
	NetworkManager.error_received.connect(func(message): error_text = message; refresh())
	NetworkManager.visual_event.connect(func(a, k, t):
		if is_instance_valid(table):
			table.animate(a, k, t))
	NetworkManager.table_event.connect(func(event):
		if is_instance_valid(table):
			table.presentation(event))
	refresh()
	if OS.has_feature("web") and OS.is_debug_build() and bool(JavaScriptBridge.eval("new URLSearchParams(location.search).get('e2e') === '1'")):
		var test_bridge: Node = load("res://scripts/network/BrowserTestBridge.gd").new()
		test_bridge.app = self
		add_child(test_bridge)

func _process(_delta: float) -> void:
	if is_instance_valid(reaction_label):
		reaction_label.text = TextCatalog.text("Respond in %.1f seconds") % maxf(0, reaction_until - Time.get_ticks_msec() / 1000.0)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if selected >= 0 or sid_mode:
			selected = -1
			sid_mode = false
			sid_cards.clear()
		elif not NetworkManager.public_state.is_empty() and NetworkManager.public_state.get("started", false):
			menu_open = not menu_open
		refresh()

func label(text: String, size: int = 18, parent: Node = content) -> Label:
	var node := Label.new()
	node.text = TextCatalog.text(text)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_font_size_override("font_size", size)
	parent.add_child(node)
	return node

func button(text: String, callback: Callable, parent: Node = content, disabled: bool = false) -> Button:
	var node := Button.new()
	node.text = TextCatalog.text(text)
	node.tooltip_text = node.text
	node.disabled = disabled
	node.pressed.connect(callback)
	node.pressed.connect(func(): presentation_feedback.emit("button"))
	node.mouse_entered.connect(func():
		if not node.disabled:
			node.create_tween().tween_property(node, "modulate", Color("#ffe4af"), 0.12))
	node.mouse_exited.connect(func(): node.create_tween().tween_property(node, "modulate", Color.WHITE, 0.16))
	parent.add_child(node)
	return node

func refresh() -> void:
	for child in root.get_children():
		# A host button can synchronously publish state while still emitting pressed.
		# Detach the old screen now and destroy it after signal delivery completes.
		root.remove_child(child)
		child.queue_free()
	reaction_label = null
	var state: Dictionary = NetworkManager.public_state
	var in_game: bool = not state.is_empty() and state.get("started", false)
	if in_game and not is_instance_valid(table):
		table = load("res://scenes/game/GameTable.tscn").instantiate()
		add_child(table)
		table.targeting.target_chosen.connect(play_selected)
		table.targeting.cancelled.connect(func(): selected = -1; refresh())
		table.targeting.world_chosen.connect(func(token):
			if is_instance_valid(match_hud):
				match_hud.world_action(token))
	elif not in_game and is_instance_valid(table):
		table.free()
		table = null
	var backdrop: Control
	if in_game and hud_match != int(state.match_id):
		hud_match = state.match_id
		selected = -1
		sid_mode = false
		sid_cards.clear()
		menu_open = false
		noticed_turn = -1
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
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	if not in_game:
		var inset: int = maxi(24, int((root.size.x - (880 if not state.is_empty() else 760)) / 2))
		margin.add_theme_constant_override("margin_left", inset)
		margin.add_theme_constant_override("margin_right", inset)
		margin.add_theme_constant_override("margin_top", 18 if root.size.y < 800 else 48)
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
		frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		frame.add_theme_stylebox_override("panel", SaloonTheme.panel(Color(0.065, 0.12, 0.16, 0.96), SaloonTheme.GOLD, 28))
		scroll.add_child(frame)
		frame.add_child(content)
	if state.is_empty():
		build_menu()
	elif not in_game:
		build_lobby(state)
	else:
		build_game(state)
	if not error_text.is_empty():
		var warning := PanelContainer.new()
		warning.add_theme_stylebox_override("panel", SaloonTheme.panel(Color("#4c2e2c"), Color("#dd8b62")))
		content.add_child(warning)
		var notice := HBoxContainer.new()
		warning.add_child(notice)
		var message := label(TextCatalog.message(error_text), 16, notice)
		message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button("Dismiss", func(): error_text = ""; refresh(), notice)

func build_menu() -> void:
	var ornament := label("✦  SALOON NIGHTS  ✦", 16)
	ornament.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ornament.add_theme_color_override("font_color", SaloonTheme.GOLD)
	var title := label("WILD WEST\nPARTY ONLINE", 30 if root.size.x < 900 else 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", SaloonTheme.GOLD)
	title.add_theme_color_override("font_shadow_color", Color("#080f17"))
	title.add_theme_constant_override("shadow_offset_y", 4)
	var pulse := title.create_tween().set_loops()
	pulse.tween_property(title, "modulate", Color("#f5c879"), 1.8).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(title, "modulate", Color.WHITE, 1.8).set_trans(Tween.TRANS_SINE)
	var subtitle := label("A private saloon. A hidden allegiance. One last card.", 16)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(HSeparator.new())
	if NetworkManager.connecting:
		label("Connecting to the host…", 24)
		button("CANCEL", leave)
		return
	var space := Control.new()
	space.custom_minimum_size.y = 12
	content.add_child(space)
	if screen == "main":
		button("HOST GAME", func(): screen = "host"; refresh())
		button("JOIN GAME", func(): screen = "join"; refresh())
		if not OS.has_feature("web"):
			button("QUIT", func(): get_tree().quit())
		return
	label("HOST A SALOON" if screen == "host" else "JOIN A SALOON", 26)
	label("Player name")
	name_field = LineEdit.new()
	name_field.text = NetworkManager.local_name
	name_field.max_length = 24
	content.add_child(name_field)
	if screen == "join":
		label("MÃ PHÒNG")
		room_field = LineEdit.new()
		room_field.name = "RoomCode"
		room_field.placeholder_text = "AB7KQ2"
		room_field.max_length = 6
		content.add_child(room_field)
	button("HOST" if screen == "host" else "JOIN", connect_game)
	button("BACK", func(): screen = "main"; refresh())

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
	NetworkManager.leave()

func build_game(state: Dictionary) -> void:
	var own: Dictionary = NetworkManager.private_state
	if own.get("match_id", state.match_id) != state.match_id:
		own = {}
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
	overlay = ColorRect.new()
	overlay.color = Color(0.025, 0.03, 0.05, 0.96)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = minf(720, root.size.x - 112)
	box.add_theme_constant_override("separation", 20)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", SaloonTheme.panel(Color("#172b37"), SaloonTheme.GOLD, 28))
	center.add_child(frame)
	frame.add_child(box)
	var enter := frame.create_tween()
	frame.modulate = Color(1, 1, 1, 0.75)
	enter.tween_property(frame, "modulate", Color.WHITE, 0.18)
	return box

func show_role(role: String, match_number: int) -> void:
	var box := modal()
	label("YOUR ROLE", 24, box)
	var badge := label("✦  " + TextCatalog.text(role) + "  ✦", 40, box)
	badge.add_theme_color_override("font_color", SaloonTheme.GOLD)
	var goals := {"SHERIFF": "Eliminate every Outlaw and the Renegade.",
		"DEPUTY": "Protect the Sheriff and eliminate the enemies.",
		"OUTLAW": "Eliminate the Sheriff.", "RENEGADE": "Be the last living player."}
	label(goals.get(role, ""), 21, box)
	label("The Sheriff is public. Keep your allegiance secret.", 17, box)
	button("CONTINUE", func(): seen_role = match_number; refresh(), box)

func show_reaction(request: Dictionary) -> void:
	var box := modal()
	var kind: String = request.reaction_type
	label(request.get("title", {"dodge": "YOU ARE BEING SHOT", "survive": "USE DRINK TO SURVIVE?", "duel": "SHOWDOWN • RESPOND WITH SHOOT"}.get(kind, "CHỌN HÀNH ĐỘNG")), 25, box)
	reaction_label = label("", 22, box)
	reaction_until = Time.get_ticks_msec() / 1000.0 + float(request.remaining)
	var request_id: int = request.request_id
	if request.has("cards"):
		var choices: Node = load("res://scripts/ui/ChoicePanel.gd").new()
		box.add_child(choices)
		choices.configure(self, request.cards, int(request.get("pick_count", 1)), func(ids):
			intent("reaction", {"request": request_id, "accept": true, "cards": ids}))
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
	label("CHỌN NHÂN VẬT", 32, box)
	label("Chỉ bạn thấy hai lựa chọn này. Hết giờ: máy chủ chọn ngẫu nhiên.", 17, box)
	reaction_label = label("", 18, box)
	reaction_until = Time.get_ticks_msec() / 1000.0 + float(own.get("character_remaining", 25))
	var options: Array = own.get("character_options", [])
	if own.get("character_chosen", false):
		label("ĐÃ CHỌN • Đang chờ những người chơi còn lại...", 22, box)
	for data in options:
		var key: String = data.character_id
		var option := button("%s • %d Máu\n%s" % [data.display_name, data.max_hp, data.ability_description_vi],
			func(): intent("character", {"character": key}), box)
		option.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		option.custom_minimum_size = Vector2(minf(660, root.size.x - 112), 100)

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
