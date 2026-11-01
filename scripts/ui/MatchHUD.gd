extends Control

var app: Node
var state: Dictionary
var own: Dictionary
var request: Dictionary
var hand: Control
var preview: Control
var layout: Script = preload("res://scripts/ui/MatchLayout.gd")
var top_signature: String = ""
var log_signature: String = ""
var hand_signature: String = ""
var flow_signature: String = ""
var target_picker: Control
var loadout_panel: Control
var dismissed_picker_request: int = -1


func initialize(owner_app: Node, snapshot: Dictionary, private: Dictionary) -> void:
	app = owner_app
	state = snapshot
	own = private
	request = own.get("reaction", {})
	var request_identity: Dictionary = request.duplicate(true)
	# Remaining time is rendered locally. It must not invalidate the UI tree on
	# every authoritative countdown snapshot.
	request_identity.erase("remaining")
	var next_top_signature := JSON.stringify([
		state.get("current_player", 0),
		state.get("phase", ""),
		request.get("request_id", 0),
		state.get("players", []).map(func(row): return [row.get("player_id", 0), row.get("display_name", "")])
	]) + str(get_window().size)
	var next_log_signature := JSON.stringify(state.get("log", [])) + str(app.log_expanded)
	var next_hand_signature := JSON.stringify([
		own.get("hand", []), own.get("targets", {}), own.get("disabled_reasons", {}),
		request_identity, state.get("phase", ""), state.get("current_player", 0),
		state.get("players", []), app.selected, app.sid_mode, app.sid_cards
	]) + str(get_window().size)
	var next_flow_signature := JSON.stringify([
		state.get("phase", ""), state.get("winner", ""), request_identity,
		app.menu_open, app.seen_role, state.get("match_id", 0),
		own.get("role", ""), own.get("character_chosen", false),
		own.get("character_options", []),
		NetworkManager.mode == "websocket" and NetworkManager.room_client.reconnecting
	])
	var top_changed := next_top_signature != top_signature
	var log_changed := next_log_signature != log_signature
	var hand_changed := next_hand_signature != hand_signature
	var flow_changed := next_flow_signature != flow_signature
	top_signature = next_top_signature
	log_signature = next_log_signature
	hand_signature = next_hand_signature
	flow_signature = next_flow_signature

	if flow_changed:
		app.clear_game_modal()

	if app.sid_mode:
		app.sid_cards = app.sid_cards.filter(
			func(uid):
				return own.get("hand", []).any(
					func(c):
						return c.instance_id == uid
				)
		)

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name = "MatchHUD"

	app.table.targeting.blocked = false

	var targets: Array = own.get("targets", {}).get(app.selected, [])

	if app.selected >= 0 and targets.is_empty():
		app.selected = -1

	app.table.update_state(
		state,
		app.local_id(),
		targets
	)

	var reaction_source: int = int(
		request.get("source_player_id", 0)
	)

	app.table.set_reaction_focus(
		reaction_source,
		app.local_id() if reaction_source > 0 else 0
	)

	app.table.objects.sync(
		state,
		app.local_id(),
		request
	)
	_sync_table_panels()

	if app.selected >= 0:
		var selected_cards: Array = own.get("hand", []).filter(
			func(c):
				return c.instance_id == app.selected
		)

		var style: String = "GENERIC"

		if not selected_cards.is_empty():
			style = {
				"shoot": "BANG",
				"dodge": "BANG",
				"showdown": "DUEL",
				"panic": "STEAL",
				"cat_balou": "DISCARD",
				"jail": "JAIL"
			}.get(
				selected_cards[0].card_data_id,
				"GENERIC"
			)

		app.table.targeting.begin_targeting(
			app.selected,
			app.local_id(),
			targets,
			own.get("target_info", {}),
			style
		)

	else:
		app.table.targeting.cancel_targeting(false)

	if top_changed:
		_free_named("TopBar")
		build_top()

	if log_changed:
		_free_named("MatchLog")
		build_log()

	if state.phase == "CHARACTER_SELECTION":
		app.table.targeting.blocked = true
		if is_instance_valid(hand):
			hand.visible = false
		if flow_changed:
			app.show_character_selection(own)
		return

	if not state.winner.is_empty():
		if is_instance_valid(hand):
			hand.visible = false
		if flow_changed:
			build_result()
		return

	if hand_changed or not is_instance_valid(hand):
		build_hand()
	elif is_instance_valid(hand):
		hand.visible = true

	if app.menu_open:
		if flow_changed:
			build_pause()

	elif own.has("role") and app.seen_role != int(state.match_id):
		app.table.targeting.blocked = true
		if flow_changed:
			app.show_role(
				own.role,
				state.match_id
			)

	elif not request.is_empty() and not [
		"dodge",
		"survive",
		"duel",
		"indians",
		"transfer",
		"store",
		"draw_steal",
		"draw_discard"
	].has(str(request.get("reaction_type", ""))):

		var reaction_type: String = str(
			request.get("reaction_type", "")
		)

		if [
			"draw",
			"receive",
			"card_received",
			"notify",
			"notice"
		].has(reaction_type):

			app.table.targeting.blocked = false

			if flow_changed and is_instance_valid(app.personal_toasts):
				app.personal_toasts.show_notice(
					str(request.get("title", "Thông báo")),
					str(request.get("detail", "")),
					"positive",
					"▣",
					2.0
				)

		elif flow_changed:
			app.table.targeting.blocked = true
			app.show_reaction(request)


func _free_named(node_name: String) -> void:
	var old: Node = get_node_or_null(node_name)
	if old:
		remove_child(old)
		old.queue_free()

func _sync_table_panels() -> void:
	if not is_instance_valid(loadout_panel):
		loadout_panel = load("res://scenes/ui/PlayerLoadoutPanel.tscn").instantiate()
		add_child(loadout_panel)
		loadout_panel.card_inspected.connect(show_preview)
	for row in state.get("players", []):
		if int(row.get("player_id", 0)) == app.local_id():
			loadout_panel.update_loadout(row)
			break

	var is_transfer := str(request.get("reaction_type", "")) == "transfer"
	if not is_transfer:
		if is_instance_valid(target_picker):
			target_picker.dismiss()
		dismissed_picker_request = -1
		return

	if not is_instance_valid(target_picker):
		target_picker = load("res://scenes/ui/TargetCardPicker.tscn").instantiate()
		add_child(target_picker)
		target_picker.choice_selected.connect(_submit_picker_choice)
		target_picker.cancel_requested.connect(_dismiss_target_picker)
	if int(request.get("request_id", 0)) != dismissed_picker_request:
		target_picker.present(app, request, state)

func _submit_picker_choice(token: Dictionary) -> void:
	var args := {
		"request": int(request.get("request_id", 0)),
		"accept": true,
		"option": str(token.get("option", ""))
	}
	if token.has("card"):
		args["card"] = int(token.card)
	app.intent("reaction", args)

func _dismiss_target_picker() -> void:
	dismissed_picker_request = int(request.get("request_id", 0))
	if is_instance_valid(target_picker):
		target_picker.dismiss()

func _reopen_target_picker() -> void:
	dismissed_picker_request = -1
	if is_instance_valid(target_picker):
		target_picker.present(app, request, state)


func text(
	value: String,
	font_size: int = 16,
	parent: Node = self
) -> Label:
	var item: Label = app.label(
		value,
		font_size,
		parent
	)

	item.mouse_filter = Control.MOUSE_FILTER_IGNORE

	return item


func action(
	value: String,
	callback: Callable,
	parent: Node,
	disabled: bool = false
) -> Button:
	var item: Button = app.button(
		value,
		callback,
		parent,
		disabled
	)

	item.add_theme_font_size_override(
		"font_size",
		14
	)

	item.custom_minimum_size.y = 42

	if bool(
		load("res://scripts/ui/MatchLayout.gd").mobile(self)
	):
		item.custom_minimum_size.y = float(
			layout.action_height(self)
		)

		item.custom_minimum_size.x = float(
			layout.units(self, 48.0)
		)

	return item


func build_top() -> void:
	var bar := Control.new()

	bar.name = "TopBar"

	add_child(bar)

	bar.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_WIDE
	)

	bar.offset_bottom = (
		layout.get_mobile_banner_height(self)
		if layout.mobile(self)
		else 52.0
	)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var current_player_name: String = ""

	for player in state.players:
		if player.player_id == state.current_player:
			current_player_name = player.display_name

	var title: String = (
		"LƯỢT CỦA BẠN"
		if state.current_player == app.local_id()
		else "LƯỢT CỦA " + current_player_name
	)

	var phase: String = TextCatalog.text(
		state.phase
	)

	var strip: Control = load(
		"res://scripts/ui/HUDMatchStrip.gd"
	).new()

	bar.add_child(strip)

	var strip_width: float = minf(570.0, size.x - 260.0)
	if layout.mobile_landscape(self):
		strip_width = minf(layout.units(self, 470.0), size.x - layout.units(self, 224.0))

	strip.position = Vector2(
		(size.x - strip_width) / 2.0,
		layout.units(self, 4.0) if layout.mobile_landscape(self) else 8.0
	)

	strip.custom_minimum_size = Vector2(
		strip_width,
		34.0
	)

	strip.configure(
		title,
		phase,
		float(request.get("remaining", 0))
	)

	var menu := action(
		"MENU",
		func():
			app.menu_open = true
			app.refresh(),
		bar
	)

	menu.position = Vector2(
		size.x - 86.0,
		layout.units(self, 2.0) if layout.mobile_landscape(self) else 8.0
	)

	menu.size = Vector2(
		74.0,
		layout.units(self, 42.0) if layout.mobile_landscape(self) else 42.0
	)

	if bool(
		load("res://scripts/ui/MatchLayout.gd").portrait(self)
	):
		menu.size.y = 68.0

	menu.name = "PauseButton"
	menu.tooltip_text = "Menu · Luật chơi · Rời trận"

	if bool(layout.mobile(self)):
		var safe: Vector4 = layout.safe_insets(self)

		strip.position.y += safe.y

		strip.custom_minimum_size.x = maxf(
			180.0,
			strip_width - safe.x - safe.z
		)

		menu.position.x -= safe.z
		menu.position.y += safe.y


func build_log() -> void:
	var holder := VBoxContainer.new()
	holder.name = "MatchLog"

	add_child(holder)

	holder.position = Vector2(
		12.0,
		8.0
	)

	if bool(layout.mobile(self)):
		var safe: Vector4 = layout.safe_insets(self)

		holder.position += Vector2(
			safe.x,
			safe.y
		)

	holder.size.x = (
		minf(320.0, size.x * 0.28)
		if app.log_expanded
		else 105.0
	)

	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var toggle := action(
		"NHẬT KÝ  −"
		if app.log_expanded
		else "NHẬT KÝ  +",
		func():
			app.log_expanded = not app.log_expanded
			app.refresh(),
		holder
	)

	toggle.custom_minimum_size.y = 30
	toggle.add_theme_font_size_override(
		"font_size",
		12
	)

	if not app.log_expanded:
		return

	var entries: Array = state.log.slice(-2)

	if app.log_expanded:
		entries = state.log

	var scroller := ScrollContainer.new()

	holder.add_child(scroller)

	scroller.custom_minimum_size = Vector2(
		0,
		180
	)

	scroller.mouse_filter = (
		Control.MOUSE_FILTER_PASS
		if app.log_expanded
		else Control.MOUSE_FILTER_IGNORE
	)

	var rows := VBoxContainer.new()

	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE

	scroller.add_child(rows)

	for entry in entries:
		text(
			entry,
			12,
			rows
		)


func build_hand() -> void:
	_free_named("HandActions")
	var local: Dictionary = {}

	for player in state.players:
		if player.player_id == app.local_id():
			local = player

	var footer := HBoxContainer.new()

	add_child(footer)

	footer.name = "HandActions"

	footer.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_WIDE
	)

	footer.offset_left = 18
	footer.offset_right = -18
	footer.offset_top = -224
	footer.offset_bottom = -182

	var mobile_layout: bool = bool(
		load("res://scripts/ui/MatchLayout.gd").mobile(self)
	)

	var visible_hand: float = float(
		load("res://scripts/ui/MatchLayout.gd").hand_height(
			self,
			app.selected >= 0
		)
	)

	var safe: Vector4 = (
		layout.safe_insets(self)
		if mobile_layout
		else Vector4.ZERO
	)

	if mobile_layout:
		footer.offset_left = safe.x + 12
		footer.offset_right = -safe.z - 12

		footer.offset_top = (
			-safe.w
			- visible_hand
			- float(layout.action_height(self))
			- 4.0
		)

		footer.offset_bottom = (
			-safe.w
			- visible_hand
			- 4.0
		)

		footer.z_index = 200

	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var message: String = "BÀI CỦA BẠN"

	if not local.get("is_alive", false):
		message = "BẠN ĐÃ BỊ LOẠI · ĐANG THEO DÕI"
	elif int(state.get("choice_player", 0)) > 0:
		var chooser_name := "CAO BỒI"
		for chooser in state.get("players", []):
			if int(chooser.get("player_id", 0)) == int(state.choice_player):
				chooser_name = str(chooser.get("display_name", chooser_name))
				break
		message = "BÁCH HÓA · ĐẾN LƯỢT %s CHỌN BÀI" % chooser_name

	elif app.sid_mode:
		message = (
			"SID · CHỌN 2 LÁ ĐỂ BỎ (%d/2)"
			% app.sid_cards.size()
		)

	elif not request.is_empty():
		message = (
			"CHỌN LÁ PHẢN ỨNG ĐƯỢC TÔ SÁNG"
			if [
				"dodge",
				"duel",
				"indians",
				"survive"
			].has(
				str(
					request.get(
						"reaction_type",
						""
					)
				)
			)
			else reaction_message(request)
		)

		if str(
			request.get(
				"reaction_type",
				""
			)
		) == "transfer":
			message = "CHẠM VÙNG TAY KÍN / TRANG BỊ ĐƯỢC ĐÁNH DẤU"

		elif str(
			request.get(
				"reaction_type",
				""
			)
		) == "store":
			message = "CỬA HÀNG · CHẠM LÁ BÀI TRÊN BÀN"

	elif state.phase == "DISCARD_PHASE" and state.current_player == app.local_id():
		message = (
			"BỎ %d LÁ · CHẠM BÀI ĐỂ BỎ"
			% maxi(
				0,
				own.get("hand", []).size()
				- int(
					local.get(
						"current_hp",
						0
					)
				)
			)
		)

	elif app.selected >= 0:
		message = "CHẠM MỤC TIÊU"

	var prompt := text(
		message,
		14,
		footer
	)

	prompt.name = "HandPrompt"
	prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	prompt.add_theme_color_override(
		"font_color",
		SaloonTheme.GOLD
	)

	var character: Dictionary = local.get(
		"character",
		{}
	)

	prompt.tooltip_text = "%s · %s\n%s" % [
		character.get(
			"display_name",
			""
		),
		TextCatalog.text(
			own.get(
				"role",
				""
			)
		),
		character.get(
			"ability_description_vi",
			""
		)
	]

	if app.sid_mode:
		action(
			"HỒI 1 MÁU",
			func():
				app.intent(
					"ability",
					{
						"cards":
						app.sid_cards.duplicate()
					}
				)

				app.sid_mode = false
				app.sid_cards.clear()
				app.refresh(),
			footer,
			app.sid_cards.size() != 2
		).name = "SidConfirm"

		action(
			"HỦY",
			cancel_selection,
			footer
		)

	elif not request.is_empty():
		var reaction_type: String = str(
			request.get(
				"reaction_type",
				""
			)
		)

		if reaction_type == "draw_steal" or reaction_type == "draw_discard":
			prompt.text = (
				"CHỌN CHỒNG RÚT / CHỒNG BỎ"
				if reaction_type == "draw_discard"
				else "CHỌN CHỒNG RÚT HOẶC TAY BÀI ĐỐI THỦ"
			)
		elif reaction_type == "transfer":
			action(
				"CHỌN BÀI",
				_reopen_target_picker,
				footer
			).name = "OpenTargetCardPicker"

	elif app.selected >= 0:
		action(
			"× HỦY",
			cancel_selection,
			footer
		).name = "CancelSelection"

	elif state.current_player == app.local_id() and state.phase == "ACTION_PHASE":
		action(
			"END TURN",
			func():
				app.intent("end"),
			footer
		).name = "EndTurn"

	if (
		local.get("is_alive", false)
		and own.get("ability_id", "") == "discard_heal"
		and int(local.get("current_hp", 0))
		< int(local.get("max_hp", 4))
	):
		var sid := action(
			"+",
			func():
				app.sid_mode = not app.sid_mode
				app.sid_cards.clear()
				app.refresh(),
			footer
		)

		sid.name = "SidAbility"
		sid.tooltip_text = "Sid Ketchum · Chọn bỏ 2 lá để hồi 1 máu"

	var selected_ids: Array = (
		app.sid_cards.duplicate()
		if app.sid_mode
		else [app.selected]
	)

	var usable: Array = []

	var reacting: bool = (
		not request.is_empty()
		and [
			"dodge",
			"duel",
			"indians",
			"survive"
		].has(
			str(
				request.get(
					"reaction_type",
					""
				)
			)
		)
	)

	for card in own.get("hand", []):
		if (
			app.sid_mode
			or (
				state.phase == "DISCARD_PHASE"
				and state.current_player == app.local_id()
			)
			or (
				reacting
				and request.get(
					"allowed_card_types",
					[]
				).has(
					card.instance_id
				)
			)
			or (
				request.is_empty()
				and not own.get(
					"targets",
					{}
				).get(
					card.instance_id,
					[]
				).is_empty()
			)
		):
			usable.append(
				card.instance_id
			)

	if not is_instance_valid(hand):
		hand = load(
			"res://scripts/ui/HandFan.gd"
		).new()
		hand.name = "HandFan"
		add_child(hand)
		hand.card_clicked.connect(handle_card)
		hand.preview_requested.connect(show_preview)
		hand.preview_closed.connect(close_preview)

	hand.visible = true

	hand.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_WIDE
	)

	hand.offset_left = 18
	hand.offset_right = -18
	hand.offset_top = -182
	hand.offset_bottom = -4

	if mobile_layout:
		hand.offset_left = safe.x + 12
		hand.offset_right = -safe.z - 12

		hand.offset_top = (
			-safe.w
			- visible_hand
			- float(
				layout.hand_lift(
					self,
					app.selected >= 0
				)
			)
		)

		hand.offset_bottom = -safe.w

		hand.set_meta(
			"target_mode",
			app.selected >= 0
		)

	hand.configure(
		own.get("hand", []),
		usable,
		selected_ids,
		reacting,
		own.get(
			"disabled_reasons",
			{}
		)
	)



func _unhandled_input(event: InputEvent) -> void:
	if (
		(
			event is InputEventMouseButton
			or event is InputEventScreenTouch
		)
		and event.pressed
	):
		close_preview()


func handle_card(uid: int) -> void:
	AudioManager.play_card(
		"select"
	)

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
		if request.get(
			"allowed_card_types",
			[]
		).has(uid):
			app.intent(
				"reaction",
				{
					"request":
						request.request_id,
					"accept":
						true,
					"card":
						uid
				}
			)

		return

	if app.selected == uid:
		cancel_selection()
		return

	app.choose_card_action(uid)


func cancel_selection() -> void:
	AudioManager.play_card(
		"release"
	)

	app.selected = -1
	app.sid_mode = false
	app.sid_cards.clear()

	app.refresh()


func world_action(token: Dictionary) -> void:
	if app.menu_open or request.is_empty():
		return

	var args: Dictionary = {
		"request":
			request.request_id,
		"accept":
			true
	}

	match token.get("kind", ""):
		"market":
			args["cards"] = [
				token.card
			]

		"zone":
			args["option"] = (
				str(token.player)
				if str(
					request.get(
						"reaction_type",
						""
					)
				) == "draw_steal"
				else str(token.zone)
			)

			if (
				str(
					request.get(
						"reaction_type",
						""
					)
				) == "transfer"
				and str(token.zone) != "hand"
			):
				args["card"] = int(
					token.get(
						"card",
						0
					)
				)

		"deck":
			args["option"] = "deck"

		"discard":
			args["option"] = "discard"

		_:
			return

	app.intent(
		"reaction",
		args
	)


func show_preview(card: Dictionary) -> void:
	close_preview()

	var mobile_preview: bool = bool(layout.mobile(self))
	var data: Dictionary = CardData.data(card.card_data_id)
	var accent: Color = [
		Color("#bc6449"),
		Color("#6a9b9f"),
		Color("#a38748"),
		Color("#7b719d")
	][int(data.get("type", 0))]
	var unit: float = layout.units(self, 1.0) if mobile_preview else 1.0
	var safe: Vector4 = layout.safe_insets(self) if mobile_preview else Vector4.ZERO
	var preview_width: float
	if layout.mobile_landscape(self):
		preview_width = clampf(size.x * 0.31, 188.0 * unit, size.x * 0.34)
	elif mobile_preview:
		preview_width = minf(280.0 * unit, size.x - safe.x - safe.z - 24.0 * unit)
	else:
		preview_width = minf(260.0, size.x - 24.0)
	var reason: String = str(
		own.get("disabled_reasons", {}).get(card.instance_id, "")
	)
	var preview_height: float = (176.0 if not reason.is_empty() else 150.0) * unit

	preview = Panel.new()
	preview.name = "CardPreview"
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.z_index = 950

	var style: StyleBoxFlat = SaloonTheme.panel(
		Color(0.055, 0.075, 0.075, 0.97),
		accent,
		14.0 * unit
	)
	style.set_corner_radius_all(int(15.0 * unit))
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = VisualSettings.ui_shadow_size(int(7.0 * unit))
	style.shadow_offset = Vector2(0, 3.0 * unit)
	preview.add_theme_stylebox_override("panel", style)

	add_child(preview)

	var left: float
	var top: float

	if mobile_preview:
		var hand_height: float = layout.hand_height(self, app.selected >= 0)
		left = (size.x - preview_width) * 0.5
		if layout.mobile_landscape(self):
			var focus_rect: Rect2 = layout.get_table_focus_rect(self)
			top = focus_rect.position.y + maxf(4.0 * unit, (focus_rect.size.y - preview_height) * 0.28)
		else:
			top = size.y - safe.w - hand_height - preview_height - 12.0 * unit
		top = maxf(top, safe.y + layout.get_mobile_banner_height(self) + 6.0 * unit)
	else:
		var mouse: Vector2 = get_viewport().get_mouse_position()
		left = mouse.x + 18.0
		top = mouse.y - preview_height - 12.0

		if left + preview_width > size.x - 12.0:
			left = mouse.x - preview_width - 18.0

		if top < 70.0:
			top = mouse.y + 18.0

		left = clampf(left, 12.0, size.x - preview_width - 12.0)
		top = clampf(
			top,
			70.0,
			maxf(70.0, size.y - preview_height - 194.0)
		)

	var banner_rect: Rect2 = get_viewport().get_meta(
		"reaction_banner_rect",
		Rect2()
	)
	var proposed := Rect2(
		Vector2(left, top),
		Vector2(preview_width, preview_height)
	)

	if not banner_rect.size.is_zero_approx() and proposed.intersects(banner_rect):
		top = minf(
			banner_rect.end.y + 8.0 * unit,
			size.y - preview_height - 12.0 * unit
		)

	preview.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	preview.offset_left = left
	preview.offset_top = top
	preview.offset_right = left + preview_width
	preview.offset_bottom = top + preview_height

	var card_name := Label.new()
	card_name.text = str(data.get("name", ""))
	card_name.position = Vector2(14.0, 10.0) * unit
	card_name.size = Vector2(preview_width / unit - 92.0, 26.0) * unit
	card_name.add_theme_font_size_override("font_size", int(18.0 * unit))
	card_name.add_theme_color_override("font_color", accent.lightened(0.22))
	card_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(card_name)

	var corner := Label.new()
	corner.text = CardInstance.corner(card)
	corner.position = Vector2(preview_width - 76.0 * unit, 10.0 * unit)
	corner.size = Vector2(62.0, 26.0) * unit
	corner.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	corner.add_theme_font_size_override("font_size", int(17.0 * unit))
	corner.add_theme_color_override("font_color", CardInstance.suit_color(card.suit))
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(corner)

	var type_label := Label.new()
	type_label.text = TextCatalog.text(
		CardData.CardType.keys()[int(data.get("type", 0))]
	)
	type_label.position = Vector2(14.0, 39.0) * unit
	type_label.size = Vector2(preview_width / unit - 28.0, 18.0) * unit
	type_label.add_theme_font_size_override("font_size", int(12.0 * unit))
	type_label.add_theme_color_override("font_color", accent.lightened(0.12))
	type_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(type_label)

	var description := Label.new()
	description.text = str(data.get("description", ""))
	description.position = Vector2(14.0, 63.0) * unit
	description.size = Vector2(
		preview_width / unit - 28.0,
		64.0 if not reason.is_empty() else 72.0
	) * unit
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_size_override("font_size", int(14.0 * unit))
	description.add_theme_color_override("font_color", SaloonTheme.CREAM)
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(description)

	if not reason.is_empty():
		var reason_label := Label.new()
		reason_label.text = reason
		reason_label.position = Vector2(14.0, 139.0) * unit
		reason_label.size = Vector2(preview_width / unit - 28.0, 26.0) * unit
		reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reason_label.add_theme_font_size_override("font_size", int(12.0 * unit))
		reason_label.add_theme_color_override("font_color", Color("#ffb995"))
		reason_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.add_child(reason_label)

	preview.modulate.a = 0.0
	preview.scale = Vector2(0.98, 0.98)
	preview.pivot_offset = preview.size * 0.5

	var tween := preview.create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(preview, "modulate:a", 1.0, 0.13)
	tween.parallel().tween_property(preview, "scale", Vector2.ONE, 0.15)

func _input(event: InputEvent) -> void:
	if (
		is_instance_valid(preview)
		and event is InputEventScreenTouch
		and event.pressed
	):
		close_preview()


func reaction_message(active: Dictionary) -> String:
	var actor: String = ""

	var source_id: int = int(
		active.get(
			"source_player_id",
			0
		)
	)

	for row in state.players:
		if int(row.player_id) == source_id:
			actor = str(
				row.display_name
			)
			break

	match str(
		active.get(
			"reaction_type",
			""
		)
	):
		"dodge":
			return (
				actor
				+ " ĐANG BẮN BẠN · DÙNG NÉ HOẶC CHỊU 1 SÁT THƯƠNG"
				if not actor.is_empty()
				else "BẠN ĐANG BỊ BẮN · DÙNG NÉ HOẶC CHỊU 1 SÁT THƯƠNG"
			)

		"duel":
			return (
				actor
				+ " THÁCH ĐẤU BẠN · DÙNG BANG! HOẶC CHỊU 1 SÁT THƯƠNG"
				if not actor.is_empty()
				else "ĐẤU SÚNG · DÙNG BANG! HOẶC CHỊU 1 SÁT THƯƠNG"
			)

		"indians":
			return "THỔ DÂN TẤN CÔNG · DÙNG BANG! HOẶC CHỊU 1 SÁT THƯƠNG"

		"survive":
			return "BẠN SẮP BỊ LOẠI · DÙNG BIA ĐỂ SỐNG SÓT?"

	return str(
		active.get(
			"title",
			"CHỌN TRÊN BÀN"
		)
	)


func close_preview() -> void:
	if is_instance_valid(preview):
		preview.queue_free()
		preview = null


func build_pause() -> void:
	app.table.targeting.blocked = true

	var box: VBoxContainer = app.modal()

	text(
		"TẠM DỪNG GIAO DIỆN",
		25,
		box
	)

	text(
		"Trận online và đồng hồ phản ứng vẫn tiếp tục.",
		16,
		box
	)

	action(
		"TIẾP TỤC",
		func():
			app.menu_open = false
			app.refresh(),
		box
	)

	action(
		"LUẬT CHƠI",
		func():
			show_rules(),
		box
	)

	action(
		"ÂM THANH",
		app.show_audio_settings,
		box
	)

	action(
		"HÌNH ẢNH",
		app.show_visual_settings,
		box
	)

	action(
		"RỜI TRẬN",
		app.leave,
		box
	)

	if (
		app.local_id()
		== state.get(
			"host_player_id",
			1
		)
		and OS.is_debug_build()
		and state.debug
		and NetworkManager.mode != "websocket"
	):
		var fold := VBoxContainer.new()

		box.add_child(fold)

		action(
			"DEBUG ▾",
			func():
				toggle_debug(fold),
			fold
		)


func toggle_debug(fold: VBoxContainer) -> void:
	if fold.get_child_count() == 1:
		app.build_debug(
			fold,
			state
		)

	else:
		for node in fold.get_children().slice(1):
			node.queue_free()


func show_rules() -> void:
	var box: VBoxContainer = app.modal()

	text(
		"LUẬT CHƠI",
		26,
		box
	)

	text(
		"Chọn bài → chạm cao bồi. Mỗi lượt bình thường dùng 1 lá Bắn. Tầm súng và khoảng cách được máy chủ kiểm tra.\nKhi bị tấn công, chạm lá phản ứng sáng trên tay hoặc chịu đòn.\nKết thúc lượt: bỏ bớt bài để số bài không quá máu.\nChạm trang bị/tay kín khi Hoảng loạn hoặc Cat Balou yêu cầu. Chạm bài giữa bàn để chọn trong Cửa hàng.\nEsc, chuột phải, nút Hủy hoặc chạm lại lá đã chọn để hủy nhắm mục tiêu.",
		18,
		box
	)

	action(
		"TIẾP TỤC",
		func():
			app.menu_open = false
			app.refresh(),
		box
	)


func build_result() -> void:
	app.table.targeting.blocked = true

	var box: VBoxContainer = app.modal()

	text(
		"✦ AI CÒN MŨ, NGƯỜI ĐÓ THẮNG! ✦",
		21,
		box
	)

	text(
		TextCatalog.text(
			state.winner
		),
		30,
		box
	)

	for player in state.players:
		text(
			"%s · %s"
			% [
				player.display_name,
				TextCatalog.text(
					player.public_role
				)
			],
			17,
			box
		)

	if app.local_id() == state.get(
		"host_player_id",
		1
	):
		action(
			"PLAY AGAIN",
			func():
				app.intent(
					"restart"
				),
			box
		)

		action(
			"RETURN TO LOBBY",
			func():
				app.intent(
					"lobby"
				),
			box
		)

	else:
		text(
			"Đang chờ chủ phòng...",
			17,
			box
		)

	action(
		"RỜI TRẬN",
		app.leave,
		box
	)
