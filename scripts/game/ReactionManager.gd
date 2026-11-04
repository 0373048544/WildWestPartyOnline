class_name ReactionManager
extends RefCounted

enum ReactionType { DODGE_SHOT, SURVIVE_WITH_DRINK, DUEL_RESPONSE, INDIANS_RESPONSE, GENERAL_STORE_PICK, CHARACTER_DRAW_CHOICE, LUCKY_DUKE_CHOICE }
var active: Dictionary = {}
var sequence: int = 0

func create(target: int, kind: String, context: Dictionary, payload: Dictionary = {}) -> void:
	sequence += 1
	var timeout_seconds: float = float(payload.get(
		"timeout_seconds",
		15.0 if payload.has("choices") or payload.has("cards") else 8.0
	))
	active = {"request_id": sequence, "target_player_id": target, "reaction_type": kind,
		"source_player_id": context.get("source", 0),
		"allowed_actions": payload.get("allowed_actions", ["choose", "pass"]),
		"allowed_card_types": payload.get("allowed_cards", []),
		# required_count is the immutable total for UI/reconnect. The remaining
		# requirement stays authoritative in context.required.
		"required_count": context.get("total_required", context.get("required", 1)),
		"resolved_count": context.get("resolved", 0),
		"timeout_seconds": timeout_seconds,
		"deadline": Time.get_ticks_msec() + int(timeout_seconds * 1000.0),
		"context": context, "payload": payload}

func expired() -> bool:
	return not active.is_empty() and Time.get_ticks_msec() >= active.deadline

func private_prompt(id: int) -> Dictionary:
	if active.is_empty() or active.target_player_id != id:
		return {}
	var result := active.duplicate(true)
	result.erase("context")
	result.erase("deadline")
	result.merge(result.payload, true)
	result.erase("payload")
	result["remaining"] = maxf(0.0, (active.deadline - Time.get_ticks_msec()) / 1000.0)
	if active.reaction_type == "transfer":
		# Public player identifier needed to pick visible zones; no hidden card identities.
		result["zone_player_id"] = int(active.context.get("target", 0))
	return result
