extends Node

const LAYOUT = preload("res://scripts/ui/MatchLayout.gd")

var checks := 0
var failures: Array[String] = []
var app: Node

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("MOBILE SELF HEALTH HUD FAILED: " + message)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame

func set_mobile_view(css: Vector2i, safe: Vector4) -> void:
	get_window().size = css
	get_window().content_scale_size = css
	get_viewport().set_meta("match_css_size", Vector2(css))
	get_viewport().set_meta("match_safe_insets", safe)
	get_viewport().set_meta("match_force_mobile_device", true)
	get_viewport().set_meta("match_layout_generation", int(get_viewport().get_meta("match_layout_generation", 0)) + 1)

func health_hud() -> MobileSelfHealthHUD:
	return app.match_hud.get_node_or_null("MobileSelfHealthHUD") as MobileSelfHealthHUD

func publish_health(current_hp: int, max_hp: int = 4, alive: bool = true) -> void:
	GameManager.players[1].current_hp = current_hp
	GameManager.players[1].max_hp = max_hp
	GameManager.players[1].is_alive = alive
	GameManager.publish()
	app.refresh()
	await settle()

func verify_mobile_geometry(css: Vector2i, safe: Vector4) -> void:
	set_mobile_view(css, safe)
	app.responsive_layout_changed({"profile_changed": true})
	await settle()
	var hud := health_hud()
	expect(is_instance_valid(hud) and hud.visible, "self HP remains visible at %dx%d" % [css.x, css.y])
	if not is_instance_valid(hud):
		return
	var safe_rect: Rect2 = LAYOUT.safe_rect(app)
	var rect: Rect2 = hud.get_global_rect()
	expect(rect.position.x >= safe_rect.position.x - 1.0 and rect.end.x <= safe_rect.end.x + 1.0
		and rect.position.y >= safe_rect.position.y - 1.0 and rect.end.y <= safe_rect.end.y + 1.0,
		"self HP stays inside the iPhone safe area at %dx%d" % [css.x, css.y])
	var menu: Control = app.match_hud.get_node_or_null("TopBar/PauseButton") as Control
	expect(is_instance_valid(menu) and not rect.intersects(menu.get_global_rect()),
		"self HP does not cover MENU at %dx%d" % [css.x, css.y])
	var covers_nameplate := false
	for plate in app.table.nameplates.values():
		if plate.visible and rect.intersects(plate.screen_rect):
			covers_nameplate = true
			break
	expect(not covers_nameplate, "self HP exclusion keeps opponent nameplates readable at %dx%d" % [css.x, css.y])

func _ready() -> void:
	set_mobile_view(Vector2i(390, 844), Vector4(8, 24, 8, 18))
	NetworkManager.mode = "offline"
	GameManager.clear()
	for id in range(1, 5):
		GameManager.add_player(id, "Cao b\u1ed3i %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()
	GameManager.selection.expire(GameManager)
	GameManager.flow.jobs.clear()
	GameManager.reactions.active = {}
	GameManager.turns.current_player = 2
	GameManager.turns.phase = "ACTION_PHASE"
	for player in GameManager.players.values():
		player.current_hp = 4
		player.max_hp = 4
		player.is_alive = true
	GameManager.publish()

	app = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	app.seen_role = GameManager.match_id
	app.refresh()
	await settle()

	var hud := health_hud()
	expect(is_instance_valid(hud) and hud.visible, "mobile first-person creates one visible local HP HUD")
	if not is_instance_valid(hud):
		_finish()
		return
	var hud_id: int = hud.get_instance_id()
	var label: Label = hud.get_node("HealthValue") as Label
	expect(hud.health_text() == "\u2665 4/4", "4/4 HP renders with a real heart glyph")
	expect(not hud.health_text().contains("\u00c3") and not hud.health_text().contains("\ufffd"), "heart text has no mojibake or replacement glyph")
	expect(hud.mouse_filter == Control.MOUSE_FILTER_IGNORE and label.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"health HUD and child label never block table touch")

	await publish_health(3)
	expect(health_hud().health_text() == "\u2665 3/4", "damage snapshot updates local HP to 3/4")
	expect(health_hud().get_instance_id() == hud_id, "HP snapshot updates reuse the existing HUD node")

	# Current turn and opponent HP must never select the displayed health owner.
	GameManager.players[2].current_hp = 1
	GameManager.turns.current_player = 2
	GameManager.publish()
	app.refresh()
	await settle()
	expect(health_hud().health_text() == "\u2665 3/4", "HUD reads local player HP, not current-turn or opponent HP")

	await publish_health(1)
	expect(health_hud().health_text() == "\u2665 1/4", "1/4 HP remains readable")
	expect(label.get_theme_color("font_color").is_equal_approx(Color("#ffaaa0")), "1 HP uses the low-health warning color")
	await publish_health(0, 4, true)
	expect(health_hud().health_text() == "\u2665 0/4", "alive zero-HP/dying state is explicit without falsely declaring elimination")
	await publish_health(0, 4, false)
	expect(health_hud().health_text() == "\u0110\u00c3 LO\u1ea0I", "dead or spectating player sees the eliminated state")
	await publish_health(2, 4, true)
	expect(health_hud().health_text() == "\u2665 2/4", "heal/reconnect snapshot restores the authoritative HP value")

	# Countdown-only updates must not recreate the persistent HUD.
	var countdown_private: Dictionary = NetworkManager.private_state.duplicate(true)
	countdown_private["reaction"] = {"request_id": 2301, "reaction_type": "dodge", "remaining": 5.0}
	app.match_hud.initialize(app, NetworkManager.public_state, countdown_private)
	countdown_private["reaction"]["remaining"] = 4.0
	app.match_hud.initialize(app, NetworkManager.public_state, countdown_private)
	await settle()
	expect(health_hud().get_instance_id() == hud_id, "countdown refresh does not recreate the health HUD")

	# A new match snapshot updates the same presentation node instead of retaining stale HP.
	GameManager.match_id += 1
	await publish_health(4, 4, true)
	expect(health_hud().health_text() == "\u2665 4/4", "rematch snapshot clears stale HP")

	for viewport_case in [
		{"size": Vector2i(360, 640), "safe": Vector4(0, 20, 0, 16)},
		{"size": Vector2i(375, 667), "safe": Vector4(0, 20, 0, 16)},
		{"size": Vector2i(390, 844), "safe": Vector4(8, 24, 8, 18)},
		{"size": Vector2i(430, 932), "safe": Vector4(8, 26, 8, 20)},
		{"size": Vector2i(844, 390), "safe": Vector4(20, 0, 20, 12)}
	]:
		await verify_mobile_geometry(viewport_case.size, viewport_case.safe)

	get_viewport().set_meta("match_force_mobile_device", false)
	get_window().size = Vector2i(1440, 900)
	get_window().content_scale_size = Vector2i(1440, 900)
	get_viewport().set_meta("match_css_size", Vector2(1440, 900))
	get_viewport().set_meta("match_safe_insets", Vector4.ZERO)
	app.responsive_layout_changed({"profile_changed": true})
	await settle()
	expect(not health_hud().visible, "desktop keeps its existing HP presentation without the mobile self HUD")

	_finish()

func _finish() -> void:
	GameManager.clear()
	if failures.is_empty():
		print("PASS: %d authoritative mobile self-health, persistence, safe-area and desktop checks" % checks)
		get_tree().quit(0)
	else:
		print("FAIL: %d/%d mobile self-health checks" % [failures.size(), checks])
		get_tree().quit(1)
