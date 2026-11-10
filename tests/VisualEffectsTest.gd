extends Node

var app: Node
var checks: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("VISUAL FAILED: " + message)
		get_tree().quit(1)
		assert(value, message)

func active_effect_count() -> int:
	# TableEffects deliberately retains invisible nodes in bounded pools on mobile.
	# Count rendered presentation objects, not reusable pool capacity.
	return app.table.effects.get_children().filter(func(child: Node):
		return (child is Node3D and child.visible) or (child is CanvasItem and child.visible)
	).size()

func wait_for_presentation() -> void:
	var deadline := Time.get_ticks_msec() + 8000
	while (not app.table.presentation_queue.is_empty() or app.table.presentation_wait > 0 or active_effect_count() > 0) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(app.table.presentation_queue.is_empty() and active_effect_count() == 0, "queued turn presentation drains")

func capture(file_name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts/polish")
	var ignore := FileAccess.open("res://tests/artifacts/.gdignore", FileAccess.WRITE)
	ignore.close()
	get_viewport().get_texture().get_image().save_png("res://tests/artifacts/polish/" + file_name + ".png")

func _ready() -> void:
	get_window().size = Vector2i(1440, 900)
	get_window().content_scale_size = Vector2i(1440, 900)
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	app = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	for id in range(1, 5):
		GameManager.add_player(id, "Cao bồi %d" % id)
		GameManager.players[id].ready = true
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
	check(app.table.avatars.size() == 4, "four avatars")
	var turn_before: int = GameManager.turns.current_player
	GameManager.players[turn_before].hand.clear()
	GameManager.handle_intent(turn_before, "end", {})
	check(GameManager.turns.current_player != turn_before, "complete playable turn preserved")
	await wait_for_presentation()
	for kind in ["shoot", "dodge", "hit", "drink", "iced_tea", "downed", "recover", "victory", "death"]:
		app.table.animate(2, kind, 3)
		await get_tree().create_timer(0.65 if kind == "death" else 0.12).timeout
		await capture(kind)
		await get_tree().create_timer(1.5 if kind == "downed" else 1.0).timeout
		check(active_effect_count() == 0, kind + " effects cleaned up while bounded pools remain reusable")
		check(not app.table.avatars[2].motion.is_running(), kind + " tween finishes")
	check(app.table.avatars[2].dead, "death pose retained")
	check(app.table.avatars[2].rig.rotation.z > 1.0, "goofy fall reaches final pose")
	check(not app.table.avatars[3].dead, "other avatar unaffected")
	app.table.update_state(NetworkManager.public_state, 1, [3])
	check(app.table.rings[3].visible, "valid target highlighted")
	await capture("target")
	var ring_position: Vector2 = app.table.camera.unproject_position(app.table.avatars[3].global_position + Vector3(0, 1.8, 0))
	check(ring_position.y > 225 and ring_position.y < 580, "opponent framed between HUD and hand")
	GameManager.winner = "OUTLAWS WIN"
	for p in GameManager.players.values():
		p.ready = true
	GameManager.start_match()
	for id in GameManager.players:
		GameManager.selection.choose(GameManager, id, GameManager.selection.options[id][0])
	GameManager.publish()
	await get_tree().process_frame
	check(not app.table.avatars[2].dead, "restart clears visual death")
	check(active_effect_count() == 0, "restart clears visible VFX")
	print("PASS: %d visual, animation, VFX lifetime and turn checks" % checks)
	GameManager.clear()
	get_tree().quit()
