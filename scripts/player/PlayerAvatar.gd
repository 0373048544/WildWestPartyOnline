class_name PlayerAvatar
extends Node3D

var arm: Node3D
var bottle: MeshInstance3D
var motion: Tween
var dead: bool = false
var base_y: float = 0.0
var rig: Node3D
var hat: Node3D
var gun: MeshInstance3D
var materials: Dictionary = {}
var aim_yaw: float = 0.0
var picking_area: Area3D

func part(mesh: Mesh, at: Vector3, color: Color, parent: Node3D = null) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	if not materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.85
		materials[color] = material
	node.material_override = materials[color]
	(parent if parent != null else rig).add_child(node)
	node.position = at
	return node

func box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh

func cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 10
	return mesh

func sphere(radius: float, height: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 6
	return mesh

func build(color: Color) -> void:
	rig = Node3D.new()
	add_child(rig)
	part(box(Vector3(0.69, 0.68, 0.44)), Vector3(0, 1.03, 0), color)
	part(box(Vector3(0.18, 0.55, 0.025)), Vector3(0, 1.03, -0.235), Color("#f3dcb5"))
	part(box(Vector3(0.75, 0.12, 0.48)), Vector3(0, 0.76, 0), Color("#50382c"))
	part(box(Vector3(0.15, 0.12, 0.04)), Vector3(0, 0.76, -0.26), Color("#e9c878"))
	for x in [-0.22, 0.22]:
		part(box(Vector3(0.26, 0.38, 0.28)), Vector3(x, 0.5, 0), Color("#35424b"))
		part(box(Vector3(0.31, 0.22, 0.46)), Vector3(x, 0.2, -0.08), Color("#44332e"))
	part(sphere(0.44, 0.78), Vector3(0, 1.73, -0.025), Color("#e9b77f"))
	for x in [-0.16, 0.16]:
		part(sphere(0.085, 0.15), Vector3(x, 1.83, -0.4), Color("#fff0d7"))
		part(sphere(0.035, 0.085), Vector3(x, 1.83, -0.47), Color("#243342"))
		var brow := part(box(Vector3(0.15, 0.035, 0.045)), Vector3(x, 1.96, -0.4), Color("#604131"))
		brow.rotation.z = 0.14 if x < 0 else -0.14
		var mustache := part(box(Vector3(0.19, 0.07, 0.07)), Vector3(x * 0.65, 1.64, -0.435), Color("#624235"))
		mustache.rotation.z = -0.18 if x < 0 else 0.18
	part(sphere(0.085, 0.13), Vector3(0, 1.73, -0.48), Color("#dc9b68"))
	part(box(Vector3(0.38, 0.13, 0.45)), Vector3(0, 1.4, -0.03), color.lightened(0.25))
	var scarf := part(box(Vector3(0.18, 0.25, 0.045)), Vector3(0.08, 1.26, -0.26), color.lightened(0.25))
	scarf.rotation.z = 0.3
	hat = Node3D.new()
	rig.add_child(hat)
	hat.position.y = 2.08
	part(cylinder(0.76, 0.79, 0.1), Vector3.ZERO, Color("#6c452e"), hat)
	part(cylinder(0.34, 0.43, 0.43), Vector3(0, 0.22, 0), Color("#ab7947"), hat)
	part(cylinder(0.42, 0.44, 0.095), Vector3(0, 0.07, 0), color, hat)
	part(box(Vector3(0.09, 0.09, 0.04)), Vector3(0, 0.07, -0.44), Color("#f1cf78"), hat)
	part(box(Vector3(0.23, 0.49, 0.23)), Vector3(-0.48, 1.02, 0), color)
	part(sphere(0.12, 0.2), Vector3(-0.48, 0.76, 0), Color("#e9b77f"))
	arm = Node3D.new()
	rig.add_child(arm)
	arm.position = Vector3(0.47, 1.27, 0)
	part(box(Vector3(0.23, 0.49, 0.23)), Vector3(0, -0.23, 0), color, arm)
	part(sphere(0.12, 0.2), Vector3(0, -0.5, 0), Color("#e9b77f"), arm)
	gun = part(box(Vector3(0.12, 0.17, 0.36)), Vector3(0, -0.51, -0.16), Color("#55616a"), arm)
	bottle = part(cylinder(0.065, 0.11, 0.34), Vector3(0, -0.55, -0.12), Color("#61a582"), arm)
	bottle.visible = false
	picking_area = Area3D.new()
	picking_area.collision_layer = 1
	picking_area.collision_mask = 0
	add_child(picking_area)
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.64
	capsule.height = 2.9
	collision.shape = capsule
	collision.position.y = 1.35
	picking_area.add_child(collision)

func set_target_state(dimmed: bool) -> void:
	for color in materials:
		materials[color].albedo_color = Color(color).darkened(0.48) if dimmed else color

func _process(_delta: float) -> void:
	if rig == null or dead:
		return
	if motion == null or not motion.is_running():
		var time: float = Time.get_ticks_msec() * 0.002 + position.x
		rig.position.y = sin(time) * 0.025
		rig.scale.y = 1.0 + sin(time) * 0.012
		hat.rotation.z = sin(time * 0.7) * 0.025

func face_target(at: Vector3) -> void:
	var local := to_local(at)
	aim_yaw = atan2(-local.x, -local.z)

func act(kind: String) -> void:
	if dead or rig == null:
		return
	if motion:
		motion.kill()
	rig.position = Vector3.ZERO
	rig.rotation = Vector3.ZERO
	rig.scale = Vector3.ONE
	arm.rotation = Vector3.ZERO
	hat.rotation = Vector3.ZERO
	bottle.visible = kind == "drink"
	gun.visible = kind != "drink"
	motion = create_tween()
	match kind:
		"death":
			dead = true
			motion.tween_property(rig, "position:y", 0.18, 0.12)
			motion.tween_interval(0.12)
			motion.tween_property(rig, "rotation:z", 1.5, 0.4).set_trans(Tween.TRANS_BACK)
			motion.parallel().tween_property(rig, "position:y", -0.1, 0.4)
			motion.parallel().tween_property(hat, "position:y", 2.4, 0.25)
			motion.tween_property(hat, "rotation:z", -0.6, 0.25)
		"shoot":
			rig.rotation.y = aim_yaw
			motion.tween_property(arm, "rotation:x", 1.7, 0.09)
			motion.tween_property(rig, "rotation:x", -0.16, 0.08)
			motion.parallel().tween_property(hat, "rotation:z", 0.18, 0.08)
			motion.tween_interval(0.12)
			motion.tween_property(arm, "rotation:x", 0.0, 0.22)
			motion.parallel().tween_property(rig, "rotation", Vector3.ZERO, 0.22)
			motion.parallel().tween_property(hat, "rotation:z", 0.0, 0.22)
		"drink":
			motion.tween_property(arm, "rotation:x", 2.5, 0.2)
			motion.parallel().tween_property(rig, "rotation:x", -0.15, 0.2)
			motion.tween_interval(0.2)
			motion.tween_property(arm, "rotation:x", 0.0, 0.18)
			motion.parallel().tween_property(rig, "rotation:x", 0.0, 0.18)
			motion.tween_property(rig, "scale", Vector3(1.08, 0.9, 1.08), 0.1)
			motion.tween_property(rig, "scale", Vector3.ONE, 0.17)
			motion.tween_callback(func(): bottle.visible = false; gun.visible = true)
		"dodge":
			motion.tween_property(rig, "rotation:z", -0.8, 0.12)
			motion.parallel().tween_property(rig, "scale:y", 0.7, 0.12)
			motion.parallel().tween_property(hat, "rotation:z", 0.45, 0.12)
			motion.tween_interval(0.17)
			motion.tween_property(rig, "rotation:z", 0.0, 0.3).set_trans(Tween.TRANS_BACK)
			motion.parallel().tween_property(rig, "scale:y", 1.0, 0.3)
			motion.parallel().tween_property(hat, "rotation:z", 0.0, 0.3)
		"hit":
			motion.tween_property(rig, "rotation:x", -0.3, 0.08)
			motion.parallel().tween_property(hat, "rotation:z", 0.38, 0.08)
			motion.tween_property(rig, "rotation:x", 0.12, 0.12)
			motion.parallel().tween_property(hat, "rotation:z", -0.25, 0.12)
			motion.tween_property(rig, "rotation:x", 0.0, 0.2)
			motion.parallel().tween_property(hat, "rotation:z", 0.0, 0.2)

