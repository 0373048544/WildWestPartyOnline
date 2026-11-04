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
var hold_touch_index: int = -1
var glow: Tween
var chosen_state: bool = false
var content_signature: String = ""
var compact_signature: String = ""
var dynamic_signature: String = ""
var touch_width_signature: float = -1.0

static var configure_calls: int = 0
static var visual_rebuilds: int = 0

func _ready() -> void:
	set_process(false)

func configure(card: Dictionary, definition: Dictionary, usable: bool, chosen: bool, reason: String = "") -> void:
	configure_calls += 1
	var next_content_signature := str([
		int(card.get("instance_id", -1)), str(card.get("card_data_id", "")),
		str(card.get("suit", "")), str(card.get("rank", "")),
		str(definition.get("name", "")), int(definition.get("type", 0)),
		int(definition.get("effect", 0)), str(definition.get("description", ""))
	])
	if next_content_signature == content_signature and is_instance_valid(visual):
		_apply_dynamic_state(definition, usable, chosen, reason)
		return
	content_signature = next_content_signature
	visual_rebuilds += 1
	compact_signature = ""
	touch_width_signature = -1.0
	dynamic_signature = "%s|%s|%s" % [usable, chosen, reason]
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
	hold_touch_index = -1
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
	band.color = Color("#8a7040") if usable else Color("#6f6653")
	band.position = Vector2(6, 6)
	band.size = Vector2(198, 33)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.add_child(band)
	var band_glint := ColorRect.new()
	band_glint.color = Color(1, 0.86, 0.58, 0.26 if usable else 0.10)
	band_glint.position = Vector2(8, 39)
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
	# WWPO_CARD_LAYOUT_V5: card hand and enlarged preview use one header hierarchy.
	var display_name: String = str(definition.get("name", "LÁ BÀI"))
	var card_name := add_text(display_name, Rect2(13, 7, 144, 28), 17, SaloonTheme.CREAM)
	card_name.name = "CardName"
	card_name.set_meta("full_title", display_name)
	card_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	card_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	card_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card_name.clip_text = false
	card_name.max_lines_visible = 1
	card_name.z_index = 3
	var corner := add_text(CardInstance.corner(card), Rect2(158, 7, 40, 28), 17, CardInstance.suit_color(card.suit))
	corner.name = "RankSuitCorner"
	corner.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	corner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	corner.autowrap_mode = TextServer.AUTOWRAP_OFF
	corner.clip_text = false
	corner.z_index = 3
	# One real Label hierarchy is shared by hand and preview. The previous V6
	# paint overlay hid these nodes and created two competing title systems.
	card_name.visible = true
	corner.visible = true

	if CardData.is_quick_equipment(str(card.get("card_data_id", ""))):
		var quick_badge := Panel.new()
		quick_badge.name = "QuickEquipBadge"
		quick_badge.visible = false
		quick_badge.position = Vector2(78, 42)
		quick_badge.size = Vector2(120, 20)
		quick_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		quick_badge.add_theme_stylebox_override("panel", SaloonTheme.card_badge(SaloonTheme.GOLD, usable))
		visual.add_child(quick_badge)
		var quick_text := add_text("TRANG BỊ NHANH", Rect2(80, 44, 116, 16), 9, SaloonTheme.CREAM)
		quick_text.name = "QuickEquipText"
		quick_text.visible = false
	var artwork_frame := Panel.new()
	artwork_frame.name = "ArtworkFrame"
	artwork_frame.position = Vector2(12, 44)
	artwork_frame.size = Vector2(186, 89)
	artwork_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	artwork_frame.clip_contents = true
	artwork_frame.add_theme_stylebox_override("panel", SaloonTheme.panel(Color("#2d2722"), accent.darkened(0.15), 3))
	visual.add_child(artwork_frame)
	var artwork := TextureRect.new()
	artwork.name = "CardArtwork"
	artwork.position = Vector2(3, 3)
	artwork.size = Vector2(180, 83)
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	artwork.texture = CardArt.texture(str(card.get("card_data_id", definition.get("id", ""))))
	artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	artwork_frame.add_child(artwork)
	var type_badge := Panel.new()
	type_badge.name = "CardTypeBadge"
	type_badge.position = Vector2(55, 137)
	type_badge.size = Vector2(100, 21)
	type_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	type_badge.add_theme_stylebox_override("panel", SaloonTheme.card_badge(accent, usable))
	visual.add_child(type_badge)
	var type_text := add_text(TextCatalog.text(CardData.CardType.keys()[definition.type]), Rect2(58, 139, 94, 17), 11, SaloonTheme.CREAM)
	type_text.name = "CardType"
	var description := add_text(str(definition.get("description", "")), Rect2(12, 164, 186, 43), 12, Color("#29333a"))
	description.name = "CardDescription"
	description.max_lines_visible = 3
	description.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var lower := add_text("", Rect2(145, 190, 54, 20), 14, CardInstance.suit_color(card.suit))
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

func _apply_dynamic_state(definition: Dictionary, usable: bool, chosen: bool, reason: String) -> void:
	var next_dynamic_signature := "%s|%s|%s" % [usable, chosen, reason]
	if next_dynamic_signature == dynamic_signature:
		return
	dynamic_signature = next_dynamic_signature
	disabled = not usable
	set_meta("disabled_reason", reason)
	chosen_state = chosen
	accent = [Color("#bc6449"), Color("#6a9b9f"), Color("#a38748"), Color("#7b719d")][int(definition.type)]
	var panel: Panel = visual.get_node_or_null("CardFace") as Panel
	if is_instance_valid(panel):
		var face_state := "selected" if chosen else ("normal" if usable else "disabled")
		panel.add_theme_stylebox_override("panel", SaloonTheme.card_face(accent, face_state, 10))
	var band: ColorRect = visual.get_node_or_null("TitleBand") as ColorRect
	if is_instance_valid(band):
		band.color = Color("#8a7040") if usable else Color("#6f6653")
	var rail: ColorRect = visual.get_node_or_null("PlayableRail") as ColorRect
	if is_instance_valid(rail):
		rail.color = (SaloonTheme.GOLD if chosen else accent.lightened(0.18)) if usable else Color("#777268")
		rail.size.x = 4 if chosen else 3
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
	if event is InputEventScreenTouch:
		if event.pressed:
			# The first finger that starts on this card owns its hold lifecycle.
			# A second finger must not cancel or complete another finger's preview.
			if hold_touch_index >= 0:
				return
			hold_touch_index = event.index
			_press_started()
		elif event.index == hold_touch_index:
			hold_touch_index = -1
			_press_ended()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_started()
		else:
			_press_ended()

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
	var next_signature := "%s|%s|%s" % [chosen, reaction, touch_layout]
	if next_signature == compact_signature:
		return
	compact_signature = next_signature
	compact_mode = true
	if not touch_layout:
		custom_minimum_size = Vector2(158, 162)
		size = custom_minimum_size
		visual.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		visual.size = Vector2(210, 214)
		visual.scale = Vector2.ONE * 0.75 * (1.05 if chosen_state else 1.0)
	# Selection is a compact hand highlight, not a second preview. Keep the lift
	# inside the requested 10-18 px range so the rendered face cannot rise behind
	# the department-store prompt or escape the HandFan bounds.
	selected_lift = -18 if chosen else 0
	visual.position.y = selected_lift
	if reaction:
		if VisualSettings.decorative_motion() and (not glow or not glow.is_valid()):
			glow = create_tween().set_loops()
			glow.tween_property(visual, "modulate", Color("#fff0b5"), 0.55)
			glow.tween_property(visual, "modulate", Color.WHITE, 0.55)
		else:
			visual.modulate = Color("#fff0c8")
	elif glow and glow.is_valid():
		glow.kill()
		glow = null
		visual.modulate = Color("#fff8e4") if chosen else (Color.WHITE if not disabled else Color(0.88, 0.88, 0.84, 0.92))

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

func cancel_touch_hold_for_drag() -> void:
	# Once HandFan classifies the gesture as a drag, neither the long-press timer
	# nor Button.pressed may turn that same gesture into a second intent.
	var was_holding: bool = holding or hold_touch_index >= 0
	holding = false
	hold_touch_index = -1
	if was_holding:
		block_activation = true
	set_process(false)

func touch_compact(width: float) -> void:
	if touch_layout and is_equal_approx(width, touch_width_signature):
		return
	var was_touch_layout := touch_layout
	touch_layout = true
	touch_width_signature = width
	selected_lift = 0.0
	custom_minimum_size = Vector2(width, width * 214.0 / 210.0)
	size = custom_minimum_size
	var touch_scale: float = maxf(0.1, width / 210.0)
	# `width` is expressed in Godot logical units. Convert the visual scale back
	# to CSS pixels before choosing fonts, otherwise Web content scaling turns a
	# nominal 12px label into roughly 8px on portrait phones.
	var logical_per_css: float = maxf(0.1, load("res://scripts/ui/MatchLayout.gd").units(self, 1.0))
	var readable_scale: float = touch_scale / logical_per_css
	# A selected hand card only lifts; it never grows into a second preview.
	visual.scale = Vector2.ONE * touch_scale
	visual.position = Vector2.ZERO
	# Card face stays identical to the desktop face: name/suit above art.
	var card_name: Label = visual.get_node("CardName") as Label
	var corner: Label = visual.get_node("RankSuitCorner") as Label
	var narrow: bool = width < load("res://scripts/ui/MatchLayout.gd").units(self, 110.0)
	var full_title: String = str(card_name.get_meta("full_title", card_name.text))
	var two_line_title: bool = full_title.length() > 7 and full_title.contains(" ")
	card_name.text = full_title
	if two_line_title:
		var title_words: PackedStringArray = full_title.split(" ", false)
		var split_at: int = ceili(float(title_words.size()) * 0.5)
		card_name.text = " ".join(title_words.slice(0, split_at)) + "\n" + " ".join(title_words.slice(split_at))
	var title_css: float = 11.5 if two_line_title else (14.5 if narrow else 15.5)
	var title_size: int = clampi(ceili(title_css / readable_scale), 20, 38)
	card_name.add_theme_font_size_override("font_size", title_size)
	card_name.position = Vector2(13, 5)
	card_name.size = Vector2(160, 64 if two_line_title else 46)
	card_name.visible = true
	card_name.clip_text = false
	card_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if two_line_title else TextServer.AUTOWRAP_OFF
	card_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card_name.max_lines_visible = 2 if two_line_title else 1
	corner.add_theme_font_size_override("font_size", clampi(ceili(11.0 / readable_scale), 14, 30))
	corner.position = Vector2(174, 5)
	corner.size = Vector2(24, 42)
	corner.visible = true
	corner.clip_text = false
	var title_band: ColorRect = visual.get_node("TitleBand") as ColorRect
	title_band.position = Vector2(6, 4)
	title_band.size = Vector2(198, 69 if two_line_title else 50)
	var artwork_frame: Control = visual.get_node("ArtworkFrame") as Control
	artwork_frame.position.y = 75.0 if two_line_title else 58.0
	artwork_frame.size.y = 77.0 if two_line_title else 94.0
	var artwork: TextureRect = artwork_frame.get_node("CardArtwork") as TextureRect
	artwork.size.y = artwork_frame.size.y - 6.0
	# Full descriptions remain readable in the deliberate long-press preview
	# instead of competing with title/artwork in the compact hand.
	var description: Label = visual.get_node("CardDescription") as Label
	description.add_theme_font_size_override("font_size", clampi(ceili(12.0 / readable_scale), 12, 30))
	description.visible = false
	var type_badge: Control = visual.get_node("CardTypeBadge") as Control
	var type_text: Label = visual.get_node("CardType") as Label
	type_badge.position.y = 160.0 if narrow else 153.0
	type_text.position.y = 162.0 if narrow else 155.0
	visual.get_node("RankSuitLower").visible = false
	var quick_badge: Control = visual.get_node_or_null("QuickEquipBadge") as Control
	var quick_text: Control = visual.get_node_or_null("QuickEquipText") as Control
	if is_instance_valid(quick_badge):
		quick_badge.visible = false
	if is_instance_valid(quick_text):
		quick_text.visible = false
	# Keep original card type and artwork geometry.
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Include the touch profile in the compact cache only after applying it once.
	if not was_touch_layout:
		compact_signature = ""

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
