extends PanelContainer

var countdown: Label
var deadline: float = 0

func configure(title: String, phase: String, remaining: float) -> void:
	name = "MatchStrip"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := SaloonTheme.panel(Color(0.12,0.16,0.17,0.82),Color("#a78150"),10)
	style.set_border_width_all(1)
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.shadow_size = 2
	add_theme_stylebox_override("panel",style)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation",12)
	add_child(row)
	var label := Label.new()
	label.text = title + "  ·  " + phase
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size",17)
	label.add_theme_color_override("font_color",SaloonTheme.CREAM)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	countdown = Label.new()
	countdown.add_theme_font_size_override("font_size",17)
	countdown.add_theme_color_override("font_color",SaloonTheme.GOLD)
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
