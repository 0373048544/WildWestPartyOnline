extends Node

var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("TURN TERMINOLOGY FAILED: " + message)
		get_tree().quit(1)
		assert(value, message)

func _ready() -> void:
	var players := {
		1: PlayerState.new(1, "A", 0),
		2: PlayerState.new(2, "B", 1),
		3: PlayerState.new(3, "C", 2),
	}
	var turns := TurnManager.new()
	turns.record_action_turn(1, players)
	check(turns.action_turn_number == 1 and turns.round_number == 1, "first action turn starts round one")
	turns.record_action_turn(2, players)
	turns.record_action_turn(3, players)
	check(turns.action_turn_number == 3 and turns.round_number == 1, "one round contains all three action turns")
	turns.record_action_turn(1, players)
	check(turns.action_turn_number == 4 and turns.round_number == 2, "round increments only after full living-player cycle")
	players[3].is_alive = false
	turns.record_action_turn(2, players)
	check(turns.round_number == 2, "remaining player's action turn stays in current round")
	turns.record_action_turn(1, players)
	check(turns.action_turn_number == 6 and turns.round_number == 3, "dead player is excluded from next round boundary")
	check(not players[1].shoot_used_this_action_turn and not players[1].panic_used_this_action_turn and not players[1].cat_balou_used_this_action_turn, "action-turn flags use explicit names")
	check(not players[1].department_store_used_this_action_turn and not players[1].general_store_used_this_match, "turn and match flags use explicit lifetimes")
	print("PASS: %d action-turn, round and match terminology checks" % checks)
	get_tree().quit()
