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
var target_style: String = "BANG"
var reticle: Node3D
var info_hover: int = 0
var hover_since: int = 0
var shot_quiet_until: int = 0
var hovered_object: Node3D

func quiet_for_shot(duration: int = 230) -> void:
	shot_quiet_until = Time.get_ticks_msec() + duration
	if targeting_arrow.guide_motion:
		targeting_arrow.guide_motion.kill()
	targeting_arrow.visible = false
	reticle.visible = false
	tooltip.visible = false

func _process(_delta: float) -> void:
	if shot_quiet_until > 0 and Time.get_ticks_msec() >= shot_quiet_until:
		shot_quiet_until = 0
		if selected_card >= 0 and hovered_target > 0:
			update_hover_target(hovered_target)
	if not blocked and selected_card < 0 and info_hover > 0 and hover_since > 0 and not load("res://scripts/ui/MatchLayout.gd").mobile_first_person(table) and Time.get_ticks_msec() - hover_since > 450:
		hover_since = 0
		table.show_context(info_hover)

func _ready() -> void:
	targeting_arrow = TargetingArrow.new()
	table.add_child(targeting_arrow)
	reticle = load("res://scripts/ui/TargetReticle3D.gd").new()
	table.add_child(reticle)
	tooltip = Label3D.new()
	tooltip.font_size = 30
	tooltip.pixel_size = 0.006
	tooltip.outline_size = 8
	tooltip.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tooltip.no_depth_test = true
	table.add_child(tooltip)
	tooltip.visible = false

func begin_targeting(uid: int, owner_id: int, targets: Array, info: Dictionary, style: String = "BANG") -> void:
	var new_card: bool = selected_card != uid
	selected_card = uid
	target_style = style
	local_player = owner_id
	valid_target_ids = targets.duplicate()
	target_info = info
	if not table.avatars.has(local_player) or targets.is_empty():
		cancel_targeting(false)
		return
	if new_card:
		table.hide_context()
		info_hover = 0
		hover_since = 0
		if targeting_arrow.guide_motion:
			targeting_arrow.guide_motion.kill()
		hovered_target = 0
		selected_target = 0
		targeting_arrow.visible = false
		reticle.visible = false
		tooltip.visible = false
	elif hovered_target > 0:
		update_hover_target(hovered_target)

func cancel_targeting(emit_event: bool = true) -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if targeting_arrow.guide_motion:
		targeting_arrow.guide_motion.kill()
	selected_card = -1
	for id in table.nameplates:
		table.nameplates[id].hovered = false
		table.avatars[id].set_hover_state(false)
	valid_target_ids.clear()
	hovered_target = 0
	selected_target = 0
	targeting_arrow.visible = false
	reticle.visible = false
	tooltip.visible = false
	table.plate_layout_key = ""
	if emit_event:
		cancelled.emit()

func update_hover_target(id: int) -> void:
	if Time.get_ticks_msec() < shot_quiet_until:
		hovered_target = id if table.avatars.has(id) and id != local_player else 0
		return
	if selected_card < 0 or not table.avatars.has(id) or id == local_player:
		if targeting_arrow.guide_motion:
			targeting_arrow.guide_motion.kill()
		hovered_target = 0
		for player_id in table.nameplates:
			table.nameplates[player_id].hovered = false
			table.avatars[player_id].set_hover_state(false)
		targeting_arrow.visible = false
		reticle.visible = false
		tooltip.visible = false
		table.plate_layout_key = ""
		return
	hovered_target = id
	for player_id in table.nameplates:
		table.nameplates[player_id].hovered = player_id == id
		table.avatars[player_id].set_hover_state(player_id == id)
	table.plate_layout_key = ""
	var valid: bool = valid_target_ids.has(id)
	var from: Vector3 = table.avatars[local_player].global_position + Vector3(0, 1.85, 0)
	var to: Vector3 = table.avatars[id].global_position + Vector3(0, 1.5, 0)
	targeting_arrow.double_ended = target_style == "DUEL"
	# Compare two gentle side bows only when the hovered player changes.
	if not targeting_arrow.requested_end.is_equal_approx(to):
		targeting_arrow.bend_offset = Vector3.ZERO
		for direction in [0, -1, 1]:
			var bend: Vector3 = table.camera.global_basis.x * direction * 0.8
			var clear := true
			for step in range(1, 16):
				var t: float = step / 16.0
				var projected: Vector2 = table.camera.unproject_position(from.lerp(to,t)+(Vector3.UP*0.65+bend)*4*t*(1-t))
				for plate in table.nameplates.values():
					if plate.screen_rect.grow(8).has_point(projected):
						clear = false
			if clear:
				targeting_arrow.bend_offset = bend
				break
	targeting_arrow.aim_smooth(from, to, valid)
	reticle.lock(to, target_style, valid)
	Input.set_default_cursor_shape(Input.CURSOR_CROSS if valid else Input.CURSOR_FORBIDDEN)
	var info: Dictionary = target_info.get(id, {})
	var distance_text: String = "Khoảng cách: %d" % info.get("distance", 0)
	if target_style == "BANG":
		distance_text += " • Tầm súng: %d" % info.get("range", 1)
	elif target_style == "STEAL":
		distance_text += " • Tầm cướp: 1"
	tooltip.text = "%s\n%s\n%s" % [
		table.player_names.get(id, ""), distance_text,
		"Có thể chọn" if valid else ("NGOÀI TẦM" if target_style in ["BANG", "STEAL"] else ("Không thể giam Cảnh sát trưởng" if target_style == "JAIL" and table.player_rows[id].public_role == "SHERIFF" else "Không hợp lệ"))]
	tooltip.modulate = Color("#ffe0a0") if valid else Color("#da9a8a")
	tooltip.position = to + Vector3(0, -1.0, 0)
	tooltip.scale = Vector3.ONE * table.nameplates[id].scale.x
	tooltip.visible = true

func select_target(id: int) -> void:
	if selected_card < 0 or not valid_target_ids.has(id):
		return
	selected_target = id
	update_hover_target(id)
	confirm_target()

func confirm_target() -> void:
	if valid_target_ids.has(selected_target):
		var chosen: int = selected_target
		cancel_targeting(false)
		target_chosen.emit(chosen)

func pick_at(screen_position: Vector2) -> int:
	if not is_instance_valid(table.camera):
		return 0
	var ray := PhysicsRayQueryParameters3D.create(table.camera.project_ray_origin(screen_position),
		table.camera.project_ray_origin(screen_position) + table.camera.project_ray_normal(screen_position) * 100, 1)
	ray.collide_with_areas = true
	ray.collide_with_bodies = false
	var result: Dictionary = table.get_world_3d().direct_space_state.intersect_ray(ray)
	return int(result.collider.get_meta("player_id", 0)) if not result.is_empty() else 0

func pick_touch_player(at: Vector2) -> int:
	# First-person opponents become physically smaller when the seated camera is
	# raised. Keep a generous presentation-only touch halo; authority still
	# validates the selected player and card range.
	var layout: Script = load("res://scripts/ui/MatchLayout.gd")
	var best: float = layout.units(self, 40.0 if layout.mobile_first_person(table) else 28.0)
	var chosen: int = 0
	# Nameplates are screen-space controls: resolve their full bounds before rays
	# can hit a different model behind the visible panel.
	for id in table.avatars:
		if (selected_card < 0 or valid_target_ids.has(id)) and table.nameplates[id].screen_rect.has_point(at):
			return id
	for id in table.avatars:
		if selected_card >= 0 and not valid_target_ids.has(id):
			continue
		var center: Vector2 = table.camera.unproject_position(table.avatars[id].global_position+Vector3.UP*1.6)
		var distance: float = at.distance_to(center)
		if distance < best:
			best = distance
			chosen = id
	if chosen > 0:
		return chosen
	var exact: int = pick_at(at)
	if exact > 0 and (selected_card < 0 or valid_target_ids.has(exact)):
		return exact
	for id in table.avatars:
		if selected_card >= 0 and not valid_target_ids.has(id):
			continue
		var panel: Rect2 = table.nameplates[id].screen_rect
		var closest := Vector2(clampf(at.x,panel.position.x,panel.end.x),clampf(at.y,panel.position.y,panel.end.y))
		var distance: float = at.distance_to(closest)
		if distance < best:
			best = distance
			chosen = id
	return chosen

func pick_object(screen_position: Vector2) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(table.camera.project_ray_origin(screen_position),
		table.camera.project_ray_origin(screen_position) + table.camera.project_ray_normal(screen_position) * 100, 2)
	ray.collide_with_areas = true
	ray.collide_with_bodies = false
	var result: Dictionary = table.get_world_3d().direct_space_state.intersect_ray(ray)
	return result.collider.get_meta("table_token", {}) if not result.is_empty() else {}

func pick_touch_object(at: Vector2) -> Dictionary:
	var exact := pick_object(at)
	if table.objects.token_allowed(exact):
		return exact
	# Presentation hit slop only: authority still validates the same physical ID.
	var radius: float = load("res://scripts/ui/MatchLayout.gd").units(self,24)
	var nearest: Dictionary = {}
	for item in table.objects.objects.values():
		if not table.objects.token_allowed(item.token):
			continue
		var center: Vector2 = table.camera.unproject_position(item.global_position+Vector3.UP*0.12)
		var distance: float = center.distance_to(at)
		if distance < radius:
			radius = distance
			nearest = item.token
	return nearest

func handle_mobile_table_tap(at: Vector2) -> void:
	if blocked:
		return
	if selected_card >= 0:
		var id := pick_touch_player(at)
		if id == selected_target and valid_target_ids.has(id):
			AudioManager.play_ui("confirm")
			confirm_target()
		else:
			selected_target = id
			update_hover_target(id)
			if valid_target_ids.has(id):
				AudioManager.play_ui("button")
				if table.nameplates.has(id):
					table.nameplates[id].flash_target()
				tooltip.text += "\nChạm lần nữa để xác nhận"
	else:
		interact(at, true)

func _input(event: InputEvent) -> void:
	if blocked:
		return
	if event is InputEventMouseMotion:
		# Mobile browsers may synthesize mouse motion after touch. Character details
		# are tap-only in first-person mode, so a stale emulated cursor cannot open a
		# large inspection card while the player scrolls the hand.
		if load("res://scripts/ui/MatchLayout.gd").mobile_first_person(table):
			info_hover = 0
			hover_since = 0
			return
		if selected_card >= 0:
			update_hover_target(pick_at(event.position))
		else:
			var object_token := pick_object(event.position)
			var next_object: Node3D = null
			for item in table.objects.objects.values():
				if item.token == object_token:
					next_object = item
					break
			if hovered_object != next_object:
				if is_instance_valid(hovered_object):
					hovered_object.set_hovered(false)
				hovered_object = next_object
				if is_instance_valid(hovered_object):
					hovered_object.set_hovered(true)
			var id := pick_at(event.position)
			if id != info_hover:
				if table.avatars.has(info_hover):
					table.avatars[info_hover].set_hover_state(false)
				if table.nameplates.has(info_hover):
					table.nameplates[info_hover].hovered = false
				info_hover = id
				hover_since = Time.get_ticks_msec() if id > 0 else 0
				if table.nameplates.has(id):
					table.nameplates[id].hovered = true
				if table.avatars.has(id):
					table.avatars[id].set_hover_state(true)
				if id == 0:
					table.hide_context()
			Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if id > 0 else Input.CURSOR_ARROW)
	elif selected_card >= 0 and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		cancel_targeting()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if blocked:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if event.device != InputEvent.DEVICE_ID_EMULATION:
			interact(event.position)
	elif event is InputEventScreenTouch and event.pressed:
		if load("res://scripts/ui/MatchLayout.gd").mobile_first_person(table):
			return
		if selected_card >= 0:
			var id := pick_touch_player(event.position)
			if id == selected_target and valid_target_ids.has(id):
				AudioManager.play_ui("confirm")
				confirm_target()
			else:
				selected_target = id
				update_hover_target(id)
				if valid_target_ids.has(id):
					AudioManager.play_ui("button")
					if table.nameplates.has(id):
						table.nameplates[id].flash_target()
					tooltip.text += "\nChạm lần nữa để xác nhận"
		else:
			interact(event.position, true)

func interact(at: Vector2, touch: bool = false) -> void:
	if selected_card >= 0:
		select_target(pick_at(at))
		return
	var token := pick_touch_object(at) if touch else pick_object(at)
	if table.objects.token_allowed(token):
		world_chosen.emit(token)
		return
	var id := pick_touch_player(at) if touch else pick_at(at)
	if id > 0:
		table.show_context(id)
	else:
		table.hide_context()
