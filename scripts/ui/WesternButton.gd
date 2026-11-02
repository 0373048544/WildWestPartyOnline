extends Button

var feedback: Tween
var hovered: bool = false
var variant: String = "secondary"

func _ready() -> void:
	custom_minimum_size.y = maxf(custom_minimum_size.y, 48.0)
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	resized.connect(func(): pivot_offset = size / 2)
	mouse_entered.connect(func(): hovered = true; animate_scale(Vector2.ONE * 1.03))
	mouse_exited.connect(func(): hovered = false; animate_scale(Vector2.ONE))
	button_down.connect(func(): animate_scale(Vector2(0.98, 0.94)))
	button_up.connect(func(): animate_scale(Vector2.ONE * (1.03 if hovered else 1.0)))
	focus_mode = Control.FOCUS_ALL
	apply_variant(variant)

func set_variant(value: String) -> void:
	variant = value
	if is_node_ready():
		apply_variant(value)

func apply_variant(value: String) -> void:
	var normal_color := Color("#56392b")
	var hover_color := Color("#745039")
	var border := Color("#a87843")
	match value:
		"primary":
			normal_color = Color("#8c562f")
			hover_color = Color("#aa713c")
			border = Color("#f0bf68")
			add_theme_font_size_override("font_size", 19)
			custom_minimum_size.y = maxf(custom_minimum_size.y, 56)
		"danger":
			normal_color = Color("#713a31")
			hover_color = Color("#8b493b")
			border = Color("#d78365")
		"quiet":
			normal_color = Color("#26343a")
			hover_color = Color("#35464b")
			border = Color("#79634b")
		_:
			add_theme_font_size_override("font_size", 16)
	add_theme_stylebox_override("normal", SaloonTheme.button_style(normal_color, border))
	add_theme_stylebox_override("hover", SaloonTheme.button_style(hover_color, border.lightened(0.14)))
	add_theme_stylebox_override("pressed", SaloonTheme.button_style(normal_color.darkened(0.20), border))
	add_theme_stylebox_override("focus", SaloonTheme.button_style(normal_color.lightened(0.05), Color("#ffe2a0"), 12))
	add_theme_stylebox_override("disabled", SaloonTheme.button_style(Color("#342f2c"), Color("#655d53")))

func animate_scale(value: Vector2) -> void:
	if disabled:
		return
	if feedback:
		feedback.kill()
	pivot_offset = size / 2
	feedback = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	feedback.tween_property(self, "scale", value, 0.12)
