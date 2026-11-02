extends Node

var checks := 0
var failures: Array[String] = []
var toast: Control
var state := {"match_id":7, "players":[{"player_id":1,"display_name":"Bạn"},{"player_id":2,"display_name":"Văn Thắng"},{"player_id":3,"display_name":"Khánh Băng"}]}

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("PERSONAL FEEDBACK FAILED: " + message)

func _ready() -> void:
	get_viewport().set_meta("match_css_size", Vector2(390, 844))
	var host := Control.new()
	host.size = Vector2(390, 844)
	add_child(host)
	toast = load("res://scripts/ui/PersonalEventToast.gd").new()
	host.add_child(toast)
	toast.reset_for_match(7)
	await get_tree().process_frame
	toast.consume_event({"kind":"bang","player":2,"target":1,"match_id":7,"event_id":"f:bang"}, 1, state)
	check(toast.current.is_empty() and toast.pending.is_empty(), "local BANG is not duplicated outside ReactionBanner")
	var damage := {"kind":"damage","player":1,"amount":1,"source":2,"match_id":7,"event_id":"f:damage"}
	toast.consume_event(damage, 1, state)
	var seen_before: int = toast.seen.size()
	var queued_before: int = toast.pending.size()
	toast.consume_event(damage, 1, state)
	check(toast.seen.size() == seen_before and toast.pending.size() == queued_before, "duplicate event ID presents once")
	var hidden: Dictionary = toast._event_item({"kind":"transfer","player":1,"to":3,"steal":true,"hidden":true,"card":{"card_data_id":"winchester"}}, 1, state)
	check(str(hidden.text).contains("Khánh Băng") and not str(hidden.text).contains("Winchester"), "hidden transfer never leaks card identity")
	var equipment: Dictionary = toast._event_item({"kind":"transfer","player":1,"to":2,"steal":false,"hidden":false,"from_zone":"weapon","card":{"card_data_id":"winchester"}}, 1, state)
	check(str(equipment.text).contains(str(CardData.data("winchester").name)), "public equipment may show its name")
	var bart: Dictionary = toast._event_item({"kind":"ability","player":1,"ability_id":"damage_draw","amount":3}, 1, state)
	var gringo: Dictionary = toast._event_item({"kind":"ability","player":1,"ability_id":"damage_steal","amount":2}, 1, state)
	var suzy: Dictionary = toast._event_item({"kind":"ability","player":1,"ability_id":"empty_draw","amount":1}, 1, state)
	check(str(bart.text).contains("RÚT 3 LÁ"), "Bart feedback aggregates multi-damage")
	check(str(gringo.text).contains("LẤY 2 LÁ"), "El Gringo reports actual transfers")
	check(str(suzy.text).contains("HẾT BÀI"), "Suzy refill feedback is explicit")
	await get_tree().process_frame
	var rect := Rect2(toast.panel.position, toast.panel.size)
	check(rect.position.y >= 0 and rect.end.y < 719, "mobile toast stays above hand/browser toolbar")
	check(toast.panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "toast never blocks touch")
	toast.reset_for_match(7)
	toast.consume_event(damage, 1, state)
	check(toast.seen.size() == seen_before, "same-match refresh cannot replay seen event")
	toast.reset_for_match(8)
	toast.consume_event({"kind":"damage","player":1,"match_id":7,"event_id":"f:stale"}, 1, {"match_id":8,"players":state.players})
	check(toast.current.is_empty() and toast.pending.is_empty(), "stale previous-match event is ignored")
	if failures.is_empty():
		print("PASS: %d authoritative feedback, privacy, dedupe, ability and mobile checks" % checks)
		get_tree().quit()
	else:
		push_error("FAIL: %d/%d personal feedback checks failed" % [failures.size(), checks])
		get_tree().quit(1)
