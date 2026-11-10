extends Node

var checks: int = 0
var app: Node

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		push_error("VISUAL POLISH FAILED: " + message)
		get_tree().quit(1)
		assert(ok,message)

func settle() -> void:
	await get_tree().create_timer(0.25).timeout
	await get_tree().physics_frame

func capture(label: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/artifacts/visual-polish-"+label+".png")

func _ready() -> void:
	get_window().size = Vector2i(1440,900)
	get_window().content_scale_size = Vector2i(1440,900)
	app = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	GameManager.clear()
	for id in range(1,8):
		GameManager.add_player(id,"Cao bồi %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()
	GameManager.selection.expire(GameManager)
	GameManager.flow.jobs.clear()
	GameManager.reactions.active = {}
	GameManager.turns.current_player = 1
	GameManager.turns.phase = "ACTION_PHASE"
	# Presentation fixtures only; never used by shipped gameplay.
	var characters: Array = CharacterVisualData.presets().keys()
	for id in range(1,8):
		GameManager.players[id].character_id = characters[id-1]
		GameManager.players[id].weapon = CardInstance.make(800+id,"remington","HEART",7)
	GameManager.publish()
	app.seen_role = GameManager.match_id
	app.refresh()
	GameManager.flow.start_store(1)
	GameManager.flow.run()
	GameManager.publish()
	await settle()
	var controller: TargetingController = app.table.targeting
	check(GameManager.flow.market.size() == 7,"seven visible Store cards")
	for viewport_size in [Vector2i(1440,900),Vector2i(844,390)]:
		get_window().size = viewport_size
		get_window().content_scale_size = Vector2i(960,600) if viewport_size.x < 900 else viewport_size
		await settle()
		for key in app.table.objects.objects:
			if not key.begins_with("market:") and not key.ends_with(":weapon"):
				continue
			var item: Node3D = app.table.objects.objects[key]
			var at: Vector2 = app.table.camera.unproject_position(item.global_position+Vector3.UP*0.12)
			check(controller.pick_object(at) == item.token,"7-player physical ray reaches "+key)
			if key.begins_with("market:"):
				check(controller.pick_touch_object(at) == item.token,"touch preserves Store physical ID")
		# A true Store chooser intentionally blocks character-info popups. Close
		# only the local presentation modal before auditing the standalone card.
		app.clear_game_modal()
		app.table.show_context(2)
		await settle()
		var popup: Control = app.root.get_node_or_null("PlayerInfoCard")
		check(is_instance_valid(popup),"character info card opens outside a true modal")
		var center: Vector2 = app.root.size/2
		check(not popup.get_global_rect().has_point(center),"character card leaves table center open")
		var portrait_id: int = popup.find_child("CharacterPortrait",true,false).get_instance_id()
		GameManager.publish()
		check(app.root.get_node("PlayerInfoCard").find_child("CharacterPortrait",true,false).get_instance_id()==portrait_id,"refresh keeps cached portrait")
		await capture("table-"+str(viewport_size.x))
		app.table.hide_context()
		app.refresh()
	controller.begin_targeting(999,1,[2],{})
	controller.update_hover_target(2)
	var guide_id: int = controller.targeting_arrow.geometry.get_instance_id()
	var reticle_id: int = controller.reticle.geometry.get_instance_id()
	for _repeat in range(10):
		controller.update_hover_target(2)
	check(controller.targeting_arrow.geometry.get_instance_id()==guide_id and controller.reticle.geometry.get_instance_id()==reticle_id,"stationary preview reuses mesh resources")
	app.table.presentation_queue.clear()
	app.table.presentation_wait = 0
	app.table.present_event({"kind":"animation","actor":1,"animation":"shoot","target":2,"audio_event_id":"visual-polish-shot"})
	check(not controller.targeting_arrow.visible and not controller.reticle.visible,"preview hidden before cock/flash/shot")
	var deadline: int = Time.get_ticks_msec()+2000
	while not is_instance_valid(TableEffects.gun_puff_mesh) and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	check(is_instance_valid(TableEffects.gun_puff_mesh),"gun smoke follows muzzle flash")
	await get_tree().create_timer(0.75).timeout
	var visible_effects: Array[Node] = app.table.effects.get_children().filter(
		func(node: Node): return node is Node3D and (node as Node3D).visible
	)
	check(visible_effects.is_empty(),"shot visuals clean up without persistent tracer")
	GameManager.clear()
	print("PASS: %d seven-player picking, mobile reachability, portrait cache, preview reuse and shot checks" % checks)
	get_tree().quit()
