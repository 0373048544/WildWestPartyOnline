class_name SaloonTheme
extends RefCounted

const GOLD := Color("#e7b86d")
const INK := Color("#152531")
const CREAM := Color("#f6e7c8")
const SEATS: Array[Color] = [Color("#df805c"), Color("#66b7be"), Color("#d6b65c"), Color("#ad88c6"), Color("#78ae75"), Color("#d584a4"), Color("#809ede")]

static func panel(color: Color = INK, border: Color = GOLD, padding: float = 14.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 4)
	return style

static func create() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 17
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI", "Arial", "DejaVu Sans"])
	theme.default_font = font
	theme.set_stylebox("panel", "PanelContainer", panel(Color("#182933"), Color("#806445"), 22))
	theme.set_stylebox("normal", "Button", panel(Color("#263744"), Color("#99764e")))
	theme.set_stylebox("hover", "Button", panel(Color("#45504b"), GOLD))
	theme.set_stylebox("pressed", "Button", panel(Color("#715335"), GOLD))
	theme.set_stylebox("focus", "Button", panel(Color(0, 0, 0, 0), GOLD))
	theme.set_stylebox("disabled", "Button", panel(Color("#24303a"), Color("#536067")))
	theme.set_stylebox("normal", "LineEdit", panel(Color("#0f202c"), Color("#806445")))
	theme.set_stylebox("focus", "LineEdit", panel(Color("#172e3c"), GOLD))
	theme.set_color("font_color", "Label", CREAM)
	theme.set_color("font_color", "Button", CREAM)
	theme.set_color("font_hover_color", "Button", Color("#fff4d8"))
	theme.set_color("font_disabled_color", "Button", Color("#a1a9ac"))
	theme.set_color("font_color", "LineEdit", CREAM)
	return theme
