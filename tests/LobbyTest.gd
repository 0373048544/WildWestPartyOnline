extends Node

var app: Node
var host: bool
var last_error: String = ""

func require(value: bool, message: String) -> void:
	if not value:
		push_error("LOBBY FAILED: " + message)
		get_tree().quit(1)
		assert(value, message)

func until(condition: Callable, description: String) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			require(false, "Timeout: " + description)
			return
		await get_tree().process_frame

func pause() -> void:
	await get_tree().create_timer(0.4).timeout

func snapshot() -> Dictionary:
	return NetworkManager.public_state

func count_players() -> int:
	return snapshot().get("players", []).size()

func remote_ready() -> bool:
	for player in snapshot().get("players", []):
		if player.player_id != 1:
			return player.ready
	return false

func visible_text(node: Node) -> String:
	var result := ""
	if node is Label or node is Button:
		result += str(node.text) + "\n"
	for child in node.get_children():
		result += visible_text(child)
	return result

func lobby_control(control_name: String) -> Node:
	return app.content.find_child(control_name, true, false)

func press_ready() -> void:
	lobby_control("ReadyButton").pressed.emit()

func join_from_form(title: String) -> void:
	# Legacy ENet adapter regression. Production forms now use room codes.
	NetworkManager.join_game(title, "127.0.0.1", 7000)

func _ready() -> void:
	host = OS.get_cmdline_user_args().has("--host")
	NetworkManager.error_received.connect(func(message): last_error = message)
	app = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	if host:
		await test_host()
	else:
		await test_client()
	get_tree().quit()

func test_host() -> void:
	app.screen = "host"
	app.refresh()
	NetworkManager.host_game("Lobby Host", 7000)
	require(count_players() == 1 and not snapshot().started, "HOST enters lobby without gameplay")
	require(app.content.name == "Lobby" and not is_instance_valid(app.table), "Lobby scene loaded before table")
	require(snapshot().players[0].player_id == 1 and snapshot().players[0].display_name == "Lobby Host", "Host registered as Player 1")
	require("CHỦ" in visible_text(app.content.get_node("PlayerList/Player1")), "HOST badge")
	require(lobby_control("StartButton").disabled, "Start disabled with one player")
	NetworkManager.send_intent("start")
	require(not snapshot().started, "Server rejects insufficient player count")
	await pause()
	press_ready()
	await until(func(): return count_players() == 2, "client registration")
	require(snapshot().players[1].display_name == "Lobby Client", "client name synchronized")
	require(lobby_control("StartButton").disabled, "unready client blocks Start")
	await until(remote_ready, "client becomes ready")
	require("SẴN SÀNG" in visible_text(app.content.get_node("PlayerList/Player%d" % snapshot().players[1].player_id)), "ready UI synchronized")
	await until(func(): return not remote_ready(), "client unready")
	require(lobby_control("StartButton").disabled, "unready synchronization disables Start")
	await until(func(): return count_players() == 1, "client disconnect removed")
	require(app.content.get_node("PlayerList").get_child_count() >= 2, "disconnected slot available")
	await until(func(): return count_players() == 2, "client rejoins")
	require(snapshot().players[1].display_name == "Rejoined Cowboy" and not remote_ready(), "rejoin uses new name and resets ready")
	await until(remote_ready, "rejoined player ready")
	require(not lobby_control("StartButton").disabled, "two ready players enable production Start")
	lobby_control("StartButton").pressed.emit()
	require(snapshot().started and is_instance_valid(app.table), "host loads GameTable on Start")
	await choose_character()
	await get_tree().create_timer(1.0).timeout
	NetworkManager.leave()
	await get_tree().create_timer(1.0).timeout
	print("PASS: Host -> Lobby; names, host badge, ready/unready, disconnect/rejoin; production 2-player Start -> GameTable on 127.0.0.1:7000")

func test_client() -> void:
	join_from_form("Lobby Client")
	await until(func(): return count_players() == 2, "joined shared lobby")
	require(app.content.name == "Lobby" and not snapshot().started, "Join enters lobby without gameplay")
	require(not is_instance_valid(lobby_control("StartButton")), "client has no Start button")
	require(snapshot().server_port == 7000, "selected server port synchronized")
	await until(func(): return snapshot().players[0].ready, "host ready synchronized")
	require(snapshot().players[0].display_name == "Lobby Host", "host name synchronized")
	require("CHỦ" in visible_text(app.content.get_node("PlayerList/Player1")), "client sees HOST badge")
	NetworkManager.send_intent("start")
	await pause()
	require(not snapshot().started, "remote Start request rejected")
	press_ready()
	await pause()
	require(remote_ready(), "own ready reflected by server")
	press_ready()
	await pause()
	require(not remote_ready(), "own unready reflected by server")
	NetworkManager.leave()
	await pause()
	join_from_form("Rejoined Cowboy")
	await until(func(): return count_players() == 2, "rejoined lobby")
	await pause()
	press_ready()
	await until(func(): return snapshot().get("started", false), "synchronized Start")
	require(is_instance_valid(app.table), "client loads GameTable")
	await choose_character()
	await until(func(): return "Máy chủ" in last_error or last_error == "Host disconnected.", "host disconnect notification")
	require(snapshot().is_empty() and not is_instance_valid(app.table), "host disconnect returns to menu")
	print("PASS: Join -> same Lobby; host name/ready synchronized; remote Start rejected; GameTable and host disconnect verified")

func choose_character() -> void:
	await pause()
	await until(func(): return NetworkManager.private_state.get("character_options", []).size() == 2, "private character choices")
	NetworkManager.send_intent("character", {"character": NetworkManager.private_state.character_options[0].character_id})
	await until(func(): return snapshot().phase != "CHARACTER_SELECTION", "all characters selected")
	require(snapshot().players.all(func(p): return p.public_role != "SHERIFF"), "two-player mode has no Sheriff")
	require(snapshot().players.any(func(p): return p.player_id == snapshot().current_player), "server randomly chooses a valid two-player opener")
