extends Node3D

var geometry := ImmediateMesh.new()
var material := StandardMaterial3D.new()
var pulse: Tween
var locked_style: String = ""
var locked_valid: bool = false
var locked_position := Vector3.INF
var lock_age: float = 0

func _process(delta: float) -> void:
	if visible:
		lock_age += delta
		if not pulse or not pulse.is_running():
			scale = Vector3.ONE * (1.0 + 0.025 * sin(lock_age * 4.5))

func _ready() -> void:
	var mark := MeshInstance3D.new()
	mark.mesh = geometry
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.render_priority = 15
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mark.material_override = material
	add_child(mark)
	visible = false

func line(a: Vector2, b: Vector2, width: float = 0.024) -> void:
	for outline in [true, false]:
		var side: Vector2 = (b - a).normalized().orthogonal() * (width + (0.035 if outline else 0)) / 2
		geometry.surface_set_color(Color("#231c18") if outline else Color.WHITE)
		for at in [a-side, a+side, b+side, a-side, b+side, b-side]:
			geometry.surface_add_vertex(Vector3(at.x, at.y, -0.002 if outline else 0))

func card(center: Vector2, extent: Vector2 = Vector2(0.19, 0.27)) -> void:
	var corners: Array = [center-extent, center+Vector2(extent.x,-extent.y), center+extent, center+Vector2(-extent.x,extent.y)]
	for index in range(4):
		line(corners[index], corners[(index+1)%4])

func lock(at: Vector3, style: String, valid: bool) -> void:
	var changed: bool = not visible or not locked_position.is_equal_approx(at)
	position = at
	if style == locked_style and valid == locked_valid and not changed:
		return
	locked_position = at
	locked_style = style
	locked_valid = valid
	lock_age = 0
	geometry.clear_surfaces()
	geometry.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# Rounded-looking brass corners remain recognizable for every card context.
	for x in [-1, 1]:
		for y in [-1, 1]:
			var corner := Vector2(x * 0.4, y * 0.34)
			line(corner, corner - Vector2(x * 0.14, 0), 0.035)
			line(corner, corner - Vector2(0, y * 0.14), 0.035)
	match style:
		"BANG":
			pass
		"DUEL":
			for x in [-1, 1]:
				line(Vector2(x * -0.28, -0.24), Vector2(x * 0.28, 0.24), 0.045)
				line(Vector2(x * -0.28, -0.24), Vector2(x * -0.35, -0.09), 0.05)
		"STEAL":
			card(Vector2(0.13, 0))
			line(Vector2(-0.38, 0), Vector2(0.02, 0))
			line(Vector2(-0.38, 0), Vector2(-0.25, 0.13))
			line(Vector2(-0.38, 0), Vector2(-0.25, -0.13))
		"DISCARD":
			card(Vector2.ZERO)
			line(Vector2(-0.3,-0.3), Vector2(0.3,0.3), 0.04)
			line(Vector2(-0.3,0.3), Vector2(0.3,-0.3), 0.04)
		"JAIL":
			card(Vector2.ZERO, Vector2(0.3, 0.3))
			for x in [-0.15, 0, 0.15]:
				line(Vector2(x,-0.3), Vector2(x,0.3))
		_:
			var corners: Array = [Vector2(0,0.3), Vector2(0.3,0), Vector2(0,-0.3), Vector2(-0.3,0)]
			for index in range(4):
				line(corners[index], corners[(index+1)%4])
	geometry.surface_end()
	var palette := {"BANG": "#efc77c", "DUEL": "#dca56f", "STEAL": "#b7c88d", "DISCARD": "#dba08b", "JAIL": "#b6c5c3", "GENERIC": "#e6d7b2"}
	material.albedo_color = Color(palette.get(style, "#e6d7b2")) if valid else Color("#bc7568")
	visible = true
	scale = Vector3.ONE * 0.86
	if pulse:
		pulse.kill()
	pulse = create_tween().set_trans(Tween.TRANS_BACK)
	pulse.tween_property(self, "scale", Vector3.ONE, 0.14)
