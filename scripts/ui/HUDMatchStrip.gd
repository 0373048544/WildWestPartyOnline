extends PanelContainer

var countdown: Label
var deadline: float = 0

func configure(title: String, phase: String, remaining: float) -> void:
	name = "MatchStrip"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layout: Script = load("res://scripts/ui/MatchLayout.gd")
	var compact_landscape: bool = bool(layout.mobile_landscape(self))
	var phone: bool = bool(layout.mobile_portrait(self) or compact_landscape)
	var style := SaloonTheme.panel(Color(0.12,0.16,0.17,0.82),Color("#a78150"),10)
	style.set_border_width_all(1)
	style.content_margin_top = layout.units(self, 3.0 if compact_landscape else 4.0) if phone else 6
	style.content_margin_bottom = style.content_margin_top
	style.shadow_size = 2
	add_theme_stylebox_override("panel",style)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation",8 if compact_landscape else 12)
	add_child(row)
	var marker := ColorRect.new()
	marker.name = "TurnMarker"
	marker.color = SaloonTheme.GOLD
	marker.custom_minimum_size = Vector2(layout.units(self, 3.0), layout.units(self, 22.0 if compact_landscape else 24.0)) if phone else Vector2(4, 28)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(marker)
	var label := Label.new()
	label.text = title if phone else title + "  ·  " + phase
	label.tooltip_text = title + " · " + phase
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	label.custom_minimum_size.x = 0.0
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", int(layout.units(self, 13.0 if compact_landscape else 14.0)) if phone else 17)
	label.add_theme_color_override("font_color",SaloonTheme.CREAM)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	countdown = Label.new()
	countdown.add_theme_font_size_override("font_size", int(layout.units(self, 13.0)) if phone else 17)
	countdown.add_theme_color_override("font_color",SaloonTheme.GOLD)
	countdown.add_theme_stylebox_override("normal", SaloonTheme.badge(SaloonTheme.GOLD, 7))
	countdown.custom_minimum_size.x = layout.units(self, 48.0) if phone else 58
	countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(countdown)
	deadline = Time.get_ticks_msec()/1000.0 + remaining
	countdown.visible = remaining > 0
	set_process(countdown.visible)
	modulate.a = 0.6
	create_tween().tween_property(self,"modulate:a",1.0,0.12)

func _process(_delta: float) -> void:
	if countdown and countdown.visible:
		var remaining := maxf(0,deadline-Time.get_ticks_msec()/1000.0)
		countdown.text = "%.1f s" % remaining
		if remaining <= 0:
			set_process(false)
