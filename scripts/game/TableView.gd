extends Node3D

var avatars: Dictionary = {}
signal character_info_requested(player: Dictionary)
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
var nameplates: Dictionary = {}
var turn_marker: MeshInstance3D
var objects: Node3D
var player_rows: Dictionary = {}
var local_player: int = 1
var context_label: Label3D
var context_player: int = 0
var duel_focus := Vector3.ZERO
var duel_until: int = 0
var presentation_queue: Array = []
var presentation_wait: float = 0
var seen_presentation: Dictionary = {}

func _ready() -> void:
	AudioManager.table = self
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
	objects = load("res://scripts/game/TableObjects.gd").new()
	objects.table = self
	add_child(objects)
	targeting = TargetingController.new()
	targeting.table = self
	add_child(targeting)
	turn_marker = load("res://scripts/ui/PlayerNameplate.gd").make_star()
	add_child(turn_marker)
	context_label = Label3D.new()
	context_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	context_label.no_depth_test = true
	context_label.font_size = 25
	context_label.width = 560
	context_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	context_label.pixel_size = 0.005
	context_label.outline_size = 8
	context_label.modulate = Color("#ffe7b7")
	context_label.visible = false
	add_child(context_label)

func _process(delta: float) -> void:
	presentation_wait = maxf(0, presentation_wait - delta)
	if presentation_wait <= 0 and not presentation_queue.is_empty():
		var event: Dictionary = presentation_queue.pop_front()
		present_event(event)
		var kind: String = event.get("kind", "")
		presentation_wait = 1.4 if kind in ["judge", "reveal"] else (0.45 + 0.22 * (mini(8, int(event.get("count", 1))) - 1) if kind in ["draw", "transfer"] else 0.42)
	if camera_goal == Vector3.ZERO:
		return
	camera_shake = maxf(0.0, camera_shake - delta * 0.25)
	var offset := Vector3(sin(Time.get_ticks_msec() * 0.08), cos(Time.get_ticks_msec() * 0.1), 0) * camera_shake
	camera.position = camera.position.lerp(camera_goal + offset, minf(1.0, delta * 12))
	camera.look_at(duel_focus if Time.get_ticks_msec() < duel_until else Vector3(0, 1.0, 0))
	layout_nameplates()
	for ring in rings.values():
		ring.rotation.y += delta * 0.5
		ring.scale = Vector3.ONE * (1.0 + 0.025 * sin(Time.get_ticks_msec() * 0.005))
	if avatars.has(turns_player()):
		turn_marker.position = avatars[turns_player()].position + Vector3(0, 3.8 + sin(Time.get_ticks_msec() * 0.004) * 0.1, 0)

func turns_player() -> int:
	return int(NetworkManager.public_state.get("current_player", 0))

func layout_nameplates() -> void:
	var placements: Array = []
	for id in nameplates:
		placements.append({"plate": nameplates[id], "rect": nameplates[id].place(camera, avatars[id].global_position)})
	placements.sort_custom(func(a, b): return a.rect.position.y < b.rect.position.y if not is_equal_approx(a.rect.position.y,b.rect.position.y) else a.rect.position.x < b.rect.position.x)
	var occupied: Array[Rect2] = []
	var width: float = get_viewport().get_visible_rect().size.x
	for item in placements:
		var rect: Rect2 = item.rect
		rect.position.x = clampf(rect.position.x, 8, maxf(8, width - rect.size.x - 8))
		# Preserve font size and seat association: lift a colliding plate first.
		for _attempt in range(8):
			var collided := false
			for previous in occupied:
				if rect.grow(3).intersects(previous):
					var above: float = previous.position.y - rect.size.y - 8
					if above >= 62:
						rect.position.y = above
					else:
						rect.position.x = clampf(previous.end.x + 8,8,maxf(8,width-rect.size.x-8))
						if rect.intersects(previous):
							rect.position.y = previous.end.y + 8
					collided = true
			if not collided:
				break
		var depth: float = -camera.to_local(item.plate.global_position).z
		item.plate.global_position = camera.project_position(rect.get_center(), depth)
		item.plate.screen_rect = rect
		occupied.append(rect)

func update_state(state: Dictionary, local_id: int, targets: Array) -> void:
	local_player = local_id
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
		for plate in nameplates.values():
			plate.free()
		nameplates.clear()
		objects.clear()
		presentation_queue.clear()
		seen_presentation.clear()
		presentation_wait = 0
		hide_context()
		targeting.cancel_targeting(false)
		for effect in effects.get_children():
			effect.queue_free()
		built_match = state.match_id
	var count: int = state.players.size()
	var local_seat := 0
	for p in state.players:
		var id: int = p.player_id
		player_rows[id] = p
		player_names[id] = p.display_name
		var angle: float = TAU * float(p.seat_index) / count
		var at := Vector3(sin(angle) * 3.9, 0, cos(angle) * 3.9)
		var seat_color: Color = SaloonTheme.SEATS[int(p.seat_index) % SaloonTheme.SEATS.size()]
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
			var ring_mesh: MeshInstance3D = load("res://scripts/ui/TargetRing3D.gd").new()
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
			var plate: Node3D = load("res://scripts/ui/PlayerNameplate.gd").new()
			add_child(plate)
			plate.position = at + Vector3.UP * 3.2
			nameplates[id] = plate
			var status_label: Label3D = plate.label
			status_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			status_labels[id] = status_label
		avatars[id].apply_character(str(p.get("character_id", "")))
		nameplates[id].update_info(p, local_id, int(state.current_player))
		avatars[id].set_target_state(not targets.is_empty() and not targets.has(id) and id != local_id)
		if targets.has(id):
			avatars[id].set_expression("targeted", 1000)
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
	if context_player > 0:
		show_context(context_player)

func equipment_symbols(ids: Array) -> String:
	var symbols := {"horse": "♞", "spyglass": "⌕", "barrel": "▣", "jail": "▥", "dynamite": "✹"}
	return " ".join(ids.map(func(id): return symbols.get(id, "◆")))

func show_context(id: int) -> void:
	if not player_rows.has(id) or not avatars.has(id):
		return
	context_player = id
	var p: Dictionary = player_rows[id]
	var character: Dictionary = p.get("character", {})
	var info: Dictionary = NetworkManager.private_state.get("target_info", {}).get(id, {})
	var visible_role: String = p.public_role
	if id == local_player:
		visible_role = str(NetworkManager.private_state.get("role", visible_role))
	context_label.text = "%s · %s\n%s%s" % [
		p.display_name, character.get("display_name", ""),
		TextCatalog.text(visible_role) if not visible_role.is_empty() else "Vai trò bí mật",
		" · Khoảng cách %d" % info.distance if info.has("distance") else ""]
	context_label.position = avatars[id].position + Vector3(0, 3.7, 0)
	# Details live in the cached character card, never over the nameplate.
	context_label.visible = false
	character_info_requested.emit(p)

func hide_context() -> void:
	context_player = 0
	character_info_requested.emit({})
	if is_instance_valid(context_label):
		context_label.visible = false

func presentation(event: Dictionary) -> void:
	if event.has("match_id") and int(event.match_id) != built_match:
		return
	var event_id: String = str(event.get("audio_event_id", ""))
	if not event_id.is_empty():
		if seen_presentation.has(event_id):
			return
		seen_presentation[event_id] = true
		if seen_presentation.size() > 1024:
			seen_presentation.erase(seen_presentation.keys()[0])
	if presentation_queue.size() < 256:
		var visual: Dictionary = event.duplicate(true)
		if event.get("kind", "") == "transfer" and not event.get("hidden", true):
			var key: String = "%d:%s" % [int(event.get("player", 0)), str(event.get("from_zone", ""))]
			if objects.objects.has(key):
				visual["visual_origin"] = objects.objects[key].position
		presentation_queue.append(visual)

func present_event(event: Dictionary) -> void:
	if event.get("kind", "") == "animation" and event.get("animation", "") in ["shoot","gatling"]:
		targeting.quiet_for_shot(450 if event.animation == "gatling" else 230)
	AudioManager.consume_event(event)
	if event.get("kind", "") == "animation":
		play_animation(int(event.actor), str(event.animation), int(event.target))
		return
	var id: int = int(event.get("player", 0))
	var kind: String = str(event.get("kind", ""))
	if not avatars.has(id):
		return
	var at: Vector3 = avatars[id].position
	match kind:
		"draw":
			for index in range(mini(8, int(event.get("count", 1)))):
				effects.flying_card(Vector3(-0.45, 1.7, 0), at + Vector3.UP * 1.4, {}, index * 0.22)
		"judge", "reveal":
			effects.judgement(at + Vector3.UP * 2.7, event.get("card", {}), kind == "reveal")
			if kind == "reveal":
				# Black Jack reveals a card that remains in hand, never in discard.
				var reveal_id: int = int(event.get("card", {}).get("instance_id", 0))
				var revealed: Node3D = effects.judgement_cards.get(reveal_id)
				effects.judgement_cards.erase(reveal_id)
				if is_instance_valid(revealed):
					var reveal := revealed.create_tween()
					reveal.tween_interval(0.95)
					reveal.tween_property(revealed, "position", at + Vector3.UP * 1.4, 0.3)
					reveal.tween_callback(revealed.queue_free)
		"judgement_discard":
			effects.discard_judgement(at + Vector3.UP * 2.7, event.get("card", {}))
		"barrel_result":
			effects.floating(at + Vector3.UP * 2.7, ("THÙNG: NÉ" if event.success else "THÙNG: TRƯỢT") + " %d/%d" % [event.resolved, event.required], Color("#b5dbe2"))
		"missed":
			effects.floating(at + Vector3.UP * 2.7, "NÉ %d/%d" % [event.resolved, event.required], Color("#b5dbe2"))
		"ability":
			effects.floating(at + Vector3.UP * 2.7, player_rows[id].get("character", {}).get("display_name", "KỸ NĂNG"), Color("#e7cf91"))
		"role":
			effects.floating(at + Vector3.UP * 2.7, TextCatalog.text(event.role), Color("#e7cf91"))
		"damage":
			effects.floating(at + Vector3.UP * 2.7, "−%d MÁU" % event.get("amount", 1), Color("#ff967c"))
			if int(event.get("amount", 1)) == 3:
				effects.starburst(at + Vector3.UP * 1.9, 1.0)
				effects.smoke(at + Vector3.UP * 1.3)
				avatars[id].set_expression("panic", 1000)
				camera_shake = 0.14
				effects.floating(at + Vector3.UP * 3.4, "BOOM!", Color("#ffc269"))
				effects.spark(at + Vector3.UP, Color("#d89a65"), 12, 1.2)
		"transfer":
			var destination: Vector3 = avatars.get(int(event.get("to", 0)), avatars[id]).position + Vector3.UP * 1.4
			var origin: Vector3 = at + Vector3.UP * 1.4
			if not event.get("hidden", true):
				# Start visible-card removal at its actual table slot, including after
				# the next authoritative snapshot has already removed that object.
				origin = event.get("visual_origin", at.normalized() * 2.55 + Vector3.UP * 1.5)
			if not event.get("steal", true):
				destination = Vector3(0.45, 1.7, 0)
			for index in range(mini(8, int(event.get("count", 1)))):
				effects.flying_card(origin, destination, event.get("card", {}), index * 0.22, bool(event.get("hidden", true)))
		"discard":
			var origin: Vector3 = Vector3(0, 1.7, 0) if event.get("from_zone", "") == "market" else at + Vector3.UP * 1.4
			effects.flying_card(origin, Vector3(0.45, 1.7, 0), event.get("card", {}))
		"equip":
			var from: Vector3 = avatars.get(int(event.get("from_player", id)), avatars[id]).position
			effects.flying_card(from + Vector3.UP * 1.6, at.normalized() * 2.55 + Vector3.UP * 1.5, event.get("card", {}))
		"reclaim":
			effects.flying_card(Vector3(0.45, 1.7, 0), at + Vector3.UP * 1.4, event.get("card", {}))
		"dynamite_pass":
			if avatars.has(int(event.get("to", 0))):
				effects.flying_card(at + Vector3.UP * 1.4, avatars[int(event.to)].position + Vector3.UP * 1.4, event.get("card", {}))
		"jail_result":
			effects.floating(at + Vector3.UP * 2.7, "THOÁT GIAM!" if event.get("escaped", false) else "BỊ GIAM", Color("#b5dbe2"))
			effects.spark(at + Vector3.UP, Color("#b1babb"), 4)
		"store_pick":
			effects.flying_card(Vector3(0, 1.7, 0), at + Vector3.UP * 1.4, event.get("card", {}))
		"duel":
			var target: int = int(event.get("target", 0))
			if avatars.has(target):
				duel_focus = (at + avatars[target].position) / 2 + Vector3.UP
				duel_until = Time.get_ticks_msec() + 800
			effects.floating(at + Vector3.UP * 3, "ĐẤU SÚNG!", Color("#edc983"))

func animate(actor: int, kind: String, target: int) -> void:
	presentation({"kind": "animation", "actor": actor, "animation": kind, "target": target})

func play_animation(actor: int, kind: String, target: int) -> void:
	if not avatars.has(actor):
		return
	var spread_targets: Array = []
	if kind == "gatling":
		for id in avatars:
			if id != actor and not avatars[id].dead:
				spread_targets.append(avatars[id].position + Vector3.UP * 1.5)
		kind = "shoot"
	if kind == "shoot" and avatars.has(target):
		avatars[actor].face_target(avatars[target].global_position)
	avatars[actor].act(kind)
	var at: Vector3 = avatars[actor].position + Vector3(0, 2.6, 0)
	match kind:
		"shoot":
			camera_shake = maxf(camera_shake, 0.018)
			var shooting_avatar: PlayerAvatar = avatars[actor]
			var flash_timing := shooting_avatar.create_tween()
			flash_timing.tween_interval(0.095)
			flash_timing.tween_callback(func():
				if is_instance_valid(shooting_avatar):
					var muzzle: Vector3 = shooting_avatar.arm.to_global(Vector3(0, -0.5, -0.37))
					effects.muzzle(muzzle)
					effects.gun_smoke(muzzle)
					if avatars.has(target):
						effects.bullet(muzzle, avatars[target].position + Vector3.UP * 1.5, 0.012)
					for index in range(spread_targets.size()):
						effects.bullet(muzzle, spread_targets[index], 0.012 + index * 0.045))
		"hit":
			effects.starburst(at - Vector3.UP * 0.7)
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

