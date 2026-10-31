class_name TargetingArrow
extends Node3D

var geometry := ImmediateMesh.new()
var material := StandardMaterial3D.new()
var tint := Color("#e8b966")

func _ready() -> void:
	var surface := MeshInstance3D.new()
	surface.mesh = geometry
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	surface.material_override = material
	add_child(surface)
	visible = false

func _process(_delta: float) -> void:
	material.albedo_color = tint.lerp(Color("#fff0c3"), 0.12 + 0.10 * sin(Time.get_ticks_msec() * 0.006))

func aim(origin: Vector3, destination: Vector3, valid: bool = true) -> void:
	if origin.distance_to(destination) < 0.1:
		visible = false
		return
	visible = true
	tint = Color("#e8b966") if valid else Color("#a75e56")
	geometry.clear_surfaces()
	geometry.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array[Vector3] = []
	for i in range(17):
		var t: float = float(i) / 16
		points.append(origin.lerp(destination, t) + Vector3.UP * sin(t * PI) * 0.75)
	for i in range(16):
		var direction: Vector3 = (points[i + 1] - points[i]).normalized()
		var side: Vector3 = direction.cross(Vector3.UP).normalized() * 0.065
		for vertex in [points[i] - side, points[i] + side, points[i + 1] + side,
			points[i] - side, points[i + 1] + side, points[i + 1] - side]:
			geometry.surface_add_vertex(vertex)
	var forward: Vector3 = (destination - points[15]).normalized()
	var width: Vector3 = forward.cross(Vector3.UP).normalized() * 0.25
	for vertex in [destination + forward * 0.25, destination - forward * 0.35 + width, destination - forward * 0.35 - width]:
		geometry.surface_add_vertex(vertex)
	geometry.surface_end()
