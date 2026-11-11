extends SubViewportContainer

var avatar: PlayerAvatar
var viewport: SubViewport

func configure(id: String, height: float = 160) -> void:
	name = "CharacterPortrait"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.y = height
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stretch = true
	stretch_shrink = 1
	viewport = SubViewport.new()
	viewport.size = Vector2i(320, int(height))
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	avatar = PlayerAvatar.new()
	viewport.add_child(avatar)
	avatar.build(SaloonTheme.GOLD)
	avatar.apply_character(id, false)
	# A cached portrait keeps an open-eyed pose and consumes no idle animation work.
	avatar.set_process(false)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 1.9, -4.2)
	camera.fov = 31
	camera.look_at(Vector3(0, 1.65, 0))
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("#152b32")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("#c1d6dc")
	settings.ambient_light_energy = 0.72
	environment.environment = settings
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	viewport.add_child(light)
	light.rotation_degrees = Vector3(-35, -25, 0)
	light.light_color = Color("#ffe4bb")
	light.light_energy = 1.35
	var rim := DirectionalLight3D.new()
	viewport.add_child(rim)
	rim.rotation_degrees = Vector3(-18, 150, 0)
	rim.light_color = Color("#70bbc0")
	rim.light_energy = 0.48
	# A tiny portrait stage gives every procedural character a consistent premium
	# silhouette on desktop and Web/mobile without adding per-frame work.
	var halo := MeshInstance3D.new()
	var halo_mesh := CylinderMesh.new()
	halo_mesh.top_radius = 1.08
	halo_mesh.bottom_radius = 1.08
	halo_mesh.height = 0.035
	halo_mesh.radial_segments = 40
	halo.mesh = halo_mesh
	halo.position = Vector3(0, 1.55, 0.42)
	halo.rotation_degrees = Vector3(90, 0, 0)
	var halo_material := StandardMaterial3D.new()
	halo_material.albedo_color = Color("#b77a42")
	halo_material.emission_enabled = true
	halo_material.emission = Color("#7b4d2d")
	halo_material.emission_energy_multiplier = 0.28
	halo_material.roughness = 0.78
	halo.material_override = halo_material
	viewport.add_child(halo)

func react(kind: String = "drink") -> void:
	var avatar_action: String = {
		"damage": "hit",
		"heal": "drink",
		"selected": "drink",
		"surprised": "panic"
	}.get(kind, kind)
	avatar.set_process(true)
	avatar.act(avatar_action)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var animation := create_tween()
	animation.tween_interval(0.72 if avatar_action in ["shoot", "dodge", "hit", "panic"] else 0.9)
	animation.tween_callback(func(): avatar.set_process(false); viewport.render_target_update_mode = SubViewport.UPDATE_ONCE)
