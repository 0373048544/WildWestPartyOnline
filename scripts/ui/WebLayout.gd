extends Node

var _last_css_size := Vector2.ZERO
var _current_text_input: Control
var _resize_pending := false
var _resize_timer: Timer
var _viewport_timer: Timer


func _ready() -> void:
	# Text focus is event-driven. Polling focus every frame used to race the
	# browser's hidden IME input while visualViewport was changing.
	set_process(false)
	set_process_input(OS.has_feature("web") or OS.has_feature("mobile"))

	if OS.has_feature("web"):
		_resize_timer = Timer.new()
		_resize_timer.one_shot = true
		_resize_timer.wait_time = 0.075
		_resize_timer.timeout.connect(_flush_resize)
		add_child(_resize_timer)
		_viewport_timer = Timer.new()
		_viewport_timer.wait_time = 0.25
		_viewport_timer.timeout.connect(_poll_css_viewport)
		add_child(_viewport_timer)
		_viewport_timer.start()
		get_viewport().size_changed.connect(_request_resize)
		_request_resize()


func _poll_css_viewport() -> void:
	# Safari/embedded browsers resize visualViewport when their toolbar expands
	# without always changing the outer canvas immediately. Poll only viewport
	# geometry (not focus), and postpone reflow for the whole IME composition.
	var measured: Variant = JavaScriptBridge.eval("JSON.stringify([Math.min(window.visualViewport?.width||window.innerWidth,window.innerWidth,window.screen?.width||window.innerWidth),Math.min(window.visualViewport?.height||window.innerHeight,window.innerHeight,window.screen?.height||window.innerHeight)])")
	var parsed: Variant = JSON.parse_string(str(measured))
	if parsed is Array and parsed.size() == 2:
		var next_css := Vector2(float(parsed[0]), float(parsed[1]))
		if not next_css.is_equal_approx(_last_css_size):
			_request_resize()


func register_text_input(control: Control) -> void:
	if not is_instance_valid(control) or not _is_text_input(control):
		return
	control.add_to_group("mobile_text_input")
	if not control.focus_entered.is_connected(_on_focus_entered.bind(control)):
		control.focus_entered.connect(_on_focus_entered.bind(control))
	if not control.focus_exited.is_connected(_on_focus_exited.bind(control)):
		control.focus_exited.connect(_on_focus_exited.bind(control))


func is_text_edit_active() -> bool:
	if is_instance_valid(_current_text_input) and _current_text_input.has_focus():
		return true
	var focus: Control = get_viewport().gui_get_focus_owner()
	return is_instance_valid(focus) and _is_text_input(focus)


func finish_text_input(control: Control = null, hide_keyboard: bool = true) -> void:
	var target: Control = control
	if not is_instance_valid(target):
		target = get_viewport().gui_get_focus_owner()
	if is_instance_valid(target) and _is_text_input(target) and target.has_focus():
		target.release_focus()
	if hide_keyboard:
		_hide_virtual_keyboard()
	call_deferred("_settle_focus_exit")


func _on_focus_entered(control: Control) -> void:
	_current_text_input = control


func _on_focus_exited(_control: Control) -> void:
	# The browser briefly moves focus between its hidden textarea and Godot.
	# Settle after GUI dispatch and never hide the keyboard just for focus_exited.
	call_deferred("_settle_focus_exit")


func _settle_focus_exit() -> void:
	var focus: Control = get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus) and _is_text_input(focus):
		_current_text_input = focus
		return
	_current_text_input = null
	if get_parent().has_method("text_input_settled"):
		get_parent().call_deferred("text_input_settled")
	if _resize_pending:
		_request_resize()


func _request_resize() -> void:
	_resize_pending = true
	if is_text_edit_active():
		return
	if is_instance_valid(_resize_timer):
		_resize_timer.start()
	else:
		call_deferred("_flush_resize")


func _flush_resize() -> void:
	if is_text_edit_active():
		return
	_resize_pending = false
	resize()


func _input(event: InputEvent) -> void:
	if not (OS.has_feature("web") or OS.has_feature("mobile")):
		return

	var focus: Control = get_viewport().gui_get_focus_owner()

	if not is_instance_valid(focus) or not _is_text_input(focus):
		return

	# Defer outside-tap handling until Godot GUI has had a chance to transfer
	# focus. Otherwise a tap from PlayerName to RoomCode closes the keyboard
	# because the pointer is outside the previously focused LineEdit.
	# Never release focus on pointer-down: a viewport resize between touchStart
	# and touchEnd cancels the Button press, forcing users to tap Submit twice.
	# Resolve outside taps only after the complete click/touch gesture.
	if event is InputEventScreenTouch and not event.pressed:
		call_deferred("_finish_pointer_focus", focus, event.position)
		return

	# Also support mouse/pointer taps in mobile browsers and desktop testing.
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			call_deferred("_finish_pointer_focus", focus, event.position)


func _finish_pointer_focus(previous_focus: Control, pointer_position: Vector2) -> void:
	if not is_instance_valid(previous_focus) or not _is_text_input(previous_focus):
		return
	var current_focus: Control = get_viewport().gui_get_focus_owner()
	# Switching directly between two text fields must keep the same keyboard.
	if is_instance_valid(current_focus) and _is_text_input(current_focus):
		if current_focus != previous_focus or current_focus.get_global_rect().has_point(pointer_position):
			return
	if previous_focus.get_global_rect().has_point(pointer_position):
		return
	if previous_focus.has_focus():
		previous_focus.release_focus()
	_hide_virtual_keyboard()


func _is_text_input(control: Control) -> bool:
	return control is LineEdit or control is TextEdit


func _hide_virtual_keyboard() -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_hide()


func resize() -> void:
	if not OS.has_feature("web"):
		return
	if is_text_edit_active():
		_resize_pending = true
		return

	# screen.* closes a Chromium touch-emulation edge case where visualViewport
	# briefly reports the legacy 980 px layout viewport despite a phone screen.
	var width: int = int(JavaScriptBridge.eval("Math.min(window.visualViewport?.width||window.innerWidth,window.innerWidth,window.screen?.width||window.innerWidth)"))
	var height: int = int(JavaScriptBridge.eval("Math.min(window.visualViewport?.height||window.innerHeight,window.innerHeight,window.screen?.height||window.innerHeight)"))
	_last_css_size = Vector2(width, height)
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
