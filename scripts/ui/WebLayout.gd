extends Node

var _last_css_size := Vector2.ZERO
var _current_text_input: Control
var _resize_pending := false
var _resize_timer: Timer
var _viewport_timer: Timer
var _layout_generation := 0
var _recovery_generation := 0
var _recovery_active := false
var _recovery_stable_samples := 0
var _recovery_last_sample := Vector4.ZERO
var _last_browser_geometry: Dictionary = {}

const RECOVERY_REQUIRED_SAMPLES := 3
const RECOVERY_TOLERANCE_CSS_PX := 0.75


func _ready() -> void:
	# Text focus is event-driven. Polling focus every frame used to race the
	# browser's hidden IME input while visualViewport was changing.
	set_process(false)
	set_process_input(OS.has_feature("web") or OS.has_feature("mobile"))

	if OS.has_feature("web"):
		_resize_timer = Timer.new()
		_resize_timer.one_shot = true
		_resize_timer.wait_time = 0.12
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
	var geometry := _read_browser_geometry()
	if geometry.is_empty():
		return
	var next_css := Vector2(float(geometry.width), float(geometry.height))
	if is_text_edit_active():
		_resize_pending = true
		return
	if _recovery_active:
		if _observe_recovery_sample(geometry):
			_complete_viewport_recovery()
		return
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


func is_viewport_recovering() -> bool:
	return _recovery_active


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
	_begin_viewport_recovery()


func _begin_viewport_recovery() -> void:
	_recovery_generation += 1
	_recovery_active = OS.has_feature("web")
	_recovery_stable_samples = 0
	_recovery_last_sample = Vector4.ZERO
	_resize_pending = true
	if is_instance_valid(_resize_timer):
		_resize_timer.stop()
	if not _recovery_active:
		_complete_viewport_recovery()


func _observe_recovery_sample(geometry: Dictionary) -> bool:
	var sample := Vector4(
		float(geometry.get("width", 0.0)),
		float(geometry.get("height", 0.0)),
		float(geometry.get("left", 0.0)),
		float(geometry.get("top", 0.0))
	)
	if sample.x < 1.0 or sample.y < 1.0:
		_recovery_stable_samples = 0
		return false
	if _recovery_last_sample != Vector4.ZERO and _geometry_close(_recovery_last_sample, sample):
		_recovery_stable_samples += 1
	else:
		_recovery_stable_samples = 1
	_recovery_last_sample = sample
	return _recovery_stable_samples >= RECOVERY_REQUIRED_SAMPLES


func _geometry_close(a: Vector4, b: Vector4) -> bool:
	return absf(a.x - b.x) <= RECOVERY_TOLERANCE_CSS_PX \
		and absf(a.y - b.y) <= RECOVERY_TOLERANCE_CSS_PX \
		and absf(a.z - b.z) <= RECOVERY_TOLERANCE_CSS_PX \
		and absf(a.w - b.w) <= RECOVERY_TOLERANCE_CSS_PX


func _complete_viewport_recovery() -> void:
	_recovery_active = false
	_recovery_stable_samples = 0
	_resize_pending = false
	resize()
	if get_parent().has_method("text_input_settled"):
		get_parent().call_deferred("text_input_settled")


func _request_resize() -> void:
	_resize_pending = true
	if is_text_edit_active() or _recovery_active:
		return
	if is_instance_valid(_resize_timer):
		_resize_timer.start()
	else:
		call_deferred("_flush_resize")


func _flush_resize() -> void:
	if is_text_edit_active() or _recovery_active:
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


func resize(notify_parent: bool = true) -> void:
	if not OS.has_feature("web"):
		return
	if is_text_edit_active():
		_resize_pending = true
		return

	var geometry := _read_browser_geometry()
	if geometry.is_empty():
		return
	var width: int = maxi(1, roundi(float(geometry.width)))
	var height: int = maxi(1, roundi(float(geometry.height)))
	_last_css_size = Vector2(width, height)
	get_viewport().set_meta("match_browser_geometry", geometry.duplicate(true))
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

	var profile_changed := previous_target.x != target.x
	var width_changed := previous_css == Vector2.ZERO or absf(previous_css.x - width) > 1.0
	var height_only := not profile_changed and not width_changed and absf(previous_css.y - height) > 1.0
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

	var previous_insets: Vector4 = get_viewport().get_meta("match_safe_insets", Vector4.ZERO)
	var insets: Vector4 = previous_insets
	if padding is Array and padding.size() == 4:
		var sx: float = (
			float(target.x)
			/ maxi(1, width)
		)

		var sy: float = (
			float(target.y)
			/ maxi(1, height)
		)

		insets = Vector4(
			padding[0] * sx,
			padding[1] * sy,
			padding[2] * sx,
			padding[3] * sy
		)

		get_viewport().set_meta(
			"match_safe_insets",
			insets
		)

	var changed := previous_css != Vector2(width, height) or previous_target != target or previous_insets != insets
	if changed:
		_layout_generation += 1
		get_viewport().set_meta("match_layout_generation", _layout_generation)
		if notify_parent and get_parent().has_method("responsive_layout_changed"):
			get_parent().call_deferred("responsive_layout_changed", {
				"generation": _layout_generation,
				"height_only": height_only,
				"profile_changed": profile_changed,
				"width_changed": width_changed,
				"css_size": Vector2(width, height),
				"logical_size": Vector2(target),
				"safe_insets": insets
			})


func _read_browser_geometry() -> Dictionary:
	if not OS.has_feature("web"):
		return {}
	var encoded: Variant = JavaScriptBridge.eval(
		"""JSON.stringify((()=>{
const vv=window.visualViewport;
const root=document.documentElement;
const width=Math.max(1,vv?vv.width:window.innerWidth||root.clientWidth);
const height=Math.max(1,vv?vv.height:window.innerHeight||root.clientHeight);
const left=vv?vv.offsetLeft:0;
const top=vv?vv.offsetTop:0;
root.style.setProperty('--wwpo-viewport-width',width+'px');
root.style.setProperty('--wwpo-viewport-height',height+'px');
root.style.setProperty('--wwpo-viewport-left',left+'px');
root.style.setProperty('--wwpo-viewport-top',top+'px');
const canvas=document.getElementById('canvas');
const rect=canvas?canvas.getBoundingClientRect():{left:0,top:0,width:width,height:height};
return {
	width:width,height:height,left:left,top:top,
	inner_width:window.innerWidth||width,inner_height:window.innerHeight||height,
	client_width:root.clientWidth||width,client_height:root.clientHeight||height,
	canvas_left:rect.left,canvas_top:rect.top,canvas_width:rect.width,canvas_height:rect.height,
	dpr:window.devicePixelRatio||1
};
})())"""
	)
	var parsed: Variant = JSON.parse_string(str(encoded))
	if parsed is Dictionary:
		_last_browser_geometry = parsed
		return parsed
	return _last_browser_geometry
