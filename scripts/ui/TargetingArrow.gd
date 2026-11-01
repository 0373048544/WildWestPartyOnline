class_name TargetingArrow
extends Node3D

# One reusable ribbon mesh and a cached rounded dash mask; no custom shader.
var geometry := ImmediateMesh.new()
var material := StandardMaterial3D.new()
var tint := Color("#e8b966")
var guide_motion: Tween
var endpoint: Vector3 = Vector3.ZERO
var double_ended: bool = false
var bend_offset := Vector3.ZERO
var last_origin := Vector3.INF
var requested_end := Vector3.INF
var last_valid := true
static var dash_texture: Texture2D

func aim_smooth(origin: Vector3, destination: Vector3, valid: bool) -> void:
	if visible and requested_end.is_equal_approx(destination) and last_origin.is_equal_approx(origin) and last_valid == valid:
		return
	requested_end = destination
	last_origin = origin
	last_valid = valid
	if guide_motion:
		guide_motion.kill()
	if not visible or endpoint == Vector3.ZERO:
		endpoint = destination
		aim(origin, destination, valid)
		return
	guide_motion = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	guide_motion.tween_method(func(at): endpoint = at; aim(origin, at, valid), endpoint, destination, 0.15)

func _ready() -> void:
	if not dash_texture:
		var mask := Image.create(64, 16, false, Image.FORMAT_RGBA8)
		for x in range(64):
			for y in range(16):
				var p := Vector2(x / 63.0, y / 15.0)
				var nearest := Vector2(clampf(p.x, 0.23, 0.57), 0.5)
				var distance: float = Vector2((p.x-nearest.x)*4, (p.y-nearest.y)).length()
				mask.set_pixel(x, y, Color(1, 1, 1, 1-smoothstep(0.37, 0.49, distance)))
		dash_texture = ImageTexture.create_from_image(mask)
	var surface := MeshInstance3D.new()
	surface.mesh = geometry
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = dash_texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	surface.material_override = material
	add_child(surface)
	visible = false
	visibility_changed.connect(func(): set_process(visible))
	set_process(false)

func _process(_delta: float) -> void:
	if visible:
		material.albedo_color = tint
		material.uv1_offset.x = -fmod(Time.get_ticks_msec() * 0.00022, 1.0)

func point(origin: Vector3, destination: Vector3, t: float) -> Vector3:
	# Quadratic arc stays below nameplates; a sideways bow can route around one.
	return origin.lerp(destination, t) + (Vector3.UP * 0.65 + bend_offset) * (4*t*(1-t))

func vertex(at: Vector3, uv: Vector2) -> void:
	geometry.surface_set_uv(uv)
	geometry.surface_add_vertex(at)

func aim(origin: Vector3, destination: Vector3, valid: bool = true) -> void:
	if origin.distance_to(destination) < 0.1:
		visible = false
		return
	visible = true
	tint = Color("#e8b966") if valid else Color("#b77769")
	geometry.clear_surfaces()
	geometry.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var camera := get_viewport().get_camera_3d()
	for index in range(64):
		var t: float = index / 64.0
		var u: float = (index+1) / 64.0
		var p: Vector3 = point(origin, destination, t)
		var q: Vector3 = point(origin, destination, u)
		var view: Vector3 = (camera.global_position - p).normalized() if camera else Vector3.UP
		var side: Vector3 = (q-p).normalized().cross(view).normalized()
		var a: Vector3 = side * lerpf(0.025, 0.064, t)
		var b: Vector3 = side * lerpf(0.025, 0.064, u)
		var steps: float = clampf(origin.distance_to(destination) * 1.5, 7, 15)
		vertex(p-a, Vector2(t*steps,0)); vertex(p+a, Vector2(t*steps,1)); vertex(q+b, Vector2(u*steps,1))
		vertex(p-a, Vector2(t*steps,0)); vertex(q+b, Vector2(u*steps,1)); vertex(q-b, Vector2(u*steps,0))
	# Small brass arrowhead, rather than a giant targeting triangle.
	for reverse in ([false,true] if double_ended else [false]):
		var end: Vector3 = origin if reverse else destination
		var forward: Vector3 = (end-point(origin,destination,0.02 if reverse else 0.98)).normalized()
		var view: Vector3 = (camera.global_position-end).normalized() if camera else Vector3.UP
		var side: Vector3 = forward.cross(view).normalized() * 0.14
		for at in [end+forward*0.12,end-forward*0.18+side,end-forward*0.18-side]:
			vertex(at, Vector2(0.4,0.5))
	geometry.surface_end()
