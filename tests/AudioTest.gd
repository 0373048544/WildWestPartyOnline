extends Node
var checks := 0
var played: Array = []

func wait_for(condition: Callable) -> void:
	var deadline := Time.get_ticks_msec() + 2000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("AUDIO FAILED: " + message)
		get_tree().quit(1)
		assert(value, message)

func _ready() -> void:
	await get_tree().process_frame
	AudioManager.enabled = true
	AudioManager.unlocked = true
	AudioManager.muted = false
	AudioManager.sound_played.connect(func(key, _bus): played.append(key))
	for bus in ["Master", "Music", "Ambient", "SFX", "WorldSFX", "UI", "Character"]:
		check(AudioServer.get_bus_index(bus) >= 0, "bus exists " + bus)
	for key in AudioManager.manifest:
		for path in AudioManager.manifest[key]:
			var stream := AudioStreamWAV.load_from_file(path)
			check(stream != null and stream.get_length() > 0, "valid audible PCM " + path)
	for optional_cue in ["beer_burp", "iced_tea_drink", "iced_tea_fart", "mischievous_laugh"]:
		check(AudioManager.manifest.has(optional_cue), "central special-card cue is registered: " + optional_cue)
	# Optional empty cues must safely remain silent instead of loading a broken path.
	check(not AudioManager.play_sound("beer_burp") and not AudioManager.play_sound("iced_tea_fart")
		and not AudioManager.play_sound("mischievous_laugh"),
		"missing comedy assets fail silently without creating invalid resources")
	AudioManager.consume_event({"audio_event_id": "test:1", "kind": "animation", "animation": "shoot"})
	await wait_for(func(): return played.has("bang"))
	AudioManager.consume_event({"audio_event_id": "test:1", "kind": "animation", "animation": "shoot"})
	check(played.count("bang") == 1, "duplicate network event ignored even after cooldown")
	AudioManager.consume_event({"audio_event_id": "test:2", "kind": "animation", "animation": "dodge"})
	check(played.has("dodge") and not played.has("hit"), "Dodge distinct from damage")
	AudioManager.consume_event({"audio_event_id": "test:3", "kind": "draw", "count": 3})
	await wait_for(func(): return played.count("draw") == 3)
	check(played.count("draw") == 3, "three staggered physical draw sounds")
	var nodes := AudioManager.get_child_count()
	for index in range(200):
		AudioManager.play_ui("hover")
	check(AudioManager.get_child_count() == nodes and nodes == 26, "bounded reusable players and hover cooldown")
	AudioManager.settings_path = "res://tests/artifacts/test-audio.cfg"
	AudioManager.set_volume("SFX", 0.31)
	AudioManager.set_muted(true)
	check(not AudioManager.play_sound("bang"), "mute blocks effects")
	AudioManager.volumes.SFX = 0.9
	AudioManager.load_settings()
	check(is_equal_approx(AudioManager.volumes.SFX, 0.31) and AudioManager.muted, "preferences persist and reload")
	AudioManager.set_muted(false)
	AudioManager.unlocked = false
	check(not AudioManager.play_sound("button"), "Web unlock gate suppresses autoplay")
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	AudioManager._input(touch)
	check(AudioManager.unlocked, "first touch unlocks audio")
	var app: Node = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	app.show_audio_settings()
	check(app.root.find_child("VolumeMaster", true, false) != null, "Vietnamese audio settings UI")
	AudioManager.previous = {}
	NetworkManager.public_state = {"started": true, "match_id": 78, "round": 9, "players": [], "winner": "OUTLAWS WIN"}
	var before: int = played.size()
	AudioManager.observe_state()
	AudioManager.observe_state()
	check(played.size() == before, "reconnect/state refresh never replays start/win/turn")
	AudioManager.settings_path = "user://audio_settings.cfg"
	AudioManager.load_settings()
	print("PASS: %d audio assets, buses, deduplication, overlap, settings, UI and touch-unlock checks" % checks)
	for player in AudioManager.pool + AudioManager.world_pool + AudioManager.loops:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.15).timeout
	get_tree().quit()
