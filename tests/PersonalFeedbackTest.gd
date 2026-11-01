extends Node

var checks := 0
var toast: Control
var state := {"match_id": 7, "players": [
	{"player_id": 1, "display_name": "Bạn"},
	{"player_id": 2, "display_name": "Văn Thắng"},
	{"player_id": 3, "display_name": "Khánh Băng"}]}

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("FAILED: " + message)
		get_tree().quit(1)
		assert(value, message)

func _ready() -> void:
	get_viewport().set_meta("match_css_size", Vector2(390, 844))
	var mobile_host := Control.new()
	mobile_host.size = Vector2(390, 844)
	add_child(mobile_host)
	toast = load("res://scripts/ui/PersonalEventToast.gd").new()
	mobile_host.add_child(toast)
	toast.reset_for_match(7)
	await get_tree().process_frame
	test_bang_and_reaction()
	test_private_transfer_and_public_equipment()
	test_deduplication_and_order()
	test_mobile_placement()
	test_reconnect_does_not_replay()
	print("PASS: %d authoritative personal feedback, privacy, queue and mobile checks" % checks)
	get_tree().quit()

func test_bang_and_reaction() -> void:
	toast.consume_event({"kind": "bang", "player": 2, "target": 1, "match_id": 7, "audio_event_id": "f:bang"}, 1, state)
	check(toast.history.size() == 1 and "Văn Thắng" in toast.history[0] and "BANG" in toast.history[0], "local BANG toast includes source name")
	toast.consume_reaction({"request_id": 41, "reaction_type": "dodge", "source_player_id": 2}, state)
	check(toast.pending.any(func(item): return "Văn Thắng" in str(item.text) and "NÉ" in str(item.detail)), "Missed reaction prompt names shooter and required response")

func test_private_transfer_and_public_equipment() -> void:
	toast.consume_event({"kind": "transfer", "player": 1, "to": 3, "steal": true, "hidden": true,
		"card": {"card_data_id": "winchester"}, "match_id": 7, "audio_event_id": "f:hidden"}, 1, state)
	var hidden_text := str(toast.pending.back().text)
	check("Khánh Băng" in hidden_text and "ngẫu nhiên" in hidden_text, "hidden-hand transfer identifies actor and random card")
	check(not "Winchester" in hidden_text and not "winchester" in hidden_text, "hidden-hand identity is never leaked even if payload is malformed")
	toast.consume_event({"kind": "transfer", "player": 1, "to": 2, "steal": false, "hidden": false,
		"from_zone": "weapon", "card": {"card_data_id": "winchester"}, "match_id": 7, "audio_event_id": "f:equipment"}, 1, state)
	check(str(CardData.data("winchester").name) in str(toast.pending.back().text), "face-up equipment name may be shown")

func test_deduplication_and_order() -> void:
	var before: int = toast.pending.size()
	var damage := {"kind": "damage", "player": 1, "amount": 1, "source": 2, "match_id": 7, "audio_event_id": "f:damage"}
	toast.consume_event(damage, 1, state)
	toast.consume_event(damage, 1, state)
	check(toast.pending.size() == before + 1, "duplicate network event creates one toast")
	toast.consume_event({"kind": "heal", "player": 1, "amount": 1, "match_id": 7, "audio_event_id": "f:heal"}, 1, state)
	check("mất 1 máu" in str(toast.pending[-2].text) and "+1 HP" in str(toast.pending[-1].text), "queued events preserve authoritative order")

func test_mobile_placement() -> void:
	await get_tree().process_frame
	var rect := Rect2(toast.panel.position, toast.panel.size)
	var hand_top := 844.0 - 125.0
	check(rect.position.y >= 844.0 * 0.19 and rect.end.y < hand_top, "mobile toast stays below browser top and above hand/reaction area")
	check(toast.panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "toast never blocks mobile taps")

func test_reconnect_does_not_replay() -> void:
	var before: int = toast.history.size() + toast.pending.size()
	toast.reset_for_match(7)
	toast.consume_event({"kind": "bang", "player": 2, "target": 1, "match_id": 7, "audio_event_id": "f:bang"}, 1, state)
	check(toast.history.size() + toast.pending.size() == before, "same-match reconnect cannot replay seen events")
	toast.reset_for_match(8)
	toast.consume_event({"kind": "damage", "player": 1, "amount": 1, "match_id": 7, "audio_event_id": "f:stale"}, 1, {"match_id": 8, "players": state.players})
	check(toast.current.is_empty() and toast.pending.is_empty(), "stale previous-match event is ignored")
