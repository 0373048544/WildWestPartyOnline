# Dedicated Godot room server

Run from the project root:

    godot --headless --path . server/DedicatedServer.tscn -- --development

Default address: 127.0.0.1:7000. Set WWPO_BIND only when intentionally testing from another machine. --port=7000 chooses a port. --development allows the existing two-player debug role pool; without it the server requires 4–7 ready players even when using a debug executable. Release executables always require 4–7.

Each room owns one instance of the existing GameManager script and one RoomBridge. The server is not a participant. Player IDs start at 100 and never encode roles or administration. Room membership and host ownership are separate from randomized game roles. No rules are implemented in JavaScript.

## Protocol v1

Client frames are WebSocket text JSON:

    {"version":1,"type":"PLAY_CARD","payload":{"card_instance_id":123,"target_player_id":105}}

Handshake: CREATE_ROOM {player_name}, JOIN_ROOM {player_name,room_code}, RESUME_SESSION {session_token}. Reply: ROOM_CREATED, JOIN_ACCEPTED or SESSION_RESUMED with {player_id,room_code,host_player_id,session_token}. Only the admitted connection gets the token.

Intents: SET_READY, START_MATCH, SELECT_CHARACTER {character}, PLAY_CARD, END_TURN, DISCARD_CARD {card_instance_id}, REACTION {request,accept,card_instance_id?,cards?,option?}, ABILITY_ACTION {cards:[id,id]}, RESTART_MATCH, RETURN_TO_LOBBY, LEAVE_ROOM. The server derives player identity from the connection and validates intents through the existing GameManager.

STATE {public,private} is a per-connection atomic envelope. public is the sanitized shared snapshot plus room_code, host_player_id and revision. private is only that recipient's hand/role/options/reaction/valid targets. This prevents UI from mixing public and private revisions. A STATE envelope is constructed and sent separately for each recipient; it is never broadcast with a list of all private states.

VISUAL_EVENT and TABLE_EVENT carry only cosmetic data already allowed by the game. JOIN_REJECTED/ERROR carry Vietnamese {message,fatal}. PING/PONG provide liveness. JSON number conversion and numeric dictionary keys are normalized in RoomProtocol at the boundary.

No debug gameplay command is accepted through the Web protocol.

## Recovery and cleanup

Temporary socket loss reserves membership for 45 seconds. Lobby ready becomes false, host administration transfers to a connected room member, and a public connection indicator changes. During a live match the authoritative player remains in play during this grace period; reaction/character timers continue. Resume restores the same player, cards, character and role.

After the grace period the existing disconnect/forfeit path applies. Explicit LEAVE_ROOM forfeits immediately. Host migration changes administration only, never Sheriff or game roles. Empty rooms are deleted. Rooms with no player actions for two hours expire. All state is in memory: server restart invalidates sessions and rooms.

This is a local-development milestone. Future public hosting needs TLS/WSS termination, origin policy, operational monitoring and a decision about durable session/state storage. It has not been deployed publicly.
