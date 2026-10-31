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
