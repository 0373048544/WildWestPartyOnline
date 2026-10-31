class_name TableEffects
extends Node3D

func spark(at: Vector3, color: Color, count: int = 6, radius: float = 0.65) -> void:
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

func muzzle(at: Vector3) -> void:
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

func flying_card(origin: Vector3, destination: Vector3, face: Dictionary = {}, delay: float = 0.0) -> void:
	var card := TableObject.new()
	add_child(card)
	var data: Dictionary = CardData.data(face.get("card_data_id", "")).duplicate()
	if not face.is_empty():
		data["suit"] = face.get("suit", "")
		data["rank_label"] = str(face.get("rank", ""))
	card.configure("card" if not face.is_empty() else "hand", data, {})
	card.area.collision_layer = 0
	card.position = origin
	card.scale = Vector3.ONE * 0.65
	var tween := card.create_tween()
	tween.tween_interval(delay)
	tween.tween_property(card, "position", origin.lerp(destination, 0.5) + Vector3.UP * 0.8, 0.18).set_trans(Tween.TRANS_SINE)
	tween.tween_property(card, "position", destination, 0.22).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(card, "scale", Vector3.ONE * 0.2, 0.22)
	tween.tween_callback(card.queue_free)

func judgement(at: Vector3, face: Dictionary) -> void:
	if face.is_empty():
		return
	var card := TableObject.new()
	add_child(card)
	var data: Dictionary = CardData.data(face.card_data_id).duplicate()
	data["suit"] = face.suit
	data["rank_label"] = GameManager.rank_text(int(face.rank))
	card.configure("card", data, {})
	card.area.collision_layer = 0
	card.position = at
	card.rotation.x = PI / 3
	var tween := card.create_tween()
	tween.tween_property(card, "position:y", at.y + 0.2, 0.16)
	tween.tween_interval(1.0)
	tween.tween_property(card, "scale", Vector3.ONE * 0.01, 0.2)
	tween.tween_callback(card.queue_free)
