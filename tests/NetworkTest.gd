extends Node

var is_host: bool = false
var elapsed: float = 0.0
var tick: float = 0.0
var started_at: float = -1.0
var checked: bool = false
var restarted: bool = false
var app: Node
var stage: int = 0
var overflow: bool = false
var observed_match: int = 0
var observed_game_over: bool = false
var expected_players: int = 4

func _ready() -> void:
	is_host = OS.get_cmdline_user_args().has("--host")
	overflow = OS.get_cmdline_user_args().has("--overflow")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--players="):
			expected_players = int(arg.trim_prefix("--players="))
	app = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	NetworkManager.updated.connect(observe_lifecycle)
	if overflow:
		NetworkManager.error_received.connect(func(message):
			if message == "Server full.":
				print("PASS: fifth player receives Server full")
				get_tree().quit()
			else:
				require(false, "Expected Server full, got " + message))
	if is_host:
		NetworkManager.host_game("Host", 17070)
	else:
		NetworkManager.join_game("Client", "127.0.0.1", 17070)

func observe_lifecycle() -> void:
	# Observe each delivered snapshot, including multiple updates in one frame.
	# Polling at 180 ms can miss a terminal state during a busy UI refresh.
	var state: Dictionary = NetworkManager.public_state
	if not state.get("started", false):
		return
	var current_match: int = state.match_id
	if observed_match > 0 and current_match > observed_match:
		require(observed_game_over, "game-over snapshot delivered before restart")
		stage = 2
		print("PASS: fresh match restart, peer ", multiplayer.get_unique_id())
		observed_game_over = false
	observed_match = current_match
	if not str(state.winner).is_empty():
		observed_game_over = true

func require(value: bool, message: String) -> void:
	if not value:
		push_error("NETWORK FAILED: " + message)
		get_tree().quit(1)

func _process(delta: float) -> void:
	elapsed += delta
	tick += delta
	if elapsed > 35:
		push_error("NETWORK FAILED: timeout")
		get_tree().quit(1)
	if tick < 0.18:
		return
	tick = 0
	if overflow:
		return
	var state: Dictionary = NetworkManager.public_state
	if state.is_empty():
		return
	var id := multiplayer.get_unique_id()
	if not state.started:
		if restarted or stage == 2:
			print("PASS: ENet lobby returned, peer ", id)
			set_process(false)
			await get_tree().create_timer(0.8).timeout
			get_tree().quit()
			return
		for p in state.players:
			if p.player_id == id and not p.ready:
				NetworkManager.send_intent("ready")
				return
		if is_host and elapsed > 3.0 and state.players.size() == expected_players and state.players.all(func(p): return p.ready):
			NetworkManager.send_intent("start")
		return
	var own: Dictionary = NetworkManager.private_state
	if not own.has("role"):
		return
	if state.phase == "CHARACTER_SELECTION":
		require(state.players.all(func(p): return not p.has("character_options")), "private character pairs never public")
		if own.get("character_options", []).size() == 2:
			NetworkManager.send_intent("character", {"character": own.character_options[0].character_id})
		return
	if started_at < 0:
		started_at = elapsed
		for p in state.players:
			require(not p.has("hand") and not p.has("role"), "public privacy")
			if p.player_id != id and p.public_role != "SHERIFF":
				require(p.public_role.is_empty(), "hidden role privacy")
		require(own.has("hand"), "private hand delivered")
		var local_player: Dictionary = state.players.filter(func(p): return p.player_id == id)[0]
		require(own.hand.size() >= local_player.max_hp, "starting hand follows character HP")
		require(is_host or GameManager.players.is_empty(), "clients have no server registry")
		checked = true
		print("PASS: admitted, ready, match, private snapshot, peer ", id)
		app.seen_role = state.match_id
		app.refresh()
	if elapsed - started_at < 1.0:
		return
	if not state.winner.is_empty():
		if stage == 0:
			stage = 1
			if is_host:
				# Let every peer observe the terminal snapshot before replacing it.
				set_process(false)
				await get_tree().create_timer(1.0).timeout
				NetworkManager.send_intent("restart")
				set_process(true)
			return
		if is_host and stage == 2:
			set_process(false)
			await get_tree().create_timer(1.0).timeout
			restarted = true
			NetworkManager.send_intent("lobby")
			set_process(true)
			print("PASS: ENet match, game over, restart and return to lobby")
		return
	if stage == 1:
		stage = 2
		print("PASS: fresh match restart, peer ", id)
	if is_host and elapsed - started_at > 5:
		# Deterministic end-state exercises game-over delivery and restart.
		for p in GameManager.players.values():
			if p.role != PlayerState.Role.SHERIFF:
				GameManager.kill_player(p.player_id, 1)
		GameManager.publish()
		return
	var reaction: Dictionary = own.get("reaction", {})
	if not reaction.is_empty():
		var response: Dictionary = {"request": reaction.request_id, "accept": true}
		if reaction.has("cards"):
			response["cards"] = reaction.cards.slice(0, reaction.get("pick_count", 1)).map(func(c): return c.instance_id)
		elif reaction.has("choices"):
			response["option"] = str(reaction.choices[0].id)
		elif reaction.get("allowed_card_types", []).is_empty():
			response.accept = false
		NetworkManager.send_intent("reaction", response)
		return
	if int(state.current_player) != id:
		return
	if state.phase == "DISCARD_PHASE":
		if not own.hand.is_empty():
			NetworkManager.send_intent("discard", {"card": own.hand[0].instance_id})
	elif state.phase == "ACTION_PHASE":
		for card in own.hand:
			var targets: Array = own.get("targets", {}).get(card.instance_id, [])
			if not targets.is_empty():
				NetworkManager.send_intent("play", {"card": card.instance_id, "target": targets[0]})
				return
		NetworkManager.send_intent("end")
