extends Node3D

var materials: Dictionary = {}
var key_light: DirectionalLight3D

func apply_quality() -> void:
	if key_light:
		key_light.shadow_enabled = VisualSettings.level == "HIGH" and not OS.has_feature("web")

func material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var key := str(color) + str(glow)
	if materials.has(key):
		return materials[key]
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.85
	if glow:
		result.emission_enabled = true
		result.emission = color
		result.emission_energy_multiplier = 1.5
	materials[key] = result
	return result

func shape(mesh: Mesh, at: Vector3, color: Color, glow: bool = false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material(color, glow)
	add_child(node)
	node.position = at
	return node

func block(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return shape(mesh, at, color)

func cylinder(radius: float, height: float, at: Vector3, color: Color, segments: int = 16) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	return shape(mesh, at, color)

func _ready() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("#42626c")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("#c1d0cf")
	settings.ambient_light_energy = 0.65
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = settings
	add_child(environment)
	var light := DirectionalLight3D.new()
	key_light = light
	light.rotation_degrees = Vector3(-52, -32, 0)
	light.light_color = Color("#ffdcac")
	light.light_energy = 1.05
	apply_quality()
	VisualSettings.changed.connect(apply_quality)
	light.directional_shadow_max_distance = 24
	add_child(light)
	var rim_light := DirectionalLight3D.new()
	rim_light.rotation_degrees = Vector3(-24, 145, 0)
	rim_light.light_color = Color("#9bc8d7")
	rim_light.light_energy = 0.28
	add_child(rim_light)
	for plank in range(24):
		var color: Color = [Color("#765039"), Color("#80593e"), Color("#694633")][plank % 3]
		block(Vector3(0.65, 0.12, 16), Vector3(-7.8 + plank * 0.67, -0.1, 0), color)
		for seam in [-4.0, 0.0, 4.0]:
			block(Vector3(0.62, 0.005, 0.018), Vector3(-7.8 + plank * 0.67, -0.035, seam + (plank % 2) * 1.5), Color("#49392e"))
	for wall_index in range(4):
		var wall := Node3D.new()
		add_child(wall)
		wall.rotation.y = wall_index * PI / 2
		for row in range(7):
			var board := block(Vector3(16, 0.62, 0.18), Vector3(0, 0.35 + row * 0.64, -7.7), Color("#36424a") if row > 2 else Color("#5d4535"))
			board.reparent(wall, false)
		for post in [-7.5, -4.2, 4.2, 7.5]:
			var beam := block(Vector3(0.22, 4.8, 0.3), Vector3(post, 2.3, -7.5), Color("#392e29"))
			beam.reparent(wall, false)
		var trim := block(Vector3(16, 0.12, 0.25), Vector3(0, 1.85, -7.5), Color("#b88a50"))
		trim.reparent(wall, false)
		lantern(wall, Vector3(-4.1, 3.0, -7.15))
		lantern(wall, Vector3(4.1, 3.0, -7.15))
	# A single warm fill keeps lantern props inexpensive; their cores are emissive.
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 5.5, 0)
	fill.light_color = Color("#ffc47e")
	fill.light_energy = 0.45
	fill.omni_range = 11
	add_child(fill)
	build_table()
	for at in [Vector3(-5.8, 0, -5.8), Vector3(5.8, 0, 5.8), Vector3(-5.8, 0, 5.8)]:
		barrel(at)
		cylinder(0.12, 0.45, at + Vector3(0.15, 1.55, 0), Color("#568f78"))
		cylinder(0.06, 0.16, at + Vector3(0.15, 1.85, 0), Color("#568f78"))
	block(Vector3(3.8, 0.16, 0.7), Vector3(0, 2.1, -7.1), Color("#996b43"))
	for i in range(7):
		cylinder(0.12, 0.4 + (i % 3) * 0.07, Vector3(-1.4 + i * 0.46, 2.4, -7.1), [Color("#689877"), Color("#b57a4c"), Color("#6b9fa4")][i % 3])
	signboard(Vector3(0, 3.35, -7.45), 0.0)
	signboard(Vector3(0, 3.35, 7.45), PI)
	build_decor()

func build_decor() -> void:
	# All props remain behind the playing ring; none creates a picking collider.
	for side in [-1, 1]:
		var x: float = side * 5.7
		block(Vector3(1.5, 1.8, 0.12), Vector3(x, 2.6, -7.52), Color("#ddaf6e"))
		block(Vector3(1.27, 1.55, 0.14), Vector3(x, 2.6, -7.43), Color("#8cc6cc"))
		block(Vector3(0.09, 1.6, 0.19), Vector3(x, 2.6, -7.32), Color("#b67a4b"))
		block(Vector3(1.4, 0.1, 0.19), Vector3(x, 2.6, -7.3), Color("#b67a4b"))
		cylinder(0.08, 0.55, Vector3(x + 0.4, 2.2, -7.24), Color("#54926d"), 6)
		block(Vector3(0.3, 0.08, 0.08), Vector3(x + 0.32, 2.3, -7.23), Color("#54926d"))
		block(Vector3(0.8, 1.1, 0.04), Vector3(side * 2.8, 2.8, -7.36), Color("#edd4a1"))
		var wanted := Label3D.new()
		wanted.text = "TRUY NÃ\n★\n$ 500"
		wanted.font_size = 34
		wanted.pixel_size = 0.004
		wanted.modulate = Color("#653c32")
		wanted.outline_size = 0
		add_child(wanted)
		wanted.position = Vector3(side * 2.8, 2.8, -7.29)
	for index in range(7):
		var angle: float = TAU * index / 7.0
		var at := Vector3(sin(angle) * 5.15, 0, cos(angle) * 5.15)
		cylinder(0.4, 0.15, at + Vector3.UP * 0.6, Color("#ba7d4b"), 10)
		for dx in [-0.23, 0.23]:
			block(Vector3(0.09, 0.55, 0.1), at + Vector3(dx, 0.28, 0), Color("#714a35"))

func lantern(parent: Node3D, at: Vector3) -> void:
	var lantern_node: Node3D = load("res://scenes/props/SaloonLantern.tscn").instantiate()
	parent.add_child(lantern_node)
	lantern_node.position = at

func barrel(at: Vector3) -> void:
	cylinder(0.49, 1.25, at + Vector3(0, 0.62, 0), Color("#9b6b42"), 10)
	for y in [0.18, 0.95]:
		cylinder(0.505, 0.1, at + Vector3(0, y, 0), Color("#3f474a"), 10)
	cylinder(0.46, 0.05, at + Vector3(0, 1.27, 0), Color("#bd915c"), 10)

func signboard(at: Vector3, yaw: float) -> void:
	var sign := Node3D.new()
	sign.name = "SwingingSign"
	add_child(sign)
	sign.position = at + Vector3.UP * 0.45
	sign.rotation.y = yaw
	var board := block(Vector3(3.6, 0.9, 0.16), Vector3(0, -0.45, 0), Color("#a57644"))
	board.reparent(sign, false)
	var text := Label3D.new()
	text.text = "MIỀN TÂY\nĐẠI CHIẾN"
	text.font_size = 48
	text.pixel_size = 0.007
	text.modulate = Color("#ffe5ab")
	text.outline_size = 3
	sign.add_child(text)
	text.position = Vector3(0, -0.45, 0.12)
	if VisualSettings.decorative_motion():
		var swing := sign.create_tween().set_loops().set_trans(Tween.TRANS_SINE)
		swing.tween_property(sign, "rotation:z", 0.025, 2.8)
		swing.tween_property(sign, "rotation:z", -0.025, 2.8)
	# A low-poly horseshoe assembled from nine small metal segments.
	for index in range(9):
		var angle: float = PI + PI * index / 8.0
		var piece := block(Vector3(0.12, 0.18, 0.08), at + Vector3(2.35 + cos(angle) * 0.3, sin(angle) * 0.3, 0.08 * cos(yaw)), Color("#819695"))
		piece.rotation.z = angle - PI / 2

func build_table() -> void:
	cylinder(0.65, 1.1, Vector3(0, 0.5, 0), Color("#49382c"))
	for side in [-1, 1]:
		block(Vector3(3.5, 0.16, 0.3), Vector3(0, 0.12, side * 0.65), Color("#59402d"))
	cylinder(3.17, 0.28, Vector3(0, 1.13, 0), Color("#714c31"), 48)
	cylinder(3.18, 0.06, Vector3(0, 1.29, 0), Color("#d3a05c"), 48)
	cylinder(2.98, 0.055, Vector3(0, 1.33, 0), Color("#946a43"), 48)
	cylinder(2.72, 0.025, Vector3(0, 1.37, 0), Color("#235859"), 48)
	for index in range(6):
		var angle: float = TAU * index / 6.0
		var at := Vector3(sin(angle) * 2.2, 1.41, cos(angle) * 2.2)
		for chip in range(2):
			cylinder(0.085, 0.035, at + Vector3.UP * chip * 0.035, Color("#dfad60") if index % 2 == 0 else Color("#cf7565"), 8)
	var rim := TorusMesh.new()
	rim.inner_radius = 2.59
	rim.outer_radius = 2.62
	rim.rings = 48
	rim.ring_segments = 8
	shape(rim, Vector3(0, 1.39, 0), Color("#b29b60"))
	for i in range(12):
		var angle: float = TAU * i / 12.0
		cylinder(0.035, 0.025, Vector3(sin(angle) * 2.88, 1.38, cos(angle) * 2.88), Color("#e7b66b"), 6)
	for i in range(5):
		block(Vector3(0.46, 0.028, 0.65), Vector3(-0.45, 1.42 + i * 0.03, 0), Color("#ddd0ae"))
	block(Vector3(0.43, 0.01, 0.62), Vector3(-0.45, 1.565, 0), Color("#a14f3c"))
	block(Vector3(0.46, 0.028, 0.65), Vector3(0.45, 1.42, 0), Color("#f1dfb9"))
	for x in [-0.45, 0.45]:
		var caption := Label3D.new()
		caption.text = "RÚT BÀI" if x < 0 else "BỎ BÀI"
		caption.font_size = 32
		caption.pixel_size = 0.006
		caption.modulate = Color("#e7c681")
		caption.rotation.x = -PI / 2
		add_child(caption)
		caption.position = Vector3(x, 1.4, 0.65)
