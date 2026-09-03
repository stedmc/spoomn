# Plan: Game Logic Bugs

Items from needtofix.md: 7, 8, 9, 11, 12

---

## Item 7 & 8 — Player stuck in trading phase after dice roll

These two are related. Rolling dice should never put a player into trading mode.

### Debug first (per item 17 rule)

- Do NOT guess-fix. Instead:
  1. Add console log at the point where the client receives a phase update from the server.
  2. Log: current phase, expected phase, player ID, and what triggered the transition.
  3. Create `.claude/bugs/bug-trade-phase-after-roll.md` to track findings.
- Once logs are captured and the root cause is clear, implement the fix.

### Likely areas to investigate

- Server-side turn phase state machine — what transitions are valid after a roll?
- Does rolling dice ever trigger a trade-open event erroneously?
- Is there a race condition between the roll result and phase broadcast?

## Item 9 — Phase label text should reflect actual sub-action

- The main turn text should always be `"Player X's turn"` during the roll/move phase.
- Only update to `"Player X is trading"` when the trade menu is explicitly opened by that player.
- Similarly: `"Player X is building"` when build menu is open, `"Player X is mortgaging"` when mortgage menu is open.
- Find where the phase label string is set and add guards so it only changes on explicit user action, not on server phase transitions.

## Item 11 — Show 'Roll again' instead of 'End turn' after a double

- When a player rolls a double, the server should indicate they get another roll.
- In the client UI, if the current player rolled a double and has not yet rolled again:
  - Hide the `End Turn` button.
  - Show a `Roll again` button that triggers the dice roll action.
- Find the button visibility logic and add the double-roll condition.

## Item 12 — Build, mortgage, trade buttons visible throughout whole turn

- Currently these buttons only appear in the end phase.
- They should be visible and tappable from the moment it is the player's turn (after roll phase begins or after the player lands).
- Find the condition controlling button visibility and expand it to cover the full turn duration, not just the end phase.
- Ensure tapping them while in roll phase doesn't break turn flow (e.g. open the menu but don't advance the phase).

---

## Files to investigate

- Server: turn phase state machine and phase broadcast logic.
- Client: dice roll handler, phase label widget, action button visibility conditions.
- Create `.claude/bugs/bug-trade-phase-after-roll.md` before touching items 7/8.
