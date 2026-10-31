extends Node3D

func _ready() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.16
	mesh.bottom_radius = 0.22
	mesh.height = 0.42
	mesh.radial_segments = 6
	var glass := MeshInstance3D.new()
	glass.mesh = mesh
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("#ffd37b")
	glow.emission_enabled = true
	glow.emission = Color("#ffc260")
	glow.emission_energy_multiplier = 2.0
	glass.material_override = glow
	add_child(glass)
	for y in [-0.25, 0.25]:
		var cap := MeshInstance3D.new()
		var cap_mesh := CylinderMesh.new()
		cap_mesh.top_radius = 0.24
		cap_mesh.bottom_radius = 0.24
		cap_mesh.height = 0.08
		cap_mesh.radial_segments = 6
		cap.mesh = cap_mesh
		var metal := StandardMaterial3D.new()
		metal.albedo_color = Color("#332c28")
		cap.material_override = metal
		add_child(cap)
		cap.position.y = y
