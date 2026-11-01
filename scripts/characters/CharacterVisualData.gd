class_name CharacterVisualData
extends RefCounted

static var cache: Dictionary = {}

static func presets() -> Dictionary:
	if cache.is_empty():
		cache = JSON.parse_string(FileAccess.get_file_as_string("res://resources/characters/visuals/base_visuals.json"))
	return cache

static func get_preset(id: String) -> Dictionary:
	return presets().get(id, {})
