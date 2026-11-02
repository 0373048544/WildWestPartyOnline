class_name WesternToast
extends PanelContainer

func show_message(message: String, tone: String = "neutral", duration: float = 2.2) -> void:
	name = "OutGameToast"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 90
	var color: Color = {"success": SaloonTheme.SUCCESS, "danger": SaloonTheme.DANGER, "warning": SaloonTheme.WARNING}.get(tone, SaloonTheme.GOLD)
	add_theme_stylebox_override("panel", SaloonTheme.panel(Color("#2b2623"), color, 14))
	var label := Label.new()
	label.text = ({"success": "✓  ", "danger": "!  ", "warning": "◆  "}.get(tone, "✦  ")) + message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", SaloonTheme.CREAM)
	add_child(label)
	modulate.a = 0.0
	position.y -= 8
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.16)
	tween.parallel().tween_property(self, "position:y", position.y + 8, 0.18).set_trans(Tween.TRANS_QUAD)
	tween.tween_interval(duration)
	tween.tween_property(self, "modulate:a", 0.0, 0.18)
	tween.tween_callback(queue_free)
