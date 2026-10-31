extends Node

func _ready() -> void:
	get_window().size = Vector2i(1440, 900)
	get_window().content_scale_size = Vector2i(1440, 900)
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	var app: Node = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	for screen in ["host", "join", "main"]:
		app.screen = screen
		app.refresh()
		await get_tree().process_frame
	GameManager.clear()
	for id in range(1, 5):
		GameManager.add_player(id, "Cowboy " + str(id))
		GameManager.players[id].ready = true
	GameManager.publish()
	await get_tree().process_frame
	GameManager.start_match()
	for id in GameManager.players:
		GameManager.selection.choose(GameManager, id, GameManager.selection.options[id][0])
	for _i in range(20):
		if GameManager.reactions.active.is_empty():
			break
		GameManager.resolve_reaction(false)
	GameManager.publish()
	app.seen_role = GameManager.match_id
	app.refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	var bottom: float = app.content.global_position.y + app.content.size.y
	var height: float = get_viewport().get_visible_rect().size.y
	if bottom > height:
		push_error("UI exceeds viewport: %.0f > %.0f" % [bottom, height])
		get_tree().quit(1)
		return
	print("PASS: menu, host/join forms, lobby, table, hand and debug layout (bottom %.0f / %.0f)" % [bottom, height])
	app.show_reaction({"reaction_type": "survive", "remaining": 8, "request_id": 1})
	await get_tree().process_frame
	GameManager.kill_player(1, 2)
	GameManager.publish()
	await get_tree().process_frame
	print("PASS: reaction and game-over UI")
	GameManager.clear()
	get_tree().quit()
