extends Node

var checks := 0
var played: Array = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("AUDIO REWORK FAILED: " + message)
		get_tree().quit(1)
		assert(value, message)

func _ready() -> void:
	await get_tree().process_frame
	AudioManager.enabled = true
	AudioManager.unlocked = true
	AudioManager.muted = false
	AudioManager.sound_played.connect(func(key, bus): played.append({"key": key, "bus": bus}))
	AudioManager.update_mix_policy({})
	AudioManager.start_ambience()
	check(AudioManager.music_allowed, "menu permits music")
	var music: AudioStreamPlayer = AudioManager.loops[1]
	check(music.playing, "menu loop playing")
	var preference: float = AudioManager.volumes.Music
	for phase in ["TURN_START", "DRAW_PHASE", "ACTION_PHASE", "REACTION", "DISCARD_PHASE", "TURN_END"]:
		AudioManager.update_mix_policy({"started": true, "phase": phase, "winner": ""})
		AudioManager._process(0.5)
		check(not AudioManager.music_allowed and not music.playing, "no music source during active phase " + phase)
		check(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) <= -80, "Music bus faded to silence " + phase)
		check(AudioManager.loops[0].playing, "environmental ambience remains during " + phase)
	check(AudioManager.volumes.Music == preference, "policy never overwrites saved user music preference")
	for state in [{"started": false, "phase": "WAITING"}, {"started": true, "phase": "GAME_OVER", "winner": "OUTLAWS WIN"}, {"started": true, "phase": "CHARACTER_SELECTION"}]:
		AudioManager.update_mix_policy(state)
		AudioManager._process(0.5)
		check(AudioManager.music_allowed and music.playing, "music may return only in allowed state")
	AudioManager.update_mix_policy({"started": true, "phase": "REACTION"})
	AudioManager.consume_event({"audio_event_id": "rework:duel", "kind": "duel"})
	AudioManager._process(0.5)
	check(AudioManager.duel_active and AudioManager.duck_gain <= 0.35 and not music.playing, "Duel uses quieter ambience, never looping music")
	AudioManager.consume_event({"audio_event_id": "rework:fuse", "kind": "judge", "purpose": "dynamite"})
	AudioManager._process(0.5)
	check(AudioManager.dynamite_active and AudioManager.duck_gain <= 0.18, "Dynamite strongly ducks ambience")
	AudioManager.consume_event({"audio_event_id": "rework:safe", "kind": "dynamite_pass"})
	check(not AudioManager.dynamite_active, "safe Dynamite releases tension")
	check((AudioManager.pool + AudioManager.world_pool).all(func(p): return not p.playing or p.get_meta("cue", "") != "fuse"), "safe result stops fuse immediately")
	for pair in [["bang", 4], ["remington", 3], ["carabine", 3], ["winchester", 3], ["draw", 4], ["play", 3], ["discard", 3], ["ricochet", 4], ["hit", 3], ["wood_creak", 4], ["jail", 2], ["explosion", 2]]:
		check(AudioManager.manifest[pair[0]].size() >= pair[1], "minimum variants " + pair[0])
	var hashes: Dictionary = {}
	for key in ["bang", "schofield", "remington", "carabine", "winchester", "volcanic"]:
		var stream: AudioStreamWAV = AudioStreamWAV.load_from_file(AudioManager.manifest[key][0])
		hashes[hash(stream.data)] = true
	check(hashes.size() == 6, "six weapon profiles have different waveforms")
	AudioManager.consume_event({"audio_event_id": "rework:shot", "kind": "animation", "animation": "shoot"})
	var deadline: int = Time.get_ticks_msec() + 1000
	while not played.any(func(p): return p.key == "bang") and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(played.any(func(p): return p.key == "cock") and played.any(func(p): return p.key == "bang" and p.bus == "Weapons"), "mechanical cock precedes shot on Weapons bus: " + str(played))
	var count: int = played.filter(func(p): return p.key in ["bang", "cock"]).size()
	AudioManager.consume_event({"audio_event_id": "rework:shot", "kind": "animation", "animation": "shoot"})
	await get_tree().create_timer(0.2).timeout
	check(played.filter(func(p): return p.key in ["bang", "cock"]).size() == count, "duplicate shot cannot schedule more audio")
	for player in AudioManager.pool + AudioManager.world_pool + AudioManager.loops:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.15).timeout
	print("PASS: %d music policy, ambience/tension, weapon variants, shot sequencing and deduplication checks" % checks)
	get_tree().quit()
