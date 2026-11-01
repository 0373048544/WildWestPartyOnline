class_name TableEffects
extends Node3D

var judgement_cards: Dictionary = {}

func spark(at: Vector3, color: Color, count: int = 6, radius: float = 0.65) -> void:
	count = VisualSettings.particle_count(count)
	for i in range(count):
		var piece := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.045
		mesh.height = 0.09
		mesh.radial_segments = 6
		mesh.rings = 3
		piece.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		piece.material_override = material
		add_child(piece)
		piece.position = at
		var angle: float = TAU * i / count
		var end := at + Vector3(cos(angle) * radius, 0.3 + (i % 3) * 0.2, sin(angle) * radius)
		var tween := piece.create_tween().set_parallel()
		tween.tween_property(piece, "position", end, 0.45).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(piece, "scale", Vector3.ONE * 0.01, 0.5)
		tween.chain().tween_callback(piece.queue_free)

func floating(at: Vector3, value: String, color: Color) -> void:
	var label: Label3D = load("res://scenes/vfx/FloatingText.tscn").instantiate()
	add_child(label)
	label.text = value
	label.modulate = color
	label.position = at
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", at.y + 1.1, 0.95).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.4).set_delay(0.55)
	tween.chain().tween_callback(label.queue_free)

func starburst(at: Vector3, size: float = 0.5, duration: float = 0.33) -> void:
	var shape := ImmediateMesh.new()
	shape.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array[Vector3] = []
	for index in range(12):
		var angle: float = TAU * index / 12.0
		var radius: float = size if index % 2 == 0 else size * 0.42
		points.append(Vector3(cos(angle), sin(angle), 0) * radius)
	for index in range(12):
		shape.surface_add_vertex(Vector3.ZERO)
		shape.surface_add_vertex(points[index])
		shape.surface_add_vertex(points[(index + 1) % 12])
	shape.surface_end()
	var node := MeshInstance3D.new()
	node.mesh = shape
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = Color("#ffdc75")
	node.material_override = material
	add_child(node)
	node.position = at
	node.scale = Vector3.ONE * 0.25
	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector3.ONE, duration * 0.24).set_trans(Tween.TRANS_BACK)
	tween.tween_property(node, "scale", Vector3.ONE * 0.01, duration * 0.76)
	tween.tween_callback(node.queue_free)

func smoke(at: Vector3) -> void:
	for index in range(VisualSettings.particle_count(6)):
		var puff := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.3
		mesh.height = 0.55
		mesh.radial_segments = 7
		mesh.rings = 4
		puff.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#b9b6a3") if index % 2 == 0 else Color("#e0cfae")
		puff.material_override = material
		add_child(puff)
		puff.position = at
		var angle: float = index * TAU / 6
		var tween := puff.create_tween().set_parallel()
		tween.tween_property(puff, "position", at + Vector3(cos(angle) * 0.75, 0.5 + index * 0.06, sin(angle) * 0.75), 0.65)
		tween.tween_property(puff, "scale", Vector3.ONE * 1.8, 0.35)
		tween.chain().tween_property(puff, "scale", Vector3.ONE * 0.01, 0.25)
		tween.chain().tween_callback(puff.queue_free)

func muzzle(at: Vector3) -> void:
	starburst(at, 0.23, 0.12)
	var flash := OmniLight3D.new()
	flash.light_color = Color("#ffca70")
	flash.light_energy = 2.0
	flash.omni_range = 2.0
	add_child(flash)
	flash.position = at
	var tween := flash.create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.12)
	tween.tween_callback(flash.queue_free)
	spark(at, Color("#ffd978"), 5, 0.35)

func bullet(origin: Vector3, target: Vector3, delay: float = 0) -> void:
	# No collision, damage or authority. A short moving fleck, never a laser.
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.028, 0.028, 0.22)
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("#ffeab0")
	node.material_override = material
	add_child(node)
	node.position = origin
	if origin.distance_to(target) > 0.01:
		node.look_at(target)
	var tween := node.create_tween()
	if delay > 0:
		node.visible = false
		tween.tween_interval(delay)
		tween.tween_callback(func(): node.visible = true)
	tween.tween_property(node, "position", target, 0.08)
	tween.tween_callback(node.queue_free)

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
	card.scale = Vector3.ONE * 0.65
	var tween := card.create_tween()
	tween.tween_interval(delay)
	tween.tween_property(card, "position", origin.lerp(destination, 0.5) + Vector3.UP * 0.8, 0.18).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(card, "rotation:y", 0.55, 0.18)
	tween.tween_property(card, "position", destination, 0.22).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(card, "rotation:y", 0.0, 0.22)
	tween.parallel().tween_property(card, "scale", Vector3.ONE * 0.2, 0.22)
	if hidden and not face.is_empty():
		tween.tween_callback(func():
			for child in card.get_children():
				child.free()
			card.configure("card", data, {})
			card.area.collision_layer = 0
			card.scale = Vector3.ONE * 0.65)
		tween.tween_interval(0.35)
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
