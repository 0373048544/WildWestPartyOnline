class_name DeckManager
extends RefCounted

var draw_pile: Array = []
var discard_pile: Array = []
var next_id: int = 1

func validate_definition(definition: Variant) -> String:
	if not definition is Dictionary or not definition.get("cards") is Array or definition.get("expected_count") != 80 or definition.cards.size() != 80:
		return "Deck manifest expected 80 cards."
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/cards/base_manifest.json"))
	var expected: Dictionary = {}
	for id in manifest.cards:
		for pair in manifest.cards[id]:
			var key: String = id + ":" + pair
			expected[key] = int(expected.get(key, 0)) + 1
	for entry in definition.cards:
		if not entry is Dictionary or not entry.get("rank") is String or not CardInstance.RANKS.has(entry.rank) or not CardInstance.SUITS.has(entry.get("suit", "")) or not CardData.definitions().has(entry.get("card_data_id", "")):
			return "Invalid card ID, rank or suit in base deck."
		var key: String = entry.card_data_id + ":" + entry.rank + ":" + entry.suit
		if int(expected.get(key, 0)) <= 0:
			return "Unexpected physical card: " + key
		expected[key] -= 1
	if expected.values().any(func(count): return count != 0):
		return "Missing physical card in base deck."
	return ""

func reset() -> bool:
	draw_pile.clear()
	discard_pile.clear()
	next_id = 1
	var definition: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://resources/cards/base_deck.json"))
	var problem := validate_definition(definition)
	if not problem.is_empty():
		push_error(problem)
		return false
	var counts: Dictionary = {}
	for entry in definition.cards:
		counts[entry.card_data_id] = int(counts.get(entry.card_data_id, 0)) + 1
		draw_pile.append(CardInstance.make(next_id, entry.card_data_id, entry.suit, entry.rank))
		next_id += 1
	for id in CardData.definitions():
		if int(counts.get(id, 0)) != int(CardData.data(id).count):
			push_error("Invalid card quantity: " + id)
			draw_pile.clear()
			return false
	draw_pile.shuffle()
	return true

func draw() -> Dictionary:
	if draw_pile.is_empty():
		draw_pile = discard_pile
		discard_pile = []
		draw_pile.shuffle()
	if draw_pile.is_empty():
		return {}
	return draw_pile.pop_back()

func discard(card: Dictionary) -> void:
	if not card.is_empty():
		discard_pile.append(card)
