extends PanelContainer

# Local HP is rendered in screen space because the first-person camera hides
# the player's own 3D nameplate. The authoritative public snapshot owns HP.
var _hp_label: Label

func _ready() -> void:
	name = "MobileSelfHealthHUD"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#412e25", 0.92)
	style.border_color = Color("#c6a267")
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	add_theme_stylebox_override("panel", style)
	_hp_label = Label.new()
	_hp_label.name = "HealthValue"
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_hp_label)

func update_health(row: Dictionary, layout: Script) -> void:
	var current_hp: int = maxi(0, int(row.get("current_hp", 0)))
	var max_hp: int = maxi(1, int(row.get("max_hp", 1)))
	_hp_label.text = "%s %d/%d" % [char(0x2665), current_hp, max_hp]
	_hp_label.add_theme_font_size_override("font_size", maxi(12, int(layout.units(self, 14.0))))
	_hp_label.add_theme_color_override("font_color", Color("#ffaaa0") if current_hp <= 1 else Color("#ffe5bb"))
	var safe: Vector4 = layout.safe_insets(self)
	var margin: float = layout.units(self, 8.0)
	var desired_size := Vector2(layout.units(self, 92.0), layout.units(self, 34.0))
	custom_minimum_size = desired_size
	size = desired_size
	var viewport_width: float = get_viewport().get_visible_rect().size.x
	position = Vector2(
		maxf(safe.x + margin, viewport_width - safe.z - margin - desired_size.x),
		safe.y + layout.get_mobile_banner_height(self) + margin
	)
