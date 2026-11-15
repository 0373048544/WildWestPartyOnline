class_name WesternStatusBadge
extends PanelContainer

var text_label: Label
var _signature := ""
static var _style_cache: Dictionary = {}

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_label = Label.new()
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_label.add_theme_font_size_override("font_size", 13)
	add_child(text_label)

func configure(text: String, tone: String = "neutral") -> void:
	var next_signature := "%s|%s" % [text, tone]
	if next_signature == _signature:
		return
	_signature = next_signature
	text_label.text = text
	if not _style_cache.has(tone):
		var color: Color = {
			"success": SaloonTheme.SUCCESS,
			"warning": SaloonTheme.WARNING,
			"danger": SaloonTheme.DANGER,
			"host": SaloonTheme.GOLD
		}.get(tone, Color("#80939a"))
		_style_cache[tone] = SaloonTheme.badge(color)
	add_theme_stylebox_override("panel", _style_cache[tone])
	text_label.add_theme_color_override("font_color", Color("#fff0cf"))
