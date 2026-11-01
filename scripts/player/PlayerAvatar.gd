class_name PlayerAvatar
extends Node3D

var arm: Node3D
var left_arm: Node3D
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
var character_id: String = ""
var visual_preset: Dictionary = {}
var eyes: Array = []
var brows: Array = []
var mouth: Node3D
var head: Node3D
var hands: Array = []
var expression: String = "idle"
var expression_until: int = 0
var hat_rest_y: float = 2.08
var target_dimmed: bool = false
var idle_phase: float = 0
var weapon_visual_id: String = ""
static var mesh_cache: Dictionary = {}

func apply_character(id: String, celebrate: bool = true) -> void:
	if character_id == id:
		return
	var preset: Dictionary = load("res://scripts/characters/CharacterVisualData.gd").get_preset(id)
	if preset.is_empty():
		return
	if motion:
		motion.kill()
	if is_instance_valid(rig):
		rig.free()
	materials.clear()
	eyes.clear()
	brows.clear()
	hands.clear()
	character_id = id
	visual_preset = preset
	idle_phase = float(absi(hash(id)) % 1000) / 100.0 + position.x
	dead = false
	load("res://scripts/characters/CharacterParts.gd").new().build(self, preset)
	apply_weapon_visual(weapon_visual_id,true)
	if is_instance_valid(picking_area):
		var collision: CollisionShape3D = picking_area.get_child(0)
		collision.shape = collision.shape.duplicate()
		collision.shape.radius = maxf(0.64, float(preset.brim) * 0.95)
		collision.shape.height = 3.25
		collision.position.y = 1.5
	if celebrate:
		motion = create_tween()
		rig.scale = Vector3.ONE * 0.8
		motion.tween_property(rig, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK)

func set_expression(value: String, duration: int = 600) -> void:
	expression = value
	expression_until = Time.get_ticks_msec() + duration
	for index in range(eyes.size()):
		eyes[index].scale.y = 0.25 if value in ["hit", "death"] else (1.35 if value in ["dodge", "panic", "targeted"] else 1.0)
	for index in range(brows.size()):
		brows[index].rotation.z = (-1 if index == 0 else 1) * (0.4 if value == "shoot" else (-0.3 if value in ["dodge", "targeted"] else 0.14))
	if is_instance_valid(mouth):
		mouth.scale = Vector3(0.8, 4.0, 1) if value in ["panic", "dodge", "targeted"] else (Vector3(1.4, 0.7, 1) if value in ["drink","shoot"] else Vector3.ONE)
		mouth.rotation.z = 0.24 if value == "death" else 0.0
	for hand in hands:
		hand.scale = Vector3(1.18,0.85,1.05) if value in ["shoot","panic"] else Vector3.ONE
	if is_instance_valid(head):
		head.rotation = Vector3(-0.07,0,-0.10) if value == "targeted" else Vector3.ZERO

func apply_weapon_visual(key: String, force: bool = false) -> void:
	if not is_instance_valid(gun) or (weapon_visual_id == key and not force):
		return
	weapon_visual_id = key
	gun.mesh = load("res://scripts/player/WeaponVisuals.gd").mesh_for(key)
	gun.material_override = null
	gun.rotation.x = -PI/2

func muzzle_position() -> Vector3:
	var profile: Dictionary = load("res://scripts/player/WeaponVisuals.gd").profile(weapon_visual_id)
	return gun.to_global(Vector3(0,0.035,-float(profile.length)))

func tailored_mesh(width: float, height: float, style: String, crown: bool = false) -> ArrayMesh:
	var key := "tailored:%s:%s:%s:%s" % [width,height,style,crown]
	if mesh_cache.has(key):
		return mesh_cache[key]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for level in range(3):
		var ring: Array[Vector3] = []
		for index in range(13):
			var angle: float = index * TAU / 12
			var radius: float = [0.36,0.44,0.35][level] * width
			var y: float = [-0.5,0.1,0.5][level] * height
			var depth: float = 0.72
			if crown:
				radius = [0.43,0.39,0.33][level]
				y = level * height / 2
				depth = 0.95
				if style in ["gambler","porkpie","flat"]:
					radius = [0.43,0.44,0.42][level]
				elif style in ["pinch","creased","scout","tall"]:
					radius *= 1.0 - level * 0.09 * absf(cos(angle))
				elif style == "sombrero":
					radius *= 1.0 - level * 0.16
				if style in ["battered","slouch","turned"]:
					y += level * sin(angle+0.8) * 0.035
				ring.append(Vector3(cos(angle)*radius,y,sin(angle)*radius*depth))
			else:
				ring.append(Vector3(cos(angle)*radius,y,sin(angle)*radius*depth))
		rings.append(ring)
	for level in range(2):
		for index in range(12):
			for vertex in [rings[level][index],rings[level+1][index],rings[level+1][index+1],rings[level][index],rings[level+1][index+1],rings[level][index+1]]:
				surface.add_vertex(vertex)
	for index in range(12):
		var center := Vector3(0,height if crown else height/2,0)
		if crown and style in ["pinch","creased","scout"]:
			center.y -= 0.065
		for vertex in [center,rings[2][index+1],rings[2][index]]:
			surface.add_vertex(vertex)
	surface.generate_normals()
	var mesh := surface.commit()
	mesh_cache[key] = mesh
	return mesh

func flower_mesh() -> ArrayMesh:
	if mesh_cache.has("flower"):
		return mesh_cache.flower
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for petal in range(6):
		var angle: float = petal * TAU / 6
		var center := Vector3(cos(angle),sin(angle),0)*0.09
		for index in range(8):
			var a: Vector3 = center+Vector3(cos(index*TAU/8),sin(index*TAU/8),0)*0.065
			var b: Vector3 = center+Vector3(cos((index+1)*TAU/8),sin((index+1)*TAU/8),0)*0.065
			for at in [center,a,b,center,b,a]:
				surface.add_vertex(at)
	surface.generate_normals()
	var mesh := surface.commit()
	mesh_cache.flower = mesh
	return mesh

func part(mesh: Mesh, at: Vector3, color: Color, parent: Node3D = null) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	if not materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.85
		if color == Color("#6a7f89"):
			material.metallic = 0.55
			material.roughness = 0.36
		materials[color] = material
	node.material_override = materials[color]
	(parent if parent != null else rig).add_child(node)
	node.position = at
	return node

func box(size: Vector3) -> BoxMesh:
	var key := "box:" + str(size)
	if mesh_cache.has(key):
		return mesh_cache[key]
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_cache[key] = mesh
	return mesh

func cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var key := "cylinder:%s:%s:%s" % [top, bottom, height]
	if mesh_cache.has(key):
		return mesh_cache[key]
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 10
	mesh_cache[key] = mesh
	return mesh

func sphere(radius: float, height: float) -> SphereMesh:
	var key := "sphere:%s:%s" % [radius, height]
	if mesh_cache.has(key):
		return mesh_cache[key]
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh_cache[key] = mesh
	return mesh

func curved_brim(radius: float, floppy: bool) -> ArrayMesh:
	var key := "brim:%s:%s" % [radius, floppy]
	if mesh_cache.has(key):
		return mesh_cache[key]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(16):
		var top: Array = []
		var bottom: Array = []
		for step in [index, index + 1]:
			var angle: float = step * TAU / 16
			var bend: float = sin(angle * 3) * 0.045 if floppy else pow(absf(cos(angle)), 4) * 0.13
			for r in [radius * 0.36, radius]:
				var y: float = bend if r == radius else 0.0
				top.append(Vector3(cos(angle) * r, y + 0.045, sin(angle) * r * 0.9))
				bottom.append(Vector3(cos(angle) * r, y - 0.045, sin(angle) * r * 0.9))
		for triangle in [[top[0], top[2], top[3]], [top[0], top[3], top[1]], [bottom[0], bottom[3], bottom[2]], [bottom[0], bottom[1], bottom[3]], [top[1], top[3], bottom[3]], [top[1], bottom[3], bottom[1]]]:
			for vertex in triangle:
				surface.add_vertex(vertex)
	surface.generate_normals()
	var mesh := surface.commit()
	mesh_cache[key] = mesh
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
	target_dimmed = dimmed
	for color in materials:
		materials[color].albedo_color = Color(color).darkened(0.48) if dimmed else color

func set_hover_state(value: bool) -> void:
	for color in materials:
		var base: Color = Color(color).darkened(0.48) if target_dimmed else color
		materials[color].albedo_color = base.lightened(0.12) if value else base

func _process(_delta: float) -> void:
	if rig == null or dead:
		return
	if expression != "idle" and Time.get_ticks_msec() > expression_until:
		set_expression("idle", 0)
	if motion == null or not motion.is_running():
		var time: float = Time.get_ticks_msec() * 0.002 + position.x + idle_phase
		rig.position.y = sin(time) * 0.025
		rig.scale.y = 1.0 + sin(time) * 0.012
		hat.rotation.z = float(visual_preset.get("tilt", 0)) + sin(time * 0.7) * 0.025
		rig.rotation.x = 0.08 if visual_preset.get("idle", "") == "lean" else 0.0
		if visual_preset.get("idle", "") in ["quick", "lively"]:
			arm.rotation.z = sin(time * 1.5) * 0.07
		if is_instance_valid(head) and expression == "idle":
			head.rotation.y = sin(time * 0.65) * 0.07
			head.rotation.z = sin(time * 0.9) * 0.025
			var blink: bool = fmod(time + idle_phase, 5.3) < 0.09
			for eye in eyes:
				eye.scale.y = 0.12 if blink else 1.0

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
	if is_instance_valid(left_arm):
		left_arm.rotation = Vector3.ZERO
	hat.rotation = Vector3.ZERO
	bottle.visible = kind == "drink"
	gun.visible = kind != "drink"
	set_expression(kind)
	motion = create_tween()
	if load("res://scripts/player/AvatarGestures.gd").new().play(self,kind):
		return
	match kind:
		"death":
			dead = true
			motion.tween_property(rig, "position:y", 0.18, 0.12)
			motion.tween_interval(0.12)
			motion.tween_property(rig, "rotation:z", 1.5, 0.4).set_trans(Tween.TRANS_BACK)
			motion.parallel().tween_property(rig, "position:y", -0.1, 0.4)
			motion.parallel().tween_property(hat, "position:y", hat_rest_y + 0.55, 0.25)
			motion.tween_property(hat, "rotation:z", -0.6, 0.25)
		"shoot":
			rig.rotation.y = aim_yaw
			motion.tween_property(arm, "rotation:x", 1.7, 0.07 if visual_preset.get("idle", "") == "quick" else 0.09)
			motion.tween_interval(0.01)
			motion.tween_property(arm, "rotation:x", 1.92, 0.045)
			motion.parallel().tween_property(rig, "position:z", 0.07, 0.045)
			motion.tween_property(rig, "rotation:x", -0.25 if visual_preset.get("idle", "") == "heavy" else -0.16, 0.08)
			motion.parallel().tween_property(hat, "rotation:z", 0.18, 0.08)
			motion.tween_interval(0.12)
			motion.tween_property(arm, "rotation:x", 0.0, 0.22)
			motion.parallel().tween_property(rig, "rotation", Vector3.ZERO, 0.22)
			motion.parallel().tween_property(hat, "rotation:z", 0.0, 0.22)
			motion.parallel().tween_property(rig, "position:z", 0.0, 0.22)
		"panic", "targeted":
			motion.tween_property(rig,"rotation:z",-0.08,0.08)
			motion.parallel().tween_property(arm,"rotation:z",-0.25,0.08)
			motion.tween_property(rig,"rotation:z",0.09,0.12)
			motion.parallel().tween_property(hat,"rotation:z",0.22,0.12)
			motion.tween_property(rig,"rotation:z",0.0,0.16)
			motion.parallel().tween_property(arm,"rotation:z",0.0,0.16)
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

