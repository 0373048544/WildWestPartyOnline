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
var choice_status_signature: String = ""
var target_picker: Control
var loadout_panel: Control
var dismissed_picker_request: int = -1
var department_give_request_id: int = -1
var department_give_selected: int = -1


func initialize(owner_app: Node, snapshot: Dictionary, private: Dictionary) -> void:
	app = owner_app
	state = snapshot
	own = private
	request = own.get("reaction", {})
	var request_identity: Dictionary = request.duplicate(true)
	# Remaining time is rendered locally. It must not invalidate the UI tree on
	# every authoritative countdown snapshot.
	request_identity.erase("remaining")
	var department_give_active: bool = str(request.get("reaction_type", "")) == "department_store_give"
	var next_department_request: int = int(request.get("request_id", -1)) if department_give_active else -1
	if next_department_request != department_give_request_id:
		department_give_request_id = next_department_request
		department_give_selected = -1
	if not department_give_active:
		_free_named("DepartmentStoreGivePanel")
	var local_row: Dictionary = {}
	for row in state.get("players", []):
		if int(row.get("player_id", 0)) == app.local_id():
			local_row = row
			break
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
		own.get("spectating", false), local_row.get("is_alive", true),
		state.get("players", []).map(func(row): return [row.get("player_id", 0), row.get("ready", false), row.get("is_connected", true)]),
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
	if not local_row.is_empty() and bool(local_row.get("is_alive", true)):
		_free_named("SpectatorBar")

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
	_sync_choice_status()

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

	if not local_row.is_empty() and not bool(local_row.get("is_alive", true)):
		app.table.targeting.blocked = true
		app.selected = -1
		_free_named("HandActions")
		if is_instance_valid(hand):
			hand.visible = false
		if bool(own.get("spectating", false)):
			if flow_changed or not has_node("SpectatorBar"):
				build_spectator_bar()
		elif flow_changed:
			build_death_prompt()
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

		elif reaction_type == "department_store_give":
			app.table.targeting.blocked = true
			_sync_department_store_give_panel()

		elif flow_changed:
			app.table.targeting.blocked = true
			app.show_reaction(request)


func _free_named(node_name: String) -> void:
	var old: Node = get_node_or_null(node_name)
	if old:
		remove_child(old)
		old.queue_free()

func _sync_choice_status() -> void:
	var choice_player: int = int(state.get("choice_player", 0))
	var choice_type: String = str(state.get("choice_type", ""))
	var signature := "%d:%s:%d" % [choice_player, choice_type, int(request.get("request_id", 0))]
	if signature == choice_status_signature:
		return
	# A chooser change is only a status-text update. Keep one compact banner so
	# repeated authoritative snapshots cannot replay its entrance animation.
	var persistent_status: Control = get_node_or_null("CenterChoiceStatus") as Control
	if is_instance_valid(persistent_status) and choice_player > 0 and request.is_empty():
		var updated_name := "CAO BỒI"
		for row in state.get("players", []):
			if int(row.get("player_id", 0)) == choice_player:
				updated_name = str(row.get("display_name", updated_name))
				break
		var status_title: Label = persistent_status.get_node_or_null("Content/Title") as Label
		var status_detail: Label = persistent_status.get_node_or_null("Content/Detail") as Label
		if is_instance_valid(status_title):
			status_title.text = "CỬA HÀNG" if choice_type == "store" else "BÁCH HÓA"
		if is_instance_valid(status_detail):
			status_detail.text = ("Đang chờ %s chọn..." % updated_name
				if choice_type == "store" else "Đang chờ %s đưa 1 lá..." % updated_name)
		choice_status_signature = signature
		return
	choice_status_signature = signature
	_free_named("CenterChoiceStatus")
	# The active picker receives the interactive modal. Other players receive a
	# compact public status panel without any private card list.
	if choice_player <= 0 or not request.is_empty():
		return
	var chooser_name := "CAO BỒI"
	for player in state.get("players", []):
		if int(player.get("player_id", 0)) == choice_player:
			chooser_name = str(player.get("display_name", chooser_name))
			break
	var panel := PanelContainer.new()
	panel.name = "CenterChoiceStatus"
	panel.z_index = layout.Z_TOAST
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var usable: Rect2 = layout.modal_rect(self)
	var panel_width: float = minf(layout.units(self, 520), usable.size.x * (0.90 if layout.mobile(self) else 0.72))
	panel.position = Vector2(usable.get_center().x - panel_width * 0.5, usable.position.y + layout.units(self, 54))
	panel.custom_minimum_size = Vector2(panel_width, layout.units(self, 78))
	panel.add_theme_stylebox_override("panel", SaloonTheme.panel(Color(0.07, 0.09, 0.09, 0.94), SaloonTheme.GOLD, 14))
	add_child(panel)
	var column := VBoxContainer.new()
	column.name = "Content"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	var title := text("CỬA HÀNG" if choice_type == "store" else "BÁCH HÓA", 20, column)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var subtitle_text := (
		"Đang chờ %s chọn..." % chooser_name
		if choice_type == "store"
		else "Đang chờ %s đưa 1 lá..." % chooser_name
	)
	var subtitle := text(subtitle_text, 15, column)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.get_child(0).name = "Title"
	subtitle.name = "Detail"


func _department_give_card_ids() -> Array:
	return request.get("cards", []).map(func(card): return int(card.get("instance_id", -1)))


func _department_give_selected_name() -> String:
	for card in request.get("cards", []):
		if int(card.get("instance_id", -1)) == department_give_selected:
			return str(CardData.data(str(card.get("card_data_id", ""))).get("name", "LÁ BÀI"))
	return ""


func _sync_department_store_give_panel() -> void:
	if str(request.get("reaction_type", "")) != "department_store_give":
		_free_named("DepartmentStoreGivePanel")
		return
	var panel: PanelContainer = get_node_or_null("DepartmentStoreGivePanel") as PanelContainer
	if not is_instance_valid(panel):
		panel = PanelContainer.new()
		panel.name = "DepartmentStoreGivePanel"
		panel.z_index = layout.Z_REACTION
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.add_theme_stylebox_override("panel", SaloonTheme.panel(Color(0.09, 0.075, 0.055, 0.97), SaloonTheme.GOLD, 11))
		add_child(panel)
		var padding := MarginContainer.new()
		padding.name = "Padding"
		for side in ["left", "right"]:
			padding.add_theme_constant_override("margin_" + side, int(layout.units(self, 12.0)))
		for side in ["top", "bottom"]:
			padding.add_theme_constant_override("margin_" + side, int(layout.units(self, 7.0)))
		panel.add_child(padding)
		var content := HBoxContainer.new()
		content.name = "Content"
		content.add_theme_constant_override("separation", int(layout.units(self, 10.0)))
		padding.add_child(content)
		var copy := VBoxContainer.new()
		copy.name = "Copy"
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		copy.add_theme_constant_override("separation", int(layout.units(self, 3.0)))
		content.add_child(copy)
		var heading := text("BÁCH HÓA", 18, copy)
		heading.name = "Title"
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		heading.add_theme_color_override("font_color", SaloonTheme.GOLD)
		var question := text("", 14, copy)
		question.name = "Question"
		question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var buttons := HBoxContainer.new()
		buttons.name = "Actions"
		buttons.add_theme_constant_override("separation", int(layout.units(self, 8.0)))
		content.add_child(buttons)
		var confirm := action("ĐƯA", _confirm_department_store_give, buttons, true)
		confirm.name = "ConfirmGive"
		confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		confirm.set_variant("primary")
		var reset := action("CHỌN LẠI", _reset_department_store_give, buttons, true)
		reset.name = "ResetGive"
		reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var selected_name := _department_give_selected_name()
	var question_label: Label = panel.get_node("Padding/Content/Copy/Question") as Label
	question_label.text = (
		str(request.get("confirm_question", "Đưa {card}?")).replace("{card}", selected_name)
		if not selected_name.is_empty()
		else str(request.get("detail", "Chọn 1 lá trên tay để đưa."))
	)
	var confirm_button: Button = panel.get_node("Padding/Content/Actions/ConfirmGive") as Button
	var reset_button: Button = panel.get_node("Padding/Content/Actions/ResetGive") as Button
	confirm_button.disabled = selected_name.is_empty()
	reset_button.disabled = selected_name.is_empty()
	var action_touch_height: float = maxf(44.0, layout.units(self, 44.0))
	confirm_button.custom_minimum_size.y = action_touch_height
	reset_button.custom_minimum_size.y = action_touch_height
	var safe: Rect2 = layout.safe_rect(self, 8.0 if layout.mobile(self) else 18.0)
	var targeting_hand: bool = department_give_selected >= 0
	var action_zone: Rect2 = layout.action_rect(self, targeting_hand)
	var panel_width: float = (
		minf(layout.units(self, 560.0), safe.size.x * 0.92)
		if layout.mobile_portrait(self)
		else minf(layout.units(self, 540.0), safe.size.x * (0.68 if layout.mobile_landscape(self) else 0.58))
	)
	var panel_height: float = minf(
		layout.units(self, 112.0 if layout.mobile_landscape(self) else (126.0 if layout.mobile_portrait(self) else 138.0)),
		safe.size.y * (0.30 if layout.mobile_landscape(self) else 0.22)
	)
	var panel_bottom: float = action_zone.position.y - layout.units(self, 7.0)
	var desired_size := Vector2(panel_width, panel_height)
	# Clear the previous orientation's minimum first; Control otherwise clamps the
	# new size to the old minimum and a portrait panel can never shrink in landscape.
	panel.custom_minimum_size = desired_size
	panel.reset_size()
	panel.size = desired_size
	var desired_position := Vector2(safe.get_center().x - panel_width * 0.5, maxf(safe.position.y, panel_bottom - panel_height))
	panel.position = desired_position
	# PanelContainer can still be inside a pending minimum-size sort after the
	# previous Store modal closes. Reapply the compact rect after that sort so an
	# old large Control size cannot survive even though its minimum is now small.
	panel.set_deferred("size", desired_size)
	panel.set_deferred("position", desired_position)


func _select_department_store_give(uid: int) -> void:
	if not _department_give_card_ids().has(uid):
		return
	department_give_selected = uid
	build_hand()
	_sync_department_store_give_panel()


func _reset_department_store_give() -> void:
	department_give_selected = -1
	build_hand()
	_sync_department_store_give_panel()


func _confirm_department_store_give() -> void:
	if not _department_give_card_ids().has(department_give_selected):
		return
	var confirm: Button = get_node_or_null("DepartmentStoreGivePanel/Padding/Content/Actions/ConfirmGive") as Button
	if is_instance_valid(confirm):
		confirm.disabled = true
	app.intent("reaction", {
		"request": int(request.get("request_id", -1)),
		"accept": true,
		"cards": [department_give_selected]
	})

func set_modal_blocked(value: bool) -> void:
	if is_instance_valid(loadout_panel):
		loadout_panel.set_modal_blocked(value)
	if is_instance_valid(hand):
		hand.visible = not value
	var actions: Control = get_node_or_null("HandActions") as Control
	if is_instance_valid(actions):
		actions.visible = not value
	if is_instance_valid(target_picker):
		target_picker.visible = not value and str(request.get("reaction_type", "")) == "transfer"
	if value:
		close_preview()
		var info: Node = app.root.get_node_or_null("PlayerInfoCard")
		if info:
			app.root.remove_child(info)
			info.queue_free()

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
		"LƯỢT HÀNH ĐỘNG CỦA BẠN"
		if state.current_player == app.local_id()
		else "LƯỢT HÀNH ĐỘNG CỦA " + current_player_name
	)
	for player in state.players:
		if int(player.player_id) == app.local_id() and not bool(player.get("is_alive", true)):
			title = "ĐANG XEM · LƯỢT CỦA " + current_player_name
			break

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
	var department_give_active: bool = str(request.get("reaction_type", "")) == "department_store_give"
	var hand_selection_active: bool = app.selected >= 0 or (department_give_active and department_give_selected >= 0)

	for player in state.players:
		if player.player_id == app.local_id():
			local = player

	var footer := HBoxContainer.new()

	add_child(footer)

	footer.name = "HandActions"
	footer.z_index = layout.Z_ACTION

	footer.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_WIDE
	)

	var mobile_layout: bool = bool(
		load("res://scripts/ui/MatchLayout.gd").mobile(self)
	)

	var visible_hand: float = float(
		load("res://scripts/ui/MatchLayout.gd").hand_height(
			self,
			hand_selection_active
		)
	)

	var safe: Vector4 = (
		layout.safe_insets(self)
		if mobile_layout
		else Vector4.ZERO
	)
	var phone_layout: bool = bool(layout.mobile_portrait(self) or layout.mobile_landscape(self))
	if phone_layout:
		# Preserve the existing phone placement; it is coordinated with the compact
		# equipment chip and mobile browser safe area.
		footer.offset_left = safe.x + 12.0
		footer.offset_right = -safe.z - 12.0
		footer.offset_top = -safe.w - visible_hand - float(layout.action_height(self)) - 4.0
		footer.offset_bottom = -safe.w - visible_hand - 4.0
		footer.z_index = layout.Z_ACTION
	else:
		# Desktop/tablet action controls follow the actual top of the hand instead
		# of the obsolete -224/-182 fixed offsets.
		var hand_lift: float = float(layout.hand_lift(self, hand_selection_active)) if mobile_layout else 0.0
		var hand_top_offset: float = -safe.w - visible_hand - hand_lift
		footer.offset_left = 18.0
		footer.offset_right = -18.0
		footer.offset_top = hand_top_offset - float(layout.action_height(self)) - 8.0
		footer.offset_bottom = hand_top_offset - 8.0

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
		match str(state.get("choice_type", "")):
			"store":
				message = "CỬA HÀNG · ĐANG CHỜ %s CHỌN..." % chooser_name
			"department_store_give":
				message = "BÁCH HÓA · ĐANG CHỜ %s ĐƯA BÀI..." % chooser_name
			_:
				message = "ĐẾN PHẦN %s CHỌN BÀI" % chooser_name

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
		elif reaction_type == "department_store_give":
			prompt.text = "BÁCH HÓA · CHỌN 1 LÁ TRỰC TIẾP TRÊN TAY"

	elif app.selected >= 0:
		action(
			"× HỦY",
			cancel_selection,
			footer
		).name = "CancelSelection"

	elif state.current_player == app.local_id() and state.phase == "ACTION_PHASE":
		var end_turn := action(
			"KẾT THÚC LƯỢT",
			func():
				app.intent("end"),
			footer
		)
		end_turn.name = "EndTurn"
		if layout.mobile_landscape(self):
			end_turn.custom_minimum_size = Vector2(layout.units(self, 128.0), layout.units(self, 46.0))
		elif layout.mobile_portrait(self):
			end_turn.custom_minimum_size.x = minf(layout.units(self, 180.0), size.x * 0.46)
		else:
			end_turn.custom_minimum_size = Vector2(180.0, 44.0)

	if (
		local.get("is_alive", false)
		and not department_give_active
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
		else ([department_give_selected] if department_give_active else [app.selected])
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
				department_give_active
				and _department_give_card_ids().has(int(card.instance_id))
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
	hand.z_index = layout.Z_HAND

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
					hand_selection_active
				)
			)
		)

		hand.offset_bottom = -safe.w

		hand.set_meta(
			"target_mode",
			hand_selection_active
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
		if str(request.get("reaction_type", "")) == "department_store_give":
			_select_department_store_give(uid)
			return
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
	preview.z_index = layout.Z_PREVIEW

	var style: StyleBoxFlat = SaloonTheme.card_face(accent, "preview", 14.0 * unit)
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

	var title_band := ColorRect.new()
	title_band.name = "PreviewTitleBand"
	title_band.color = accent.darkened(0.16)
	title_band.position = Vector2(7.0, 7.0) * unit
	title_band.size = Vector2(preview_width / unit - 14.0, 31.0) * unit
	title_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(title_band)
	var title_glint := ColorRect.new()
	title_glint.color = Color(1, 0.86, 0.58, 0.28)
	title_glint.position = Vector2(9.0, 37.0) * unit
	title_glint.size = Vector2(preview_width / unit - 18.0, 2.0) * unit
	title_glint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(title_glint)

	var card_name := Label.new()
	card_name.text = str(data.get("name", ""))
	card_name.position = Vector2(14.0, 10.0) * unit
	card_name.size = Vector2(preview_width / unit - 92.0, 26.0) * unit
	card_name.add_theme_font_size_override("font_size", int(18.0 * unit))
	card_name.add_theme_color_override("font_color", SaloonTheme.CREAM)
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
	type_label.add_theme_color_override("font_color", accent.darkened(0.28))
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
	description.add_theme_color_override("font_color", SaloonTheme.INK_SOFT)
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(description)

	if not reason.is_empty():
		var reason_label := Label.new()
		reason_label.text = reason
		reason_label.position = Vector2(14.0, 139.0) * unit
		reason_label.size = Vector2(preview_width / unit - 28.0, 26.0) * unit
		reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reason_label.add_theme_font_size_override("font_size", int(12.0 * unit))
		reason_label.add_theme_color_override("font_color", Color("#8f3328"))
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
			var options: Array = active.get("survival_options", [])
			var has_tea := options.any(func(option): return str(option.get("card_data_id", "")) == "iced_tea")
			var has_beer := options.any(func(option): return str(option.get("card_data_id", "")) == "drink")
			if has_tea and has_beer:
				return "BẠN SẮP BỊ LOẠI · DÙNG BIA HOẶC TRÀ ĐÁ ĐỂ SỐNG SÓT?"
			if has_tea:
				return "BẠN SẮP BỊ LOẠI · DÙNG TRÀ ĐÁ ĐỂ SỐNG SÓT?"
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
		"Chọn bài → chạm cao bồi. Mỗi lượt hành động bình thường dùng 1 lá Bắn. Tầm súng và khoảng cách được máy chủ kiểm tra.\nKhi bị tấn công, chạm lá phản ứng sáng trên tay hoặc chịu đòn.\nKết thúc lượt hành động: bỏ bớt bài để số bài không quá máu.\nChạm trang bị/tay kín khi Hoảng loạn hoặc Cat Balou yêu cầu. Chạm bài giữa bàn để chọn trong Cửa hàng.\nEsc, chuột phải, nút Hủy hoặc chạm lại lá đã chọn để hủy nhắm mục tiêu.",
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


func compact_modal_frame(preferred_width: float, preferred_height: float) -> void:
	if not is_instance_valid(app.overlay):
		return
	var frame: PanelContainer = app.overlay.get_node_or_null("ModalFrame")
	if not is_instance_valid(frame):
		return
	var available: Rect2 = layout.modal_rect(self)
	var frame_size := Vector2(
		minf(preferred_width, available.size.x * (0.92 if layout.mobile(self) else 0.78)),
		minf(preferred_height, available.size.y * (0.82 if layout.mobile_landscape(self) else 0.88))
	)
	frame.custom_minimum_size = frame_size
	frame.size = frame_size
	frame.position = available.get_center() - frame_size * 0.5


func build_death_prompt() -> void:
	var box: VBoxContainer = app.modal()
	app.overlay.color = Color(0.025, 0.03, 0.04, 0.58)
	compact_modal_frame(520.0, 310.0)
	var heading := text("☠  BẠN ĐÃ BỊ HẠ", 28, box)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_color_override("font_color", Color("#e7b86d"))
	var detail := text("Bạn vẫn ở trong phòng và có thể xem phần còn lại của ván chơi.", 17, box)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var watch := action("XEM TIẾP", func(): app.intent("spectate"), box)
	watch.name = "SpectateButton"
	watch.set_variant("primary")
	var leave_button := action("RỜI PHÒNG", app.leave, box)
	leave_button.name = "DeathLeaveButton"
	leave_button.set_variant("danger")


func build_spectator_bar() -> void:
	_free_named("SpectatorBar")
	var bar := PanelContainer.new()
	bar.name = "SpectatorBar"
	bar.z_index = layout.Z_ACTION
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	var safe: Vector4 = layout.safe_insets(self) if layout.mobile(self) else Vector4.ZERO
	bar.offset_left = safe.x + 12.0
	bar.offset_right = -safe.z - 12.0
	bar.offset_top = -safe.w - (58.0 if layout.mobile_landscape(self) else 68.0)
	bar.offset_bottom = -safe.w - 8.0
	bar.add_theme_stylebox_override("panel", SaloonTheme.panel(Color(0.08, 0.12, 0.14, 0.94), SaloonTheme.GOLD, 10))
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	var notice := text("☠  Bạn đã bị hạ · Đang xem trận đấu", 14 if layout.mobile(self) else 16, row)
	notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var leave_button := action("RỜI PHÒNG", app.leave, row)
	leave_button.name = "SpectatorLeaveButton"
	leave_button.set_variant("danger")
	leave_button.custom_minimum_size.x = layout.units(self, 126.0) if layout.mobile(self) else 150.0


func build_result() -> void:
	app.table.targeting.blocked = true
	_free_named("SpectatorBar")
	var box: VBoxContainer = app.modal()
	app.overlay.color = Color(0.025, 0.03, 0.04, 0.64)
	compact_modal_frame(620.0, 500.0)
	var heading := text("✦  KẾT THÚC VÁN  ✦", 24, box)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_color_override("font_color", SaloonTheme.GOLD)
	var winner_label := text(TextCatalog.text(state.winner), 30, box)
	winner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for player in state.players:
		var status := " · SẴN SÀNG VÁN MỚI" if bool(player.get("ready", false)) and bool(player.get("is_connected", true)) else ""
		var row := text("%s · %s%s" % [player.display_name, TextCatalog.text(player.public_role), status], 15, box)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var local_ready := false
	var connected_count := 0
	var ready_count := 0
	for player in state.players:
		if bool(player.get("is_connected", true)):
			connected_count += 1
			ready_count += int(bool(player.get("ready", false)))
		if int(player.player_id) == app.local_id():
			local_ready = bool(player.get("ready", false))
	if local_ready:
		var ready_label := text("✓  BẠN ĐÃ SẴN SÀNG", 19, box)
		ready_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ready_label.add_theme_color_override("font_color", SaloonTheme.SUCCESS.lightened(0.18))
		var waiting := text("Đang chờ người chơi khác...  %d/%d" % [ready_count, connected_count], 15, box)
		waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		var continue_button := action("TIẾP TỤC", func(): app.intent("rematch"), box)
		continue_button.name = "RematchReadyButton"
		continue_button.set_variant("primary")
	var leave_button := action("RỜI PHÒNG", app.leave, box)
	leave_button.name = "ResultLeaveButton"
	leave_button.set_variant("danger")
