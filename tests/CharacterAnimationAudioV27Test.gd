extends Node

var checks: int = 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("V27 CHARACTER/AUDIO FAILED: " + message)

func _ready() -> void:
	await get_tree().process_frame
	var presets: Dictionary = CharacterVisualData.presets()
	check(presets.size() == 16, "all 16 base character presets remain available")
	for character_id in presets:
		var avatar := PlayerAvatar.new()
		add_child(avatar)
		avatar.build(Color("#9b6847"))
		avatar.apply_character(character_id, false)
		var hitbox_transform: Transform3D = avatar.picking_area.transform
		check(is_instance_valid(avatar.tea_glass) and not avatar.tea_glass.visible, character_id + " owns a cached dedicated iced-tea prop")
		avatar.act("downed")
		check(avatar.downed and not avatar.dead, character_id + " downed state remains alive")
		avatar.act("recover")
		check(not avatar.downed and not avatar.dead, character_id + " recovery clears only the downed pose")
		avatar.act("iced_tea")
		check(avatar.tea_glass.visible and not avatar.bottle.visible, character_id + " iced tea is visually distinct from Beer")
		avatar.act("victory")
		check(is_instance_valid(avatar.motion), character_id + " victory animation is available")
		check(avatar.picking_area.transform == hitbox_transform, character_id + " cosmetic actions never move the targeting hitbox")
		avatar.act("death")
		check(avatar.dead and not avatar.downed, character_id + " confirmed death is distinct from downed")
		avatar.queue_free()

	var required_cues := {
		"bang": 4, "schofield": 3, "remington": 3, "carabine": 3,
		"winchester": 3, "volcanic": 3, "draw": 4, "play": 3,
		"hit": 3, "dodge": 2, "death": 1, "beer": 1,
		"iced_tea_drink": 1, "sheriff_win": 1, "outlaw_win": 1, "renegade_win": 1
	}
	for cue in required_cues:
		var paths: Array = AudioManager.manifest.get(cue, [])
		check(paths.size() >= int(required_cues[cue]), "licensed cue pool has required variants: " + cue)
		for path in paths:
			check(ResourceLoader.exists(path) or FileAccess.file_exists(path), "audio asset exists: " + path)
	var license: String = FileAccess.get_file_as_string("res://assets/audio/LICENSE.md")
	check(license.contains("Original procedural audio") and license.contains("No recordings"), "audio provenance documents original project synthesis")
	var bus_names: Dictionary = {}
	for index in range(AudioServer.bus_count):
		var bus_name: String = AudioServer.get_bus_name(index)
		check(not bus_names.has(bus_name), "audio bus is declared once: " + bus_name)
		bus_names[bus_name] = true
	for required_bus in ["Master", "Music", "Ambient", "SFX", "WorldSFX", "UI", "Character", "Weapons", "Cards"]:
		check(bus_names.has(required_bus), "professional mix bus exists: " + required_bus)
	var table_logic: Node3D = load("res://scripts/game/TableView.gd").new()
	check(table_logic._role_wins("SHERIFF", "SHERIFF TEAM WINS") and table_logic._role_wins("DEPUTY", "SHERIFF TEAM WINS"), "Sheriff team receives victory animation")
	check(table_logic._role_wins("OUTLAW", "OUTLAWS WIN") and not table_logic._role_wins("RENEGADE", "OUTLAWS WIN"), "Outlaw result animates only its winning role")
	check(table_logic._role_wins("RENEGADE", "RENEGADE WINS"), "Renegade receives solo victory animation")
	check(table_logic._role_wins("DEPUTY", "DEPUTY WINS") and not table_logic._role_wins("OUTLAW", "DEPUTY WINS"), "small-table Deputy result remains deterministic")
	table_logic.free()

	if failures.is_empty():
		print("PASS: %d V27 character-state, hitbox, audio-variant, provenance and bus checks" % checks)
		get_tree().quit(0)
	else:
		print("FAIL: %d/%d V27 checks failed" % [failures.size(), checks])
		get_tree().quit(1)
