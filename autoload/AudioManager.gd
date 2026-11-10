extends Node

signal sound_played(key: String, bus: String)
const DEFAULTS := {"Master": 0.65, "Music": 0.22, "Ambient": 0.16, "SFX": 0.75, "UI": 0.5, "Character": 0.65}
var volumes: Dictionary = DEFAULTS.duplicate()
var muted := false
var unlocked := false
var enabled := true
var manifest: Dictionary = {}
var streams: Dictionary = {}
var pool: Array = []
var world_pool: Array = []
var loops: Array = []
var cooldowns: Dictionary = {}
var seen: Dictionary = {}
var pending: Array = []
var schedule_generation: int = 0
var unique_loop_players: Dictionary = {}
var rng := RandomNumberGenerator.new()
var duck_until := 0
var duck_gain := 1.0
var table: Node3D
var previous: Dictionary = {}
var reaction_id := -1
var reaction_deadline := 0
var last_tick := -1
var warnings: Dictionary = {}
var settings_path := "user://audio_settings.cfg"
var local_once: Dictionary = {}
var music_allowed: bool = true
var music_gain: float = 1.0
var tension_until: int = 0
var duel_active: bool = false
var dynamite_active: bool = false
var local_threat: bool = false
var next_detail: int = 0
var tension_deadline: int = 0
var reconnecting_active: bool = false

const SPECIAL_CUES := {
	"beer_drink": "beer",
	"beer_burp": "beer_burp",
	"iced_tea_drink": "iced_tea_drink",
	"iced_tea_fart": "iced_tea_fart",
	"mischievous_laugh": "mischievous_laugh"
}

func update_mix_policy(state: Dictionary) -> void:
	music_allowed = not bool(state.get("started", false)) or not str(state.get("winner", "")).is_empty() or state.get("phase", "") == "CHARACTER_SELECTION"
	if music_allowed:
		duel_active = false
		dynamite_active = false
		local_threat = false

func stop_cue(key: String) -> void:
	for player in pool + world_pool:
		if player.get_meta("cue", "") == key:
			player.stop()
			player.stream = null
			player.set_meta("cue", "")
	unique_loop_players.erase(key)

func start_unique_loop(key: String, bus: String = "SFX", at: Variant = null, gain: float = 0) -> bool:
	var current: Node = unique_loop_players.get(key)
	if is_instance_valid(current) and current.playing:
		if current is AudioStreamPlayer3D and at is Vector3:
			current.global_position = at
		return false
	stop_cue(key)
	if not play_sound(key, bus, at, gain):
		return false
	for player in pool + world_pool:
		if player.playing and player.get_meta("cue", "") == key:
			unique_loop_players[key] = player
			return true
	return false

func stop_unique_loop(key: String) -> void:
	stop_cue(key)

func cancel_transient_audio() -> void:
	schedule_generation += 1
	pending.clear()
	stop_unique_loop("fuse")
	dynamite_active = false
	duel_active = false
	tension_deadline = 0

func _exit_tree() -> void:
	for player in pool + world_pool + loops:
		player.stop()
		player.stream = null
		player.set_meta("cue", "")
	pending.clear()
	unique_loop_players.clear()
	streams.clear()

func play_once(identity: String, cue: String) -> void:
	if not local_once.has(identity):
		local_once[identity] = true
		play_gameplay(cue)

func _ready() -> void:
	rng.randomize() # Presentation has its own RNG, never the gameplay RNG.
	enabled = DisplayServer.get_name() != "headless"
	unlocked = not OS.has_feature("web")
	manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/manifest.json"))
	load_settings()
	for index in range(16):
		var player := AudioStreamPlayer.new()
		add_child(player)
		pool.append(player)
	for index in range(8):
		var player := AudioStreamPlayer3D.new()
		player.unit_size = 12
		player.max_distance = 45
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		player.panning_strength = 0.35
		add_child(player)
		world_pool.append(player)
	for key in ["saloon", "piano"]:
		var player := AudioStreamPlayer.new()
		player.bus = "Ambient" if key == "saloon" else "Music"
		player.set_meta("loop_key", key)
		add_child(player)
		var stream: AudioStreamWAV = get_stream(key)
		if stream:
			stream = stream.duplicate()
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_end = stream.data.size() / 2
			player.stream = stream
		loops.append(player)
	NetworkManager.updated.connect(observe_state)
	NetworkManager.error_received.connect(func(_message): play_ui("error"))
	if unlocked:
		start_ambience()

func _input(event: InputEvent) -> void:
	if not unlocked and ((event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed) or (event is InputEventKey and event.pressed)):
		unlocked = true
		start_ambience()

func start_ambience() -> void:
	if enabled:
		for player in loops:
			if player.stream and not player.playing and (player.bus != "Music" or music_allowed):
				player.play()

func get_stream(key: String) -> AudioStreamWAV:
	var choices: Array = manifest.get(key, [])
	if choices.is_empty():
		# An explicitly registered empty list is an optional silent cue. Only an
		# unknown key is a manifest mistake worth warning about.
		if OS.is_debug_build() and not manifest.has(key) and not warnings.has(key):
			warnings[key] = true
			push_warning("Missing audio cue: " + key)
		return null
	var path: String = choices[rng.randi_range(0, choices.size() - 1)]
	if not streams.has(path):
		if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
			if OS.is_debug_build() and not warnings.has(path):
				warnings[path] = true
				push_warning("Missing audio asset: " + path)
			return null
		streams[path] = load(path) if ResourceLoader.exists(path) else AudioStreamWAV.load_from_file(path)
	return streams[path]

func play_sound(key: String, bus: String = "SFX", at: Variant = null, gain: float = 0) -> bool:
	if not enabled or not unlocked or muted:
		return false
	if key == "piano" and not music_allowed:
		return false
	var now := Time.get_ticks_msec()
	if now - int(cooldowns.get(key, -1000)) < (110 if key == "hover" else 55):
		return false
	var stream := get_stream(key)
	if stream == null:
		return false
	var players: Array = world_pool if at is Vector3 and is_instance_valid(table) else pool
	var player: Node = null
	var same := 0
	for candidate in players:
		if candidate.playing and candidate.get_meta("cue", "") == key:
			same += 1
		if not candidate.playing and player == null:
			candidate.set_meta("cue", "")
			player = candidate
	if same >= 3:
		return false
	if player == null:
		if key in ["reaction", "survive", "explosion"]:
			player = players[0]
			player.stop()
		else:
			return false
	cooldowns[key] = now
	player.set_meta("cue", key)
	player.stream = stream
	if key == "fuse" and dynamite_active:
		var looping: AudioStreamWAV = stream.duplicate()
		looping.loop_mode = AudioStreamWAV.LOOP_FORWARD
		looping.loop_end = looping.data.size() / 2
		player.stream = looping
	player.bus = bus
	player.volume_db = -5 + gain
	player.pitch_scale = rng.randf_range(0.98, 1.02) if bus == "Weapons" else rng.randf_range(0.96, 1.04)
	if player is AudioStreamPlayer3D:
		player.global_position = at
	player.play()
	if bus == "Weapons":
		duck_until = maxi(duck_until, now + (700 if key == "explosion" else 220))
	sound_played.emit(key, bus)
	return true

func play_ui(key: String) -> void:
	play_sound(key, "UI")

func play_card(key: String) -> void:
	play_sound(key, "Cards", null, -5)

func play_gameplay(key: String) -> void:
	play_sound(key)

func play_world(key: String, position: Vector3) -> void:
	play_sound(key, "WorldSFX", position)

func play_character(key: String, player_id: int) -> void:
	play_sound(key, "Character", position_for(player_id))

func play_special(key: String, player_id: int = 0, delay: float = 0.0, gain: float = 0.0, context: Dictionary = {}) -> void:
	# A single safe lookup keeps optional comedy assets out of gameplay scripts.
	# Missing/empty manifest entries intentionally resolve to silence.
	var cue: String = str(SPECIAL_CUES.get(key, ""))
	if cue.is_empty():
		return
	var at: Variant = position_for(player_id) if player_id > 0 else null
	if delay > 0.0:
		schedule(cue, delay, "Character", at, gain, context)
	else:
		play_sound(cue, "Character", at, gain)

func position_for(id: int) -> Variant:
	return table.avatars[id].global_position + Vector3.UP if is_instance_valid(table) and table.avatars.has(id) else null

func schedule(key: String, delay: float, bus: String = "SFX", at: Variant = null, gain: float = 0, context: Dictionary = {}) -> void:
	if pending.size() < 64:
		pending.append({
			"key": key,
			"at_ms": Time.get_ticks_msec() + int(delay * 1000),
			"bus": bus,
			"position": at,
			"gain": gain,
			"generation": schedule_generation,
			"match_id": int(context.get("match_id", NetworkManager.public_state.get("match_id", 0))),
			"event_id": str(context.get("audio_event_id", context.get("event_id", "")))
		})

func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	if tension_deadline > 0 and now > tension_deadline:
		duel_active = false
		dynamite_active = false
		stop_unique_loop("fuse")
		tension_deadline = 0
	var tension: bool = duel_active or dynamite_active or local_threat or now < tension_until
	duck_gain = move_toward(duck_gain, 0.18 if dynamite_active else (0.35 if tension else (0.55 if now < duck_until else 1.0)), delta * 2)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambient"), linear_to_db(maxf(0.0001, float(volumes.Ambient) * duck_gain)))
	music_gain = move_toward(music_gain, 1.0 if music_allowed else 0.0, delta * 2.5)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(0.00001, float(volumes.Music) * music_gain)))
	for player in loops:
		if player.bus == "Music":
			if music_gain <= 0 and player.playing:
				player.stop()
			elif music_allowed and enabled and unlocked and not player.playing and player.stream:
				player.play()
	# Sparse non-musical room details; no continuous patterned tension track.
	if enabled and unlocked and now >= next_detail:
		next_detail = now + rng.randi_range(11000, 24000)
		if not tension:
			play_sound("wood_creak" if rng.randf() < 0.8 else "glass", "Ambient", null, -15)
	for item in pending.duplicate():
		var current_match: int = int(NetworkManager.public_state.get("match_id", 0))
		if int(item.get("generation", -1)) != schedule_generation or (int(item.get("match_id", 0)) > 0 and current_match > 0 and int(item.match_id) != current_match):
			pending.erase(item)
			continue
		if now >= int(item.at_ms):
			pending.erase(item)
			play_sound(item.key, item.bus, item.position, item.gain)
	var seconds := ceili((reaction_deadline - now) / 1000.0)
	if seconds in [1, 2, 3] and seconds != last_tick:
		last_tick = seconds
		play_ui("tick")

func consume_event(event: Dictionary) -> void:
	var event_match: int = int(event.get("match_id", 0))
	var current_match: int = int(NetworkManager.public_state.get("match_id", 0))
	if event_match > 0 and current_match > 0 and event_match != current_match:
		return
	var identity: String = str(event.get("audio_event_id", ""))
	if not identity.is_empty():
		if seen.has(identity):
			return
		seen[identity] = true
		if seen.size() > 1024:
			seen.erase(seen.keys()[0])
	var kind: String = str(event.get("kind", ""))
	var id := int(event.get("player", event.get("actor", 0)))
	var at: Variant = position_for(id)
	var card: Dictionary = event.get("card", {})
	match kind:
		"animation":
			var cue: String = {"shoot": "bang", "gatling": "gatling", "dodge": "dodge", "death": "death"}.get(event.get("animation", ""), "")
			if cue == "bang":
				var weapon: String = table.player_rows.get(id, {}).get("weapon_id", "") if is_instance_valid(table) else ""
				cue = weapon if weapon in ["schofield", "remington", "carabine", "winchester", "volcanic"] else "bang"
				play_sound("cock", "Weapons", at, -10)
				schedule(cue, 0.1, "Weapons", at, 0, event)
				return
			if cue == "dodge":
				schedule("ricochet", 0.04, "Weapons", at, -8, event)
			if cue == "death":
				tension_until = Time.get_ticks_msec() + 900
				# Match the physical fall/thud, not the first anticipation frame.
				schedule("death", 0.22, "Character", at, 0, event)
				return
			if not cue.is_empty():
				play_sound(cue, "Weapons" if cue == "gatling" else "Character", at)
		"draw":
			for index in range(mini(8, int(event.get("count", 1)))):
				schedule("draw", index * 0.09, "Cards", null, -6, event)
		"discard":
			play_card("play")
			schedule("discard", 0.35, "SFX", null, -7, event)
			# Drink audio belongs to the successful HEAL event, not card removal;
			# otherwise Beer would play twice and rejected/failed heals could sound valid.
			var special: String = {"saloon": "glass", "supply": "wagon", "wells_fargo": "coins", "general_store": "fan", "panic": "snatch", "cat_balou": "discard", "indians": "danger"}.get(card.get("card_data_id", ""), "")
			if event.get("event_type", "") == "CARD_PLAYED" and not special.is_empty():
				play_sound(special)
		"transfer":
			# Hidden card identity is deliberately ignored.
			play_card("snatch" if event.get("steal", true) else "discard")
			schedule("place", 0.35, "SFX", null, -7, event)
			if not event.get("hidden", true):
				var material: String = {"barrel": "barrel", "spyglass": "scope", "jail": "jail", "horse": "wood_creak"}.get(card.get("card_data_id", ""), "weapon")
				play_sound(material, "WorldSFX", at, -7)
		"store_pick", "reclaim": play_card("draw")
		"equip":
			var equipment: String = card.get("card_data_id", "")
			play_sound({"dynamite": "fuse", "spyglass": "scope"}.get(equipment, equipment if equipment in ["horse", "barrel", "jail"] else "weapon"), "WorldSFX", at)
		"judge":
			if event.get("purpose", "") == "dynamite":
				dynamite_active = true
				tension_deadline = Time.get_ticks_msec() + 18000
			if event.get("purpose", "") in ["dynamite", "barrel"]:
				if event.purpose == "dynamite":
					start_unique_loop("fuse", "WorldSFX", at)
				else:
					play_sound("barrel", "WorldSFX", at)
			schedule("flip", 0.14, "SFX", null, 0, event)
		"reveal": play_card("flip")
		"barrel_result": play_sound("lucky" if event.get("success", false) else "fail", "WorldSFX", at)
		"damage":
			var explosion: bool = dynamite_active and int(event.get("amount", 1)) >= 3
			stop_unique_loop("fuse")
			dynamite_active = false
			duel_active = false
			play_sound("explosion" if explosion else "hit", "Weapons" if explosion else "Character", at)
		"heal":
			var healing_card: String = str(event.get("card_data_id", ""))
			if healing_card == "drink":
				play_special("beer_drink", id)
				play_special("beer_burp", id, 0.42, 1.0, event)
			elif healing_card == "iced_tea":
				play_special("iced_tea_drink", id)
				play_special("iced_tea_fart", id, 0.42, -1.5, event)
			play_sound("heal", "Character", at, -8)
		"store_started", "department_store":
			play_special("mischievous_laugh", id, 0.24, -1.0, event)
		"duel":
			duel_active = true
			tension_deadline = Time.get_ticks_msec() + 18000
			play_gameplay("duel")
		"bang":
			if int(event.get("target", 0)) == NetworkManager.local_player_id():
				tension_until = Time.get_ticks_msec() + 500
		"jail_result": play_sound("unlock" if event.get("escaped", false) else "jail", "WorldSFX", at)
		"dynamite_pass":
			stop_unique_loop("fuse")
			dynamite_active = false
			play_sound("pass", "WorldSFX", at)
		"reward": play_gameplay("reward")
		"penalty": play_gameplay("dump")

func observe_state() -> void:
	var current: Dictionary = NetworkManager.public_state
	update_mix_policy(current)
	var reconnecting_now: bool = NetworkManager.mode == "websocket" and is_instance_valid(NetworkManager.room_client) and NetworkManager.room_client.reconnecting
	if reconnecting_now and not reconnecting_active:
		# The retained snapshot is only a reconnect baseline. Any delayed cue from
		# before the transport interruption no longer has reliable presentation context.
		cancel_transient_audio()
	reconnecting_active = reconnecting_now
	if current.get("phase", "") != "REACTION":
		duel_active = false
	if music_allowed:
		stop_cue("fuse")
	if current.is_empty():
		previous = {}
		reaction_deadline = 0
		last_tick = -1
		cancel_transient_audio()
		return
	if previous.is_empty() and current.get("started", false):
		# A reconnect snapshot is a baseline, not a replay of match start/win/turn.
		previous = current.duplicate(true)
	if previous.is_empty():
		play_ui("confirm")
	elif not current.get("started", false):
		var old: Array = previous.get("players", [])
		var rows: Array = current.get("players", [])
		if rows.size() != old.size():
			play_gameplay("door_open" if rows.size() > old.size() else "door_close")
		for row in rows:
			var before: Array = old.filter(func(p): return p.player_id == row.player_id)
			if not before.is_empty() and before[0].ready != row.ready:
				play_ui("ready" if row.ready else "unready")
	if current.get("match_id", 0) != previous.get("match_id", 0) and current.get("started", false):
		cancel_transient_audio()
		play_gameplay("start")
		play_card("fan")
	var local_row: Array = current.get("players", []).filter(func(p): return p.player_id == NetworkManager.local_player_id())
	var old_local: Array = previous.get("players", []).filter(func(p): return p.player_id == NetworkManager.local_player_id())
	if not local_row.is_empty() and not old_local.is_empty() and local_row[0].get("character_id", "") != old_local[0].get("character_id", "") and not str(local_row[0].get("character_id", "")).is_empty():
		play_ui("confirm")
	if previous.get("phase", "") == "CHARACTER_SELECTION" and current.get("phase", "") != "CHARACTER_SELECTION":
		play_ui("turn")
	if current.get("winner", "") != previous.get("winner", "") and not str(current.get("winner", "")).is_empty():
		cancel_transient_audio()
		play_gameplay({"SHERIFF TEAM WINS": "sheriff_win", "DEPUTY WINS": "sheriff_win",
			"OUTLAWS WIN": "outlaw_win", "OUTLAW WINS": "outlaw_win", "RENEGADE WINS": "renegade_win"}.get(current.winner, "start"))
	if current.get("action_turn", 0) != previous.get("action_turn", 0) and current.get("current_player", 0) == NetworkManager.local_player_id():
		play_ui("turn")
	var reaction: Dictionary = NetworkManager.private_state.get("reaction", {})
	local_threat = reaction.get("reaction_type", "") in ["dodge", "duel", "indians", "survive"]
	var request_id := int(reaction.get("request_id", -1))
	if request_id != reaction_id:
		reaction_id = request_id
		last_tick = -1
		reaction_deadline = Time.get_ticks_msec() + int(float(reaction.get("remaining", 0)) * 1000) if request_id >= 0 else 0
		if request_id >= 0:
			play_ui({"survive": "survive", "duel": "duel_alert", "indians": "danger"}.get(reaction.get("reaction_type", ""), "reaction"))
	previous = current.duplicate(true)

func set_volume(bus: String, value: float, persist: bool = true) -> void:
	if not volumes.has(bus):
		return
	volumes[bus] = clampf(value, 0, 1)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus), linear_to_db(maxf(0.0001, volumes[bus])))
	if persist:
		save_settings()

func set_muted(value: bool) -> void:
	muted = value
	AudioServer.set_bus_mute(0, value)
	save_settings()

func save_settings() -> void:
	var config := ConfigFile.new()
	for bus in volumes:
		config.set_value("volumes", bus, volumes[bus])
	config.set_value("audio", "muted", muted)
	config.save(settings_path)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("localStorage.setItem('wwpo_audio', " + JSON.stringify(JSON.stringify({"volumes": volumes, "muted": muted})) + ")")

func load_settings() -> void:
	var config := ConfigFile.new()
	config.load(settings_path)
	for bus in volumes:
		set_volume(bus, float(config.get_value("volumes", bus, DEFAULTS[bus])), false)
	muted = bool(config.get_value("audio", "muted", false))
	if OS.has_feature("web"):
		var saved: Variant = JSON.parse_string(str(JavaScriptBridge.eval("localStorage.getItem('wwpo_audio') || '{}'")))
		if saved is Dictionary:
			for bus in volumes:
				set_volume(bus, float(saved.get("volumes", {}).get(bus, volumes[bus])), false)
			muted = bool(saved.get("muted", muted))
	AudioServer.set_bus_mute(0, muted)
