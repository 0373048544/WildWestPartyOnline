extends Node

var checks := 0
var played: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("AUDIO RELIABILITY FAILED: " + message)
		get_tree().quit(1)
		assert(value, message)

func count_cue(key: String) -> int:
	return played.count(key)

func wait_for_audio(delay: float = 0.5) -> void:
	var deadline := Time.get_ticks_msec() + int(delay * 1000.0)
	while Time.get_ticks_msec() < deadline and not AudioManager.pending.is_empty():
		await get_tree().process_frame

func reset_audio() -> void:
	AudioManager.enabled = true
	AudioManager.unlocked = true
	AudioManager.muted = false
	AudioManager.seen.clear()
	AudioManager.cooldowns.clear()
	AudioManager.cancel_transient_audio()
	for player in AudioManager.pool + AudioManager.world_pool:
		player.stop()
		player.stream = null
		player.set_meta("cue", "")
	played.clear()

func event(id: String, kind: String, extra: Dictionary = {}) -> Dictionary:
	var result := extra.duplicate(true)
	result["audio_event_id"] = id
	result["event_id"] = id
	result["match_id"] = 410
	result["kind"] = kind
	return result

func _ready() -> void:
	await get_tree().process_frame
	AudioManager.sound_played.connect(func(key: String, _bus: String): played.append(key))
	NetworkManager.public_state = {"started": true, "match_id": 410, "phase": "ACTION_PHASE", "winner": "", "players": [], "action_turn": 1, "current_player": 2}
	NetworkManager.private_state = {}
	reset_audio()
	var enet_stamped: Dictionary = NetworkManager.stamp_audio({"kind": "draw", "match_id": 410})
	check(str(enet_stamped.audio_event_id).begins_with("enet:410:") and int(enet_stamped.match_id) == 410, "ENet table events receive stable match-scoped audio identity")
	var bridge: Node = load("res://server/RoomBridge.gd").new()
	bridge.room = {"room_code": "AUDIO", "game": GameManager}
	var websocket_stamped: Dictionary = bridge.stamp_audio({"kind": "draw", "match_id": 410})
	check(str(websocket_stamped.audio_event_id).begins_with("AUDIO:410:") and int(websocket_stamped.match_id) == 410, "WebSocket table events receive stable room/match-scoped audio identity")
	bridge.free()
	AudioManager.consume_event({"audio_event_id": "409:stale", "match_id": 409, "kind": "animation", "animation": "shoot"})
	check(played.is_empty(), "previous-match event is rejected before it can play or schedule audio")

	var shot := event("410:shot", "animation", {"animation": "shoot", "actor": 2, "target": 1})
	AudioManager.consume_event(shot)
	await wait_for_audio()
	AudioManager.consume_event(shot)
	await get_tree().create_timer(0.12).timeout
	check(count_cue("cock") == 1 and count_cue("bang") == 1, "one BANG event owns exactly one cock and one gunshot")

	AudioManager.consume_event(event("410:dodge", "animation", {"animation": "dodge", "actor": 1}))
	await wait_for_audio()
	check(count_cue("dodge") == 1 and count_cue("ricochet") == 1 and count_cue("hit") == 0, "one Dodge owns one dodge/ricochet sequence and no hit")

	AudioManager.consume_event(event("410:draw", "draw", {"player": 1, "count": 2}))
	await wait_for_audio()
	check(count_cue("draw") == 2, "draw-two schedules exactly two staggered card sounds")

	AudioManager.consume_event(event("410:beer", "heal", {"player": 1, "card_data_id": "drink", "amount": 1}))
	AudioManager.consume_event(event("410:beer", "heal", {"player": 1, "card_data_id": "drink", "amount": 1}))
	await wait_for_audio()
	check(count_cue("beer") == 1 and count_cue("heal") == 1 and count_cue("beer_burp") <= 1, "Beer success audio is owned once by HEAL")

	await get_tree().create_timer(0.08).timeout
	AudioManager.consume_event(event("410:tea", "heal", {"player": 1, "card_data_id": "iced_tea", "amount": 1}))
	AudioManager.consume_event(event("410:tea", "heal", {"player": 1, "card_data_id": "iced_tea", "amount": 1}))
	await wait_for_audio()
	check(count_cue("iced_tea_drink") == 1 and count_cue("heal") == 2 and count_cue("iced_tea_fart") <= 1, "Iced Tea success audio is owned once by HEAL")

	AudioManager.consume_event(event("410:fuse-a", "judge", {"player": 1, "purpose": "dynamite"}))
	AudioManager.consume_event(event("410:fuse-b", "judge", {"player": 1, "purpose": "dynamite"}))
	check(count_cue("fuse") == 1, "multiple relevant snapshots/events cannot start a second fuse loop")
	check((AudioManager.pool + AudioManager.world_pool).filter(func(p): return p.playing and p.get_meta("cue", "") == "fuse").size() == 1, "at most one physical fuse player is active")
	AudioManager.consume_event(event("410:pass", "dynamite_pass", {"player": 1, "to": 2}))
	check(not AudioManager.dynamite_active and (AudioManager.pool + AudioManager.world_pool).all(func(p): return not p.playing or p.get_meta("cue", "") != "fuse"), "Dynamite pass stops and clears the old fuse")

	await get_tree().create_timer(0.08).timeout
	AudioManager.consume_event(event("410:fuse-c", "judge", {"player": 2, "purpose": "dynamite"}))
	AudioManager.consume_event(event("410:explosion", "damage", {"player": 2, "amount": 3}))
	check(count_cue("explosion") == 1 and not AudioManager.dynamite_active, "explosion stops fuse first and plays exactly once")

	AudioManager.previous = NetworkManager.public_state.duplicate(true)
	AudioManager.schedule("bang", 0.3, "Weapons", null, 0, {"match_id": 410, "audio_event_id": "410:late"})
	NetworkManager.public_state = {"started": true, "match_id": 410, "phase": "GAME_OVER", "winner": "OUTLAWS WIN", "players": [], "action_turn": 1, "current_player": 0}
	AudioManager.observe_state()
	var win_count := count_cue("outlaw_win")
	AudioManager.observe_state()
	check(AudioManager.pending.is_empty() and win_count == 1 and count_cue("outlaw_win") == 1, "game over cancels delayed cues and winner transition plays once")

	AudioManager.schedule("bang", 0.3, "Weapons", null, 0, {"match_id": 410, "audio_event_id": "410:obsolete"})
	NetworkManager.public_state = {"started": true, "match_id": 411, "phase": "CHARACTER_SELECTION", "winner": "", "players": [], "action_turn": 0, "current_player": 0}
	NetworkManager.private_state = {}
	AudioManager.observe_state()
	var start_count := count_cue("start")
	AudioManager.observe_state()
	check(AudioManager.pending.is_empty() and start_count == 1 and count_cue("start") == 1, "rematch cancels old pending audio and match-start plays once")

	AudioManager.dynamite_active = true
	AudioManager.start_unique_loop("fuse", "WorldSFX")
	AudioManager.schedule("bang", 0.3, "Weapons", null, 0, {"match_id": 411})
	NetworkManager.public_state = {}
	AudioManager.observe_state()
	check(AudioManager.pending.is_empty() and not AudioManager.dynamite_active and not AudioManager.unique_loop_players.has("fuse"), "leaving room clears scheduled audio and fuse loop")

	NetworkManager.public_state = {"started": true, "match_id": 412, "phase": "REACTION", "winner": "", "players": [], "action_turn": 1, "current_player": 2}
	NetworkManager.private_state = {"reaction": {"request_id": 99, "reaction_type": "dodge", "remaining": 3.0}}
	AudioManager.previous = NetworkManager.public_state.duplicate(true)
	AudioManager.observe_state()
	AudioManager.observe_state()
	check(count_cue("reaction") == 1, "repeated reaction snapshots emit one request-ID-owned alert")
	AudioManager._process(0.0)
	AudioManager._process(0.0)
	check(count_cue("tick") == 1, "reaction countdown emits at most one tick in the same second")
	NetworkManager.private_state = {}
	AudioManager.observe_state()
	check(AudioManager.reaction_deadline == 0 and AudioManager.last_tick == -1, "resolved reaction clears countdown context")

	AudioManager.schedule("bang", 0.3, "Weapons", null, 0, {"match_id": 412})
	NetworkManager.mode = "websocket"
	NetworkManager.room_client.reconnecting = true
	AudioManager.observe_state()
	check(AudioManager.pending.is_empty(), "reconnect baseline cancels delayed pre-interruption cues without replaying state audio")
	NetworkManager.room_client.reconnecting = false
	NetworkManager.mode = "offline"
	AudioManager.observe_state()

	print("PASS: %d event-owner, dedupe, scheduled-context, fuse-loop, winner/rematch and reaction-tick checks" % checks)
	for player in AudioManager.pool + AudioManager.world_pool + AudioManager.loops:
		player.stop()
	get_tree().quit()
