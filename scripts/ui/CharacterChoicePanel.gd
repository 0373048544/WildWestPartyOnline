extends VBoxContainer

var app: Node
var cards: Dictionary = {}
var confirm: Button
var selected_id: String = ""
var portraits: Dictionary = {}

func configure(owner_app: Node, options: Array) -> void:
	app = owner_app
	name = "CharacterChoicePanel"
	var layout: Script = load("res://scripts/ui/MatchLayout.gd")
	var landscape_phone: bool = bool(layout.mobile_landscape(self))
	var portrait_phone: bool = bool(layout.mobile_portrait(self))
	var body := ScrollContainer.new()
	body.name = "CharacterOptionsScroll"
	body.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if portrait_phone else ScrollContainer.SCROLL_MODE_DISABLED
	body.custom_minimum_size.y = layout.units(self, 178.0) if landscape_phone else (layout.units(self, 480.0) if portrait_phone else 330.0)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(body)
	var row: Container = VBoxContainer.new() if portrait_phone else HBoxContainer.new()
	row.add_theme_constant_override("separation", int(layout.units(self, 8.0 if landscape_phone else 14.0)))
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	for index in range(options.size()):
		var data: Dictionary = options[index]
		var option_accent: Color = SaloonTheme.SEATS[index % SaloonTheme.SEATS.size()]
		var card := Button.new()
		card.name = "CharacterOption%d" % index
		card.set_meta("character_id", data.character_id)
		card.set_meta("option_accent", option_accent)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(0, layout.units(self, 166.0) if landscape_phone else (layout.units(self, 286.0) if portrait_phone else 310.0))
		card.tooltip_text = data.display_name + "\n" + data.ability_description_vi
		card.add_theme_stylebox_override("normal", SaloonTheme.panel(Color("#172b37"), option_accent.darkened(0.14), 12))
		card.add_theme_stylebox_override("hover", SaloonTheme.panel(Color("#223b43"), option_accent.lightened(0.18), 12))
		card.add_theme_stylebox_override("pressed", SaloonTheme.panel(Color("#10232d"), SaloonTheme.GOLD, 12))
		card.add_theme_stylebox_override("focus", SaloonTheme.panel(Color(0, 0, 0, 0), SaloonTheme.GOLD, 10))
		row.add_child(card)
		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var inset: float = float(layout.units(self, 6.0 if landscape_phone else 12.0))
		column.offset_left = inset
		column.offset_right = -inset
		column.offset_top = inset
		column.offset_bottom = -inset
		card.add_child(column)
		var title: Label = app.label(data.display_name, 17 if landscape_phone else 21, column)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var portrait: Control = load("res://scripts/ui/CharacterPortrait.gd").new()
		column.add_child(portrait)
		portrait.configure(data.character_id, int(layout.units(self, 58.0 if landscape_phone else (112.0 if portrait_phone else 145.0))))
		portraits[data.character_id] = portrait
		card.mouse_entered.connect(func(): portrait.react("dodge"))
		var hp: Label = app.label("%d MÁU" % data.max_hp, 15 if landscape_phone else 20, column)
		hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var icon: String = CharacterData.ability_icon(data.ability_id)
		var ability: Label = app.label(icon + " " + data.ability_description_vi, 13 if landscape_phone else 16, column)
		ability.max_lines_visible = 2 if landscape_phone else 3
		ability.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		ability.set_meta("ability_id", data.ability_id)
		for child in column.get_children():
			if child is Control:
				child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.pressed.connect(select.bind(str(data.character_id)))
		cards[data.character_id] = card
	confirm = app.button("XÁC NHẬN NHÂN VẬT", commit, self, true)
	confirm.name = "ConfirmCharacter"
	confirm.custom_minimum_size.y = layout.units(self, 44.0 if landscape_phone else 48.0) if layout.mobile(self) else 46.0
	if cards.has(app.character_draft):
		select(app.character_draft)

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

