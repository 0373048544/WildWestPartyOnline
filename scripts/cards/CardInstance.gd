class_name CardInstance
extends RefCounted

const RANKS := ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]
const SUITS := {"HEART": "♥", "DIAMOND": "♦", "CLUB": "♣", "SPADE": "♠"}

static func rank_label(rank: Variant) -> String:
	# Numeric input is supported only for legacy debug/test constructors.
	return str({1: "A", 11: "J", 12: "Q", 13: "K"}.get(rank, str(rank)))

static func corner(card: Dictionary) -> String:
	return rank_label(card.get("rank", "")) + str(SUITS.get(card.get("suit", ""), ""))

static func suit_color(suit: String) -> Color:
	return Color("#a5212c") if suit in ["HEART", "DIAMOND"] else Color("#18222c")

static func make(uid: int, data_id: String, suit: String, rank: Variant) -> Dictionary:
	return {"instance_id": uid, "card_data_id": data_id, "suit": suit, "rank": rank_label(rank)}
