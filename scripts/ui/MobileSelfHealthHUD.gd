class_name MobileSelfHealthHUD
extends PanelContainer

# Local HP is rendered in screen space because the first-person camera hides
# the player's own 3D nameplate. The authoritative public snapshot owns HP.
var _hp_label: Label
var _heart: Control
var _panel_style: StyleBoxFlat
var _last_health_signature: String = ""

const NORMAL_BACKGROUND := Color("#412e25", 0.92)
const NORMAL_BORDER := Color("#c6a267")
const WARNING_BACKGROUND := Color("#552b25", 0.95)
const WARNING_BORDER := Color("#d58a62")
const ELIMINATED_BACKGROUND := Color("#272525", 0.96)
const ELIMINATED_BORDER := Color("#8e7660")

class HeartIcon extends Control:
	var heart_color := Color("#ffe5bb")

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(18, 18)

	func set_heart_color(value: Color) -> void:
		if heart_color != value:
			heart_color = value
			queue_redraw()

	func _draw() -> void:
		# Drawn geometry avoids relying on emoji/symbol fallback fonts in Safari.
		draw_circle(Vector2(5.5, 5.5), 4.4, heart_color)
		draw_circle(Vector2(12.5, 5.5), 4.4, heart_color)
		draw_colored_polygon(PackedVector2Array([
			Vector2(1.4, 6.2), Vector2(16.6, 6.2), Vector2(9.0, 16.2)
		]), heart_color)

func _ready() -> void:
	name = "MobileSelfHealthHUD"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = NORMAL_BACKGROUND
	_panel_style.border_color = NORMAL_BORDER
	_panel_style.set_border_width_all(1)
	_panel_style.set_corner_radius_all(7)
	_panel_style.content_margin_left = 8.0
	_panel_style.content_margin_right = 8.0
	_panel_style.content_margin_top = 5.0
	_panel_style.content_margin_bottom = 5.0
	add_theme_stylebox_override("panel", _panel_style)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	_heart = HeartIcon.new()
	row.add_child(_heart)
	_hp_label = Label.new()
	_hp_label.name = "HealthValue"
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_hp_label)

func update_health(row: Dictionary, layout: Script) -> void:
	var current_hp: int = maxi(0, int(row.get("current_hp", 0)))
	var max_hp: int = maxi(1, int(row.get("max_hp", 1)))
	var is_alive: bool = bool(row.get("is_alive", current_hp > 0))
	var health_signature := "%d:%d:%s" % [current_hp, max_hp, is_alive]
	if health_signature != _last_health_signature:
		_last_health_signature = health_signature
		if not is_alive:
			_hp_label.text = "\u0110\u00c3 LO\u1ea0I"
			_heart.visible = false
			_hp_label.add_theme_color_override("font_color", Color("#cbb9a5"))
			_panel_style.bg_color = ELIMINATED_BACKGROUND
			_panel_style.border_color = ELIMINATED_BORDER
		elif current_hp <= 0:
			_hp_label.text = "HẤP HỐI"
			_heart.visible = false
			_hp_label.add_theme_color_override("font_color", Color("#ff9b87"))
			_panel_style.bg_color = WARNING_BACKGROUND
			_panel_style.border_color = WARNING_BORDER
		elif current_hp <= 1:
			_hp_label.text = "%d/%d" % [current_hp, max_hp]
			_heart.visible = true
			_heart.set_heart_color(Color("#ffaaa0"))
			_hp_label.add_theme_color_override("font_color", Color("#ffaaa0"))
			_panel_style.bg_color = WARNING_BACKGROUND
			_panel_style.border_color = WARNING_BORDER
		else:
			_hp_label.text = "%d/%d" % [current_hp, max_hp]
			_heart.visible = true
			_heart.set_heart_color(Color("#ffe5bb"))
			_hp_label.add_theme_color_override("font_color", Color("#ffe5bb"))
			_panel_style.bg_color = NORMAL_BACKGROUND
			_panel_style.border_color = NORMAL_BORDER
	_hp_label.add_theme_font_size_override("font_size", maxi(12, int(layout.units(self, 14.0))))
	var safe: Vector4 = layout.safe_insets(self)
	var margin: float = layout.units(self, 8.0)
	var desired_size := Vector2(
		layout.units(self, 92.0 if layout.mobile_landscape(self) else 98.0),
		layout.units(self, 32.0 if layout.mobile_landscape(self) else 34.0)
	)
	custom_minimum_size = desired_size
	size = desired_size
	var viewport_width: float = get_viewport().get_visible_rect().size.x
	position = Vector2(
		maxf(safe.x + margin, viewport_width - safe.z - margin - desired_size.x),
		safe.y + layout.get_mobile_banner_height(self) + margin
	)

func health_text() -> String:
	return _hp_label.text if is_instance_valid(_hp_label) else ""

func health_signature() -> String:
	return _last_health_signature
