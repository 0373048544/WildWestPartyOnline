class_name CardInstance
extends RefCounted

static func make(uid: int, data_id: String, suit: String, rank: int) -> Dictionary:
	return {"instance_id": uid, "card_data_id": data_id, "suit": suit, "rank": rank}
