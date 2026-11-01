# Stabilization checkpoint

Scope: existing 80-card manifest and private two-character choice remain frozen. No new mechanics/content. Existing modular characters and AudioManager are retained.

Initial audit:
- Existing complete-match simulation covers 4–7 players and conservation of all 80 instances; repeat it after fixes.
- WebSocket intents have no duplicate identifier. Duplicate ready toggles can change state twice after the short input cooldown.
- Judgement presentation currently shrinks a revealed card away instead of visibly sending it to discard.
- Public/private snapshots must be compared at the same revision during multi-client QA.
- Player-info portraits rebuild whenever an open context receives a state refresh; cache unchanged presentation content.
- Primitive geometry remains box-heavy; improve existing modular parts, keeping per-avatar mesh budgets.
- Audio assets are original synthesized placeholders. Automated waveform/route checks cannot establish subjective sound quality; do not claim human listening acceptance.
- Desktop, Web and mobile-quality measurements must distinguish actual renderer data from headless logic checks and device emulation from a physical phone.

Evidence, corrections and any remaining acceptance limits are appended after testing.

## Corrections delivered

- Authenticated intents now carry session-scoped IDs; duplicate delivery remains suppressed after reconnect. Presentation IDs are also bounded and deduplicated independently of audio.
- Return reserved Lucky/Kit cards to discard on interrupted matches; discard leftover General Store stock after the final eligible chooser disconnects. Confirmed character choices survive disconnect, and dead players stay at zero HP.
- Judgement cards stay visible until the authoritative discard event moves them to the pile. Black Jack reveals return to hand. Player-info portraits survive unchanged refreshes and HP updates.
- Existing modular hats, sleeves, boots and facial expressions were refined. Table meshes/materials are shared where immutable.
- Compact nameplates use actual heart/card/star geometry, consistent minimum screen size, viewport bounds and separation. Targeting starts with no opponent selected; hover/touch previews have segmented curved guides and distinct vector reticles. Touch confirms on the second tap. Shot flecks last 0.08 seconds and have no collision or gameplay authority.
- Replaced the old menu loop with an original 16-bar saloon waltz. The Music prohibition during active play remains enforced; no gameplay waits for audio or VFX.

## Verification evidence

- Headless suites pass: targeting (57 checks, including seven-player mobile label bounds/separation), tabletop UX (39), VFX (20), character visuals (187), stabilization (14), music policy (44), audio (113), rules (1,935), canonical deck/full matches (3,780), discard zones (78), character choice (8,814). Localization also passes after compact-label text removal.
- Real WebSocket clients completed 4/5/6/7-player matches in 72/111/92/168 actions. Every synchronized revision conserved all 80 cards and matched public state across peers. Coverage included reconnect during turns, Dodge, Duel and General Store; private character offers and rematch were checked. Protocol/isolation and seven-player capacity/eighth rejection tests pass.
- Two isolated Edge desktop clients and two touch-emulated clients pass room creation/join, ready, private selection/hands, Sheriff first turn, actual 3D shooting and refresh/reconnect. Touch additionally verifies preview before confirmation. Browser tests explicitly focus tabs before reading layouts because background Web render loops pause.
- Actual Intel UHD renderer, 1440x900, seven avatars and seven market cards: roughly 60 FPS over 120 sampled frames per quality level, with 736 draw calls / 47,178 primitives at Low/Medium and 1,796 / 119,862 at High. 682 mesh instances, 446 unique meshes, 281 materials, 26 audio players, empty presentation queue. This is a single-device, VSync-bound observation, not a mobile performance guarantee.
- Debug Web export succeeds. Logs and screenshots are under ignored `tests/artifacts/`; repeatable test sources are available in `tests/`.

## Remaining acceptance limits

Physical-phone testing and subjective speaker/headphone listening are still needed. Automated synthesis/route checks do not establish artistic sound quality. Windows sandbox logs include unavailable root-certificate store and shader-cache/editor-settings write warnings; the listed game tests and Web export finish successfully without GDScript parser errors.
