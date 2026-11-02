extends Node

const LAYOUT = preload("res://scripts/ui/MatchLayout.gd")

var checks: int = 0
var failures: int = 0


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("END TURN POSITION FAILED: " + message)


func _ready() -> void:
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	var app: Node = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	GameManager.clear()
	for id in range(1, 5):
		GameManager.add_player(id, "Cao bồi %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()
	GameManager.selection.expire(GameManager)
	GameManager.flow.jobs.clear()
	GameManager.reactions.active = {}
	GameManager.turns.current_player = 1
	GameManager.turns.phase = "ACTION_PHASE"
	for player in GameManager.players.values():
		player.ability_id = ""
		player.current_hp = 4
		player.max_hp = 4
	GameManager.publish()
	app.seen_role = GameManager.match_id
	await get_tree().process_frame

	for css in [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1712, 870), Vector2i(1920, 1080)]:
		get_window().size = css
		get_window().content_scale_size = Vector2i(1440, int(1440.0 * css.y / css.x))
		get_viewport().set_meta("match_css_size", Vector2(css))
		get_viewport().set_meta("match_safe_insets", Vector4.ZERO)
		var stable_hand_rect := Rect2()
		for card_count in [2, 7, 10]:
			GameManager.players[1].hand.clear()
			for index in range(card_count):
				GameManager.players[1].hand.append(CardInstance.make(8000 + card_count * 100 + index, "shoot", "HEART", 7))
			GameManager.publish()
			app.refresh()
			await get_tree().process_frame
			await get_tree().process_frame
			var hand: Control = app.match_hud.hand
			var footer: Control = app.match_hud.get_node("HandActions")
			var end_turn: Button = footer.get_node("EndTurn")
			var hand_rect := hand.get_global_rect()
			var footer_rect := footer.get_global_rect()
			if stable_hand_rect == Rect2():
				stable_hand_rect = hand_rect
			else:
				check(stable_hand_rect.is_equal_approx(hand_rect), "desktop hand container remains unchanged at %s with %d cards" % [css, card_count])
			var phone_layout: bool = LAYOUT.mobile_portrait(app.match_hud) or LAYOUT.mobile_landscape(app.match_hud)
			var expected_gap: float = 0.0 if phone_layout else 8.0
			check(absf(footer_rect.end.y - (hand_rect.position.y - expected_gap)) <= 1.0, "action bar stays above hand at %s with %d cards footer=%s hand=%s" % [css, card_count, footer_rect, hand_rect])
			check(not footer_rect.intersects(hand_rect), "action bar never overlaps cards at %s with %d cards footer=%s hand=%s" % [css, card_count, footer_rect, hand_rect])
			check(end_turn.text == "KẾT THÚC LƯỢT" and end_turn.size.x >= 160.0 and end_turn.size.x <= 210.0 and end_turn.size.y >= 44.0, "End Turn button is compact and readable at %s with %d cards" % [css, card_count])
			check(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).encloses(end_turn.get_global_rect()), "End Turn remains inside viewport at %s with %d cards" % [css, card_count])
			if not LAYOUT.mobile(app.match_hud):
				check(is_equal_approx(hand.offset_top, -182.0) and is_equal_approx(hand.offset_bottom, -4.0), "desktop hand offsets were not changed at %s" % css)
	print("PASS: %d End Turn/HandActions checks for 2, 7 and 10 cards across 5 desktop resolutions" % checks)
	get_tree().quit(1 if failures > 0 else 0)

