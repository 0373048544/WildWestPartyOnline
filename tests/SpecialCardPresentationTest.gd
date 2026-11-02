extends Node

var checks := 0
var app: Node

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("SPECIAL PRESENTATION FAILED: " + message)
		get_tree().quit(1)
		assert(value, message)

func settle(seconds: float = 0.08) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	get_window().content_scale_size = Vector2i(1280, 720)
	app = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	GameManager.clear()
	for id in range(1, 3):
		GameManager.add_player(id, "Cao bồi %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()
	GameManager.selection.expire(GameManager)
	GameManager.flow.jobs.clear()
	GameManager.reactions.active = {}
	for id in range(1, 3):
		GameManager.players[id].character_id = CharacterVisualData.presets().keys()[id - 1]
	GameManager.turns.current_player = 1
	GameManager.turns.phase = "ACTION_PHASE"
	GameManager.publish()
	app.seen_role = GameManager.match_id
	app.refresh()
	await settle(0.2)
	var table: Node3D = app.table
	check(is_instance_valid(table.special_presenter), "reusable presenter is attached once to persistent table")
	table.present_event({"kind": "store_started", "player": 1, "audio_event_id": "special:store"})
	check(table.special_presenter.banner.visible
		and table.special_presenter.title_label.text == "CỬA HÀNG",
		"accepted CỬA HÀNG event shows compact intro banner")
	check(table.avatars[1].expression == "laugh" and table.effects.get_child_count() >= 2,
		"CỬA HÀNG intro produces laugh gesture, comic text and presentation card")
	await settle(1.25)
	check(not table.special_presenter.banner.visible, "event banner removes itself quickly")
	table.present_event({"kind": "heal", "player": 1, "card_data_id": "iced_tea",
		"amount": 1, "rescued": true, "audio_event_id": "special:tea"})
	check(table.special_presenter.banner.visible
		and table.special_presenter.subtitle_label.text.contains("TRÀ ĐÁ CỨU MẠNG"),
		"successful dying TRÀ ĐÁ event gets stronger rescue presentation")
	check(table.avatars[1].expression == "drink", "TRÀ ĐÁ reuses physical drinking gesture")
	# Layout uses the shared safe viewport rectangle in both phone orientations.
	for size in [Vector2i(390, 844), Vector2i(844, 390)]:
		get_window().size = size
		get_window().content_scale_size = size
		get_viewport().set_meta("match_safe_insets", Vector4(8, 22, 8, 18))
		table.special_presenter._layout_banner()
		var usable: Rect2 = load("res://scripts/ui/MatchLayout.gd").modal_rect(table.special_presenter.root)
		check(usable.encloses(table.special_presenter.banner.get_rect()),
			"special banner stays inside mobile safe area at %s" % str(size))
	GameManager.clear()
	print("PASS: %d special-card intro, heal/rescue, comedy and responsive banner checks" % checks)
	get_tree().quit()
