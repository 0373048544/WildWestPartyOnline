extends Node

var checks: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("CHARACTER VISUAL FAILED: " + message)
		get_tree().quit(1)
		assert(value, message)

func mesh_count(node: Node) -> int:
	var count: int = int(node is MeshInstance3D)
	for child in node.get_children():
		count += mesh_count(child)
	return count

func _ready() -> void:
	get_window().size = Vector2i(1600, 1100)
	get_window().content_scale_size = Vector2i(1600, 1100)
	var data: Dictionary = load("res://scripts/characters/CharacterVisualData.gd").presets()
	check(data.size() == 16, "all 16 cosmetic presets")
	var gallery := Control.new()
	gallery.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(gallery)
	var background := ColorRect.new()
	background.color = Color("#203943")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gallery.add_child(background)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.position = Vector2(25, 20)
	grid.size = Vector2(1550, 1060)
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	gallery.add_child(grid)
	var silhouettes: Dictionary = {}
	for id in data:
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(375, 250)
		card.add_theme_stylebox_override("panel", SaloonTheme.panel(Color("#294c55"), Color(data[id].accent), 10))
		grid.add_child(card)
		var column := VBoxContainer.new()
		card.add_child(column)
		var portrait: Control = load("res://scripts/ui/CharacterPortrait.gd").new()
		column.add_child(portrait)
		portrait.configure(id, 190)
		var title := Label.new()
		title.text = CharacterData.get_data(id).display_name
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 22)
		column.add_child(title)
		var avatar: PlayerAvatar = portrait.avatar
		check(avatar.character_id == id and is_instance_valid(avatar.arm) and is_instance_valid(avatar.hat), "model/portrait ID matches " + id)
		check(mesh_count(avatar) <= 65 and mesh_count(avatar) >= 30, "bounded modular mesh count " + id)
		check(avatar.eyes.size() == 2 and avatar.brows.size() == 2, "expressive face " + id)
		avatar.picking_area.set_meta("player_id", 88)
		var area: Area3D = avatar.picking_area
		var rig_id: int = avatar.rig.get_instance_id()
		avatar.apply_character(id)
		check(avatar.rig.get_instance_id() == rig_id, "snapshot refresh never rebuilds same character")
		check(avatar.picking_area == area and area.get_meta("player_id") == 88, "cosmetics preserve targeting identity")
		silhouettes[str([data[id].width, data[id].height, data[id].brim, data[id].crown, data[id].hair_style, data[id].outfit, data[id].prop])] = true
		for kind in ["targeted", "panic", "shoot", "dodge", "hit", "drink", "death"]:
			avatar.act(kind)
			check(is_instance_valid(avatar.motion), "animation hook " + kind + " " + id)
		# Reset the same original model after animation test for the contact sheet.
		avatar.motion.kill()
		avatar.dead = false
		avatar.rig.position = Vector3.ZERO
		avatar.rig.rotation = Vector3.ZERO
		avatar.rig.scale = Vector3.ONE
		avatar.arm.rotation = Vector3.ZERO
		avatar.hat.rotation.z = data[id].tilt
		avatar.set_expression("idle")
	check(silhouettes.size() == 16, "16 distinct silhouette/part combinations, not recolors")
	await get_tree().process_frame
	await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/artifacts/character-gallery.png")
	gallery.free()
	var app: Node = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	GameManager.clear()
	for id in range(1, 8):
		GameManager.add_player(id, "Player %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()
	# This suite inspects the public character card, not the once-per-match role
	# reveal modal. Mark that reveal seen so the real modal correctly stays closed.
	app.seen_role = GameManager.match_id
	GameManager.publish()
	check(app.table.avatars.values().all(func(a): return a.character_id.is_empty()), "unconfirmed/private character appearance never leaked")
	var offered: Dictionary = GameManager.selection.options.duplicate(true)
	GameManager.selection.choose(GameManager, 1, offered[1][0])
	GameManager.publish()
	check(app.table.avatars[1].character_id == offered[1][0], "confirmed server choice transforms avatar immediately")
	check(app.table.avatars[2].character_id.is_empty(), "other player's private options remain hidden")
	for id in range(2, 8):
		GameManager.selection.choose(GameManager, id, offered[id][0])
	GameManager.publish()
	for id in range(1, 8):
		check(app.table.avatars[id].character_id == GameManager.players[id].character_id, "all seven public model IDs synchronized")
		check(GameManager.players[id].ability_id == CharacterData.get_data(GameManager.players[id].character_id).ability_id, "cosmetics never change ability")
	app.table.show_context(2)
	check(app.root.get_node_or_null("PlayerInfoCard") != null, "public player info includes matching portrait")
	check(not app.table.context_label.text.contains("TỘI PHẠM"), "portrait cannot expose hidden role")
	app.table.hide_context()
	var original_quality: String = VisualSettings.level
	for level in ["LOW", "MEDIUM", "HIGH"]:
		VisualSettings.set_quality(level, false)
		check(VisualSettings.particle_count(10) == {"LOW": 3, "MEDIUM": 6, "HIGH": 10}[level], "bounded particles for quality " + level)
		check(app.table.avatars.size() == 7 and app.table.avatars[1].character_id == GameManager.players[1].character_id, "quality preserves all gameplay visuals " + level)
	VisualSettings.set_quality(original_quality, false)
	app.seen_role = GameManager.match_id
	app.refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/artifacts/character-table-seven.png")
	GameManager.clear()
	print("PASS: %d character models, portraits, animation hooks, mesh budgets, privacy and seven-player visual sync checks" % checks)
	get_tree().quit()
