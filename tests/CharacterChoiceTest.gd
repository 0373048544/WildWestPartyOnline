extends Node

var checks: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("CHARACTER CHOICE FAILED: " + message)
		get_tree().quit(1)
		assert(value, message)

func begin(count: int) -> void:
	GameManager.clear()
	for id in range(1, count + 1):
		GameManager.add_player(id, "Player %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()

func _ready() -> void:
	await get_tree().process_frame
	var seen_by_seat: Dictionary = {}
	for count in [4, 5, 6, 7]:
		for trial in range(40):
			begin(count)
			var all_options: Dictionary = {}
			for id in GameManager.players:
				var own: Dictionary = GameManager.private_snapshot(id)
				check(own.character_options.size() == 2, "exactly two owner options")
				check(own.character_options[0].character_id != own.character_options[1].character_id, "distinct pair")
				var ids: Array = own.character_options.map(func(c): return c.character_id)
				check(ids == GameManager.selection.options[id], "snapshot contains exactly owner's pair")
				for option in ids:
					check(not all_options.has(option), "dealt without replacement across every player")
					all_options[option] = true
					if not seen_by_seat.has(id):
						seen_by_seat[id] = {}
					seen_by_seat[id][option] = true
			check(all_options.size() == count * 2, "7 players get 14 unique offers; others get 2 each")
			var public: Dictionary = GameManager.public_snapshot()
			check(not public.has("character_options") and public.players.all(func(p): return not p.has("character_options") and p.character_id.is_empty()), "no unconfirmed offers public")
			var previous: Dictionary = GameManager.selection.options.duplicate(true)
			var selected: String = previous[1][0]
			GameManager.rate_limits.clear()
			GameManager.handle_intent(1, "character", {"character": selected, "match_id": GameManager.match_id - 1})
			check(GameManager.selection.chosen.is_empty(), "stale selection from old match rejected")
			check(not GameManager.selection.choose(GameManager, 1, previous[2][0]), "reject another owner's option")
			check(GameManager.selection.choose(GameManager, 1, selected), "accept offered selection")
			check(not GameManager.selection.choose(GameManager, 1, previous[1][1]), "cannot select twice")
			public = GameManager.public_snapshot()
			check(public.players[0].character_id == selected, "confirmed character public immediately")
			check(public.players.slice(1).all(func(p): return p.character_id.is_empty()), "unconfirmed other characters stay private")
			check(GameManager.private_snapshot(1).selected_character.character_id == selected and GameManager.private_snapshot(1).character_options.is_empty(), "owner gets selected-name waiting state")
			for id in range(2, count + 1):
				check(GameManager.private_snapshot(id).character_options.map(func(c): return c.character_id) == previous[id], "other owners retain only own choices")
			check(not JSON.stringify(public).contains(previous[1][1]), "unselected choice never public")
			GameManager.selection.deadline = 0
			GameManager._process(0)
			for id in GameManager.players:
				var p: PlayerState = GameManager.players[id]
				check(previous[id].has(p.character_id), "timeout only chooses from owner's offered two")
				check(p.max_hp == int(CharacterData.get_data(p.character_id).max_hp) + int(p.role == PlayerState.Role.SHERIFF), "character HP plus Sheriff")
			GameManager.winner = "OUTLAWS WIN"
			for p in GameManager.players.values():
				p.ready = true
			GameManager.start_match()
			check(GameManager.selection.options != previous, "rematch rebuilds/shuffles full pool")
			check(GameManager.players.values().all(func(p): return p.character_id.is_empty() and p.hand.is_empty()), "rematch clears choices and hands")
	for id in seen_by_seat:
		check(seen_by_seat[id].size() == 16, "host/each seat samples full pool; no bound character")
	# Exercise the actual two-stage UI rather than bypassing its confirmation.
	begin(4)
	var app: Node = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	GameManager.publish()
	await get_tree().process_frame
	var panel: Node = app.root.find_child("CharacterChoicePanel", true, false)
	check(panel != null and panel.cards.size() == 2 and panel.confirm.disabled, "two large cards with disabled initial confirm")
	var keys: Array = panel.cards.keys()
	await get_tree().process_frame
	await get_tree().process_frame
	var portrait_stack: bool = load("res://scripts/ui/MatchLayout.gd").mobile_portrait(panel)
	var correctly_arranged: bool = (
		panel.cards[keys[0]].global_position.y < panel.cards[keys[1]].global_position.y
		if portrait_stack
		else panel.cards[keys[0]].global_position.x < panel.cards[keys[1]].global_position.x and is_equal_approx(panel.cards[keys[0]].global_position.y, panel.cards[keys[1]].global_position.y)
	)
	check(correctly_arranged, "character cards use portrait stack or landscape/desktop side-by-side layout")
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/artifacts/character-options.png")
	panel.cards[keys[0]].pressed.emit()
	check(GameManager.selection.chosen.is_empty(), "card tap is draft only")
	check(panel.selected_id == keys[0] and not panel.confirm.disabled, "draft highlight enables confirm")
	panel.cards[keys[1]].pressed.emit()
	check(panel.selected_id == keys[1] and GameManager.selection.chosen.is_empty(), "can change draft before confirmation")
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/artifacts/character-draft.png")
	panel.confirm.pressed.emit()
	check(GameManager.selection.chosen[1] == keys[1], "confirm selects exactly draft")
	check(app.root.find_child("CharacterChoicePanel", true, false) == null, "confirmed player waits rather than choosing again")
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/artifacts/character-confirmed.png")
	GameManager.clear()
	print("PASS: %d two-character distribution, privacy, confirmation, timeout and rematch checks" % checks)
	get_tree().quit()
