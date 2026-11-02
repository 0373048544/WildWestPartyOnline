class_name WesternStatusBadge
extends PanelContainer

var text_label: Label

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_label = Label.new()
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_label.add_theme_font_size_override("font_size", 13)
	add_child(text_label)

func configure(text: String, tone: String = "neutral") -> void:
	text_label.text = text
	var color: Color = {
		"success": SaloonTheme.SUCCESS,
		"warning": SaloonTheme.WARNING,
		"danger": SaloonTheme.DANGER,
		"host": SaloonTheme.GOLD
	}.get(tone, Color("#80939a"))
	add_theme_stylebox_override("panel", SaloonTheme.badge(color))
	text_label.add_theme_color_override("font_color", Color("#fff0cf"))
