extends Control

var app: Node
var panel: PanelContainer
var icon: Label
var message: Label
var action: Button
var shown_status := NetworkManager.CONNECTION_IDLE
var previous_status := NetworkManager.CONNECTION_IDLE
var hide_at := 0
var spinner_step := 0
var spinner_at := 0
var layout: Script = preload("res://scripts/ui/MatchLayout.gd")

func _ready() -> void:
	name = "ConnectionStatusBanner"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = layout.Z_TOAST
	visible = false
	set_process(false)
	resized.connect(_position)

func setup(owner_app: Node) -> void:
	app = owner_app
	if not NetworkManager.connection_status_changed.is_connected(sync):
		NetworkManager.connection_status_changed.connect(sync)
	sync(NetworkManager.connection_status)

func sync(status: String) -> void:
	var was_recovering := shown_status in [
		NetworkManager.CONNECTION_RECONNECTING,
		NetworkManager.CONNECTION_DISCONNECTED
	]
	previous_status = shown_status
	shown_status = status
	hide_at = 0
	match status:
		NetworkManager.CONNECTION_RECONNECTING:
			_show("⌁", "MẤT KẾT NỐI — ĐANG THỬ KẾT NỐI LẠI…", "warning", false)
		NetworkManager.CONNECTION_DISCONNECTED:
			_show("⌁", "MẤT KẾT NỐI", "danger", false)
		NetworkManager.CONNECTION_SESSION_EXPIRED:
			_show("!", "KHÔNG THỂ KHÔI PHỤC PHIÊN", "danger", true)
		NetworkManager.CONNECTION_SERVER_UNAVAILABLE:
			_show("!", "KHÔNG THỂ LIÊN LẠC MÁY CHỦ", "danger", true)
		NetworkManager.CONNECTION_CONNECTED:
			if was_recovering:
				_show("✓", "ĐÃ KẾT NỐI LẠI", "success", false)
				hide_at = Time.get_ticks_msec() + 2000
			else:
				_hide()
		_:
			_hide()

func _show(icon_text: String, text_value: String, tone: String, terminal: bool) -> void:
	_build()
	icon.text = icon_text
	message.text = text_value
	action.visible = terminal
	var border: Color = {
		"success": SaloonTheme.SUCCESS,
		"warning": SaloonTheme.WARNING,
		"danger": SaloonTheme.DANGER
	}.get(tone, SaloonTheme.GOLD)
	panel.add_theme_stylebox_override("panel", SaloonTheme.panel(Color(0.06, 0.09, 0.10, 0.97), border, 12))
	visible = true
	set_process(true)
	_position()

func _build() -> void:
	if is_instance_valid(panel):
		return
	panel = PanelContainer.new()
	panel.name = "StatusPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	icon = Label.new()
	icon.custom_minimum_size.x = 24
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 18)
	icon.add_theme_color_override("font_color", SaloonTheme.GOLD)
	row.add_child(icon)
	message = Label.new()
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message.add_theme_font_size_override("font_size", 14)
	message.add_theme_color_override("font_color", SaloonTheme.CREAM)
	row.add_child(message)
	action = load("res://scripts/ui/WesternButton.gd").new()
	action.text = "VỀ TRANG CHỦ"
	action.custom_minimum_size = Vector2(126, 42)
	action.pressed.connect(func():
		if is_instance_valid(app):
			app.leave())
	row.add_child(action)

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if hide_at > 0 and now >= hide_at:
		_hide()
		return
	if shown_status == NetworkManager.CONNECTION_RECONNECTING and now >= spinner_at:
		spinner_at = now + 220
		spinner_step = (spinner_step + 1) % 4
		icon.text = ["⌁", "⌁·", "⌁··", "⌁···"][spinner_step]

func _position() -> void:
	if not is_instance_valid(panel):
		return
	var safe: Vector4 = layout.safe_insets(self) if layout.mobile(self) else Vector4.ZERO
	var width: float = minf(layout.units(self, 440.0) if layout.mobile(self) else 440.0, size.x - safe.x - safe.z - layout.units(self, 16.0))
	var height: float = layout.units(self, 48.0) if layout.mobile(self) else 48.0
	panel.position = Vector2((size.x - width) * 0.5, safe.y + layout.units(self, 5.0))
	panel.size = Vector2(width, height)

func _hide() -> void:
	visible = false
	set_process(false)
	hide_at = 0
