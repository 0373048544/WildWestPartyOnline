extends Button

signal preview_requested
signal preview_closed

var visual: Control
var lift: Tween
var accent: Color
var effect: int = 0
var selected_lift: float = 0.0
var compact_mode: bool = false
var touch_layout: bool = false
var block_activation: bool = false
var holding: bool = false
var hold_time: float = 0.0
var glow: Tween
var chosen_state: bool = false

func _ready() -> void:
	set_process(false)

func configure(card: Dictionary, definition: Dictionary, usable: bool, chosen: bool, reason: String = "") -> void:
	if lift:
		lift.kill()
	if glow:
		glow.kill()
	if is_instance_valid(visual):
		visual.free()
	compact_mode = false
	touch_layout = false
	chosen_state = chosen
	selected_lift = 0.0
	holding = false
	set_process(false)
	custom_minimum_size = Vector2(210, 214)
	disabled = not usable
	# MatchHUD owns the single compact preview on both desktop and touch.
	# Keeping the native tooltip empty prevents a second preview from appearing.
	tooltip_text = ""
	set_meta("disabled_reason", reason)
	accent = [Color("#bc6449"), Color("#6a9b9f"), Color("#a38748"), Color("#7b719d")][int(definition.type)]
	effect = definition.effect
	# The Button owns input; its child carries the hover lift outside container layout.
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	visual = Control.new()
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(visual)
	var panel := Panel.new()
	panel.name = "CardFace"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var face_state := "selected" if chosen else ("normal" if usable else "disabled")
	var face := SaloonTheme.card_face(accent, face_state, 10)
	panel.add_theme_stylebox_override("panel", face)
	visual.add_child(panel)
	var band := ColorRect.new()
	band.name = "TitleBand"
	band.color = accent.darkened(0.10) if usable else accent.darkened(0.38)
	band.position = Vector2(6, 6)
	band.size = Vector2(198, 31)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.add_child(band)
	var band_glint := ColorRect.new()
	band_glint.color = Color(1, 0.86, 0.58, 0.26 if usable else 0.10)
	band_glint.position = Vector2(8, 34)
	band_glint.size = Vector2(194, 2)
	band_glint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.add_child(band_glint)
	var status_rail := ColorRect.new()
	status_rail.name = "PlayableRail"
	status_rail.color = (SaloonTheme.GOLD if chosen else accent.lightened(0.18)) if usable else Color("#777268")
	status_rail.position = Vector2(6, 42)
	status_rail.size = Vector2(4 if chosen else 3, 157)
	status_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.add_child(status_rail)
	var card_name := add_text(definition.name, Rect2(10, 8, 190, 25), 17, SaloonTheme.CREAM)
	card_name.name = "CardName"
	card_name.clip_text = false
	card_name.max_lines_visible = 2
	card_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var corner := add_text(CardInstance.corner(card), Rect2(10, 39, 62, 32), 22, CardInstance.suit_color(card.suit))
	corner.name = "RankSuitCorner"
	corner.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	if CardData.is_quick_equipment(str(card.get("card_data_id", ""))):
		var quick_badge := Panel.new()
		quick_badge.name = "QuickEquipBadge"
		quick_badge.position = Vector2(78, 42)
		quick_badge.size = Vector2(120, 20)
		quick_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		quick_badge.add_theme_stylebox_override("panel", SaloonTheme.card_badge(SaloonTheme.GOLD, usable))
		visual.add_child(quick_badge)
		var quick_text := add_text("TRANG BỊ NHANH", Rect2(80, 44, 116, 16), 9, SaloonTheme.CREAM)
		quick_text.name = "QuickEquipText"
	var artwork_frame := Panel.new()
	artwork_frame.name = "ArtworkFrame"
	artwork_frame.position = Vector2(12, 62)
	artwork_frame.size = Vector2(186, 76)
	artwork_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	artwork_frame.clip_contents = true
	artwork_frame.add_theme_stylebox_override("panel", SaloonTheme.panel(Color("#2d2722"), accent.darkened(0.15), 3))
	visual.add_child(artwork_frame)
	var artwork := TextureRect.new()
	artwork.name = "CardArtwork"
	artwork.position = Vector2(3, 3)
	artwork.size = Vector2(180, 70)
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	artwork.texture = CardArt.texture(str(card.get("card_data_id", definition.get("id", ""))))
	artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	artwork_frame.add_child(artwork)
	var type_badge := Panel.new()
	type_badge.name = "CardTypeBadge"
	type_badge.position = Vector2(55, 141)
	type_badge.size = Vector2(100, 21)
	type_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	type_badge.add_theme_stylebox_override("panel", SaloonTheme.card_badge(accent, usable))
	visual.add_child(type_badge)
	var type_text := add_text(TextCatalog.text(CardData.CardType.keys()[definition.type]), Rect2(58, 143, 94, 17), 11, SaloonTheme.CREAM)
	type_text.name = "CardType"
	var description := add_text(definition.description, Rect2(12, 163, 186, 25), 11, Color("#29333a"))
	description.name = "CardDescription"
	description.max_lines_visible = 2
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var lower := add_text(CardInstance.corner(card), Rect2(145, 190, 54, 20), 14, CardInstance.suit_color(card.suit))
	lower.name = "RankSuitLower"
	lower.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var icon := Control.new()
	icon.name = "EffectIcon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.draw.connect(func(): draw_symbol(icon))
	icon.visible = not CardArt.has_dedicated(str(card.get("card_data_id", definition.get("id", ""))))
	visual.add_child(icon)
	visual.pivot_offset = Vector2(105, 107)
	visual.scale = Vector2.ONE * (1.05 if chosen else 1.0)
	if not mouse_entered.is_connected(_hover_entered):
		mouse_entered.connect(_hover_entered)
	if not mouse_exited.is_connected(_hover_exited):
		mouse_exited.connect(_hover_exited)
	if not button_down.is_connected(_press_started):
		button_down.connect(_press_started)
	if not button_up.is_connected(_press_ended):
		button_up.connect(_press_ended)
	visual.modulate = Color("#fff8e4") if chosen else (Color.WHITE if usable else Color(0.88, 0.88, 0.84, 0.92))

func add_text(value: String, bounds: Rect2, font_size: int, color: Color) -> Label:
	var text_label := Label.new()
	text_label.text = value
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.add_theme_font_size_override("font_size", font_size)
	text_label.add_theme_color_override("font_color", color)
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.add_child(text_label)
	# Apply bounds after wrap/font changes so Label minimum-size updates cannot widen it.
	text_label.position = bounds.position
	text_label.size = bounds.size
	return text_label

func _gui_input(event: InputEvent) -> void:
	# Disabled cards remain inspectable by touch/long press.
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		holding = event.pressed
		set_process(holding)
		if event.pressed:
			hold_time = 0
			block_activation = false

func hover(raised: bool) -> void:
	if touch_layout:
		return
	if lift:
		lift.kill()
	lift = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	lift.tween_property(visual, "position:y", minf(selected_lift, -22.0 if raised and compact_mode else (-6.0 if raised else 0.0)), 0.16)
	z_index = 100 if raised else get_index()
	if raised:
		AudioManager.play_ui("hover")
		preview_requested.emit()
	else:
		preview_closed.emit()

func compact(chosen: bool, reaction: bool) -> void:
	set_meta("chosen_card", chosen)
	compact_mode = true
	custom_minimum_size = Vector2(158, 162)
	size = custom_minimum_size
	visual.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	visual.size = Vector2(210, 214)
	visual.scale = Vector2.ONE * 0.75 * (1.05 if chosen_state else 1.0)
	selected_lift = -30 if chosen else 0
	visual.position.y = selected_lift
	if reaction:
		if VisualSettings.decorative_motion():
			glow = create_tween().set_loops()
			glow.tween_property(visual, "modulate", Color("#fff0b5"), 0.55)
			glow.tween_property(visual, "modulate", Color.WHITE, 0.55)
		else:
			visual.modulate = Color("#fff0c8")

func _process(delta: float) -> void:
	if holding:
		hold_time += delta
		if hold_time >= 0.45 and not block_activation:
			block_activation = true
			preview_requested.emit()
			set_process(false)

func _hover_entered() -> void:
	hover(true)

func _hover_exited() -> void:
	hover(false)

func _press_started() -> void:
	holding = true
	hold_time = 0.0
	block_activation = false
	set_process(true)

func _press_ended() -> void:
	holding = false
	set_process(false)

func touch_compact(width: float) -> void:
	touch_layout = true
	selected_lift = 0
	custom_minimum_size = Vector2(width,width*214/210)
	size = custom_minimum_size
	var touch_scale: float = width / 210.0
	visual.scale = Vector2.ONE * touch_scale * (1.05 if chosen_state else 1.0)
	visual.position = Vector2.ZERO
	# Compensate both font and bounds before scaling. Previously the font grew
	# while CardName remained only 25 source pixels high, so its line was clipped
	# on portrait phones even though artwork and type remained visible.
	var portrait_card: bool = width >= 128.0
	var card_name: Label = visual.get_node("CardName") as Label
	var desired_title_font: float = 16.0 if portrait_card else 14.0
	if card_name.text.length() > 10:
		desired_title_font = 14.0
	var desired_title_height: float = 30.0 if portrait_card else 21.0
	var source_title_font: int = mini(38, maxi(17, ceili(desired_title_font / touch_scale)))
	var source_title_height: float = minf(52.0, maxf(34.0, desired_title_height / touch_scale))
	card_name.visible = true
	card_name.clip_text = false
	# Keep compact hand titles horizontal. Long names reduce font slightly rather
	# than turning into a vertical stack of one-character lines.
	card_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	card_name.max_lines_visible = 1
	card_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card_name.position = Vector2(8.0, 5.0)
	card_name.size = Vector2(194.0, source_title_height)
	card_name.add_theme_font_size_override("font_size", source_title_font)
	# Font changes invalidate Label's minimum size. Reapply the reserved header
	# rect afterwards so an intrinsic text minimum cannot consume the artwork.
	card_name.size = Vector2(194.0, source_title_height)
	var title_band: ColorRect = visual.get_node("TitleBand") as ColorRect
	title_band.position = Vector2(6.0, 5.0)
	title_band.size = Vector2(198.0, minf(55.0, source_title_height + 3.0))
	# Quick-equip detail remains available in the long-press preview. Hiding this
	# secondary badge prevents it from covering a two-line mobile card name.
	var quick_badge: Control = visual.get_node_or_null("QuickEquipBadge") as Control
	var quick_text: Control = visual.get_node_or_null("QuickEquipText") as Control
	if is_instance_valid(quick_badge):
		quick_badge.visible = false
	if is_instance_valid(quick_text):
		quick_text.visible = false
	visual.get_node("CardDescription").add_theme_font_size_override(
		"font_size",
		mini(36, maxi(18, int(round(15.0 / touch_scale))))
	)
	# Mobile face is glanceable: name, rank/suit, icon and type. Full rules text
	# belongs to the deliberate 0.45s long-press preview.
	visual.get_node("CardDescription").visible = false
	visual.get_node("RankSuitLower").visible = false
	# Mobile priority row below artwork: rank/suit first, then type. Its font and
	# height are also compensated so neither label collapses after card scaling.
	var rank_suit: Label = visual.get_node("RankSuitCorner") as Label
	rank_suit.position = Vector2(12.0, 140.0)
	rank_suit.size = Vector2(50.0, minf(48.0, 20.0 / touch_scale))
	rank_suit.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rank_suit.add_theme_font_size_override("font_size", mini(34, maxi(18, int(round(14.0 / touch_scale)))))
	var type_badge: Control = visual.get_node("CardTypeBadge") as Control
	type_badge.position = Vector2(66.0, 141.0)
	type_badge.size = Vector2(132.0, minf(44.0, 20.0 / touch_scale))
	var type_label: Label = visual.get_node("CardType") as Label
	type_label.position = Vector2(70.0, 141.0)
	type_label.size = Vector2(124.0, minf(44.0, 20.0 / touch_scale))
	type_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	type_label.add_theme_font_size_override("font_size", mini(32, maxi(17, int(round(13.0 / touch_scale)))))
	mouse_filter = Control.MOUSE_FILTER_STOP

func draw_symbol(icon: Control) -> void:
	var center := Vector2(105, 80)
	icon.draw_circle(center, 17, accent.darkened(0.12))
	var ink := SaloonTheme.CREAM
	match effect:
		CardData.EffectType.ATTACK, CardData.EffectType.EQUIP_WEAPON, CardData.EffectType.DUEL:
			icon.draw_line(center + Vector2(-12, -4), center + Vector2(12, -4), ink, 6)
			icon.draw_line(center + Vector2(-7, -3), center + Vector2(-3, 10), ink, 5)
			if effect == CardData.EffectType.DUEL:
				icon.draw_line(center + Vector2(7, 1), center + Vector2(3, 12), ink, 4)
		CardData.EffectType.HEAL:
			icon.draw_line(center + Vector2(-10, 0), center + Vector2(10, 0), ink, 5)
			icon.draw_line(center + Vector2(0, -10), center + Vector2(0, 10), ink, 5)
		CardData.EffectType.DODGE:
			icon.draw_arc(center, 10, -2.6, 0.8, 14, ink, 3)
			icon.draw_line(center + Vector2(8, 6), center + Vector2(0, 6), ink, 3)
		_:
			icon.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -12), center + Vector2(11, 0), center + Vector2(0, 12), center + Vector2(-11, 0)]), ink)
