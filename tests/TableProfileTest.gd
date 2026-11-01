extends Node

func count_assets(node: Node, meshes: Dictionary, materials: Dictionary) -> int:
	var count: int = 0
	if node is MeshInstance3D:
		count = 1
		meshes[node.mesh.get_instance_id()] = true
		if node.material_override:
			materials[node.material_override.get_instance_id()] = true
	for child in node.get_children():
		count += count_assets(child, meshes, materials)
	return count

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Profile needs an actual renderer; headless counters are not measurements.")
		get_tree().quit(1)
		return
	get_window().size = Vector2i(1440, 900)
	var app: Node = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	GameManager.clear()
	for id in range(1, 8):
		GameManager.add_player(id, "QA %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()
	GameManager.selection.expire(GameManager)
	for _index in range(8):
		if GameManager.reactions.active.is_empty():
			break
		GameManager.flow.resolve({"accept": false})
	GameManager.publish()
	app.seen_role = GameManager.match_id
	app.refresh()
	# Seven face-up cards exercise the crowded center using real physical instances.
	GameManager.flow.start_store(GameManager.turns.current_player)
	GameManager.flow.run()
	GameManager.publish()
	var saved: String = VisualSettings.level
	var results: Array = []
	for quality in ["LOW", "MEDIUM", "HIGH"]:
		VisualSettings.set_quality(quality, false)
		for _frame in range(30):
			await get_tree().process_frame
		var began := Time.get_ticks_usec()
		for _frame in range(120):
			await get_tree().process_frame
		var elapsed: float = (Time.get_ticks_usec() - began) / 1000000.0
		var meshes: Dictionary = {}
		var materials: Dictionary = {}
		var mesh_instances: int = count_assets(app.table, meshes, materials)
		var result := {"quality": quality, "measured_fps_120_frames": 120.0 / elapsed,
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			"mesh_instances": mesh_instances, "unique_meshes": meshes.size(), "materials": materials.size(),
			"audio_players": AudioManager.get_child_count(), "presentation_queue": app.table.presentation_queue.size(),
			"market_cards": GameManager.flow.market.size(), "renderer": RenderingServer.get_video_adapter_name()}
		results.append(result)
		print("PROFILE " + JSON.stringify(result))
		if quality == "MEDIUM":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://tests/artifacts/table-seven-market.png")
	VisualSettings.set_quality(saved, false)
	var file := FileAccess.open("res://tests/artifacts/desktop-profile.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "  "))
	file.close()
	GameManager.clear()
	print("PASS: actual desktop renderer profiled at all three quality levels; seven-player market captured")
	get_tree().quit()
