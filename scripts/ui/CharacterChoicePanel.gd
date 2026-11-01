extends VBoxContainer

var app: Node
var cards: Dictionary = {}
var confirm: Button
var selected_id: String = ""
var portraits: Dictionary = {}

func configure(owner_app: Node, options: Array) -> void:
	app = owner_app
	name = "CharacterChoicePanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	add_child(row)
	for index in range(options.size()):
		var data: Dictionary = options[index]
		var card := Button.new()
		card.name = "CharacterOption%d" % index
		card.set_meta("character_id", data.character_id)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(0, 310)
		card.tooltip_text = data.display_name + "\n" + data.ability_description_vi
		row.add_child(card)
		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		column.offset_left = 12
		column.offset_right = -12
		column.offset_top = 12
		column.offset_bottom = -12
		card.add_child(column)
		var title: Label = app.label(data.display_name, 21, column)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var portrait: Control = load("res://scripts/ui/CharacterPortrait.gd").new()
		column.add_child(portrait)
		portrait.configure(data.character_id, 145)
		portraits[data.character_id] = portrait
		card.mouse_entered.connect(func(): portrait.react("dodge"))
		var hp: Label = app.label("%d MÁU" % data.max_hp, 20, column)
		hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var icon: String = CharacterData.ability_icon(data.ability_id)
		var ability: Label = app.label(icon + " " + data.ability_description_vi, 16, column)
		ability.set_meta("ability_id", data.ability_id)
		for child in column.get_children():
			if child is Control:
				child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.pressed.connect(func(): select(data.character_id))
		cards[data.character_id] = card
	confirm = app.button("XÁC NHẬN NHÂN VẬT", commit, self, true)
	confirm.name = "ConfirmCharacter"
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
		var style := SaloonTheme.panel(Color("#354a4d") if selected else Color("#172b37"), SaloonTheme.GOLD if selected else Color("#627474"), 12)
		style.set_border_width_all(4 if selected else 1)
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

