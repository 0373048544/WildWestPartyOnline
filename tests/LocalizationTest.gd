extends Node

var app: Node
var checks: int = 0
var capture_index: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("LOCALIZATION FAILED: " + message)
		get_tree().quit(1)
		assert(value, message)

func verify_controls(node: Node) -> void:
	if node is Label or node is Button:
		var value: String = node.text
		check(not TextCatalog.TEXT.has(value) or TextCatalog.text(value) == value, "English UI: " + value)
		if node is Label and not value.is_empty():
			check(node.get_line_count() == node.get_visible_line_count(), "Clipped label: " + value)
	for child in node.get_children():
		verify_controls(child)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	verify_controls(app.root)
	var bottom: float = app.content.global_position.y + app.content.size.y
	check(bottom <= 900, "Screen exceeds target viewport")
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://tests/artifacts/vietnamese")
		var ignore := FileAccess.open("res://tests/artifacts/.gdignore", FileAccess.WRITE)
		ignore.close()
		capture_index += 1
		get_viewport().get_texture().get_image().save_png("res://tests/artifacts/vietnamese/screen-%02d.png" % capture_index)

func _ready() -> void:
	get_window().size = Vector2i(1440, 900)
	get_window().content_scale_size = Vector2i(1440, 900)
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	app = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	var font: Font = app.root.theme.default_font
	for character in "ăâêôơưđáàảãạĂÂÊÔƠƯĐÁÀẢÃẠ":
		check(font.has_char(character.unicode_at(0)), "Missing Vietnamese glyph: " + character)
	for screen in ["main", "host", "join"]:
		app.screen = screen
		app.refresh()
		await settle()
	GameManager.clear()
	for id in range(1, 5):
		GameManager.add_player(id, "Người chơi %d" % id)
		GameManager.players[id].ready = true
	GameManager.publish()
	await settle()
	GameManager.start_match()
	GameManager.publish()
	await settle()
	for id in GameManager.players:
		GameManager.selection.choose(GameManager, id, GameManager.selection.options[id][0])
	for _i in range(20):
		if GameManager.reactions.active.is_empty():
			break
		GameManager.resolve_reaction(false)
	GameManager.turns.current_player = 1
	for kind in CardData.definitions():
		GameManager.players[1].hand.append(CardInstance.make(GameManager.deck.next_id, kind, "HEART", 7))
		GameManager.deck.next_id += 1
	GameManager.players[1].weapon = CardInstance.make(500, "schofield", "SPADE", 1)
	GameManager.players[1].equipment.horse = CardInstance.make(501, "horse", "CLUB", 2)
	GameManager.players[1].equipment.spyglass = CardInstance.make(502, "spyglass", "DIAMOND", 3)
	GameManager.publish()
	app.seen_role = GameManager.match_id
	app.refresh()
	await settle()
	for role in PlayerState.ROLE_NAMES:
		app.refresh()
		app.show_role(role, GameManager.match_id)
		await settle()
	for kind in ["dodge", "survive", "duel"]:
		app.refresh()
		app.show_reaction({"reaction_type": kind, "remaining": 8, "request_id": 1})
		await settle()
	for result in ["OUTLAWS WIN", "SHERIFF TEAM WINS", "RENEGADE WINS"]:
		GameManager.winner = result
		GameManager.publish()
		await settle()
	for source in ["Server full.", "Host disconnected.", "Invalid IP. Enter an IPv4 or IPv6 address.",
		"Connection failed: server did not admit this player.", "Cannot host on that port: Already in use"]:
		check(TextCatalog.message(source) != source, "Untranslated network error")
	check(PlayerState.ROLE_NAMES[0] == "SHERIFF", "Role protocol unchanged")
	check(CardData.definitions().shoot.name == "BẮN", "Card display name")
	check(CardData.CardType.keys()[0] == "ACTION", "Card enum unchanged")
	GameManager.clear()
	print("PASS: %d localization, glyph, screen and layout checks" % checks)
	get_tree().quit()
