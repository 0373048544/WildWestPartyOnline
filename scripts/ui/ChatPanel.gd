class_name ChatPanel
extends Control

const MAX_RENDERED := 40

var app: Node
var expanded := false
var blocked := true
var unread := 0
var rendered: Dictionary = {}
var room_code := ""
var last_submit_text := ""
var last_submit_at := 0
var preview_generation := 0
var next_keyboard_poll := 0

var toggle_button: Button
var panel: PanelContainer
var message_scroll: ScrollContainer
var message_list: VBoxContainer
var input: LineEdit
var send_button: Button
var close_button: Button
var preview: Label
var chat_margin: MarginContainer
var chat_body: VBoxContainer
var chat_title: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = load("res://scripts/ui/MatchLayout.gd").Z_CHAT
	_build()
	get_viewport().size_changed.connect(layout_chat)
	set_process(false)

func setup(owner_app: Node) -> void:
	app = owner_app
	if is_instance_valid(app) and is_instance_valid(app.get("web_layout")):
		app.web_layout.register_text_input(input)
	if not NetworkManager.chat_message.is_connected(_on_message):
		NetworkManager.chat_message.connect(_on_message)
	if not NetworkManager.chat_history.is_connected(_on_history):
		NetworkManager.chat_history.connect(_on_history)
	if not NetworkManager.chat_error.is_connected(_on_error):
		NetworkManager.chat_error.connect(_on_error)
	_on_history(NetworkManager.chat_messages)

func _build() -> void:
	toggle_button = load("res://scripts/ui/WesternButton.gd").new()
	toggle_button.name = "ChatToggle"
	toggle_button.text = "CHAT"
	toggle_button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	toggle_button.mouse_filter = Control.MOUSE_FILTER_STOP
	toggle_button.pressed.connect(open_chat)
	add_child(toggle_button)
	# WesternButton applies its default ellipsis in _ready(); restore the compact
	# chat label contract after it has entered the tree.
	toggle_button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING

	panel = PanelContainer.new()
	panel.name = "ChatWindow"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", SaloonTheme.panel(Color(0.075, 0.052, 0.035, 0.97), SaloonTheme.GOLD, 14))
	panel.gui_input.connect(func(event):
		if event is InputEventScreenTouch or event is InputEventScreenDrag:
			accept_event())
	add_child(panel)
	chat_margin = MarginContainer.new()
	chat_margin.name = "ChatMargin"
	for side in ["left", "right", "top", "bottom"]:
		chat_margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(chat_margin)
	chat_body = VBoxContainer.new()
	chat_body.name = "ChatBody"
	chat_body.add_theme_constant_override("separation", 7)
	chat_margin.add_child(chat_body)
	var header := HBoxContainer.new()
	chat_body.add_child(header)
	chat_title = Label.new()
	chat_title.name = "ChatTitle"
	chat_title.text = "TRÒ CHUYỆN"
	chat_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_title.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	chat_title.add_theme_color_override("font_color", SaloonTheme.GOLD)
	chat_title.add_theme_font_size_override("font_size", 18)
	header.add_child(chat_title)
	close_button = load("res://scripts/ui/WesternButton.gd").new()
	close_button.name = "ChatClose"
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(44, 44)
	close_button.pressed.connect(close_chat)
	header.add_child(close_button)

	message_scroll = ScrollContainer.new()
	message_scroll.name = "ChatMessages"
	message_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	message_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	message_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	message_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	chat_body.add_child(message_scroll)
	message_list = VBoxContainer.new()
	message_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_list.add_theme_constant_override("separation", 4)
	message_scroll.add_child(message_list)

	var composer := HBoxContainer.new()
	composer.add_theme_constant_override("separation", 6)
	chat_body.add_child(composer)
	input = LineEdit.new()
	input.name = "ChatInput"
	input.placeholder_text = "Nhắn gì đó..."
	input.max_length = ChatRoomState.MAX_LENGTH
	input.virtual_keyboard_enabled = true
	input.clear_button_enabled = true
	input.custom_minimum_size.y = 46
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.text_submitted.connect(func(_value): submit())
	input.focus_entered.connect(func(): set_process(OS.has_feature("web") or OS.has_feature("mobile")); layout_chat())
	input.focus_exited.connect(func(): set_process(false); layout_chat())
	composer.add_child(input)
	send_button = load("res://scripts/ui/WesternButton.gd").new()
	send_button.name = "ChatSend"
	send_button.text = "GỬI"
	send_button.custom_minimum_size = Vector2(64, 46)
	send_button.pressed.connect(submit)
	composer.add_child(send_button)

	preview = Label.new()
	preview.name = "ChatPreview"
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	preview.add_theme_stylebox_override("normal", SaloonTheme.inset_panel(8))
	preview.add_theme_color_override("font_color", SaloonTheme.CREAM)
	preview.add_theme_font_size_override("font_size", 14)
	preview.hide()
	add_child(preview)
	panel.hide()
	toggle_button.hide()

func sync_state(state: Dictionary, own: Dictionary, has_modal: bool) -> void:
	var active := not state.is_empty() and bool(state.get("started", false))
	visible = active
	var next_room := str(state.get("room_code", "ENET" if NetworkManager.mode == "enet" else ""))
	if next_room != room_code:
		room_code = next_room
		clear_rows()
		_on_history(NetworkManager.chat_messages)
	var reaction_kind := str(own.get("reaction", {}).get("reaction_type", ""))
	var public_choice := str(state.get("choice_type", ""))
	# Any authoritative choice deserves uncontested touch space: attacks, survival,
	# card-zone targeting, character abilities, Store and Bách Hóa.
	var urgent := not reaction_kind.is_empty() or not public_choice.is_empty()
	set_blocked(not active or has_modal or urgent or str(state.get("phase", "")) == "CHARACTER_SELECTION" or not str(state.get("winner", "")).is_empty())
	layout_chat()

func set_blocked(value: bool) -> void:
	blocked = value
	if blocked:
		close_chat()
	if is_instance_valid(toggle_button):
		toggle_button.visible = visible and not blocked and not expanded

func open_chat() -> void:
	if blocked:
		return
	expanded = true
	unread = 0
	_update_badge()
	preview.hide()
	panel.show()
	toggle_button.hide()
	layout_chat()
	if VisualSettings.reduced_motion:
		panel.modulate = Color.WHITE
	else:
		panel.modulate = Color(1, 1, 1, 0.25)
		panel.create_tween().tween_property(panel, "modulate", Color.WHITE, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	call_deferred("_scroll_to_bottom", true)

func close_chat() -> void:
	expanded = false
	if is_instance_valid(panel):
		panel.hide()
	if is_instance_valid(toggle_button):
		toggle_button.visible = visible and not blocked
	if is_instance_valid(input) and input.has_focus():
		_finish_input()
	set_process(false)
	layout_chat()

func submit() -> void:
	var text := ChatRoomState.sanitize_text(input.text)
	if text.is_empty():
		return
	var now := Time.get_ticks_msec()
	if text == last_submit_text and now - last_submit_at < 250:
		return
	last_submit_text = text
	last_submit_at = now
	NetworkManager.send_chat(text)
	input.clear()
	_finish_input()
	set_process(false)
	layout_chat()

func _on_history(messages: Array) -> void:
	if messages.is_empty() and NetworkManager.chat_room.is_empty():
		clear_rows()
		return
	for message in messages:
		if message is Dictionary:
			append_message(message, false)
	call_deferred("_scroll_to_bottom", true)

func _on_message(message: Dictionary) -> void:
	if not append_message(message, true):
		return
	var own := int(message.get("sender_id", 0)) == NetworkManager.local_player_id()
	if not expanded and not own:
		unread += 1
		_update_badge()
		show_preview(message)

func append_message(message: Dictionary, _live: bool) -> bool:
	var id := str(message.get("message_id", ""))
	if id.is_empty() or rendered.has(id):
		return false
	rendered[id] = true
	var row := Label.new()
	row.name = "ChatMessage"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.text = "%s%s: %s" % ["☠ " if bool(message.get("dead", false)) else "", str(message.get("sender_name", "Cao bồi")), str(message.get("text", ""))]
	var layout: Script = load("res://scripts/ui/MatchLayout.gd")
	row.add_theme_font_size_override("font_size", roundi(layout.units(self, 13.0)) if layout.mobile(self) else 15)
	row.add_theme_color_override("font_color", SaloonTheme.CREAM)
	row.add_theme_stylebox_override("normal", SaloonTheme.inset_panel(6))
	message_list.add_child(row)
	while message_list.get_child_count() > MAX_RENDERED:
		var old := message_list.get_child(0)
		for key in rendered.keys():
			if old.get_meta("message_id", "") == key:
				rendered.erase(key)
		old.queue_free()
	row.set_meta("message_id", id)
	if expanded:
		call_deferred("_scroll_to_bottom", false)
	return true

func clear_rows() -> void:
	rendered.clear()
	unread = 0
	if is_instance_valid(message_list):
		for child in message_list.get_children():
			child.queue_free()
	_update_badge()

func show_preview(message: Dictionary) -> void:
	preview_generation += 1
	var generation := preview_generation
	preview.text = "%s: %s" % [str(message.get("sender_name", "Cao bồi")), str(message.get("text", ""))]
	preview.show()
	layout_chat()
	get_tree().create_timer(2.0).timeout.connect(func():
		if generation == preview_generation and not expanded:
			preview.hide())

func _on_error(message: String) -> void:
	if not expanded:
		return
	preview_generation += 1
	preview.text = message
	preview.show()
	layout_chat()

func _update_badge() -> void:
	if is_instance_valid(toggle_button):
		toggle_button.text = "CHAT" if unread <= 0 else "CHAT %d" % unread

func _scroll_to_bottom(force: bool) -> void:
	if not is_instance_valid(message_scroll):
		return
	var bar := message_scroll.get_v_scroll_bar()
	var near_bottom := bar.value >= bar.max_value - bar.page - 36
	if force or near_bottom:
		bar.value = bar.max_value

func layout_chat() -> void:
	if not is_inside_tree():
		return
	var layout: Script = load("res://scripts/ui/MatchLayout.gd")
	var touch: float = float(layout.units(self, 44.0))
	var compact_mobile: bool = bool(layout.mobile(self))
	var panel_padding: int = roundi(layout.units(self, 7.0 if compact_mobile else 10.0))
	for side in ["left", "right", "top", "bottom"]:
		chat_margin.add_theme_constant_override("margin_" + side, panel_padding)
	chat_body.add_theme_constant_override("separation", roundi(layout.units(self, 4.0 if compact_mobile else 7.0)))
	chat_title.add_theme_font_size_override("font_size", roundi(layout.units(self, 15.0)) if compact_mobile else 18)
	toggle_button.add_theme_font_size_override("font_size", roundi(layout.units(self, 12.0)) if compact_mobile else 16)
	panel.add_theme_stylebox_override(
		"panel",
		SaloonTheme.panel(Color(0.075, 0.052, 0.035, 0.97), SaloonTheme.GOLD, 8.0 if compact_mobile else 14.0)
	)
	for row in message_list.get_children():
		if row is Label:
			row.add_theme_font_size_override("font_size", roundi(layout.units(self, 13.0)) if compact_mobile else 15)
	close_button.custom_minimum_size = Vector2(touch, touch)
	input.custom_minimum_size.y = touch
	send_button.custom_minimum_size = Vector2(layout.units(self, 64.0), touch)
	var button_rect: Rect2 = _journal_button_rect(layout)
	if layout.mobile(self):
		button_rect.size.x = minf(button_rect.size.x, layout.units(self, 72.0))
	toggle_button.position = button_rect.position
	toggle_button.size = button_rect.size
	var panel_rect: Rect2 = layout.chat_panel_rect(self)
	panel_rect.position.x = button_rect.position.x
	panel_rect.position.y = button_rect.end.y + layout.units(self, 6.0)
	var keyboard_shift := _keyboard_shift()
	var safe_top: float = layout.safe_rect(self, 8.0).position.y
	panel_rect.position.y = maxf(safe_top, panel_rect.position.y - keyboard_shift)
	var bottom_limit: float = layout.action_rect(self).position.y - layout.units(self, 8.0)
	panel_rect.size.y = minf(panel_rect.size.y, maxf(1.0, bottom_limit - panel_rect.position.y))
	panel.position = panel_rect.position
	panel.custom_minimum_size = panel_rect.size
	panel.size = panel_rect.size
	# Containers may enforce a slightly taller minimum than the calculated short-
	# landscape rect. Keep the real bottom above End Turn/hand, moving upward only
	# as far as the safe viewport permits.
	panel.position.y = maxf(safe_top, minf(panel.position.y, bottom_limit - panel.size.y))
	preview.position = Vector2(button_rect.position.x, button_rect.end.y + layout.units(self, 4.0))
	preview.size = Vector2(minf(layout.units(self, 320.0), layout.safe_rect(self).size.x * 0.75), layout.units(self, 36.0))

func _journal_button_rect(layout: Script) -> Rect2:
	var hud: Node = app.get("match_hud") if is_instance_valid(app) else null
	if is_instance_valid(hud):
		var holder: Node = hud.get_node_or_null("MatchLog")
		if is_instance_valid(holder):
			var child := holder.find_child("ToggleHistory", true, false) as Button
			if is_instance_valid(child) and child.is_visible_in_tree():
				var journal: Rect2 = child.get_global_rect()
				return Rect2(
					Vector2(journal.position.x, journal.end.y + layout.units(self, 4.0)),
					Vector2(
						minf(journal.size.x, layout.units(self, 72.0)) if layout.mobile(self) else journal.size.x,
						maxf(layout.units(self, 40.0), journal.size.y)
					)
				)
	return layout.chat_button_rect(self)

func _keyboard_shift() -> float:
	if not OS.has_feature("web") or not is_instance_valid(input) or not input.has_focus():
		return 0.0
	var css_hidden := float(JavaScriptBridge.eval("Math.max(0,window.innerHeight-(window.visualViewport?.height||window.innerHeight)-(window.visualViewport?.offsetTop||0))"))
	return load("res://scripts/ui/MatchLayout.gd").units(self, css_hidden)

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() >= next_keyboard_poll:
		next_keyboard_poll = Time.get_ticks_msec() + 100
		layout_chat()

func _hide_keyboard() -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_hide()

func _finish_input() -> void:
	if is_instance_valid(app) and app.has_method("finish_text_input"):
		app.finish_text_input(input)
	else:
		if input.has_focus():
			input.release_focus()
		_hide_keyboard()
