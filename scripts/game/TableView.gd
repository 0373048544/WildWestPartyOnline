extends Node3D

var avatars: Dictionary = {}
var rings: Dictionary = {}
var camera: Camera3D
var seats: Node3D
var built_match: int = -1
var effects: TableEffects
var camera_goal := Vector3.ZERO
var camera_shake: float = 0.0
var targeting: TargetingController
var player_names: Dictionary = {}
var status_labels: Dictionary = {}
var turn_marker: Label3D

func _ready() -> void:
	var room: Node3D = load("res://scripts/game/SaloonRoom.gd").new()
	add_child(room)
	effects = TableEffects.new()
	add_child(effects)
	seats = Node3D.new()
	seats.name = "Seats"
	add_child(seats)
	camera = Camera3D.new()
	add_child(camera)
	camera.current = true
	camera.fov = 57
	targeting = TargetingController.new()
	targeting.table = self
	add_child(targeting)
	turn_marker = Label3D.new()
	turn_marker.text = "▼ LƯỢT HIỆN TẠI"
	turn_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	turn_marker.font_size = 28
	turn_marker.pixel_size = 0.005
	turn_marker.modulate = Color("#ffdc89")
	add_child(turn_marker)

func _process(delta: float) -> void:
	if camera_goal == Vector3.ZERO:
		return
	camera_shake = maxf(0.0, camera_shake - delta * 0.25)
	var offset := Vector3(sin(Time.get_ticks_msec() * 0.08), cos(Time.get_ticks_msec() * 0.1), 0) * camera_shake
	camera.position = camera.position.lerp(camera_goal + offset, minf(1.0, delta * 12))
	camera.look_at(Vector3(0, 1.0, 0))
	for ring in rings.values():
		ring.rotation.y += delta * 0.5
	if avatars.has(turns_player()):
		turn_marker.position = avatars[turns_player()].position + Vector3(0, 3.8 + sin(Time.get_ticks_msec() * 0.004) * 0.1, 0)

func turns_player() -> int:
	return int(NetworkManager.public_state.get("current_player", 0))

func update_state(state: Dictionary, local_id: int, targets: Array) -> void:
	if built_match != int(state.match_id):
		for avatar in avatars.values():
			avatar.free()
		for ring in rings.values():
			ring.free()
		for marker in seats.get_children():
			marker.free()
		avatars.clear()
		rings.clear()
		for status_label in status_labels.values():
			status_label.free()
		status_labels.clear()
		targeting.cancel_targeting(false)
		for effect in effects.get_children():
			effect.queue_free()
		built_match = state.match_id
	var count: int = state.players.size()
	var local_seat := 0
	for p in state.players:
		var id: int = p.player_id
		player_names[id] = p.display_name
		var angle: float = TAU * float(p.seat_index) / count
		var at := Vector3(sin(angle) * 3.9, 0, cos(angle) * 3.9)
		var seat_color: Color = SaloonTheme.SEATS[int(p.seat_index) % 4]
		if not avatars.has(id):
			var marker := Marker3D.new()
			seats.add_child(marker)
			marker.position = at
			var avatar := PlayerAvatar.new()
			add_child(avatar)
			avatar.position = at
			avatar.build(seat_color)
			avatar.picking_area.set_meta("player_id", id)
			avatar.look_at(Vector3.ZERO, Vector3.UP)
			avatars[id] = avatar
			var ring := TorusMesh.new()
			ring.inner_radius = 0.68
			ring.outer_radius = 0.75
			ring.rings = 24
			ring.ring_segments = 8
			var ring_mesh := MeshInstance3D.new()
			ring_mesh.mesh = ring
			ring_mesh.material_override = StandardMaterial3D.new()
			add_child(ring_mesh)
			ring_mesh.position = at + Vector3(0, 0.1, 0)
			rings[id] = ring_mesh
			var seat := CylinderMesh.new()
			seat.top_radius = 0.56
			seat.bottom_radius = 0.64
			seat.height = 0.1
			var marker_mesh := MeshInstance3D.new()
			marker_mesh.mesh = seat
			var seat_material := StandardMaterial3D.new()
			seat_material.albedo_color = seat_color.darkened(0.3)
			marker_mesh.material_override = seat_material
			marker.add_child(marker_mesh)
			marker_mesh.position.y = 0.04
			var status_label := Label3D.new()
			status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			status_label.font_size = 24
			status_label.pixel_size = 0.0045
			status_label.outline_size = 6
			add_child(status_label)
			status_label.position = at + Vector3(0, 2.95, 0)
			status_labels[id] = status_label
		status_labels[id].text = "%s • %d/%d máu\n%d lá • Tầm %d" % [p.display_name, p.current_hp, p.max_hp, p.hand_count, p.weapon_range]
		status_labels[id].modulate = seat_color.lightened(0.35)
		avatars[id].set_target_state(not targets.is_empty() and not targets.has(id) and id != local_id)
		rings[id].visible = targets.has(id) or int(state.current_player) == id
		rings[id].material_override.albedo_color = Color("#ffda7b") if targets.has(id) else seat_color
		rings[id].material_override.emission_enabled = targets.has(id)
		rings[id].material_override.emission = Color("#ffc775")
		if not p.is_alive and not avatars[id].dead:
			avatars[id].act("death")
		if id == local_id:
			local_seat = p.seat_index
	turn_marker.visible = avatars.has(int(state.current_player)) and state.winner.is_empty() and state.phase != "CHARACTER_SELECTION"
	var local_angle: float = TAU * float(local_seat) / count
	camera_goal = Vector3(sin(local_angle) * 9.1, 7.7, cos(local_angle) * 9.1)
	if camera.position == Vector3.ZERO:
		camera.position = camera_goal
	camera.look_at(Vector3(0, 1.0, 0))

func animate(actor: int, kind: String, target: int) -> void:
	if not avatars.has(actor):
		return
	if kind == "gatling":
		for id in avatars:
			if id != actor and not avatars[id].dead:
				var fan := TargetingArrow.new()
				add_child(fan)
				fan.aim(avatars[actor].position + Vector3.UP * 1.5, avatars[id].position + Vector3.UP * 1.5)
				var fade := fan.create_tween()
				fade.tween_interval(0.6)
				fade.tween_callback(fan.queue_free)
		kind = "shoot"
	if kind == "shoot" and avatars.has(target):
		avatars[actor].face_target(avatars[target].global_position)
	avatars[actor].act(kind)
	var at: Vector3 = avatars[actor].position + Vector3(0, 2.6, 0)
	match kind:
		"shoot":
			var shooting_avatar: PlayerAvatar = avatars[actor]
			var flash_timing := shooting_avatar.create_tween()
			flash_timing.tween_interval(0.1)
			flash_timing.tween_callback(func():
				if is_instance_valid(shooting_avatar):
					effects.muzzle(shooting_avatar.arm.to_global(Vector3(0, -0.5, -0.37))))
		"hit":
			effects.floating(at, "−1", Color("#ff967c"))
			effects.spark(at - Vector3(0, 1.1, 0), Color("#e9bd78"))
			camera_shake = 0.055
		"drink":
			effects.floating(at, "+1", Color("#a7edac"))
			effects.spark(at - Vector3(0, 0.4, 0), Color("#99dbad"), 6, 0.4)
		"dodge":
			effects.floating(at, TextCatalog.text("DODGE") + "!", Color("#9adce4"))
			effects.spark(at - Vector3(0, 2.3, 0), Color("#d4c9af"), 5)
		"death":
			effects.spark(at - Vector3(0, 2.2, 0), Color("#bd9475"), 8)

