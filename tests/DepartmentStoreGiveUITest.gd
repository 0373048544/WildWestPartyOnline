extends Node

const LAYOUT = preload("res://scripts/ui/MatchLayout.gd")

var app: Node
var checks := 0
var next_uid := 97000

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("DEPARTMENT STORE GIVE UI FAILED: " + message)
		get_tree().quit(1)
		assert(value, message)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func give(id: int, card_id: String) -> Dictionary:
	next_uid += 1
	var card := CardInstance.make(next_uid, card_id, "HEART", 7)
	GameManager.players[id].hand.append(card)
	return card

func prompt_giver(giver: int = 1, receiver: int = 2) -> void:
	var receiver_name: String = GameManager.players[receiver].display_name
	GameManager.flow.prompt(giver, "department_store_give", {
		"source": receiver, "receiver": receiver, "giver": giver, "batch": {"count": 0}
	}, {
		"cards": GameManager.players[giver].hand.duplicate(true), "pick_count": 1,
		"title": "BÁCH HÓA", "detail": "Chọn 1 lá để đưa cho %s." % receiver_name,
		"confirm_label": "ĐƯA", "reset_label": "CHỌN LẠI",
		"confirm_question": "Đưa {card} cho %s?" % receiver_name, "timeout_seconds": 8.0
	})
	GameManager.publish()

func configure_viewport(css: Vector2i) -> void:
	get_window().size = css
	get_viewport().set_meta("match_css_size", Vector2(css))
	var logical := (
		Vector2i(600, int(600.0 * css.y / css.x)) if css.y >= css.x
		else (Vector2i(960, int(960.0 * css.y / css.x)) if css.x < 1000 else css)
	)
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	get_window().content_scale_size = logical
	get_viewport().set_meta("match_safe_insets", Vector4(10, 24, 10, 20) if css.x < 1000 else Vector4.ZERO)
	app.refresh()

func panel() -> Control:
	return app.match_hud.get_node_or_null("DepartmentStoreGivePanel") as Control

func selected_view(uid: int) -> Button:
	for view in app.match_hud.hand.cards:
		if int(view.get_meta("mobile_uid", -1)) == uid:
			return view
	return null

func _ready() -> void:
	GameManager.clear()
	NetworkManager.mode = "offline"
	GameManager.add_player(1, "Minh")
	GameManager.add_player(2, "Pedro")
	for player in GameManager.players.values():
		player.ready = true
	GameManager.start_match()
	GameManager.selection.expire(GameManager)
	GameManager.flow.jobs.clear()
	GameManager.reactions.active = {}
	GameManager.turns.current_player = 2
	GameManager.turns.phase = "ACTION_PHASE"
	for player in GameManager.players.values():
		player.hand.clear()
		player.ability_id = ""
	var first := give(1, "shoot")
	var second := give(1, "barrel")
	give(1, "iced_tea")
	get_window().size = Vector2i(1440, 900)
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	get_window().content_scale_size = Vector2i(1440, 900)
	get_viewport().set_meta("match_css_size", Vector2(1440, 900))
	get_viewport().set_meta("match_safe_insets", Vector4.ZERO)
	app = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	app.seen_role = GameManager.match_id
	# Reproduce the real round transition from a prior Store true modal.
	app.modal()
	app.clear_game_modal()
	prompt_giver()
	app.refresh()
	await settle()
	# Headless Window applies content scaling on the next frame; refresh once with
	# the settled viewport just like the runtime resize notification does.
	app.refresh()
	await settle()

	check(not is_instance_valid(app.overlay), "department_store_give creates no fullscreen modal or dim overlay")
	check(is_instance_valid(panel()), "local giver receives one compact BÁCH HÓA panel")
	check(panel().size.y <= get_viewport().get_visible_rect().size.y * 0.25, "desktop panel uses at most 25%% of viewport height panel=%s viewport=%s" % [panel().size, get_viewport().get_visible_rect().size])
	check(is_instance_valid(app.match_hud.hand) and app.match_hud.hand.visible, "real hand remains visible below the compact panel")
	check(app.match_hud.hand.cards.size() == 3, "panel does not clone or replace hand cards")
	check(not is_instance_valid(app.match_hud.get_node_or_null("HandActions/EndTurn")), "mandatory giver choice keeps End Turn locked")
	check(not is_instance_valid(app.match_hud.get_node_or_null("HandActions/SidAbility")), "mandatory giver choice exposes no active ability control")

	app.match_hud.handle_card(first.instance_id)
	await settle()
	var first_view := selected_view(first.instance_id)
	var confirm: Button = panel().get_node("Padding/Content/Actions/ConfirmGive") as Button
	check(app.match_hud.department_give_selected == first.instance_id, "tap selects a card directly from HandFan")
	check(is_instance_valid(first_view) and bool(first_view.get_meta("chosen_card", false)) and first_view.visual.position.y < 0, "selected hand card receives raised/highlighted state")
	check(not confirm.disabled and "BẮN" in str(panel().get_node("Padding/Content/Copy/Question").text), "compact panel asks confirmation using selected card name")
	check(GameManager.players[1].hand.has(first) and not GameManager.players[2].hand.has(first), "selection alone does not transfer a private card")
	panel().get_node("Padding/Content/Actions/ResetGive").pressed.emit()
	await settle()
	check(app.match_hud.department_give_selected == -1 and confirm.disabled, "CHỌN LẠI clears local selection without resolving prompt")

	app.match_hud.handle_card(second.instance_id)
	await settle()
	confirm = panel().get_node("Padding/Content/Actions/ConfirmGive") as Button
	confirm.pressed.emit()
	await settle()
	check(GameManager.reactions.active.is_empty(), "ĐƯA resolves the existing authoritative prompt")
	check(not GameManager.players[1].hand.has(second) and GameManager.players[2].hand.has(second), "confirmed card transfer remains server-authoritative")
	check(not is_instance_valid(panel()) and not is_instance_valid(app.overlay), "compact panel disappears immediately after resolution")

	prompt_giver()
	for css in [Vector2i(390, 844), Vector2i(844, 390)]:
		configure_viewport(css)
		await settle()
		var compact: Control = panel()
		var safe: Rect2 = LAYOUT.safe_rect(app.match_hud, 8.0)
		check(is_instance_valid(compact) and safe.encloses(compact.get_global_rect()), "compact giver panel stays inside mobile safe area %s" % css)
		check(not compact.get_global_rect().intersects(app.match_hud.hand.get_global_rect()), "giver panel stays above the tappable hand %s" % css)
		check(compact.size.y <= get_viewport().get_visible_rect().size.y * 0.35, "giver panel remains compact on mobile %s" % css)
		var give_button: Button = compact.get_node("Padding/Content/Actions/ConfirmGive") as Button
		var reset_button: Button = compact.get_node("Padding/Content/Actions/ResetGive") as Button
		check(give_button.custom_minimum_size.y >= 44 and reset_button.custom_minimum_size.y >= 44, "mobile actions retain touch-sized controls %s" % css)
		check(app.match_hud.hand.visible and app.match_hud.hand.cards.any(func(view): return not view.disabled), "hand remains visible and selectable on mobile %s" % css)

	GameManager.reactions.active.deadline = 0
	GameManager._process(0.0)
	await settle()
	check(GameManager.reactions.active.is_empty() and not is_instance_valid(panel()), "timeout fallback resolves and removes the compact panel")
	print("PASS: %d compact BÁCH HÓA hand-selection, confirmation, timeout and responsive checks" % checks)
	get_tree().quit()
