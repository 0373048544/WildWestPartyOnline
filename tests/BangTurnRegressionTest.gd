extends Node

var checks: int = 0
var events: Array = []
var error_text: String = ""

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		push_error("BANG REGRESSION FAILED: "+label)
		get_tree().quit(1)
		assert(ok,label)

func setup() -> void:
	GameManager.clear()
	for id in range(1,5):
		GameManager.add_player(id,"Player %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()
	GameManager.selection.expire(GameManager)
	GameManager.flow.jobs.clear()
	GameManager.reactions.active = {}
	GameManager.turns.current_player = 1
	GameManager.turns.phase = "ACTION_PHASE"
	for p in GameManager.players.values():
		p.hand.clear()
		p.ability_id = ""
		p.current_hp = 4
		p.max_hp = 4
	GameManager.players[1].role = PlayerState.Role.SHERIFF
	GameManager.rate_limits.clear()
	events.clear()
	error_text = ""

func give(id: int, key: String) -> Dictionary:
	var c := CardInstance.make(GameManager.deck.next_id,key,"CLUB",8)
	GameManager.deck.next_id += 1
	GameManager.players[id].hand.append(c)
	return c

func play(id: int, key: String, target: int) -> Dictionary:
	var c := give(id,key)
	GameManager.rate_limits.clear()
	GameManager.handle_intent(id,"play",{"card":c.instance_id,"target":target})
	return c

func answer(id: int, args: Dictionary) -> void:
	args["request"] = GameManager.reactions.active.request_id
	GameManager.rate_limits.clear()
	GameManager.handle_intent(id,"reaction",args)

func drain() -> void:
	for _step in range(12):
		if GameManager.reactions.active.is_empty():
			break
		answer(GameManager.reactions.active.target_player_id,{"accept":false})

func _ready() -> void:
	NetworkManager.table_event.connect(func(e): events.append(e.duplicate(true)))
	NetworkManager.visual_event.connect(func(a,k,t): events.append({"actor":a,"animation":k,"target":t}))
	NetworkManager.error_received.connect(func(message): error_text=message)
	setup()
	var dodge := give(2,"dodge")
	var first := play(1,"shoot",2)
	check(GameManager.find_card(1,first.instance_id).is_empty() and GameManager.players[1].bang_played_this_turn,"first BANG succeeds and sets authoritative flag")
	answer(2,{"accept":true,"card":dodge.instance_id})
	check(GameManager.players[2].current_hp==4 and not GameManager.players[2].bang_played_this_turn,"Missed outside turn neither damages nor consumes defender BANG allowance")
	check(GameManager.players[1].bang_played_this_turn,"Missed does not reset attacker's allowance")
	var second := give(1,"shoot")
	var before_log: Array = GameManager.log_lines.duplicate(true)
	var before_events: int = events.size()
	var before_discard: int = GameManager.deck.discard_pile.size()
	for _spam in range(8):
		GameManager.rate_limits.clear()
		GameManager.handle_intent(1,"play",{"card":second.instance_id,"target":2})
	check(error_text=="Bạn đã dùng BANG! trong lượt này.","server returns exact disabled reason")
	check(not GameManager.find_card(1,second.instance_id).is_empty() and GameManager.players[2].current_hp==4,"forged repeated BANG retains card and HP")
	check(GameManager.log_lines==before_log and events.size()==before_events and GameManager.deck.discard_pile.size()==before_discard,"rejected BANG has no extra log, animation, event or discard")
	check(GameManager.private_snapshot(1).targets[second.instance_id].is_empty() and GameManager.private_snapshot(1).disabled_reasons[second.instance_id]==error_text,"owner private snapshot disables remaining BANG")
	GameManager.begin_turn(1)
	drain()
	check(not GameManager.players[1].bang_played_this_turn,"next turn resets flag")
	GameManager.resolver.play(GameManager,1,second.instance_id,2)
	check(GameManager.find_card(1,second.instance_id).is_empty(),"same BANG is usable next turn")
	drain()
	for effect in ["cat_balou","panic"]:
		setup()
		play(1,"shoot",2)
		drain()
		for _copy in range(2):
			give(2,"dodge")
			var brown := play(1,effect,2)
			check(GameManager.find_card(1,brown.instance_id).is_empty() and GameManager.reactions.active.reaction_type=="transfer","BANG plus repeat legal "+effect)
			answer(1,{"accept":true,"option":"hand"})
		check(GameManager.players[1].bang_played_this_turn,"non-BANG cards do not reset allowance")
	for exception in ["unlimited_shoot","volcanic"]:
		setup()
		if exception=="unlimited_shoot":
			GameManager.players[1].ability_id=exception
		else:
			play(1,"volcanic",1)
		for _shot in range(3):
			var c := play(1,"shoot",2)
			check(GameManager.find_card(1,c.instance_id).is_empty(),"existing exception reused: "+exception)
			drain()
	for kind in ["showdown","indians"]:
		setup()
		var response := give(2,"shoot")
		play(1,kind,2 if kind=="showdown" else 1)
		check(GameManager.reactions.active.target_player_id==2,"reaction prompt selects responder")
		answer(2,{"accept":true,"card":response.instance_id})
		check(GameManager.find_card(2,response.instance_id).is_empty() and not GameManager.players[2].bang_played_this_turn,"reaction BANG does not set normal-turn flag for "+kind)
		drain()
		check(not GameManager.players[1].bang_played_this_turn,"playing "+kind+" does not use normal BANG")
	setup()
	GameManager.players[1].bang_played_this_turn = true
	play(2,"shoot",1) # Wrong turn: cannot spend any card.
	var reaction_card := give(1,"shoot")
	GameManager.flow.push({"kind":"duel","source":2,"target":1})
	GameManager.flow.run()
	answer(1,{"accept":true,"card":reaction_card.instance_id})
	check(GameManager.find_card(1,reaction_card.instance_id).is_empty() and GameManager.players[1].bang_played_this_turn,"Duel response remains legal after normal BANG and does not reset flag")
	GameManager.clear()
	print("PASS: %d authoritative BANG, normal brown-card, reaction and mutation regression checks" % checks)
	get_tree().quit()
