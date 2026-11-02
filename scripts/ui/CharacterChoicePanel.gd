extends VBoxContainer

var app: Node
var cards: Dictionary = {}
var confirm: Button
var selected_id: String = ""
var portraits: Dictionary = {}
var option_order: Array[String] = []
var carousel_index: int = 0
var carousel_mode: bool = false
var carousel_counter: Label
var navigation: HBoxContainer

func configure(owner_app: Node, options: Array) -> void:
	app = owner_app
	name = "CharacterChoicePanel"
	var layout: Script = load("res://scripts/ui/MatchLayout.gd")
	var mobile: bool = bool(layout.mobile_portrait(self) or layout.mobile_landscape(self))
	var landscape_phone: bool = bool(layout.mobile_landscape(self))
	carousel_mode = bool(layout.character_choice_carousel(self))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", int(layout.units(self, 6.0 if mobile else 12.0)))
	var body := CenterContainer.new()
	body.name = "CharacterCardArea"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	var row := HBoxContainer.new()
	row.name = "CharacterOptionsRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var css: Vector2 = layout.css_size(self)
	var gap_css: float = 10.0 if mobile else 20.0
	var card_width_css: float
	if carousel_mode:
		card_width_css = minf(360.0, maxf(240.0, css.x - 48.0))
	elif mobile:
		var horizontal_reserve_css: float = 48.0 if landscape_phone else 60.0
		card_width_css = clampf((css.x - horizontal_reserve_css - gap_css) * 0.5, 150.0, 215.0)
	else:
		card_width_css = 320.0
	var card_width: float = layout.units(self, card_width_css) if mobile else card_width_css
	var card_gap: float = layout.units(self, gap_css) if mobile else gap_css
	row.add_theme_constant_override("separation", int(card_gap))
	var visible_card_count: int = 1 if carousel_mode else options.size()
	row.custom_minimum_size.x = card_width * visible_card_count + card_gap * maxi(0, visible_card_count - 1)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	for index in range(options.size()):
		var data: Dictionary = options[index]
		var character_id := str(data.character_id)
		option_order.append(character_id)
		var option_accent: Color = SaloonTheme.SEATS[index % SaloonTheme.SEATS.size()]
		var card := Button.new()
		card.name = "CharacterOption%d" % index
		card.set_meta("character_id", data.character_id)
		card.set_meta("option_accent", option_accent)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if mobile:
			var card_height_css: float
			if landscape_phone:
				card_height_css = clampf(css.y - 190.0, 154.0, 236.0)
			elif carousel_mode:
				card_height_css = clampf(css.y - 255.0, 360.0, 510.0)
			else:
				card_height_css = clampf(css.y - 215.0, 410.0, 640.0)
			card.custom_minimum_size = Vector2(card_width, layout.units(self, card_height_css))
		else:
			card.custom_minimum_size = Vector2(card_width, 370.0)
		card.tooltip_text = data.display_name + "\n" + data.ability_description_vi
		card.add_theme_stylebox_override("normal", SaloonTheme.panel(Color("#172b37"), option_accent.darkened(0.14), 12))
		card.add_theme_stylebox_override("hover", SaloonTheme.panel(Color("#223b43"), option_accent.lightened(0.18), 12))
		card.add_theme_stylebox_override("pressed", SaloonTheme.panel(Color("#10232d"), SaloonTheme.GOLD, 12))
		card.add_theme_stylebox_override("focus", SaloonTheme.panel(Color(0, 0, 0, 0), SaloonTheme.GOLD, 10))
		row.add_child(card)
		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		column.add_theme_constant_override("separation", int(layout.units(self, 2.0 if landscape_phone else 5.0)))
		var inset: float = float(layout.units(self, 6.0 if landscape_phone else (8.0 if mobile else 12.0)))
		column.offset_left = inset
		column.offset_right = -inset
		column.offset_top = inset
		column.offset_bottom = -inset
		card.add_child(column)
		var title: Label = app.label(data.display_name, 16 if landscape_phone else (18 if mobile else 21), column)
		title.name = "CharacterName"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var portrait: Control = load("res://scripts/ui/CharacterPortrait.gd").new()
		column.add_child(portrait)
		var portrait_css: float
		if landscape_phone:
			portrait_css = clampf(css.y * 0.22, 70.0, 92.0)
		elif mobile:
			portrait_css = clampf(css.y * (0.32 if carousel_mode else 0.27), 112.0, 224.0)
		else:
			portrait_css = 145.0
		portrait.configure(data.character_id, int(layout.units(self, portrait_css)) if mobile else int(portrait_css))
		portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
		portraits[data.character_id] = portrait
		card.mouse_entered.connect(func(): portrait.react("dodge"))
		var hp: Label = app.label("%d MÁU" % data.max_hp, 13 if landscape_phone else (16 if mobile else 20), column)
		hp.name = "CharacterHP"
		hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var icon: String = CharacterData.ability_icon(data.ability_id)
		var ability: Label = app.label(icon + " " + data.ability_description_vi, 11 if landscape_phone else (13 if mobile else 16), column)
		ability.name = "CharacterAbility"
		ability.max_lines_visible = 2 if mobile else 3
		ability.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		ability.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ability.set_meta("ability_id", data.ability_id)
		var choose_badge := PanelContainer.new()
		choose_badge.name = "ChooseBadge"
		choose_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		choose_badge.custom_minimum_size.y = layout.units(self, 44.0 if mobile else 38.0)
		choose_badge.add_theme_stylebox_override("panel", SaloonTheme.panel(Color("#8e541f"), SaloonTheme.GOLD, 9))
		column.add_child(choose_badge)
		var choose_text: Label = app.label("CHỌN", 14 if mobile else 15, choose_badge)
		choose_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		choose_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		choose_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child in column.get_children():
			if child is Control:
				child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.pressed.connect(select.bind(str(data.character_id)))
		cards[data.character_id] = card
	if carousel_mode:
		build_carousel_navigation(layout)
		show_carousel_card(0, false)
	confirm = app.button("XÁC NHẬN NHÂN VẬT", commit, self, true)
	confirm.name = "ConfirmCharacter"
	confirm.custom_minimum_size.y = layout.units(self, 44.0 if landscape_phone else 48.0) if layout.mobile(self) else 46.0
	if cards.has(app.character_draft):
		select(app.character_draft)

func build_carousel_navigation(layout: Script) -> void:
	navigation = HBoxContainer.new()
	navigation.name = "CharacterCarouselNavigation"
	navigation.alignment = BoxContainer.ALIGNMENT_CENTER
	navigation.add_theme_constant_override("separation", int(layout.units(self, 10.0)))
	add_child(navigation)
	var previous: Button = app.button("‹", func(): show_carousel_card(carousel_index - 1), navigation, false)
	previous.name = "PreviousCharacter"
	previous.custom_minimum_size = Vector2(layout.units(self, 48.0), layout.units(self, 44.0))
	carousel_counter = app.label("", 14, navigation)
	carousel_counter.name = "CharacterCarouselCounter"
	carousel_counter.custom_minimum_size.x = layout.units(self, 72.0)
	carousel_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var next: Button = app.button("›", func(): show_carousel_card(carousel_index + 1), navigation, false)
	next.name = "NextCharacter"
	next.custom_minimum_size = Vector2(layout.units(self, 48.0), layout.units(self, 44.0))

func show_carousel_card(index: int, animate: bool = true) -> void:
	if option_order.is_empty():
		return
	carousel_index = posmod(index, option_order.size())
	for option_index in range(option_order.size()):
		var card: Button = cards[option_order[option_index]]
		card.visible = option_index == carousel_index
		if card.visible and animate:
			card.modulate.a = 0.55
			card.position.x = 12.0
			var reveal := card.create_tween().set_parallel(true)
			reveal.tween_property(card, "modulate:a", 1.0, 0.14)
			reveal.tween_property(card, "position:x", 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if is_instance_valid(carousel_counter):
		carousel_counter.text = "%d / %d" % [carousel_index + 1, option_order.size()]

func select(id: String) -> void:
	if not cards.has(id):
		return
	selected_id = id
	portraits[id].react("drink")
	AudioManager.play_card("select")
	app.character_draft = id
	for key in cards:
		var selected: bool = key == id
		var option_accent: Color = cards[key].get_meta("option_accent", Color("#627474"))
		var style := SaloonTheme.panel(Color("#354a4d") if selected else Color("#172b37"), SaloonTheme.GOLD if selected else option_accent.darkened(0.14), 12)
		style.set_border_width_all(4 if selected else 1)
		style.shadow_color = Color(0, 0, 0, 0.42 if selected else 0.22)
		style.shadow_size = VisualSettings.ui_shadow_size(8 if selected else 3)
		cards[key].add_theme_stylebox_override("normal", style)
		cards[key].add_theme_stylebox_override("focus", style)
		cards[key].add_theme_stylebox_override("hover", style)
		cards[key].modulate = Color("#ffe9b7") if selected else Color.WHITE
		cards[key].pivot_offset = cards[key].size / 2
		var pop: Tween = cards[key].create_tween().set_trans(Tween.TRANS_BACK)
		pop.tween_property(cards[key], "scale", Vector2.ONE * (1.018 if selected else 1.0), 0.18)
	confirm.disabled = false

func commit() -> void:
	if selected_id.is_empty() or confirm.disabled:
		return
	confirm.disabled = true
	portraits[selected_id].react("shoot")
	AudioManager.play_ui("confirm")
	app.intent("character", {"character": selected_id})

