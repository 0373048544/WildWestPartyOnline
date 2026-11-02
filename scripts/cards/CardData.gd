class_name CardData
extends RefCounted

enum CardType { ACTION, WEAPON, EQUIPMENT, REACTION }
enum TargetType { SELF, SINGLE_PLAYER, ALL_OTHER_PLAYERS, NO_TARGET }
enum EffectType { ATTACK, DODGE, HEAL, DRAW, DISCARD, STEAL, EQUIP_WEAPON, EQUIP_PASSIVE, DUEL, GROUP_HEAL, STORE, GATLING, INDIANS, JAIL, DYNAMITE, DEPARTMENT_STORE }
const QUICK_EQUIPMENT_IDS: Array[String] = ["horse", "barrel", "spyglass"]
static var cache: Dictionary = {}

static func definitions() -> Dictionary:
	if cache.is_empty():
		cache = JSON.parse_string(FileAccess.get_file_as_string("res://resources/cards/definitions.json"))
	return cache

static func canonical_id(id: String) -> String:
	return "schofield" if id == "rifle" else id

static func data(id: String) -> Dictionary:
	return definitions().get(canonical_id(id), {})

static func is_quick_equipment(id: String) -> bool:
	return QUICK_EQUIPMENT_IDS.has(canonical_id(id))

