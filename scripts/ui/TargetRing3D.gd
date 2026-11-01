extends MeshInstance3D

static var cached_mesh: ImmediateMesh

func _ready() -> void:
	if cached_mesh:
		mesh = cached_mesh
		return
	var geometry := ImmediateMesh.new()
	geometry.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(32):
		if index % 4 == 3:
			continue
		var a: float = TAU * index / 32
		var b: float = TAU * (index + 1) / 32
		var p := Vector3(cos(a), 0, sin(a))
		var q := Vector3(cos(b), 0, sin(b))
		for vertex in [p * 0.69, q * 0.69, q * 0.79, p * 0.69, q * 0.79, p * 0.79]:
			geometry.surface_add_vertex(vertex)
	geometry.surface_end()
	mesh = geometry
	cached_mesh = geometry
