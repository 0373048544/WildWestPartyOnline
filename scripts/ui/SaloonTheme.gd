class_name SaloonTheme
extends RefCounted

const GOLD := Color("#e7b86d")
const INK := Color("#152531")
const CREAM := Color("#f6e7c8")
const PARCHMENT := Color("#e8d29f")
const LEATHER := Color("#6d422b")
const WOOD := Color("#3f2a25")
const BRASS_DARK := Color("#9a6d38")
const PARCHMENT_LIGHT := Color("#f2e2bd")
const PARCHMENT_SHADE := Color("#c9aa72")
const INK_SOFT := Color("#27343a")
const SUCCESS := Color("#78ae75")
const WARNING := Color("#d6a552")
const DANGER := Color("#c86f58")
const SEATS: Array[Color] = [Color("#df805c"), Color("#66b7be"), Color("#d6b65c"), Color("#ad88c6"), Color("#78ae75"), Color("#d584a4"), Color("#809ede")]

static func panel(color: Color = INK, border: Color = GOLD, padding: float = 14.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_size = VisualSettings.ui_shadow_size(5)
	style.shadow_offset = Vector2(0, 4)
	return style

static func wood_panel(padding: float = 22.0) -> StyleBoxFlat:
	var style := panel(Color("#382925"), Color("#bd8847"), padding)
	style.set_border_width_all(3)
	style.set_corner_radius_all(16)
	style.shadow_color = Color(0.04, 0.025, 0.02, 0.48)
	style.shadow_size = VisualSettings.ui_shadow_size(9)
	style.shadow_offset = Vector2(0, 6)
	return style

static func hero_panel(padding: float = 18.0) -> StyleBoxFlat:
	var style := panel(Color("#172932e8"), Color("#d8a659"), padding)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.shadow_color = Color(0.03, 0.02, 0.015, 0.42)
	style.shadow_size = VisualSettings.ui_shadow_size(7)
	style.shadow_offset = Vector2(0, 5)
	return style

static func ribbon_panel(padding: float = 10.0) -> StyleBoxFlat:
	var style := panel(Color("#213239"), Color("#72553b"), padding)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.shadow_size = 0
	return style

static func parchment_panel(padding: float = 16.0) -> StyleBoxFlat:
	var style := panel(Color("#ddc58f"), Color("#895b32"), padding)
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0.08, 0.04, 0.02, 0.32)
	return style

static func inset_panel(padding: float = 14.0) -> StyleBoxFlat:
	var style := panel(Color("#13242c"), Color("#725439"), padding)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	return style

static func badge(color: Color, padding: float = 8.0) -> StyleBoxFlat:
	var style := panel(color.darkened(0.42), color, padding)
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	style.shadow_size = 0
	return style

static func button_style(color: Color, border: Color, padding: float = 14.0) -> StyleBoxFlat:
	var style := panel(color, border, padding)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_top = 11
	style.content_margin_bottom = 11
	return style

static func input_style(focused: bool = false) -> StyleBoxFlat:
	var style := panel(Color("#f1dfb7") if focused else Color("#dec89c"), GOLD if focused else Color("#8b6038"), 14)
	style.set_border_width_all(3 if focused else 2)
	style.set_corner_radius_all(9)
	style.content_margin_top = 11
	style.content_margin_bottom = 11
	style.shadow_size = VisualSettings.ui_shadow_size(3)
	return style

static func card_face(accent: Color, state: String = "normal", padding: float = 10.0) -> StyleBoxFlat:
	var background := PARCHMENT_LIGHT
	var border := accent.lightened(0.18)
	var border_width := 2
	match state:
		"selected":
			background = Color("#fff0c9")
			border = GOLD.lightened(0.12)
			border_width = 4
		"disabled":
			background = Color("#aaa58f")
			border = Color("#777163")
		"preview":
			background = Color("#ead6aa")
			border = accent.lightened(0.24)
			border_width = 3
	var style := panel(background, border, padding)
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(11)
	style.shadow_color = Color(0.06, 0.035, 0.02, 0.34 if state != "disabled" else 0.18)
	style.shadow_size = VisualSettings.ui_shadow_size(7 if state == "selected" else 4)
	style.shadow_offset = Vector2(0, 3)
	return style

static func card_badge(accent: Color, active: bool = true) -> StyleBoxFlat:
	var style := badge(accent if active else Color("#777163"), 7)
	style.bg_color = (accent.darkened(0.34) if active else Color("#625f57"))
	style.border_color = accent.lightened(0.24) if active else Color("#817d72")
	style.set_corner_radius_all(7)
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style

static func create() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 17
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI", "Arial", "DejaVu Sans"])
	theme.default_font = font
	theme.set_stylebox("panel", "PanelContainer", wood_panel(22))
	theme.set_stylebox("normal", "Button", button_style(Color("#56392b"), Color("#a87843")))
	theme.set_stylebox("hover", "Button", button_style(Color("#745039"), GOLD))
	theme.set_stylebox("pressed", "Button", button_style(Color("#3e2b25"), GOLD))
	theme.set_stylebox("focus", "Button", panel(Color(0, 0, 0, 0), GOLD))
	theme.set_stylebox("disabled", "Button", button_style(Color("#342f2c"), Color("#655d53")))
	theme.set_stylebox("normal", "LineEdit", input_style(false))
	theme.set_stylebox("focus", "LineEdit", input_style(true))
	theme.set_color("font_color", "Label", CREAM)
	theme.set_color("font_color", "Button", CREAM)
	theme.set_color("font_hover_color", "Button", Color("#fff4d8"))
	theme.set_color("font_disabled_color", "Button", Color("#a1a9ac"))
	theme.set_color("font_color", "LineEdit", Color("#352820"))
	theme.set_color("font_placeholder_color", "LineEdit", Color("#765f4c"))
	theme.set_color("caret_color", "LineEdit", Color("#6e3b25"))
	theme.set_color("selection_color", "LineEdit", Color(0.55, 0.32, 0.17, 0.35))
	theme.set_constant("minimum_character_width", "LineEdit", 8)
	return theme
