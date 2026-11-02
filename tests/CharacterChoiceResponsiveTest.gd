extends Node

const LAYOUT = preload("res://scripts/ui/MatchLayout.gd")

var checks: int = 0
var failures: int = 0


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("CHARACTER RESPONSIVE FAILED: " + message)


func _ready() -> void:
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	var app: Node = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	var definitions: Array = CharacterData.definitions().values()
	var phone_sizes := [
		Vector2i(360, 640), Vector2i(375, 667), Vector2i(390, 844),
		Vector2i(412, 915), Vector2i(430, 932), Vector2i(640, 360),
		Vector2i(844, 390), Vector2i(915, 412)
	]
	var desktop_sizes := [Vector2i(1366, 768), Vector2i(1440, 900), Vector2i(1920, 1080)]
	for css in phone_sizes + desktop_sizes:
		get_window().size = css
		get_viewport().set_meta("match_css_size", Vector2(css))
		var mode: String = LAYOUT.mode(app.root)
		var phone: bool = mode in [LAYOUT.MOBILE_PORTRAIT, LAYOUT.MOBILE_LANDSCAPE]
		var logical := (
			Vector2i(600, int(600.0 * css.y / css.x)) if mode == LAYOUT.MOBILE_PORTRAIT
			else (Vector2i(960, int(960.0 * css.y / css.x)) if mode == LAYOUT.MOBILE_LANDSCAPE else Vector2i(1440, int(1440.0 * css.y / css.x)))
		)
		get_window().content_scale_size = logical
		var sx: float = float(logical.x) / css.x
		var sy: float = float(logical.y) / css.y
		var safe := Vector4(10.0 * sx, 24.0 * sy, 8.0 * sx, 20.0 * sy) if phone else Vector4.ZERO
		get_viewport().set_meta("match_safe_insets", safe)
		app.clear_game_modal()
		await get_tree().process_frame
		await get_tree().process_frame
		app.show_character_selection({
			"character_options": [definitions[0], definitions[1]],
			"character_remaining": 20.0,
			"character_chosen": false
		})
		await get_tree().process_frame
		await get_tree().process_frame

		var frame: Control = app.root.get_node("GameModal/ModalFrame")
		var panel: Control = frame.find_child("CharacterChoicePanel", true, false)
		var confirm: Control = frame.find_child("ConfirmCharacter", true, false)
		var timer: Control = frame.find_child("CharacterChoiceTimer", true, false)
		var choice_rect: Rect2 = LAYOUT.character_choice_rect(app.root)
		check(is_instance_valid(panel) and panel.cards.size() == 2, "exactly two choices render at %s" % css)
		check(is_instance_valid(timer) and choice_rect.encloses(timer.get_global_rect()), "compact timer stays visible at %s" % css)
		check(is_instance_valid(confirm) and choice_rect.encloses(confirm.get_global_rect()), "confirm stays visible at %s" % css)
		var scroll: ScrollContainer = frame.find_child("ModalScroll", true, false)
		if phone:
			check(frame.get_meta("character_choice_fullscreen", false), "phone uses full-screen character overlay at %s" % css)
			check(frame.get_global_rect().is_equal_approx(choice_rect), "phone frame matches safe viewport at %s frame=%s safe=%s" % [css, frame.get_global_rect(), choice_rect])
			check(scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "phone selection cannot scroll vertically at %s" % css)
			check(confirm.size.y / sy >= 44.0, "confirm is at least 44 CSS px at %s" % css)
			var keys: Array = panel.cards.keys()
			if css.y > css.x and css.x < 390:
				check(panel.carousel_mode, "narrow portrait switches to carousel at %s" % css)
				check(panel.cards[keys[0]].visible != panel.cards[keys[1]].visible, "carousel shows one card at %s" % css)
				var previous: Control = panel.navigation.get_node("PreviousCharacter")
				var next: Control = panel.navigation.get_node("NextCharacter")
				check(previous.size.y / sy >= 44.0 and next.size.y / sy >= 44.0, "carousel arrows are touch sized at %s" % css)
				panel.show_carousel_card(1, false)
				check(not panel.cards[keys[0]].visible and panel.cards[keys[1]].visible, "carousel reaches second option at %s" % css)
			else:
				check(not panel.carousel_mode, "wide portrait/landscape uses paired cards at %s" % css)
				var first: Control = panel.cards[keys[0]]
				var second: Control = panel.cards[keys[1]]
				check(first.visible and second.visible and first.global_position.x < second.global_position.x, "two cards are side by side at %s" % css)
				check(choice_rect.encloses(first.get_global_rect()) and choice_rect.encloses(second.get_global_rect()), "cards stay inside safe viewport at %s" % css)
				check(first.find_child("ChooseBadge", true, false).size.y / sy >= 44.0, "card choice target is at least 44 CSS px at %s" % css)
		else:
			check(not frame.get_meta("character_choice_fullscreen", false), "desktop remains a centered modal at %s" % css)
			check(frame.size.x < logical.x, "desktop modal does not occupy full width at %s" % css)
			check(not panel.carousel_mode and panel.cards.values().all(func(card): return card.visible), "desktop keeps both cards visible at %s" % css)
	app.clear_game_modal()
	print("PASS: %d responsive character-choice checks across %d phone and %d desktop viewports" % [checks, phone_sizes.size(), desktop_sizes.size()])
	get_tree().quit(1 if failures > 0 else 0)

