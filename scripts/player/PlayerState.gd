class_name PlayerState
extends RefCounted

enum Role { SHERIFF, DEPUTY, OUTLAW, RENEGADE }
const ROLE_NAMES = ["SHERIFF", "DEPUTY", "OUTLAW", "RENEGADE"]
var player_id: int
var display_name: String
var seat_index: int
var role: int = Role.OUTLAW
var character_id: String = ""
var ability_id: String = ""
var max_hp: int = 4
var current_hp: int = 4
var hand: Array = []
var weapon: Dictionary = {}
var equipment: Dictionary = {}
var is_alive: bool = true
var is_connected: bool = true
var shoot_used_this_turn: bool = false
var ready: bool = false

func _init(id: int = 1, title: String = "Cowboy", seat: int = 0) -> void:
	player_id = id
	display_name = title
	seat_index = seat

func public_snapshot(reveal: bool = false, show_character: bool = true) -> Dictionary:
	return {"player_id": player_id, "display_name": display_name, "seat_index": seat_index,
		"current_hp": current_hp, "max_hp": max_hp, "hand_count": hand.size(),
		"weapon_id": weapon.get("card_data_id", ""), "equipment_ids": equipment.keys(),
		"is_alive": is_alive, "is_connected": is_connected, "ready": ready,
		"character_id": character_id if show_character else "",
		"weapon_range": DistanceManager.weapon_range(self),
		"character": CharacterData.get_data(character_id).duplicate(true) if show_character else {},
		"public_role": ROLE_NAMES[role] if reveal or not is_alive or role == Role.SHERIFF else ""}

func private_snapshot() -> Dictionary:
	return {"role": ROLE_NAMES[role], "hand": hand.duplicate(true)}
