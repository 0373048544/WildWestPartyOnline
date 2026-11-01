extends Node3D

var label: Label3D
var stats: Label3D
var backing: StandardMaterial3D
var sheriff_badge: MeshInstance3D
var hearts: Array = []
var hovered: bool = false
var base_height: float = 3.2
var screen_rect := Rect2()
static var heart_mesh: ImmediateMesh

static func make_star() -> MeshInstance3D:
	var star := MeshInstance3D.new()
	var shape := ImmediateMesh.new()
	shape.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array[Vector3] = []
	for index in range(10):
		var angle: float = PI / 2 + index * TAU / 10
		var radius: float = 0.13 if index % 2 == 0 else 0.058
		points.append(Vector3(cos(angle), sin(angle), 0) * radius)
	for index in range(10):
		for vertex in [Vector3.ZERO, points[index], points[(index + 1) % 10]]:
			shape.surface_add_vertex(vertex)
	shape.surface_end()
	star.mesh = shape
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = SaloonTheme.GOLD
	star.material_override = material
	return star

func _ready() -> void:
	var panel := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.82, 0.65)
	panel.mesh = quad
	backing = StandardMaterial3D.new()
	backing.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	backing.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	backing.albedo_color = Color(0.08, 0.14, 0.17, 0.88)
	backing.cull_mode = BaseMaterial3D.CULL_DISABLED
	backing.render_priority = -10
	panel.material_override = backing
	add_child(panel)
	label = Label3D.new()
	label.font_size = 38
	label.pixel_size = 0.0042
	label.position = Vector3(0, 0.15, 0.02)
	label.modulate = SaloonTheme.CREAM
	label.outline_size = 3
	label.no_depth_test = true
	label.render_priority = 10
	add_child(label)
	stats = Label3D.new()
	stats.font_size = 30
	stats.pixel_size = 0.004
	stats.position = Vector3(0.6, -0.15, 0.02)
	stats.modulate = SaloonTheme.CREAM
	stats.no_depth_test = true
	stats.render_priority = 10
	add_child(stats)
	sheriff_badge = make_star()
	sheriff_badge.position = Vector3(-0.79, -0.14, 0.04)
	sheriff_badge.scale = Vector3.ONE * 0.6
	add_child(sheriff_badge)
	for index in range(5):
		var heart := MeshInstance3D.new()
		if not heart_mesh:
			var shape := ImmediateMesh.new()
			shape.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			var points: Array[Vector3] = []
			for step in range(20):
				var t: float = TAU * step / 20
				points.append(Vector3(16 * pow(sin(t), 3), 13 * cos(t) - 5 * cos(2*t) - 2 * cos(3*t) - cos(4*t), 0) * 0.005)
			for step in range(20):
				for vertex in [Vector3.ZERO, points[step], points[(step+1)%20]]:
					shape.surface_add_vertex(vertex)
			shape.surface_end()
			heart_mesh = shape
		heart.mesh = heart_mesh
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		heart.material_override = material
		heart.position = Vector3(-0.55 + index * 0.175, -0.14, 0.03)
		add_child(heart)
		hearts.append(heart)
	var card := MeshInstance3D.new()
	var card_mesh := QuadMesh.new()
	card_mesh.size = Vector2(0.1, 0.15)
	card.mesh = card_mesh
	var card_mat := backing.duplicate()
	card_mat.albedo_color = SaloonTheme.GOLD
	card.material_override = card_mat
	card.position = Vector3(0.4, -0.15, 0.03)
	card.rotation.z = 0.15
	add_child(card)

func update_info(row: Dictionary, local: int, active: int) -> void:
	sheriff_badge.visible = row.public_role == "SHERIFF"
	var badges: String = "BẠN · " if int(row.player_id) == local else ""
	label.text = badges + str(row.display_name).left(12)
	label.font_size = 40 if label.text.length() > 16 else 48
	stats.text = str(row.hand_count)
	for index in range(hearts.size()):
		hearts[index].visible = index < int(row.max_hp)
		hearts[index].material_override.albedo_color = Color("#ec8d79") if index < int(row.current_hp) else Color("#57616a")
	backing.albedo_color = Color("#59472a") if int(row.player_id) == active else Color("#192c35")
	modulate_plate(row.is_alive)

func modulate_plate(alive: bool) -> void:
	label.modulate = SaloonTheme.CREAM if alive else Color("#999b99")
	stats.modulate = SaloonTheme.CREAM if alive else Color("#999b99")
	if not alive:
		backing.albedo_color = Color("#30383b")

func place(camera: Camera3D, anchor: Vector3) -> Rect2:
	global_position = anchor + Vector3.UP * base_height
	global_basis = camera.global_basis
	var center: Vector2 = camera.unproject_position(global_position)
	var edge: Vector2 = camera.unproject_position(global_position + camera.global_basis.x * 1.82)
	var projected_width: float = maxf(1, center.distance_to(edge))
	var size_factor: float = clampf(148 / projected_width, 1, 3.4)
	scale = Vector3.ONE * size_factor
	global_position.y += 0.325 * (size_factor - 1) + (0.12 if hovered else 0)
	center = camera.unproject_position(global_position)
	var screen_size := Vector2(projected_width * size_factor, projected_width * size_factor * 0.65 / 1.82)
	return Rect2(center - screen_size / 2, screen_size).grow(4)
