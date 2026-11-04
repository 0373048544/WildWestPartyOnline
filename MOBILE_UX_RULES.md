# Mobile UX and base-game validation

The current room architecture, authoritative ownership, role pool, private two-character choice and 80-card manifest remain intact. Dockerfile, nginx configuration, Render entrypoint and `/ws` routing were not edited by this pass. Other workspace changes made during the session were preserved.

## Responsive presentation

- `scripts/ui/MatchLayout.gd` centralizes portrait/mobile decisions. `WebLayout.gd` preserves the actual CSS aspect ratio instead of forcing portrait 600x960. Desktop keeps its existing camera and full hand fan.
- `HandFan.gd` shows about half a card at the bottom on mobile, raises the tapped card for reading, commits on the next tap, supports horizontal swipe/scroll and suppresses play after dragging. Targeting collapses the hand further. Mobile action/cancel buttons have larger touch heights.
- `MatchHUD.gd` / `HUDMatchStrip.gd` use a compact translucent phase/turn/countdown strip. The log starts collapsed and no large turn notice covers the table. `App.gd` refreshes match layout on orientation changes without rebuilding typing controls in the menu.
- `TargetingController.gd` accepts nearby avatar/nameplate touches with a minimum approximately 52 CSS-pixel diameter. Invalid targets never receive the intent. Equipment touch selection keeps the existing physical card ID and server validation.
- `PlayerNameplate.gd` / `TableView.gd` keep names, hearts and count separate and choose nearby non-overlapping label positions. Portrait camera framing changes presentation only. All five requested dimensions are tested with seven players: 390x844, 393x852, 430x932, 844x390 and 1440x810.

## Props and weapons

- `TableObject.gd` and `TableObjects.gd` add blue/gold card bases, clearer props, cached weapon representations, hover lift and spawn/remove tweens. Slots wrap to short rows and update as equipment changes. The larger card-base collider avoids tall props blocking neighboring cards; mobile hit slop remains generous.
- `WeaponVisuals.gd`, `AvatarGestures.gd`, `PlayerAvatar.gd` and `CharacterParts.gd` retain the existing modular rig. Six cached weapon profiles replace the generic held gun, update from public weapon state, recover the default on removal, and supply the actual muzzle position. Rifle/revolver recoil and supporting arm poses differ. Existing semantic events drive draw/equip/reach/duel/jail/dynamite gestures; AudioManager remains unchanged.

## Server validation

- `shoot_used_this_action_turn` is the authoritative BẮN allowance. `PlayerState.bang_played_this_action_turn` is an alias over that flag, so it cannot diverge or reset on animation/reconnect.
- `panic_used_this_action_turn` and `cat_balou_used_this_action_turn` are separate, card-specific limits. Willy/Volcanic override only BẮN. Reaction handlers remain separate and never consume the normal BẮN action-turn allowance.
- `department_store_used_this_action_turn` resets only when that player's next action turn begins. `general_store_used_this_match` persists for the entire match.
- Three corrupted Vietnamese admission messages in `DedicatedServer.gd` were repaired. Admission rules and authority were not changed.

## Verification

- `MobileRulesTest.gd`: 220 checks covering BANG limits and exceptions, repeated forged plays, reconnect flag preservation, multiple non-BANG brown cards, weapon replacement, duplicate Barrel rejection, six cached weapon meshes, five viewport layouts, card focus/scroll, avatar touch reachability and non-overlapping seven-player labels.
- Existing headless suites pass: AudioRework, Audio, BaseCorrection (including sixteen complete 4–7-player games), CharacterChoice, CharacterVisual, DiscardZones, GameplayUX, Localization, Presentation, RoomCreation, Rules, Stabilization, Targeting, VisualEffects and VisualPolish. ConnectionFailure passes separately. LobbyTest was run as host + client; NetworkTest as one host + three clients, covering game over, restart and return to lobby.
- Native WebSocket protocol/isolation and seven-player capacity tests pass. Complete 4/5/6/7-player WebSocket matches finished in 53/141/237/212 actions in the final wire run. Every match also reconnects after a BANG restriction and sends three forged second-BANG requests, verifying the card remains in hand and the restriction stays enforced.
- Two isolated Edge touch clients at 390x844 pass create/join, ready, private character choices/hands, card focus, 3D targeting, shot and refresh/reconnect. Gameplay music remains off. This is emulation, not physical-device testing.
- Desktop renderer profile, Intel UHD 1440x900, seven avatars and seven Store cards: approximately 60 FPS at Low/Medium/High in the isolated final sample, 799/799/1944 draw calls, 416 unique meshes, 283 materials, 26 audio players and an empty presentation queue. Concurrent browser/test loads produced lower samples; these measurements are not a device-wide performance guarantee.
- Both debug and release Web export succeed; `build/web` is left as a release export. No live Render deployment was performed. Logs/screenshots are under ignored `tests/artifacts/`, including `mobile-390x844.png`, the other requested viewport captures and `full-web-matches.json`.

The Windows sandbox emits certificate-store and editor/shader-cache write warnings. No remaining GDScript parser failure was found. Physical-phone review and live deployment verification remain outside these local tests.
