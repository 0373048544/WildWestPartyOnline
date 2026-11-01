class_name DrawPhaseResolver
extends RefCounted

var handlers: Dictionary = {"draw_reveal": black_jack, "draw_steal": jesse, "draw_choose": kit, "draw_discard": pedro}

func begin(game: Node, id: int) -> void:
	game.turns.phase = "DRAW_PHASE"
	var ability: String = game.players[id].ability_id
	if handlers.has(ability):
		handlers[ability].call(game, id)
	else:
		game.draw_cards(id, 2)

func black_jack(game: Node, id: int) -> void:
	var drawn: Array = game.draw_cards(id, 2)
	if drawn.size() >= 2:
		var card: Dictionary = drawn[1]
		game.emit_event("CARD_REVEALED", id, {"kind": "reveal", "card": card.duplicate(), "reason": "black_jack"})
		game.record("%s lộ lá rút thứ hai: %s." % [game.players[id].display_name, game.card_text(card)])
		if ["HEART", "DIAMOND"].has(card.suit):
			game.draw_cards(id, 1)

func jesse(game: Node, id: int) -> void:
	var choices: Array = [{"id": "deck", "label": "Rút từ chồng bài"}]
	for p in game.players.values():
		if p.player_id != id and p.is_alive and not p.hand.is_empty():
			choices.append({"id": str(p.player_id), "label": "Lấy ngẫu nhiên từ " + p.display_name})
	game.flow.prompt(id, "draw_steal", {"source": id}, {"choices": choices, "title": "JESSE JONES • CHỌN LÁ RÚT ĐẦU"})

func pedro(game: Node, id: int) -> void:
	var choices: Array = [{"id": "deck", "label": "Rút từ chồng bài"}]
	if not game.deck.discard_pile.is_empty():
		choices.append({"id": "discard", "label": "Lấy lá bỏ: " + game.card_text(game.deck.discard_pile.back())})
	game.flow.prompt(id, "draw_discard", {"source": id}, {"choices": choices, "title": "PEDRO RAMIREZ • CHỌN LÁ RÚT ĐẦU"})

func kit(game: Node, id: int) -> void:
	var cards: Array = []
	for _i in range(3):
		var card: Dictionary = game.deck.draw()
		if not card.is_empty():
			cards.append(card)
	if cards.size() <= 2:
		game.players[id].hand.append_array(cards)
		if not cards.is_empty():
			game.emit_event("CARD_DRAWN", id, {"kind": "draw", "count": cards.size()})
	else:
		game.flow.prompt(id, "draw_choose", {"source": id, "cards": cards}, {
			"cards": cards.duplicate(true), "pick_count": 2, "title": "KIT CARLSON • CHỌN 2 LÁ ĐỂ GIỮ"})
