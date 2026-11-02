class_name RoomProtocol
extends RefCounted

const VERSION := 1
const CHAT_MAX_LENGTH := 160
const INTENTS: Dictionary = {
	"SET_READY": "ready", "START_MATCH": "start", "SELECT_CHARACTER": "character",
	"PLAY_CARD": "play", "END_TURN": "end", "DISCARD_CARD": "discard",
	"REACTION": "reaction", "ABILITY_ACTION": "ability",
	"SPECTATE_MATCH": "spectate", "REMATCH_READY": "rematch",
	"RESTART_MATCH": "restart", "RETURN_TO_LOBBY": "lobby"
}

static func encode(action: String, args: Dictionary) -> Dictionary:
	var types: Array = INTENTS.keys().filter(func(key): return INTENTS[key] == action)
	if types.is_empty():
		return {}
	var payload := args.duplicate(true)
	if payload.has("card"):
		payload["card_instance_id"] = payload.card
		payload.erase("card")
	if payload.has("target"):
		payload["target_player_id"] = payload.target
		payload.erase("target")
	return {"type": types[0], "payload": payload, "version": VERSION}

static func encode_chat(text: String) -> Dictionary:
	# Identity is deliberately absent. The server derives it from the authenticated
	# socket/session and ignores any forged fields a modified client may add.
	return {"type": "CHAT_SEND", "payload": {"text": text}, "version": VERSION}

static func decode(kind: String, payload: Dictionary) -> Dictionary:
	var args := payload.duplicate(true)
	if args.has("card_instance_id"):
		args["card"] = args.card_instance_id
		args.erase("card_instance_id")
	if args.has("target_player_id"):
		args["target"] = args.target_player_id
		args.erase("target_player_id")
	# JSON numbers arrive as float; cast only integral, bounded numbers at the boundary.
	for key in ["card", "target", "request", "match_id"]:
		if args.has(key):
			if not integral(args[key]):
				return {}
			args[key] = int(args[key])
	if args.has("cards"):
		if not args.cards is Array or args.cards.size() > 2:
			return {}
		for value in args.cards:
			if not integral(value):
				return {}
		args.cards = args.cards.map(func(value): return int(value))
	if not INTENTS.has(kind):
		return {}
	return {"action": INTENTS[kind], "args": args}

static func integral(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and absf(float(value)) < 2147483647

static func normalize_private(snapshot: Dictionary) -> Dictionary:
	var result := snapshot.duplicate(true)
	# Dictionary keys are strings in JSON. Internal UI expects numeric instance/player keys.
	for key in ["targets", "target_info", "disabled_reasons"]:
		var normalized: Dictionary = {}
		for item in result.get(key, {}):
			if str(item).is_valid_int():
				var value: Variant = result[key][item]
				if key == "targets":
					value = value.map(func(id): return int(id))
				normalized[int(item)] = value
		result[key] = normalized
	return result

static func normalize_numbers(value: Variant) -> Variant:
	if value is float and integral(value):
		return int(value)
	if value is Array:
		return value.map(func(entry): return normalize_numbers(entry))
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[key] = normalize_numbers(value[key])
		return result
	return value
