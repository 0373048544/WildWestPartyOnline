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

func configure(card: Dictionary, definition: Dictionary, usable: bool, chosen: bool, reason: String = "") -> void:
	custom_minimum_size = Vector2(210, 214)
	disabled = not usable
	tooltip_text = definition.name + " · " + CardInstance.corner(card) + "\n" + definition.description + ("\n" + reason if not reason.is_empty() else "")
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
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var face := SaloonTheme.panel(Color("#ecdbb7") if usable else Color("#a8a28f"), SaloonTheme.GOLD if chosen else accent, 10)
	face.set_border_width_all(3 if chosen else 2)
	if usable and not chosen:
		face.border_color = accent.lightened(0.28)
	panel.add_theme_stylebox_override("panel", face)
	visual.add_child(panel)
	var band := ColorRect.new()
	band.color = accent if usable else accent.darkened(0.3)
	band.position = Vector2(6, 6)
	band.size = Vector2(198, 31)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.add_child(band)
	add_text(definition.name, Rect2(10, 8, 190, 25), 17, SaloonTheme.CREAM).name = "CardName"
	var corner := add_text(CardInstance.corner(card), Rect2(10, 39, 62, 32), 22, CardInstance.suit_color(card.suit))
	corner.name = "RankSuitCorner"
	corner.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_text(TextCatalog.text(CardData.CardType.keys()[definition.type]), Rect2(10, 98, 190, 18), 11, accent.darkened(0.3))
	add_text(definition.description, Rect2(12, 115, 186, 72), 13, Color("#29333a")).name = "CardDescription"
	var lower := add_text(CardInstance.corner(card), Rect2(145, 190, 54, 20), 14, CardInstance.suit_color(card.suit))
	lower.name = "RankSuitLower"
	lower.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var icon := Control.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(func(): draw_symbol(icon))
	visual.add_child(icon)
	mouse_entered.connect(func(): hover(true))
	mouse_exited.connect(func(): hover(false))
	button_down.connect(func(): holding = true; hold_time = 0; block_activation = false)
	button_up.connect(func(): holding = false)
	visual.modulate = Color("#fff0bd") if chosen else Color.WHITE

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
	visual.scale = Vector2.ONE * 0.75
	selected_lift = -30 if chosen else 0
	visual.position.y = selected_lift
	if reaction:
		var glow := create_tween().set_loops()
		glow.tween_property(visual, "modulate", Color("#fff0b5"), 0.55)
		glow.tween_property(visual, "modulate", Color.WHITE, 0.55)

func _process(delta: float) -> void:
	if holding:
		hold_time += delta
		if hold_time >= 0.45 and not block_activation:
			block_activation = true
			preview_requested.emit()

func touch_compact(width: float) -> void:
	touch_layout = true
	selected_lift = 0
	custom_minimum_size = Vector2(width,width*214/210)
	size = custom_minimum_size
	visual.scale = Vector2.ONE * width/210
	visual.position = Vector2.ZERO
	visual.get_node("CardName").add_theme_font_size_override("font_size",19)
	visual.get_node("CardDescription").add_theme_font_size_override("font_size",18)

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
