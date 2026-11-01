# Visual polish pass

Scope is cosmetic presentation and touch hit areas only. The 80-card manifest, authoritative rules, character selection and networking files match their SHA-256 values recorded before this pass (`tests/artifacts/visual-only-baseline.json`). No gameplay content was added.

- Curved brass guide: 64 smooth subdivisions, taper from shooter to target, cached rounded dash mask scrolling toward target, small arrowhead and optional side bow around projected nameplates. The existing ribbon mesh is reused; repeated stationary hover does not rebuild geometry.
- Reticles retain four readable corner marks for all contexts, distinct muted colors, lock-in and gentle pulse. Ground rings share cached geometry. Shot presentation suppresses previews before audio/flash without delaying rules or discarding a newly selected card.
- Shot timing: cock/raise, flash at 95 ms, existing shot cue at 100 ms, delayed 80 ms fleck, two soft smoke puffs and modest recoil. Fleck mesh/material and smoke assets are cached. No projectile collision or damage code.
- Nameplates separate name and HP/count/Sheriff rows, retain minimum projected size and lift overlapping plates before using horizontal separation. Details use a small side character card; duplicate overhead details are hidden. Unchanged portraits survive refreshes; static portrait avatars do not run idle animation.
- CharacterVisualData/CharacterParts remain in use. Cached tailored torsos/coats and shaped crowns, rounded sleeves, thumbs, holsters, boot tilt, distinctive trim/accessories and a head pivot refine existing models. Eyes/brows/mouth/head/hat support idle, targeted, panic, shoot, dodge, hit, drink and death. All sixteen preset combinations remain distinct; modular mesh limits are checked.

Verification:

- TargetingTest: 57 checks; GameplayUXTest: 39; VisualEffectsTest: 20; CharacterVisualTest: 219; StabilizationTest: 14; AudioReworkTest: 44; BaseCorrectionTest: 3,780 checks including sixteen complete 4–7-player matches.
- VisualPolishTest: 51 checks covering a seven-player table, all Store cards and weapons reachable via real 3D rays at desktop/mobile sizes, touch selection IDs, center clear of info popup, cached portraits, preview mesh reuse, pre-shot guide suppression and transient VFX cleanup.
- Actual renderer captures: `tests/artifacts/character-gallery.png`, `visual-polish-table-1440.png`, `visual-polish-table-844.png`, `targeting/mouse-arrow.png` and `table-seven-market.png`.
- Seven avatars plus seven Store cards, Intel UHD at 1440x900: approximately 60 FPS over 120 frames at each quality, 763 Low/Medium draw calls, 1,867 High; sampled scene 708 mesh instances / 408 unique meshes / 290 materials / 26 audio players, empty presentation queue. Single-device VSync-limited observation, not a physical-phone benchmark.
- Debug Web export succeeds. Two isolated touch-emulated Edge clients pass create/join, ready, private character selection, 3D shooting (preview then confirm), no active-match music and refresh/reconnect.

Physical-phone and subjective animation/art review remain external checks. Sandbox warnings concern the Windows certificate store and shader-cache/editor-settings writes, not GDScript parser failures. Test artifacts are ignored by Git.
