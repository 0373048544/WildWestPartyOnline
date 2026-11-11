class_name TableEffects
extends Node3D

static var gun_puff_mesh: QuadMesh
static var gun_puff_material: StandardMaterial3D
static var fleck_mesh: BoxMesh
static var fleck_material: StandardMaterial3D
static var spark_mesh: SphereMesh
static var spark_materials: Dictionary = {}
static var smoke_mesh: SphereMesh
static var smoke_materials: Array[StandardMaterial3D] = []
static var starburst_mesh: ImmediateMesh
static var starburst_material: StandardMaterial3D
static var muzzle_core_mesh: SphereMesh
static var muzzle_core_material: StandardMaterial3D
var floating_pool: Array[Label3D] = []
var bullet_pool: Array[MeshInstance3D] = []
var puff_pool: Array[MeshInstance3D] = []
var mesh_pool: Array[MeshInstance3D] = []
var spawned_count: int = 0
var created_mesh_count: int = 0

func _presentation_scale(value: float) -> float:
	var table: Node = get_parent()
	var mobile_camera_node: Node = table.get("mobile_camera") if is_instance_valid(table) else null
	# First-person phone cameras sit much closer to the table than the desktop
	# overview camera. Keep transient card presentations readable without letting
	# them cover opponents, the centre table, or the local hand.
	return value * 0.16 if is_instance_valid(mobile_camera_node) and bool(mobile_camera_node.get("enabled")) else value

func _camera_safe_origin(at: Vector3) -> Vector3:
	if _presentation_scale(1.0) >= 0.5:
		return at
	var camera := get_viewport().get_camera_3d()
	if not is_instance_valid(camera):
		return at
	var global_at: Vector3 = to_global(at)
	var offset: Vector3 = global_at - camera.global_position
	var distance: float = offset.length()
	# A remote barrel can point directly into the first-person near plane. Moving
	# only the cosmetic flash along the same view ray preserves its screen source
	# while preventing perspective from turning a tiny flash into a full overlay.
	if distance > 0.001 and distance < 1.65:
		return to_local(camera.global_position + offset / distance * 1.65)
	return at

func _acquire_mesh() -> MeshInstance3D:
	var node: MeshInstance3D
	if not mesh_pool.is_empty():
		node = mesh_pool.pop_back()
	else:
		node = MeshInstance3D.new()
		created_mesh_count += 1
	if not node.is_inside_tree():
		add_child(node)
	elif node.get_parent() != self:
		node.reparent(self)
	node.visible = true
	node.transparency = 0.0
	node.scale = Vector3.ONE
	node.rotation = Vector3.ZERO
	spawned_count += 1
	return node

func _release_mesh(node: MeshInstance3D) -> void:
	if not is_instance_valid(node):
		return
	node.visible = false
	node.mesh = null
	node.material_override = null
	if node.get_parent() != self:
		node.reparent(self)
	if mesh_pool.size() < 32:
		mesh_pool.append(node)
	else:
		node.queue_free()

func reset_for_match() -> void:
	# Every transient and every pooled object stays owned by this node. A rematch
	# can therefore cancel all tweens/VFX without touching gameplay table objects.
	for child in get_children():
		child.queue_free()
	floating_pool.clear()
	bullet_pool.clear()
	puff_pool.clear()
	mesh_pool.clear()
	judgement_cards.clear()
	spawned_count = 0
	created_mesh_count = 0

func gun_smoke(at: Vector3) -> void:
	if not gun_puff_mesh:
		gun_puff_mesh = QuadMesh.new()
		gun_puff_mesh.size = Vector2.ONE
		var image := Image.create(32,32,false,Image.FORMAT_RGBA8)
		for x in range(32):
			for y in range(32):
				var radius: float = Vector2(x/31.0-0.5,y/31.0-0.5).length()*2
				image.set_pixel(x,y,Color(0.73,0.7,0.62, pow(maxf(0,1-radius),2)*0.4))
		gun_puff_material = StandardMaterial3D.new()
		gun_puff_material.albedo_texture = ImageTexture.create_from_image(image)
		gun_puff_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gun_puff_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		gun_puff_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var first_person_mobile: bool = _presentation_scale(1.0) < 0.5
	at = _camera_safe_origin(at)
	for index in range(2):
		var puff: MeshInstance3D = puff_pool.pop_back() if not puff_pool.is_empty() else MeshInstance3D.new()
		puff.mesh = gun_puff_mesh
		puff.material_override = gun_puff_material
		if not puff.is_inside_tree():
			add_child(puff)
		elif puff.get_parent() != self:
			puff.reparent(self)
		puff.visible = true
		puff.transparency = 0.0
		puff.position = at
		puff.scale = Vector3.ONE * (0.055 if first_person_mobile else 0.22)
		var tween := puff.create_tween().set_parallel()
		tween.tween_property(puff,"position",at+Vector3(0.03*index,0.13+0.05*index,0) if first_person_mobile else at+Vector3(0.08*index,0.35+0.12*index,0),0.55)
		tween.tween_property(puff,"scale",Vector3.ONE*(0.18 if first_person_mobile else 0.65),0.55)
		tween.tween_property(puff,"transparency",1.0,0.55)
		tween.chain().tween_callback(_release_puff.bind(puff))

var judgement_cards: Dictionary = {}

func spark(at: Vector3, color: Color, count: int = 6, radius: float = 0.65) -> void:
	count = VisualSettings.particle_count(count)
	for i in range(count):
		var piece := _acquire_mesh()
		if not spark_mesh:
			spark_mesh = SphereMesh.new()
			spark_mesh.radius = 0.045
			spark_mesh.height = 0.09
			spark_mesh.radial_segments = 6
			spark_mesh.rings = 3
		piece.mesh = spark_mesh
		var material_key := str(color)
		if not spark_materials.has(material_key):
			var material := StandardMaterial3D.new()
			material.albedo_color = color
			material.emission_enabled = true
			material.emission = color
			spark_materials[material_key] = material
		piece.material_override = spark_materials[material_key]
		piece.position = at
		var angle: float = TAU * i / count
		var end := at + Vector3(cos(angle) * radius, 0.3 + (i % 3) * 0.2, sin(angle) * radius)
		var tween := piece.create_tween().set_parallel()
		tween.tween_property(piece, "position", end, 0.45).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(piece, "scale", Vector3.ONE * 0.01, 0.5)
		tween.chain().tween_callback(_release_mesh.bind(piece))

func floating(at: Vector3, value: String, color: Color) -> void:
	var label: Label3D = floating_pool.pop_back() if not floating_pool.is_empty() else load("res://scenes/vfx/FloatingText.tscn").instantiate()
	if not label.is_inside_tree():
		add_child(label)
	elif label.get_parent() != self:
		label.reparent(self)
	label.visible = true
	label.text = value
	label.modulate = color
	label.position = at
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", at.y + 1.1, 0.95).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.4).set_delay(0.55)
	tween.chain().tween_callback(_release_floating.bind(label))

func quiet_floating() -> void:
	# A new full-table choice takes visual priority over short-lived feedback from
	# the previous action. The existing tweens still return these labels to the
	# pool, so this does not allocate or interrupt gameplay presentation queues.
	for child in get_children():
		if child is Label3D:
			child.visible = false

func comic(at: Vector3, value: String, color: Color, duration: float = 0.8) -> void:
	var label: Label3D = floating_pool.pop_back() if not floating_pool.is_empty() else load("res://scenes/vfx/FloatingText.tscn").instantiate()
	if not label.is_inside_tree():
		add_child(label)
	elif label.get_parent() != self:
		label.reparent(self)
	label.visible = true
	label.text = value
	label.modulate = color
	label.position = at
	label.scale = Vector3.ONE * 0.38
	var tween := label.create_tween()
	tween.tween_property(label, "scale", Vector3.ONE * 0.62, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector3.ONE * 0.52, 0.10)
	tween.parallel().tween_property(label, "position:y", at.y + 0.55, duration)
	tween.tween_interval(maxf(0.08, duration - 0.42))
	tween.tween_property(label, "modulate:a", 0.0, 0.20)
	tween.tween_callback(_release_floating.bind(label))

func starburst(at: Vector3, size: float = 0.5, duration: float = 0.33) -> void:
	if not starburst_mesh:
		starburst_mesh = ImmediateMesh.new()
		starburst_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		var points: Array[Vector3] = []
		for index in range(12):
			var angle: float = TAU * index / 12.0
			var radius: float = 1.0 if index % 2 == 0 else 0.42
			points.append(Vector3(cos(angle), sin(angle), 0) * radius)
		for index in range(12):
			starburst_mesh.surface_add_vertex(Vector3.ZERO)
			starburst_mesh.surface_add_vertex(points[index])
			starburst_mesh.surface_add_vertex(points[(index + 1) % 12])
		starburst_mesh.surface_end()
		starburst_material = StandardMaterial3D.new()
		starburst_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		starburst_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		starburst_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		starburst_material.albedo_color = Color("#ffdc75")
	var node := _acquire_mesh()
	node.mesh = starburst_mesh
	node.material_override = starburst_material
	node.position = at
	node.scale = Vector3.ONE * size * 0.25
	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector3.ONE * size, duration * 0.24).set_trans(Tween.TRANS_BACK)
	tween.tween_property(node, "scale", Vector3.ONE * 0.01, duration * 0.76)
	tween.tween_callback(_release_mesh.bind(node))

func smoke(at: Vector3) -> void:
	if not smoke_mesh:
		smoke_mesh = SphereMesh.new()
		smoke_mesh.radius = 0.3
		smoke_mesh.height = 0.55
		smoke_mesh.radial_segments = 7
		smoke_mesh.rings = 4
		for color in [Color("#b9b6a3"), Color("#e0cfae")]:
			var material := StandardMaterial3D.new()
			material.albedo_color = color
			smoke_materials.append(material)
	for index in range(VisualSettings.particle_count(6)):
		var puff := _acquire_mesh()
		puff.mesh = smoke_mesh
		puff.material_override = smoke_materials[index % 2]
		puff.position = at
		var angle: float = index * TAU / 6
		var tween := puff.create_tween().set_parallel()
		tween.tween_property(puff, "position", at + Vector3(cos(angle) * 0.75, 0.5 + index * 0.06, sin(angle) * 0.75), 0.65)
		tween.tween_property(puff, "scale", Vector3.ONE * 1.8, 0.35)
		tween.chain().tween_property(puff, "scale", Vector3.ONE * 0.01, 0.25)
		tween.chain().tween_callback(_release_mesh.bind(puff))

func muzzle(at: Vector3) -> void:
	var first_person_mobile: bool = _presentation_scale(1.0) < 0.5
	at = _camera_safe_origin(at)
	# A billboard star viewed straight down the barrel grows into a screen-sized
	# polygon in first-person perspective. Mobile keeps the emissive core, sparks
	# and smoke; the broader comic star remains a desktop/table-camera accent.
	if not first_person_mobile:
		starburst(at, 0.17, 0.075)
	if not muzzle_core_mesh:
		muzzle_core_mesh = SphereMesh.new()
		muzzle_core_mesh.radius = 0.075
		muzzle_core_mesh.height = 0.15
		muzzle_core_mesh.radial_segments = 7
		muzzle_core_mesh.rings = 3
		muzzle_core_material = StandardMaterial3D.new()
		muzzle_core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		muzzle_core_material.albedo_color = Color("#fff0a1")
		muzzle_core_material.emission_enabled = true
		muzzle_core_material.emission = Color("#ffb33f")
		muzzle_core_material.emission_energy_multiplier = 2.2
	var core := _acquire_mesh()
	core.mesh = muzzle_core_mesh
	core.material_override = muzzle_core_material
	core.position = at
	core.scale = Vector3(0.065, 0.065, 0.18) if first_person_mobile else Vector3(0.48, 0.48, 1.25)
	var core_tween := core.create_tween()
	core_tween.tween_property(core, "scale", Vector3.ONE * 0.01, 0.09).set_trans(Tween.TRANS_QUAD)
	core_tween.tween_callback(_release_mesh.bind(core))
	# Dynamic lights are reserved for desktop/high quality; the emissive core keeps
	# Web/mobile gunfire readable without creating an expensive realtime light.
	if not VisualSettings.constrained_device():
		var flash := OmniLight3D.new()
		flash.light_color = Color("#ffca70")
		flash.light_energy = 1.8
		flash.omni_range = 1.8
		add_child(flash)
		flash.position = at
		var tween := flash.create_tween()
		tween.tween_property(flash, "light_energy", 0.0, 0.10)
		tween.tween_callback(flash.queue_free)
	spark(at, Color("#ffd978"), 2 if first_person_mobile else 4, 0.065 if first_person_mobile else 0.31)

func bullet(origin: Vector3, target: Vector3, delay: float = 0) -> void:
	# No collision, damage or authority. A short moving fleck, never a laser.
	var node: MeshInstance3D = bullet_pool.pop_back() if not bullet_pool.is_empty() else MeshInstance3D.new()
	if not fleck_mesh:
		fleck_mesh = BoxMesh.new()
		fleck_mesh.size = Vector3(0.028, 0.028, 0.22)
		fleck_material = StandardMaterial3D.new()
		fleck_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fleck_material.albedo_color = Color("#ffeab0")
	node.mesh = fleck_mesh
	node.material_override = fleck_material
	if not node.is_inside_tree():
		add_child(node)
	elif node.get_parent() != self:
		node.reparent(self)
	node.visible = true
	node.position = origin
	if origin.distance_to(target) > 0.01:
		node.look_at(target)
	var tween := node.create_tween()
	if delay > 0:
		node.visible = false
		tween.tween_interval(delay)
		tween.tween_callback(func(): node.visible = true)
	tween.tween_property(node, "position", target, 0.08)
	tween.tween_callback(_release_bullet.bind(node))

func _release_floating(label: Label3D) -> void:
	if not is_instance_valid(label):
		return
	label.visible = false
	if floating_pool.size() < 12:
		label.reparent(self)
		floating_pool.append(label)
	else:
		label.queue_free()

func _release_bullet(node: MeshInstance3D) -> void:
	if not is_instance_valid(node):
		return
	node.visible = false
	if bullet_pool.size() < 16:
		node.reparent(self)
		bullet_pool.append(node)
	else:
		node.queue_free()

func _release_puff(node: MeshInstance3D) -> void:
	if not is_instance_valid(node):
		return
	node.visible = false
	if puff_pool.size() < 12:
		node.reparent(self)
		puff_pool.append(node)
	else:
		node.queue_free()

func flying_card(origin: Vector3, destination: Vector3, face: Dictionary = {}, delay: float = 0.0, hidden: bool = false) -> void:
	var card := TableObject.new()
	add_child(card)
	var data: Dictionary = CardData.data(face.get("card_data_id", "")).duplicate()
	if not face.is_empty():
		data["suit"] = face.get("suit", "")
		data["rank_label"] = str(face.get("rank", ""))
	card.configure("card" if not face.is_empty() and not hidden else "hand", data, {})
	card.area.collision_layer = 0
	card.position = origin
	card.scale = Vector3.ONE * _presentation_scale(0.65)
	var tween := card.create_tween()
	tween.tween_interval(delay)
	tween.tween_property(card, "position", origin.lerp(destination, 0.5) + Vector3.UP * 0.8, 0.18).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(card, "rotation:y", 0.55, 0.18)
	tween.tween_property(card, "position", destination, 0.22).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(card, "rotation:y", 0.0, 0.22)
	tween.parallel().tween_property(card, "scale", Vector3.ONE * _presentation_scale(0.2), 0.22)
	if hidden and not face.is_empty():
		tween.tween_callback(func():
			for child in card.get_children():
				child.free()
			card.configure("card", data, {})
			card.area.collision_layer = 0
			card.scale = Vector3.ONE * _presentation_scale(0.65))
		tween.tween_interval(0.35)
	tween.tween_callback(card.queue_free)

func special_card_intro(origin: Vector3, face: Dictionary, hold: float = 0.45) -> void:
	# A readable, short presentation copy. The physical card was already consumed
	# by authority; this object never participates in input or game state.
	var card := TableObject.new()
	add_child(card)
	var data: Dictionary = CardData.data(str(face.get("card_data_id", ""))).duplicate()
	data["suit"] = str(face.get("suit", ""))
	data["rank_label"] = str(face.get("rank", ""))
	card.configure("card", data, {})
	card.area.collision_layer = 0
	card.position = origin
	card.scale = Vector3.ONE * _presentation_scale(0.58)
	card.rotation = Vector3(0.12, -0.18, 0.08)
	var center := Vector3(0, 2.35, 0)
	var tween := card.create_tween()
	tween.tween_property(card, "position", center, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(card, "scale", Vector3.ONE * _presentation_scale(0.82), 0.22)
	tween.parallel().tween_property(card, "rotation", Vector3.ZERO, 0.22)
	tween.tween_interval(clampf(hold, 0.2, 0.65))
	tween.tween_property(card, "position", Vector3(0.45, 1.7, 0), 0.18).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(card, "scale", Vector3.ONE * _presentation_scale(0.18), 0.18)
	tween.tween_callback(card.queue_free)

func judgement(at: Vector3, face: Dictionary, from_hand: bool = false) -> void:
	if face.is_empty():
		return
	var card := TableObject.new()
	add_child(card)
	var data: Dictionary = CardData.data(face.card_data_id).duplicate()
	data["suit"] = face.suit
	data["rank_label"] = GameManager.rank_text(face.rank)
	card.configure("card", data, {})
	card.area.collision_layer = 0
	card.position = at - Vector3.UP * 1.3 if from_hand else Vector3(-0.45, 1.7, 0)
	card.scale = Vector3.ONE * _presentation_scale(1.0)
	judgement_cards[int(face.instance_id)] = card
	card.rotation.x = PI / 3
	var tween := card.create_tween()
	tween.tween_property(card, "position", at + Vector3.UP * 0.2, 0.22).set_trans(Tween.TRANS_SINE)
	# Stay visible until the authority actually discards the reserved judgement.

func discard_judgement(at: Vector3, face: Dictionary) -> void:
	var id: int = int(face.get("instance_id", 0))
	var card: Node3D = judgement_cards.get(id)
	judgement_cards.erase(id)
	if not is_instance_valid(card):
		flying_card(at, Vector3(0.45, 1.7, 0), face)
		return
	var tween := card.create_tween()
	tween.tween_property(card, "position", Vector3(0.45, 1.7, 0), 0.3).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(card, "rotation:x", 0.0, 0.3)
	tween.tween_callback(card.queue_free)
