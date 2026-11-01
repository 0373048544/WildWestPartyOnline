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
	settings.background_color = Color("#233f48")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("#c1d6dc")
	settings.ambient_light_energy = 0.6
	environment.environment = settings
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	viewport.add_child(light)
	light.rotation_degrees = Vector3(-35, -25, 0)
	light.light_color = Color("#ffe4bb")
	light.light_energy = 1.2

func react(kind: String = "drink") -> void:
	avatar.set_process(true)
	avatar.act(kind)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var animation := create_tween()
	animation.tween_interval(0.9)
	animation.tween_callback(func(): avatar.set_process(false); viewport.render_target_update_mode = SubViewport.UPDATE_ONCE)
