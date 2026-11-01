class_name TableObject
extends Node3D

var area: Area3D
var frame_material: StandardMaterial3D
var title: Label3D
var token: Dictionary = {}
var enabled: bool = false
var corner_label: Label3D
var prop_kind: String = ""
var weapon_id: String = ""
var hovered: bool = false
var lift: float = 0
var spawn_tween: Tween
var base_color := Color("#446985")
static var material_cache: Dictionary = {}
static var mesh_cache: Dictionary = {}

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
	if not material_cache.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.8
		material_cache[color] = material
	item.material_override = material_cache[color]
	add_child(item)
	item.position = at
	return item

func box(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var key := str(size)
	if mesh_cache.has(key):
		return mesh(mesh_cache[key], at, color)
	var data := BoxMesh.new()
	data.size = size
	mesh_cache[key] = data
	return mesh(data, at, color)

func cylinder(radius: float, height: float, at: Vector3, color: Color) -> void:
	var key := "cylinder:%s:%s" % [radius,height]
	if mesh_cache.has(key):
		mesh(mesh_cache[key],at,color)
		return
	var data := CylinderMesh.new()
	data.top_radius = radius
	data.bottom_radius = radius
	data.height = height
	data.radial_segments = 8
	mesh_cache[key] = data
	mesh(data, at, color)

func configure(kind: String, data: Dictionary, metadata: Dictionary) -> void:
	prop_kind = kind
	base_color = Color("#476f91") if kind not in ["card","hand"] else Color("#8e6244")
	token = metadata
	var frame := box(Vector3(0.68, 0.055, 0.92), Vector3.ZERO, base_color)
	# Only the selection frame changes color; faces/props share immutable materials.
	frame.material_override = frame.material_override.duplicate()
	frame_material = frame.material_override
	box(Vector3(0.58, 0.025, 0.82), Vector3(0, 0.04, 0), Color("#e5d1a5") if kind != "hand" else Color("#654951"))
	for x in [-0.29,0.29]:
		box(Vector3(0.018,0.014,0.77),Vector3(x,0.062,0),Color("#c3a269"))
	title = Label3D.new()
	title.font_size = 28
	title.pixel_size = 0.0034
	title.outline_size = 2
	title.modulate = Color("#ffedba")
	title.modulate = Color("#2c343c")
	title.outline_size = 0
	title.width = 180
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
			cylinder(0.21,0.2,Vector3(0,0.23,-0.1),Color("#b98c52"))
			for y in [0.12, 0.34]:
				cylinder(0.185, 0.035, Vector3(0, y, -0.1), Color("#46515b"))
		"spyglass":
			var tube := CylinderMesh.new()
			tube.top_radius = 0.085
			tube.bottom_radius = 0.11
			tube.height = 0.43
			var scope := mesh(tube, Vector3(0, 0.16, -0.05), Color("#c9ab65"))
			scope.rotation.z = PI / 2
			var lens: MeshInstance3D = box(Vector3(0.04,0.14,0.14),Vector3(0.23,0.16,-0.05),Color("#86c4c9"))
			lens.rotation.z = 0.1
		"horse":
			box(Vector3(0.34, 0.17, 0.18), Vector3(0, 0.23, -0.1), Color("#a16a45"))
			box(Vector3(0.12, 0.31, 0.16), Vector3(0.16, 0.35, -0.1), Color("#a16a45"))
			for x in [-0.12, 0.12]:
				box(Vector3(0.07, 0.19, 0.12), Vector3(x, 0.11, -0.1), Color("#634733"))
			box(Vector3(0.12,0.14,0.21),Vector3(0.19,0.5,-0.13),Color("#b17b4b"))
			for x in [0.15,0.23]:
				box(Vector3(0.04,0.12,0.05),Vector3(x,0.6,-0.1),Color("#634733"))
			var tail := box(Vector3(0.06,0.25,0.06),Vector3(-0.21,0.28,-0.08),Color("#463530"))
			tail.rotation.z = -0.4
		"jail":
			for x in [-0.23, -0.08, 0.08, 0.23]:
				box(Vector3(0.035, 1.0, 0.035), Vector3(x, 0.5, 0), Color("#7d9296"))
			box(Vector3(0.55, 0.06, 0.09), Vector3(0, 0.99, 0), Color("#9d794c"))
			box(Vector3(0.55,0.06,0.09),Vector3(0,0.12,0),Color("#9d794c"))
			box(Vector3(0.13,0.16,0.07),Vector3(0,0.48,-0.07),Color("#d4ac60"))
		"dynamite":
			for x in [-0.12, 0, 0.12]:
				cylinder(0.06, 0.32, Vector3(x, 0.2, -0.07), Color("#bc5747"))
			box(Vector3(0.4, 0.05, 0.14), Vector3(0, 0.2, -0.07), Color("#65513b"))
			var fuse := box(Vector3(0.035,0.24,0.035),Vector3(0.06,0.45,-0.07),Color("#dec49b"))
			fuse.rotation.z = -0.35
		"weapon":
			var gun := MeshInstance3D.new()
			gun.name = "WeaponProp"
			gun.mesh = load("res://scripts/player/WeaponVisuals.gd").mesh_for(str(data.get("card_data_id","")))
			gun.rotation = Vector3(PI/2,0,PI/2)
			gun.position = Vector3(-0.12,0.22,-0.09)
			gun.scale = Vector3.ONE*0.65
			add_child(gun)
	area = Area3D.new()
	area.collision_layer = 2
	area.collision_mask = 0
	area.set_meta("table_token", token)
	var shape := CollisionShape3D.new()
	var bounds := BoxShape3D.new()
	# Hit the card base, avoiding tall props intercepting a neighboring slot ray.
	bounds.size = Vector3(0.72, 0.18, 0.98)
	shape.shape = bounds
	shape.position.y = bounds.size.y / 2
	area.add_child(shape)
	add_child(area)

func highlight(value: bool) -> void:
	enabled = value
	frame_material.albedo_color = Color("#f3c268") if value or hovered else base_color
	title.modulate = Color("#2c343c")

func set_hovered(value: bool) -> void:
	hovered = value
	highlight(enabled)
	if is_instance_valid(spawn_tween):
		spawn_tween.kill()
	spawn_tween = create_tween()
	spawn_tween.tween_property(self,"position:y",position.y-lift+(0.08 if value else 0),0.1)
	lift = 0.08 if value else 0

func play_spawn() -> void:
	var resting: Vector3 = scale
	scale = resting*0.7
	spawn_tween = create_tween()
	spawn_tween.tween_property(self,"scale",resting,0.18).set_trans(Tween.TRANS_BACK)

func play_remove() -> void:
	area.collision_layer = 0
	var tween := create_tween()
	tween.tween_property(self,"scale",Vector3.ONE*0.01,0.16)
	tween.tween_callback(queue_free)
