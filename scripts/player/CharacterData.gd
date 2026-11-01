class_name CharacterData
extends RefCounted

static var cache: Dictionary = {}

static func definitions() -> Dictionary:
	if cache.is_empty():
		var rows: Array = JSON.parse_string(FileAccess.get_file_as_string("res://resources/characters/characters.json"))
		for row in rows:
			cache[row.character_id] = row
	return cache

static func get_data(id: String) -> Dictionary:
	return definitions().get(id, {})

static func ability_icon(id: String) -> String:
	return str({"damage_draw": "+", "draw_reveal": "?", "convert": "↔", "damage_steal": "←",
		"draw_steal": "←", "innate_barrel": "○", "draw_choose": "3→2", "judge_choose": "2→1",
		"distance_defense": "+1", "draw_discard": "↑", "distance_sight": "−1", "discard_heal": "+",
		"double_dodge": "2", "empty_draw": "0→1", "death_collect": "←", "unlimited_shoot": "∞"}.get(id, "◆"))
