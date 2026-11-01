extends Node

var _last_focus: Control = null
var _last_css_size := Vector2.ZERO
var _next_viewport_poll: int = 0


func _ready() -> void:
	# Keyboard handling is useful on Web, Android and iOS.
	set_process(OS.has_feature("web") or OS.has_feature("mobile"))
	set_process_input(OS.has_feature("web") or OS.has_feature("mobile"))

	if OS.has_feature("web"):
		get_viewport().size_changed.connect(resize)
		resize()


func _process(_delta: float) -> void:
	if not (OS.has_feature("web") or OS.has_feature("mobile")):
		return

	var focus: Control = get_viewport().gui_get_focus_owner()

	# If a LineEdit/TextEdit has just lost focus, force-close the OS keyboard.
	if is_instance_valid(_last_focus):
		if _is_text_input(_last_focus) and focus != _last_focus:
			_hide_virtual_keyboard()

	_last_focus = focus

	# Safari/embedded browsers resize visualViewport when their toolbar expands
	# without always changing the outer canvas immediately. Poll cheaply and
	# reflow only when the real CSS viewport changed.
	if OS.has_feature("web") and Time.get_ticks_msec() >= _next_viewport_poll:
		_next_viewport_poll = Time.get_ticks_msec() + 250
		var measured: Variant = JavaScriptBridge.eval("JSON.stringify([Math.min(window.visualViewport?.width||window.innerWidth,window.innerWidth,window.screen?.width||window.innerWidth),Math.min(window.visualViewport?.height||window.innerHeight,window.innerHeight,window.screen?.height||window.innerHeight)])")
		var parsed: Variant = JSON.parse_string(str(measured))
		if parsed is Array and parsed.size() == 2:
			var next_css := Vector2(float(parsed[0]), float(parsed[1]))
			if not next_css.is_equal_approx(_last_css_size):
				_last_css_size = next_css
				resize()


func _input(event: InputEvent) -> void:
	if not (OS.has_feature("web") or OS.has_feature("mobile")):
		return

	var focus: Control = get_viewport().gui_get_focus_owner()

	if not is_instance_valid(focus) or not _is_text_input(focus):
		return

	# Enter / Done / Go on the mobile keyboard.
	if event.is_action_pressed("ui_text_submit"):
		focus.release_focus()
		_hide_virtual_keyboard()
		return

	# Tapping anywhere outside the active text field closes the keyboard.
	if event is InputEventScreenTouch and event.pressed:
		var text_control := focus as Control
		if not text_control.get_global_rect().has_point(event.position):
			text_control.release_focus()
			_hide_virtual_keyboard()
			return

	# Also support mouse/pointer taps in mobile browsers and desktop testing.
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var text_control := focus as Control
			if not text_control.get_global_rect().has_point(event.position):
				text_control.release_focus()
				_hide_virtual_keyboard()


func _is_text_input(control: Control) -> bool:
	return control is LineEdit or control is TextEdit


func _hide_virtual_keyboard() -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_hide()


func resize() -> void:
	if not OS.has_feature("web"):
		return

	# screen.* closes a Chromium touch-emulation edge case where visualViewport
	# briefly reports the legacy 980 px layout viewport despite a phone screen.
	var width: int = int(JavaScriptBridge.eval("Math.min(window.visualViewport?.width||window.innerWidth,window.innerWidth,window.screen?.width||window.innerWidth)"))
	var height: int = int(JavaScriptBridge.eval("Math.min(window.visualViewport?.height||window.innerHeight,window.innerHeight,window.screen?.height||window.innerHeight)"))
	var previous_css: Vector2 = get_viewport().get_meta("match_css_size", Vector2.ZERO)
	var previous_target: Vector2i = get_window().content_scale_size

	var target := (
		Vector2i(
			960,
			maxi(
				440,
				int(960.0 * height / maxi(1, width))
			)
		)
		if width >= height
		else Vector2i(
			600,
			int(600.0 * height / maxi(1, width))
		)
	)

	if width > 1100:
		target = Vector2i(
			1440,
			int(1440.0 * height / maxi(1, width))
		)

	if get_window().content_scale_size != target:
		get_window().content_scale_size = target

	get_viewport().set_meta(
		"match_css_size",
		Vector2(width, height)
	)

	# Read CSS env() through a temporary invisible element,
	# not user-agent detection.
	var encoded: Variant = JavaScriptBridge.eval(
		"""JSON.stringify((()=>{
const p=document.createElement('div');
p.style.cssText='position:fixed;visibility:hidden;pointer-events:none;padding:env(safe-area-inset-top,0px) env(safe-area-inset-right,0px) env(safe-area-inset-bottom,0px) env(safe-area-inset-left,0px)';
document.body.appendChild(p);
const s=getComputedStyle(p);
const result=[
	parseFloat(s.paddingLeft)||0,
	parseFloat(s.paddingTop)||0,
	parseFloat(s.paddingRight)||0,
	parseFloat(s.paddingBottom)||0
];
p.remove();
return result;
})())"""
	)

	var padding: Variant = JSON.parse_string(
		str(encoded)
	)

	if padding is Array and padding.size() == 4:
		var sx: float = (
			float(target.x)
			/ maxi(1, width)
		)

		var sy: float = (
			float(target.y)
			/ maxi(1, height)
		)

		var insets := Vector4(
			padding[0] * sx,
			padding[1] * sy,
			padding[2] * sx,
			padding[3] * sy
		)

		var previous: Vector4 = get_viewport().get_meta(
			"match_safe_insets",
			Vector4.ZERO
		)

		get_viewport().set_meta(
			"match_safe_insets",
			insets
		)

		if (
			(previous != insets
			or previous_css != Vector2(width, height)
			or previous_target != target)
			and get_parent().has_method("refresh_layout")
		):
			get_parent().call_deferred(
				"refresh_layout"
			)
