class_name TargetingController
extends Node

signal target_chosen(player_id: int)
signal cancelled
signal world_chosen(token: Dictionary)
var table: Node3D
var selected_card: int = -1
var valid_target_ids: Array = []
var hovered_target: int = 0
var selected_target: int = 0
var local_player: int = 0
var target_info: Dictionary = {}
var targeting_arrow: TargetingArrow
var tooltip: Label3D
var blocked: bool = false

func _ready() -> void:
	targeting_arrow = TargetingArrow.new()
	table.add_child(targeting_arrow)
	tooltip = Label3D.new()
	tooltip.font_size = 30
	tooltip.pixel_size = 0.006
	tooltip.outline_size = 8
	tooltip.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tooltip.no_depth_test = true
	table.add_child(tooltip)
	tooltip.visible = false

func begin_targeting(uid: int, owner_id: int, targets: Array, info: Dictionary) -> void:
	selected_card = uid
	local_player = owner_id
	valid_target_ids = targets.duplicate()
	target_info = info
	if not table.avatars.has(local_player) or targets.is_empty():
		cancel_targeting(false)
		return
	if not targets.has(hovered_target):
		hovered_target = int(targets[0])
	update_hover_target(hovered_target)

func cancel_targeting(emit_event: bool = true) -> void:
	selected_card = -1
	valid_target_ids.clear()
	hovered_target = 0
	selected_target = 0
	targeting_arrow.visible = false
	tooltip.visible = false
	if emit_event:
		cancelled.emit()

func update_hover_target(id: int) -> void:
	if selected_card < 0 or not table.avatars.has(id) or id == local_player:
		return
	hovered_target = id
	var valid: bool = valid_target_ids.has(id)
	var from: Vector3 = table.avatars[local_player].global_position + Vector3(0, 1.45, 0)
	var to: Vector3 = table.avatars[id].global_position + Vector3(0, 1.5, 0)
	targeting_arrow.aim(from, to, valid)
	var info: Dictionary = target_info.get(id, {})
	tooltip.text = "%s\nKhoảng cách: %d • Tầm súng: %d\n%s" % [
		table.player_names.get(id, ""), info.get("distance", 0), info.get("range", 1),
		"Có thể chọn" if valid else "Không hợp lệ / ngoài tầm"]
	tooltip.modulate = Color("#ffe0a0") if valid else Color("#da9a8a")
	tooltip.position = to + Vector3(0, 1.35, 0)
	tooltip.visible = true

func select_target(id: int) -> void:
	if selected_card < 0 or not valid_target_ids.has(id):
		return
	selected_target = id
	update_hover_target(id)
	confirm_target()

func confirm_target() -> void:
	if valid_target_ids.has(selected_target):
		target_chosen.emit(selected_target)

func pick_at(screen_position: Vector2) -> int:
	if not is_instance_valid(table.camera):
		return 0
	var ray := PhysicsRayQueryParameters3D.create(table.camera.project_ray_origin(screen_position),
		table.camera.project_ray_origin(screen_position) + table.camera.project_ray_normal(screen_position) * 100, 1)
	ray.collide_with_areas = true
	ray.collide_with_bodies = false
	var result: Dictionary = table.get_world_3d().direct_space_state.intersect_ray(ray)
	return int(result.collider.get_meta("player_id", 0)) if not result.is_empty() else 0

func pick_object(screen_position: Vector2) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(table.camera.project_ray_origin(screen_position),
		table.camera.project_ray_origin(screen_position) + table.camera.project_ray_normal(screen_position) * 100, 2)
	ray.collide_with_areas = true
	ray.collide_with_bodies = false
	var result: Dictionary = table.get_world_3d().direct_space_state.intersect_ray(ray)
	return result.collider.get_meta("table_token", {}) if not result.is_empty() else {}

func _input(event: InputEvent) -> void:
	if blocked:
		return
	if event is InputEventMouseMotion:
		if selected_card >= 0:
			update_hover_target(pick_at(event.position))
	elif selected_card >= 0 and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		cancel_targeting()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if blocked:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		interact(event.position)
	elif event is InputEventScreenTouch and event.pressed:
		interact(event.position)

func interact(at: Vector2) -> void:
	if selected_card >= 0:
		select_target(pick_at(at))
		return
	var token := pick_object(at)
	if table.objects.token_allowed(token):
		world_chosen.emit(token)
		return
	var id := pick_at(at)
	if id > 0:
		table.show_context(id)
	else:
		table.hide_context()
