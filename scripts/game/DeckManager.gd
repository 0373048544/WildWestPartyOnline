class_name DeckManager
extends RefCounted

var draw_pile: Array = []
var discard_pile: Array = []
var next_id: int = 1

func reset() -> void:
	draw_pile.clear()
	discard_pile.clear()
	next_id = 1
	var definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/cards/base_deck.json"))
	assert(definition.cards.size() == definition.expected_count and definition.expected_count == 80, "Invalid base deck count")
	var counts: Dictionary = {}
	for entry in definition.cards:
		assert(CardData.definitions().has(entry.card_data_id) and entry.rank >= 1 and entry.rank <= 13)
		assert(["HEART", "DIAMOND", "CLUB", "SPADE"].has(entry.suit))
		counts[entry.card_data_id] = int(counts.get(entry.card_data_id, 0)) + 1
		draw_pile.append(CardInstance.make(next_id, entry.card_data_id, entry.suit, entry.rank))
		next_id += 1
	for id in CardData.definitions():
		assert(int(counts.get(id, 0)) == int(CardData.data(id).count), "Invalid card quantity: " + id)
	draw_pile.shuffle()

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
