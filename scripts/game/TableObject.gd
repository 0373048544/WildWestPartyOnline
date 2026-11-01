class_name TableObject
extends Node3D

var area: Area3D
var frame_material: StandardMaterial3D
var title: Label3D
var token: Dictionary = {}
var enabled: bool = false
var corner_label: Label3D

func set_face(card: Dictionary) -> void:
	if not is_instance_valid(corner_label):
		corner_label = Label3D.new()
		corner_label.rotation.x = -PI / 2
		corner_label.position = Vector3(-0.13, 0.13, -0.28)
		corner_label.font_size = 28
		corner_label.pixel_size = 0.0034
		corner_label.outline_size = 0
		add_child(corner_label)
	corner_label.text = CardInstance.corner(card)
	corner_label.modulate = CardInstance.suit_color(str(card.get("suit", "")))

func mesh(mesh_data: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.mesh = mesh_data
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	item.material_override = material
	add_child(item)
	item.position = at
	return item

func box(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var data := BoxMesh.new()
	data.size = size
	return mesh(data, at, color)

func cylinder(radius: float, height: float, at: Vector3, color: Color) -> void:
	var data := CylinderMesh.new()
	data.top_radius = radius
	data.bottom_radius = radius
	data.height = height
	data.radial_segments = 8
	mesh(data, at, color)

func configure(kind: String, data: Dictionary, metadata: Dictionary) -> void:
	token = metadata
	var frame := box(Vector3(0.64, 0.045, 0.88), Vector3.ZERO, Color("#815c3f"))
	frame_material = frame.material_override
	box(Vector3(0.58, 0.025, 0.82), Vector3(0, 0.04, 0), Color("#e5d1a5") if kind != "hand" else Color("#654951"))
	title = Label3D.new()
	title.font_size = 28
	title.pixel_size = 0.0034
	title.outline_size = 2
	title.modulate = Color("#ffedba")
	title.rotation.x = -PI / 2
	title.position = Vector3(0, 0.12, 0.27)
	add_child(title)
	title.text = str(data.get("name", "TAY BÀI KÍN"))
	match kind:
		"card":
			title.text += "\n%s %s" % [TextCatalog.text(data.get("suit", "")), str(data.get("rank_label", ""))]
			title.font_size = 24
			set_face({"rank": data.get("rank_label", ""), "suit": data.get("suit", "")})
		"hand":
			for index in range(3):
				var back := box(Vector3(0.26, 0.04, 0.4), Vector3(-0.16 + index * 0.16, 0.09 + index * 0.025, -0.12), Color("#844e46"))
				back.rotation.y = (index - 1) * 0.16
		"barrel":
			cylinder(0.18, 0.35, Vector3(0, 0.23, -0.1), Color("#9c7548"))
			for y in [0.12, 0.34]:
				cylinder(0.185, 0.035, Vector3(0, y, -0.1), Color("#46515b"))
		"spyglass":
			var tube := CylinderMesh.new()
			tube.top_radius = 0.085
			tube.bottom_radius = 0.11
			tube.height = 0.43
			var scope := mesh(tube, Vector3(0, 0.16, -0.05), Color("#c9ab65"))
			scope.rotation.z = PI / 2
		"horse":
			box(Vector3(0.34, 0.17, 0.18), Vector3(0, 0.23, -0.1), Color("#a16a45"))
			box(Vector3(0.12, 0.31, 0.16), Vector3(0.16, 0.35, -0.1), Color("#a16a45"))
			for x in [-0.12, 0.12]:
				box(Vector3(0.07, 0.19, 0.12), Vector3(x, 0.11, -0.1), Color("#634733"))
		"jail":
			for x in [-0.23, -0.08, 0.08, 0.23]:
				box(Vector3(0.035, 1.0, 0.035), Vector3(x, 0.5, 0), Color("#7d9296"))
			box(Vector3(0.55, 0.06, 0.09), Vector3(0, 0.99, 0), Color("#9d794c"))
		"dynamite":
			for x in [-0.12, 0, 0.12]:
				cylinder(0.06, 0.32, Vector3(x, 0.2, -0.07), Color("#bc5747"))
			box(Vector3(0.4, 0.05, 0.14), Vector3(0, 0.2, -0.07), Color("#65513b"))
		"weapon":
			box(Vector3(0.43, 0.1, 0.09), Vector3(0, 0.17, -0.1), Color("#647880"))
			box(Vector3(0.1, 0.19, 0.1), Vector3(-0.13, 0.1, -0.1), Color("#70513a"))
	area = Area3D.new()
	area.collision_layer = 2
	area.collision_mask = 0
	area.set_meta("table_token", token)
	var shape := CollisionShape3D.new()
	var bounds := BoxShape3D.new()
	bounds.size = Vector3(0.7, 0.4 if kind != "jail" else 1.0, 0.94)
	shape.shape = bounds
	shape.position.y = bounds.size.y / 2
	area.add_child(shape)
	add_child(area)

func highlight(value: bool) -> void:
	enabled = value
	frame_material.albedo_color = Color("#f3c268") if value else Color("#685e51")
	frame_material.emission_enabled = value
	frame_material.emission = Color("#a87d36")
	title.modulate = Color("#fff1be") if value else Color("#ccc3ad")
