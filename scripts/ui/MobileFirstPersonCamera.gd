class_name MobileFirstPersonCamera
extends Node

const MIN_PITCH := deg_to_rad(-25.0)
const MAX_PITCH := deg_to_rad(20.0)
const EYE_HEIGHT := 2.18
const EYE_INSET := 0.38

var table: Node3D
var enabled := false
var yaw := 0.0
var pitch := 0.0
var initial_yaw := 0.0
var eye_position := Vector3.ZERO
var seat_key := ""
var touch_index := -1
var touch_origin := Vector2.ZERO
var dragging := false
var drag_distance := 0.0

func setup(owner_table: Node3D) -> void:
	table = owner_table
	set_process_unhandled_input(true)

func configure(local_seat_position: Vector3, local_seat_index: int, player_count: int) -> void:
	var layout: Script = load("res://scripts/ui/MatchLayout.gd")
	var should_enable: bool = layout.mobile_first_person(table)
	var next_key := "%d:%d" % [local_seat_index, player_count]
	if not should_enable:
		enabled = false
		seat_key = ""
		_cancel_touch()
		return
	var radial := Vector3(local_seat_position.x, 0.0, local_seat_position.z).normalized()
	eye_position = local_seat_position - radial * EYE_INSET + Vector3.UP * EYE_HEIGHT
	var reset_view := not enabled or seat_key != next_key
	enabled = true
	seat_key = next_key
	table.camera.position = eye_position
	table.camera.keep_aspect = Camera3D.KEEP_HEIGHT
	table.camera.fov = 68.0 if layout.mobile_portrait(table) else 72.0
	table.camera.h_offset = 0.0
	table.camera.v_offset = 0.0
	if reset_view:
		table.camera.look_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)
		yaw = table.camera.rotation.y
		pitch = clampf(table.camera.rotation.x, MIN_PITCH, MAX_PITCH)
		initial_yaw = yaw
	apply_camera()

func apply_camera() -> void:
	if not enabled or not is_instance_valid(table) or not is_instance_valid(table.camera):
		return
	table.camera.position = eye_position
	table.camera.rotation = Vector3(pitch, yaw, 0.0)

func reset_toward_table() -> void:
	if not enabled:
		return
	table.camera.position = eye_position
	table.camera.look_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)
	pitch = clampf(table.camera.rotation.x, MIN_PITCH, MAX_PITCH)
	initial_yaw = table.camera.rotation.y
	yaw = initial_yaw
	apply_camera()

func _unhandled_input(event: InputEvent) -> void:
	if not enabled or not is_instance_valid(table) or table.targeting.blocked:
		_cancel_touch()
		return
	var layout: Script = load("res://scripts/ui/MatchLayout.gd")
	if event is InputEventScreenTouch:
		if event.pressed:
			if touch_index >= 0 or not layout.get_table_focus_rect(table).has_point(event.position):
				return
			touch_index = event.index
			touch_origin = event.position
			dragging = false
			drag_distance = 0.0
			get_viewport().set_input_as_handled()
		elif event.index == touch_index:
			if not dragging:
				table.targeting.handle_mobile_table_tap(event.position)
			_cancel_touch()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == touch_index:
		drag_distance = maxf(drag_distance, event.position.distance_to(touch_origin))
		if drag_distance >= layout.drag_threshold(table):
			dragging = true
		if dragging:
			var scale_factor: float = maxf(0.5, layout.units(table, 1.0))
			yaw -= event.relative.x / scale_factor * 0.0042
			pitch = clampf(pitch - event.relative.y / scale_factor * 0.0032, MIN_PITCH, MAX_PITCH)
			apply_camera()
			table.plate_layout_key = ""
		get_viewport().set_input_as_handled()

func _cancel_touch() -> void:
	touch_index = -1
	dragging = false
	drag_distance = 0.0
