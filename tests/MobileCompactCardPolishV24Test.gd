extends Node

const LAYOUT = preload("res://scripts/ui/MatchLayout.gd")

var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("V24 COMPACT POLISH FAILED: " + message)

func _ready() -> void:
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	get_window().size = Vector2i(390, 844)
	get_window().content_scale_size = Vector2i(600, 1298)
	get_viewport().set_meta("match_css_size", Vector2(390, 844))
	get_viewport().set_meta("match_safe_insets", Vector4(8, 24, 8, 18))
	get_viewport().set_meta("match_force_mobile_device", true)

	var definition: Dictionary = CardData.data("department_store")
	var card: Button = load("res://scripts/ui/CardView.gd").new()
	add_child(card)
	card.configure(CardInstance.make(24001, "department_store", "HEART", 8), definition, true, false)
	card.touch_compact(LAYOUT.touch_card_width(card))
	var header: Control = card.visual.get_node("HeaderRegion")
	var title: Label = header.get_node("CardName")
	var corner: Label = header.get_node("RankSuitCorner")
	var artwork: Control = card.visual.get_node("ArtworkFrame")
	var face_style := card.visual.get_node("CardFace").get_theme_stylebox("panel") as StyleBoxFlat
	var header_style := header.get_node("TitleBand").get_theme_stylebox("panel") as StyleBoxFlat
	var art_style := artwork.get_theme_stylebox("panel") as StyleBoxFlat
	check(title.visible and title.clip_text and title.get_theme_font_size("font_size") * card.visual.scale.y >= 10.0, "mobile card title remains readable")
	check(not header.get_rect().intersects(artwork.get_rect()), "title header never overlaps artwork")
	check(not title.get_rect().intersects(corner.get_rect()), "title preserves the rank/suit hierarchy")
	check(face_style.corner_radius_top_left >= 12, "card face uses the polished rounded silhouette")
	check(header_style.corner_radius_top_left >= 6 and art_style.corner_radius_top_left >= 6, "title band and artwork frame share rounded styling")

	var chat: Control = load("res://scripts/ui/ChatPanel.gd").new()
	add_child(chat)
	chat.layout_chat()
	var chat_title: Label = chat.find_child("ChatTitle", true, false) as Label
	check(chat.toggle_button.text == "CHAT" and chat.toggle_button.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING, "collapsed CHAT label cannot trim to CHA")
	check(chat_title.text == "TRÒ CHUYỆN" and chat_title.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING, "compact chat header remains complete")
	check(chat.input.custom_minimum_size.y / LAYOUT.units(chat, 1.0) >= 43.5, "chat input remains finger-safe after compaction")
	check(LAYOUT.chat_panel_rect(chat).size.y <= LAYOUT.safe_rect(chat, 8.0).size.y * 0.23, "portrait chat uses a compact share of the safe viewport")
	check(LAYOUT.hand_height(card) / LAYOUT.units(card, 1.0) <= 116.0, "portrait hand zone is visibly smaller")
	check(LAYOUT.equipment_rect(card, false).size.x / LAYOUT.units(card, 1.0) <= 129.0, "collapsed equipment chip is compact")

	print("PASS: %d V24 compact mobile and card visual checks" % checks)
	get_tree().quit(1 if not failures.is_empty() else 0)
