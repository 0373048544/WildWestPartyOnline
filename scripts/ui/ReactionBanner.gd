extends Control

var app: Node
var request_id: int = 0
var deadline: float = 0.0
var primary_card: int = -1
var secondary_card: int = -1
var layout: Script = preload("res://scripts/ui/MatchLayout.gd")

@onready var banner: Panel = $Banner
@onready var icon: Label = $Banner/Content/TitleRow/Icon
@onready var title_label: Label = $Banner/Content/TitleRow/Title
@onready var countdown: Label = $Banner/Content/TitleRow/Countdown
@onready var detail_label: Label = $Banner/Content/Detail
@onready var primary_button: Button = $Banner/Content/Actions/Primary
@onready var secondary_button: Button = $Banner/Content/Actions/Secondary
@onready var skip_button: Button = $Banner/Content/Actions/Skip

func _ready() -> void:
	z_index = layout.Z_REACTION
	name = "ReactionBanner"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	visible = false
	resized.connect(_apply_layout)
	primary_button.pressed.connect(_primary)
	secondary_button.pressed.connect(_secondary)
	skip_button.pressed.connect(_skip)

func present(owner_app: Node, active: Dictionary, state: Dictionary) -> void:
	if active.is_empty() or not ["dodge", "duel", "indians", "survive"].has(str(active.get("reaction_type", ""))):
		hide_banner()
		return
	app = owner_app
	var next_id := int(active.get("request_id", 0))
	var is_new := next_id != request_id or not visible
	request_id = next_id
	deadline = Time.get_ticks_msec() / 1000.0 + float(active.get("remaining", 0.0))
	var actor := _player_name(int(active.get("source_player_id", 0)), state)
	var kind := str(active.get("reaction_type", ""))
	var copy := _copy_for(kind, actor)
	title_label.text = copy.title
	detail_label.text = copy.detail
	icon.text = copy.icon
	primary_button.text = copy.primary
	skip_button.text = TextCatalog.text("SKIP REACTION")
	var allowed: Array = active.get("allowed_card_types", [])
	primary_card = int(allowed[0]) if not allowed.is_empty() else -1
	secondary_card = -1
	secondary_button.visible = false
	if kind == "survive":
		_configure_survival_actions(active)
	primary_button.disabled = primary_card < 0
	secondary_button.disabled = secondary_card < 0
	skip_button.disabled = false
	primary_button.tooltip_text = TextCatalog.text("No valid reaction card in hand.") if primary_button.disabled else copy.detail
	_style_banner(kind)
	_apply_layout()
	visible = true
	set_process(true)
	if is_new:
		# AudioManager.observe_state() owns the request-ID-scoped reaction cue.
		# Rendering/rebuilding this banner must never replay semantic audio.
		_animate_in()

func hide_banner() -> void:
	request_id = 0
	primary_card = -1
	secondary_card = -1
	secondary_button.visible = false
	visible = false
	set_process(false)
	if get_viewport().has_meta("reaction_banner_rect"):
		get_viewport().remove_meta("reaction_banner_rect")
	_invalidate_nameplates()

func _process(_delta: float) -> void:
	countdown.text = "%.1f s" % maxf(0.0, deadline - Time.get_ticks_msec() / 1000.0)

func _primary() -> void:
	if primary_card < 0 or not is_instance_valid(app):
		return
	AudioManager.play_ui("confirm")
	primary_button.disabled = true
	secondary_button.disabled = true
	skip_button.disabled = true
	app.intent("reaction", {"request": request_id, "accept": true, "card": primary_card})
	_animate_out()

func _secondary() -> void:
	if secondary_card < 0 or not is_instance_valid(app):
		return
	AudioManager.play_ui("confirm")
	primary_button.disabled = true
	secondary_button.disabled = true
	skip_button.disabled = true
	app.intent("reaction", {"request": request_id, "accept": true, "card": secondary_card})
	_animate_out()

func _skip() -> void:
	if not is_instance_valid(app):
		return
	AudioManager.play_ui("button")
	primary_button.disabled = true
	secondary_button.disabled = true
	skip_button.disabled = true
	app.intent("reaction", {"request": request_id, "accept": false})
	_animate_out()

func _copy_for(kind: String, actor: String) -> Dictionary:
	match kind:
		"dodge":
			return {"title": TextCatalog.text("%s is shooting you!") % actor,
				"detail": TextCatalog.text("Use DODGE or take 1 damage"),
				"primary": TextCatalog.text("USE DODGE"), "icon": "✦"}
		"duel":
			return {"title": TextCatalog.text("%s challenges you to a Duel!") % actor,
				"detail": TextCatalog.text("Use BANG! or take 1 damage"),
				"primary": TextCatalog.text("USE BANG"), "icon": "♠"}
		"indians":
			return {"title": TextCatalog.text("Indians attack!"),
				"detail": TextCatalog.text("Use BANG! or take 1 damage"),
				"primary": TextCatalog.text("USE BANG"), "icon": "!"}
		"survive":
			return {"title": "BẠN ĐANG HẤP HỐI!",
				"detail": "Dùng BIA hoặc TRÀ ĐÁ để hồi 1 máu.",
				"primary": "DÙNG BIA", "icon": "♥"}
	return {"title": "", "detail": "", "primary": "", "icon": "✦"}

func _configure_survival_actions(active: Dictionary) -> void:
	secondary_card = -1
	secondary_button.visible = false
	var beer_id: int = -1
	var tea_id: int = -1
	for option in active.get("survival_options", []):
		match str(option.get("card_data_id", "")):
			"drink":
				if beer_id < 0:
					beer_id = int(option.get("instance_id", -1))
			"iced_tea":
				if tea_id < 0:
					tea_id = int(option.get("instance_id", -1))
	if beer_id >= 0:
		primary_card = beer_id
		primary_button.text = "DÙNG BIA"
		if tea_id >= 0:
			secondary_card = tea_id
			secondary_button.text = "DÙNG TRÀ ĐÁ"
			secondary_button.visible = true
			detail_label.text = "Chọn BIA hoặc TRÀ ĐÁ để hồi 1 máu."
		else:
			detail_label.text = "Dùng BIA để hồi 1 máu."
	elif tea_id >= 0:
		primary_card = tea_id
		primary_button.text = "DÙNG TRÀ ĐÁ"
		detail_label.text = "Dùng TRÀ ĐÁ để hồi 1 máu."

func _player_name(id: int, state: Dictionary) -> String:
	for player in state.get("players", []):
		if int(player.get("player_id", 0)) == id:
			return str(player.get("display_name", TextCatalog.text("Cowboy")))
	return TextCatalog.text("Cowboy")

func _style_banner(kind: String) -> void:
	var border := Color("#d97752") if kind in ["dodge", "survive"] else SaloonTheme.GOLD
	banner.add_theme_stylebox_override("panel", SaloonTheme.panel(Color(0.055, 0.075, 0.075, 0.97), border, 18))
	var main := SaloonTheme.panel(Color("#76502d"), Color("#f2c471"), 12)
	main.shadow_color = Color(0.95, 0.63, 0.2, 0.28)
	main.shadow_size = VisualSettings.ui_shadow_size(8)
	primary_button.add_theme_stylebox_override("normal", main)
	primary_button.add_theme_stylebox_override("hover", SaloonTheme.panel(Color("#8d6135"), Color("#ffe0a0"), 12))
	primary_button.add_theme_stylebox_override("disabled", SaloonTheme.panel(Color("#2c3232"), Color("#555c5b"), 12))
	secondary_button.add_theme_stylebox_override("normal", main)
	secondary_button.add_theme_stylebox_override("hover", SaloonTheme.panel(Color("#8d6135"), Color("#ffe0a0"), 12))
	secondary_button.add_theme_stylebox_override("disabled", SaloonTheme.panel(Color("#2c3232"), Color("#555c5b"), 12))
	skip_button.add_theme_stylebox_override("normal", SaloonTheme.panel(Color("#242b2c"), Color("#806445"), 12))

func _apply_layout() -> void:
	if not is_instance_valid(banner):
		return
	var mobile: bool = layout.mobile(self)
	var short_landscape := mobile and size.x > size.y
	var safe: Vector4 = layout.safe_insets(self) if mobile else Vector4.ZERO
	var width: float = minf(layout.units(self, 420 if short_landscape else 540), size.x - safe.x - safe.z - layout.units(self, 20))
	var height: float = layout.units(self, 108 if short_landscape else (150 if mobile else 138))
	var top: float = safe.y + (
		layout.get_mobile_banner_height(self) + layout.units(self, 4.0)
		if short_landscape
		else layout.units(self, 62 if mobile else 58)
	)
	primary_button.custom_minimum_size.y = layout.units(self, 44 if mobile else 40)
	secondary_button.custom_minimum_size.y = primary_button.custom_minimum_size.y
	skip_button.custom_minimum_size.y = primary_button.custom_minimum_size.y
	primary_button.add_theme_font_size_override("font_size", int(layout.units(self, 15)))
	secondary_button.add_theme_font_size_override("font_size", int(layout.units(self, 14)))
	skip_button.add_theme_font_size_override("font_size", int(layout.units(self, 15)))
	title_label.add_theme_font_size_override("font_size", int(layout.units(self, 18 if short_landscape else (20 if mobile else 21))))
	detail_label.add_theme_font_size_override("font_size", int(layout.units(self, 13 if short_landscape else 14)))
	# Child minimum-size changes can resize a Container. Apply the final panel rect last.
	var left := (size.x - width) * 0.5
	banner.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	banner.offset_left = left
	banner.offset_top = top
	banner.offset_right = left + width
	banner.offset_bottom = top + height
	get_viewport().set_meta("reaction_banner_rect", banner.get_global_rect().grow(layout.units(self, 6)))
	_invalidate_nameplates()

func _invalidate_nameplates() -> void:
	if is_instance_valid(app) and is_instance_valid(app.table):
		app.table.plate_layout_key = ""
		app.table.call_deferred("layout_nameplates")

func _animate_in() -> void:
	var target := banner.position
	banner.position.y -= layout.units(self, 8)
	banner.modulate.a = 0.0
	banner.scale = Vector2(0.985, 0.985)
	var tween := banner.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(banner, "position", target, 0.20)
	tween.parallel().tween_property(banner, "modulate:a", 1.0, 0.16)
	tween.parallel().tween_property(banner, "scale", Vector2.ONE, 0.20)

func _animate_out() -> void:
	if not visible:
		return
	var tween := banner.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(banner, "modulate:a", 0.0, 0.14)
	tween.parallel().tween_property(banner, "position:y", banner.position.y - layout.units(self, 8), 0.14)
