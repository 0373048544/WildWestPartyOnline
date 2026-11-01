extends Node

var app: Node
var checks: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("TARGETING FAILED: " + message)
		get_tree().quit(1)
		assert(value, message)

func give(id: int, kind: String) -> Dictionary:
	var card := CardInstance.make(GameManager.deck.next_id, kind, "HEART", 7)
	GameManager.deck.next_id += 1
	GameManager.players[id].hand.append(card)
	return card

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame

func capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts/targeting")
	var ignore := FileAccess.open("res://tests/artifacts/.gdignore", FileAccess.WRITE)
	ignore.close()
	get_viewport().get_texture().get_image().save_png("res://tests/artifacts/targeting/" + name + ".png")

func setup(count: int) -> void:
	GameManager.clear()
	for id in range(1, count + 1):
		GameManager.add_player(id, "Cao bồi %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()
	for id in GameManager.players:
		GameManager.selection.choose(GameManager, id, GameManager.selection.options[id][0])
	GameManager.reactions.active = {}
	GameManager.flow.jobs.clear()
	for p in GameManager.players.values():
		p.ability_id = ""
		p.character_id = "bart_cassidy"
		p.hand.clear()
		p.current_hp = 4
		p.max_hp = 4
		p.role = PlayerState.Role.OUTLAW
	GameManager.players[1].role = PlayerState.Role.SHERIFF
	GameManager.players[count].role = PlayerState.Role.RENEGADE
	GameManager.turns.current_player = 1
	GameManager.turns.phase = "ACTION_PHASE"
	GameManager.players[1].weapon = CardInstance.make(99999, "winchester", "HEART", 1)
	GameManager.publish()
	app.seen_role = GameManager.match_id
	app.selected = -1
	app.refresh()

func _ready() -> void:
	get_window().size = Vector2i(1440, 900)
	get_window().content_scale_size = Vector2i(1440, 900)
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	app = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	setup(4)
	var shot := give(1, "shoot")
	give(2, "dodge")
	GameManager.publish()
	app.choose_card(shot.instance_id)
	await settle()
	var controller: TargetingController = app.table.targeting
	check(controller.selected_card == shot.instance_id, "card enters 3D targeting")
	check(not controller.targeting_arrow.visible and controller.hovered_target == 0, "aim arc waits for actual hover")
	check(app.table.rings[2].visible, "valid avatar ring visible")
	var hit_position: Vector2 = app.table.camera.unproject_position(app.table.avatars[2].global_position + Vector3.UP * 1.65)
	check(controller.pick_at(hit_position) == 2, "ray picks real avatar Area3D")
	var hover := InputEventMouseMotion.new()
	hover.position = hit_position
	Input.parse_input_event(hover)
	await settle()
	check(controller.hovered_target == 2 and controller.tooltip.text.contains("Khoảng cách"), "mouse hover displays public distance/range")
	check(controller.reticle.visible and controller.target_style == "BANG", "BANG gets western reticle")
	await capture("mouse-arrow")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = hit_position
	Input.parse_input_event(click)
	await settle()
	check(GameManager.find_card(1, shot.instance_id).is_empty(), "real mouse click sends accepted play intention")
	check(GameManager.reactions.active.reaction_type == "dodge", "clicked target receives Dodge prompt")
	check(not controller.targeting_arrow.visible and not controller.reticle.visible, "aim preview clears before presentation fires")
	GameManager.resolve_reaction(true)
	GameManager.publish()
	check(GameManager.players[2].current_hp == 4, "Dodge succeeds after 3D click")
	GameManager.begin_turn(1)
	GameManager.rate_limits.clear()
	shot = give(1, "shoot")
	GameManager.publish()
	app.choose_card(shot.instance_id)
	await settle()
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	touch.position = hit_position
	Input.parse_input_event(touch)
	await settle()
	check(not GameManager.find_card(1, shot.instance_id).is_empty() and controller.reticle.visible, "first touch previews target without consuming card")
	Input.parse_input_event(touch.duplicate())
	await settle()
	check(GameManager.find_card(1, shot.instance_id).is_empty() and GameManager.reactions.active.get("reaction_type", "") == "dodge", "second touch confirms Shoot and opens the no-card reaction banner")
	GameManager.resolve_reaction(false)
	GameManager.publish()
	check(GameManager.players[2].current_hp == 3, "skipping the no-card reaction applies one damage")
	GameManager.begin_turn(1)
	shot = give(1, "shoot")
	GameManager.players[1].weapon = {}
	GameManager.publish()
	app.choose_card(shot.instance_id)
	await settle()
	controller.update_hover_target(3)
	controller.select_target(3)
	check(not GameManager.find_card(1, shot.instance_id).is_empty(), "invalid target cannot play")
	check(controller.tooltip.text.contains("NGOÀI TẦM"), "invalid preview clearly marked")
	var cancel := InputEventMouseButton.new()
	cancel.button_index = MOUSE_BUTTON_RIGHT
	cancel.pressed = true
	Input.parse_input_event(cancel)
	await settle()
	check(app.selected == -1 and not controller.targeting_arrow.visible, "right click cancels targeting")
	app.choose_card(shot.instance_id)
	await settle()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await settle()
	check(app.selected == -1, "Escape cancels targeting")
	setup(7)
	shot = give(1, "shoot")
	GameManager.publish()
	app.choose_card(shot.instance_id)
	await settle()
	check(app.table.avatars.size() == 7 and app.table.targeting.valid_target_ids.size() == 6, "seven-player targets")
	check(app.content.global_position.y + app.content.size.y <= 900, "seven-player HUD fits viewport")
	for plate in app.table.nameplates.values():
		check(plate.hearts.size() == 5 and not plate.label.text.contains("Tầm"), "nameplate only identity, vector hearts and hand count")
	for pair in [["showdown", "DUEL"], ["panic", "STEAL"], ["cat_balou", "DISCARD"], ["jail", "JAIL"]]:
		give(2, "beer")
		var context_card := give(1, pair[0])
		GameManager.publish()
		app.selected = context_card.instance_id
		app.refresh()
		check(app.table.targeting.target_style == pair[1], "context-specific reticle " + pair[1])
	app.selected = shot.instance_id
	app.refresh()
	await capture("seven-player")
	get_window().content_scale_size = Vector2i(960, 600)
	get_window().size = Vector2i(844, 390)
	await settle()
	var plate_rects: Array[Rect2] = []
	for plate in app.table.nameplates.values():
		var camera: Camera3D = app.table.camera
		var center: Vector2 = camera.unproject_position(plate.global_position)
		var right: Vector2 = camera.unproject_position(plate.global_position + camera.global_basis.x * 0.91 * plate.scale.x)
		var top: Vector2 = camera.unproject_position(plate.global_position + camera.global_basis.y * 0.325 * plate.scale.x)
		var extent := Vector2(absf(right.x - center.x), absf(top.y - center.y))
		var rect := Rect2(center - extent, extent * 2)
		check(rect.size.x >= 120 and rect.position.x >= 0 and rect.end.x <= get_viewport().get_visible_rect().size.x, "mobile nameplate stays readable and inside viewport")
		for previous in plate_rects:
			check(not rect.intersects(previous), "seven-player mobile nameplates do not overlap")
		plate_rects.append(rect)
	await capture("seven-player-mobile")
	print("PASS: %d real mouse/touch, arrow, cancellation and seven-player UI checks" % checks)
	GameManager.clear()
	get_tree().quit()
