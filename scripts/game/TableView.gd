extends Node3D

var avatars: Dictionary = {}
signal character_info_requested(player: Dictionary)
var rings: Dictionary = {}
var camera: Camera3D
var seats: Node3D
var built_match: int = -1
var effects: TableEffects
var special_presenter: SpecialCardPresenter
var camera_goal := Vector3.ZERO
var camera_shake: float = 0.0
var targeting: TargetingController
var player_names: Dictionary = {}
var status_labels: Dictionary = {}
var nameplates: Dictionary = {}
var plate_layout_key: String = ""
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
var reaction_source: int = 0
var reaction_target: int = 0
var state_signature: String = ""
var targeting_frame: bool = false

func _ready() -> void:
	AudioManager.table = self
	var room: Node3D = load("res://scripts/game/SaloonRoom.gd").new()
	add_child(room)
	effects = TableEffects.new()
	add_child(effects)
	special_presenter = SpecialCardPresenter.new()
	add_child(special_presenter)
	special_presenter.setup(self)
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
		if kind in ["judge", "reveal"]:
			presentation_wait = 1.4
		elif kind == "transfer" and bool(event.get("department_store", false)):
			presentation_wait = 0.22
		elif kind in ["draw", "transfer"]:
			presentation_wait = 0.45 + 0.22 * (mini(8, int(event.get("count", 1))) - 1)
		else:
			presentation_wait = 0.42
	if camera_goal == Vector3.ZERO:
		return
	camera_shake = maxf(0.0, camera_shake - delta * 0.25)
	var offset := Vector3(sin(Time.get_ticks_msec() * 0.08), cos(Time.get_ticks_msec() * 0.1), 0) * camera_shake
	var previous_camera: Vector3 = camera.position
	camera.position = camera.position.lerp(camera_goal + offset, minf(1.0, delta * 12))
	var frame_layout: Script = load("res://scripts/ui/MatchLayout.gd")
	var framing: Vector3 = (
		Vector3(0, -1.1, 0)
		if frame_layout.portrait(self)
		else (Vector3(0, -3.25, 0) if targeting_frame and frame_layout.mobile_landscape(self) else Vector3(0, 1.0, 0))
	)
	camera.look_at(duel_focus if Time.get_ticks_msec() < duel_until else framing)
	if previous_camera.distance_squared_to(camera.position) > 0.000001:
		plate_layout_key = ""
	if plate_layout_key.is_empty():
		layout_nameplates()
	for ring in rings.values():
		ring.rotation.y += delta * 0.5
		ring.scale = Vector3.ONE * (1.0 + 0.025 * sin(Time.get_ticks_msec() * 0.005))
	if avatars.has(turns_player()):
		turn_marker.position = avatars[turns_player()].position + Vector3(0, 3.8 + sin(Time.get_ticks_msec() * 0.004) * 0.1, 0)

func turns_player() -> int:
	return int(NetworkManager.public_state.get("current_player", 0))

func layout_nameplates() -> void:
	var key: String = str(camera.global_transform)+str(get_viewport().get_visible_rect())+str(built_match)+str(get_viewport().get_meta("reaction_banner_rect", Rect2()))
	for plate in nameplates.values():
		key += str(plate.get_instance_id())+str(plate.hovered)
	if key == plate_layout_key:
		return
	plate_layout_key = key
	var placements: Array = []
	for id in nameplates:
		placements.append({"id":id,"plate": nameplates[id], "rect": nameplates[id].place(camera, avatars[id].global_position)})
	placements.sort_custom(func(a, b):
		if a.id == local_player or b.id == local_player:
			return a.id == local_player
		return a.rect.position.y < b.rect.position.y if not is_equal_approx(a.rect.position.y,b.rect.position.y) else a.rect.position.x < b.rect.position.x)
	var occupied: Array[Rect2] = []
	var banner_exclusion: Rect2 = get_viewport().get_meta("reaction_banner_rect", Rect2())
	if banner_exclusion.has_area():
		occupied.append(banner_exclusion)
	var width: float = get_viewport().get_visible_rect().size.x
	if load("res://scripts/ui/MatchLayout.gd").mobile(self):
		var radius: float = load("res://scripts/ui/MatchLayout.gd").units(self,25)
		for avatar in avatars.values():
			var center: Vector2 = camera.unproject_position(avatar.global_position+Vector3.UP*1.6)
			occupied.append(Rect2(center-Vector2.ONE*radius,Vector2.ONE*radius*2))
	for item in placements:
		var rect: Rect2 = item.rect
		rect.position.x = clampf(rect.position.x, 8, maxf(8, width - rect.size.x - 8))
		var best: Rect2 = rect
		var best_score: float = INF
		for y in [0,-1,1,-2,2,-3,3,-4,4,-5,5,-6,6,-7,7,-8,8,-9,9,-10,10]:
			for x in [0,-0.25,0.25,-0.5,0.5,-1,1,-1.5,1.5,-2,2]:
				var candidate := Rect2(rect.position+Vector2(x*(rect.size.x+6),y*18),rect.size)
				candidate.position.x = clampf(candidate.position.x,8,maxf(8,width-rect.size.x-8))
				if candidate.position.y < 58:
					continue
				var overlaps: bool = occupied.any(func(previous): return candidate.grow(2).intersects(previous))
				var score: float = candidate.position.distance_squared_to(rect.position)+(1000000 if overlaps else 0)
				if score < best_score:
					best_score = score
					best = candidate
		rect = best
		var depth: float = -camera.to_local(item.plate.global_position).z
		var old_center: Vector2 = camera.unproject_position(item.plate.global_position)
		item.plate.global_position += camera.project_position(rect.get_center(), depth)-camera.project_position(old_center,depth)
		item.plate.screen_rect = rect
		occupied.append(rect)

func update_state(state: Dictionary, local_id: int, targets: Array) -> void:
	var next_signature := JSON.stringify([
		state.get("match_id", 0), state.get("players", []),
		state.get("current_player", 0), state.get("choice_player", 0),
		state.get("choice_type", ""), state.get("market", []), local_id, targets
	]) + str(get_viewport().get_visible_rect().size)
	if next_signature == state_signature:
		return
	state_signature = next_signature
	plate_layout_key = ""
	targeting_frame = not targets.is_empty()
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
		avatars[id].apply_weapon_visual(str(p.get("weapon_id","")))
		var choosing: bool = int(state.get("choice_player", 0)) == id
		nameplates[id].update_info(p, local_id, int(state.current_player), choosing)
		avatars[id].set_target_state(not targets.is_empty() and not targets.has(id) and id != local_id)
		if targets.has(id):
			avatars[id].set_expression("targeted", 1000)
		rings[id].visible = targets.has(id) or int(state.current_player) == id or choosing
		rings[id].material_override.albedo_color = Color("#ffda7b") if targets.has(id) or choosing else seat_color
		rings[id].material_override.emission_enabled = targets.has(id) or choosing
		rings[id].material_override.emission = Color("#ffc775")
		if not p.is_alive and not avatars[id].dead:
			avatars[id].act("death")
		if id == local_id:
			local_seat = p.seat_index
	turn_marker.visible = avatars.has(int(state.current_player)) and state.winner.is_empty() and state.phase != "CHARACTER_SELECTION"
	var local_angle: float = TAU * float(local_seat) / count
	var match_layout: Script = load("res://scripts/ui/MatchLayout.gd")
	var layout_mode: String = match_layout.mode(self)
	var extra_seats: float = maxf(0.0, count - 4.0)
	var camera_radius := 9.1
	var camera_height := 7.7
	camera.fov = 57.0
	if layout_mode == match_layout.MOBILE_PORTRAIT:
		camera_radius = 11.0 + extra_seats * 0.18
		camera_height = 10.8 + extra_seats * 0.12
		camera.fov = 59.0
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		camera.v_offset = 0
	elif layout_mode == match_layout.MOBILE_LANDSCAPE:
		# Landscape phones reserve only ~27% for the hand, so the camera can
		# move closer and let the table/avatars dominate the remaining space.
		camera_radius = 8.75 + extra_seats * 0.14
		camera_height = 7.15 + extra_seats * 0.10
		camera.fov = 64.0 if targeting_frame else 55.0
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		camera.v_offset = 0
	else:
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		camera.v_offset = 0
	camera_goal = Vector3(sin(local_angle) * camera_radius, camera_height, cos(local_angle) * camera_radius)
	if camera.position == Vector3.ZERO:
		camera.position = camera_goal
	var initial_framing: Vector3 = (
		Vector3(0, -1.1, 0)
		if match_layout.portrait(self)
		else (Vector3(0, -3.25, 0) if targeting_frame and layout_mode == match_layout.MOBILE_LANDSCAPE else Vector3(0, 1.0, 0))
	)
	camera.look_at(initial_framing)
	if context_player > 0:
		show_context(context_player)

func set_reaction_focus(source_id: int, target_id: int) -> void:
	var changed := reaction_source != source_id or reaction_target != target_id
	reaction_source = source_id
	reaction_target = target_id
	if source_id <= 0 or target_id <= 0:
		return
	for id in rings:
		if id != source_id and id != target_id:
			continue
		rings[id].visible = true
		rings[id].material_override.albedo_color = Color("#ffc56b") if id == source_id else Color("#ef765e")
		rings[id].material_override.emission_enabled = true
		rings[id].material_override.emission = rings[id].material_override.albedo_color
	if changed:
		if avatars.has(source_id):
			avatars[source_id].set_expression("targeted", 650)
		if nameplates.has(target_id):
			nameplates[target_id].flash_target()

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
	# Choice overlays are shown from synchronized state immediately, while the
	# cinematic queue may still be finishing the previous action. Clear only
	# transient floating labels now so they cannot overlap the new choice UI.
	if str(event.get("kind", "")) in ["store_started", "department_store"]:
		effects.quiet_floating()
	var event_id: String = str(event.get("event_id", event.get("audio_event_id", "")))
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
		"store_started":
			effects.quiet_floating()
			special_presenter.show_special_start(id, "general_store")
		"department_store":
			effects.quiet_floating()
			special_presenter.show_special_start(id, "department_store")
		"heal":
			var healing_card: String = str(event.get("card_data_id", ""))
			if healing_card in ["drink", "iced_tea"]:
				special_presenter.show_heal(id, healing_card, bool(event.get("rescued", false)))
			else:
				effects.comic(at + Vector3.UP * 2.7, "+%d MÁU" % int(event.get("amount", 1)), Color("#9fe3a9"))
		"department_store_private":
			var giver: int = int(event.get("giver", 0))
			var receiver: int = int(event.get("receiver", 0))
			if avatars.has(giver) and avatars.has(receiver):
				effects.flying_card(
					avatars[giver].position + Vector3.UP * 1.4,
					avatars[receiver].position + Vector3.UP * 1.4,
					event.get("card", {})
				)
		"draw":
			avatars[id].act("draw")
			for index in range(mini(8, int(event.get("count", 1)))):
				effects.flying_card(Vector3(-0.45, 1.7, 0), at + Vector3.UP * 1.4, {}, index * 0.22)
		"judge", "reveal":
			if event.get("purpose","") in ["jail","dynamite"]:
				avatars[id].act(str(event.purpose))
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
			if id == local_player and nameplates.has(id):
				nameplates[id].flash_hit()
			if int(event.get("amount", 1)) == 3:
				effects.starburst(at + Vector3.UP * 1.9, 1.0)
				effects.smoke(at + Vector3.UP * 1.3)
				avatars[id].set_expression("panic", 1000)
				camera_shake = 0.14
				effects.floating(at + Vector3.UP * 3.4, "BOOM!", Color("#ffc269"))
				effects.spark(at + Vector3.UP, Color("#d89a65"), 12, 1.2)
		"transfer":
			var receiver: int = int(event.get("receiver", event.get("to", 0)))
			# Participants receive a separate private face-card event. Everyone else
			# sees only this public card-back transfer.
			if bool(event.get("department_store", false)) and local_player in [id, receiver]:
				return
			if bool(event.get("department_store", false)):
				var giver_name: String = str(player_names.get(id, "Một cao bồi"))
				var receiver_name: String = str(player_names.get(receiver, "người nhận"))
				effects.comic(at + Vector3.UP * 2.7, "%s đưa 1 lá cho %s" % [giver_name, receiver_name], Color("#e7cf91"), 0.72)
			if avatars.has(receiver):
				avatars[receiver].act("snatch" if event.get("steal",true) else "discard")
			var destination: Vector3 = avatars.get(receiver, avatars[id]).position + Vector3.UP * 1.4
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
			var discarded_id: String = str(event.get("card", {}).get("card_data_id", ""))
			# These accepted cards receive a dedicated readable presentation on the
			# following semantic event instead of a duplicate generic discard flight.
			if discarded_id in ["drink", "iced_tea", "department_store", "general_store"]:
				return
			var origin: Vector3 = Vector3(0, 1.7, 0) if event.get("from_zone", "") == "market" else at + Vector3.UP * 1.4
			effects.flying_card(origin, Vector3(0.45, 1.7, 0), event.get("card", {}))
		"equip":
			avatars[id].act("equip")
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
			avatars[id].act("store")
			effects.flying_card(Vector3(0, 1.7, 0), at + Vector3.UP * 1.4, event.get("card", {}))
			var picked_name: String = str(CardData.data(str(event.get("card", {}).get("card_data_id", ""))).get("name", "1 lá"))
			effects.comic(at + Vector3.UP * 2.7, "%s chọn %s" % [str(player_names.get(id, "Một cao bồi")), picked_name], Color("#edc983"), 0.78)
		"duel":
			avatars[id].act("duel")
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
					var muzzle: Vector3 = shooting_avatar.muzzle_position()
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
			# HEAL already owns the single +HP/comedy message. This animation event
			# supplies only the physical avatar accent and must not duplicate text.
			effects.spark(at - Vector3(0, 0.4, 0), Color("#99dbad"), 6, 0.4)
		"dodge":
			effects.floating(at, TextCatalog.text("DODGE") + "!", Color("#9adce4"))
			effects.spark(at - Vector3(0, 2.3, 0), Color("#d4c9af"), 5)
		"death":
			effects.spark(at - Vector3(0, 2.2, 0), Color("#bd9475"), 8)

