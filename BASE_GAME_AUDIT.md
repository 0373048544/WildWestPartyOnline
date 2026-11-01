# Base-game correction audit

Scope: current project, base game only; no deployment. Project setup is always two private character options dealt without replacement from all 16, then one confirmed choice. This overrides single-character dealing in the printed rulebook.

Sources: [official card list](https://bang.dvgiochi.com/cardslist.php?id=1&lang=en), [official rules](https://bang.dvgiochi.com/content/1/docs/01_bang_rules_EN.pdf), [requested Vietnamese reference](https://thegioiboardgame.vn/blogs/luat-boardgame/huong-dan-choi-board-game-bang).

## Initial findings

- Existing: authoritative room server, private owner snapshots, roles for 4–7, shuffled disjoint pairs of characters, Sheriff HP/starting turn, queued reactions, distance modifiers, all base card/character handlers, desktop local room bootstrap.
- Incorrect data: 80-card quantities are correct but suit/rank entries are provisional. Generator can overwrite them with prototype values. Rank is numeric internally. Must replace with canonical manifest and validate every tuple before starting a match.
- Character UX: options are text buttons, one click immediately commits; no draft highlight/confirmation or selected-name waiting screen. Confirmed choices remain hidden until everyone finishes; requested behavior publishes each confirmed character immediately.
- Visual gaps: card rank/suit is centered descriptive text with no suit colors/corners; equipped cards and discard model omit physical rank/suit. Some moves (playing, weapon replacement, character draws/steals, death collection/penalty) mutate arrays without presentation events.
- Security/state risks: selection lacks explicit authority/invariant guards; failed manifest assertions only protect debug builds. Reaction request IDs reset on rematch. Active response states and UI disabled reasons need regression coverage.
- Existing automated rules/UX checks cover core restrictions, character handlers, reaction validation and role privacy, but do not compare all 80 canonical tuples or prove two-stage character UI and per-owner selection payloads.

## Correction order

1. Canonical deck + string ranks + fail-closed validation.
2. Rank/suit corners and public table cards.
3. Core rule/character/death regression and security fixes.
4. Private two-card draft/confirm UI, timeout/rematch tests.
5. Semantic movement events and ordered presentation; full regression.

Completion evidence and remaining limits are recorded below after validation.
