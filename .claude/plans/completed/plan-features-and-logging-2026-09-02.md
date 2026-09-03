# Plan: Features and Logging

Bugs 4, 6, 7 from needtofix.md. Activity log completeness, free parking display,
and persistent card mechanic.

---

## Bug 4 — Trade events missing from activity log

**Files:**
- `packages/spoomn_client/lib/src/widgets/game/activity_log.dart` (lines 40-74)
- `packages/spoomn_server/lib/src/handlers/trade_handler.dart`

**Problem (two parts):**

1. Server: `trade_handler.dart` does not call `_writeLog` on trade events. Other handlers
   (e.g. building_handler, action_handler) do. Trade propose/accept/reject/counter/cancel
   events never reach the log table.

2. Client: `activity_log.dart` `_formatEntry` has no cases for trade `GameAction` values
   (`proposeTrade`, `acceptTrade`, `counterTrade`, `rejectTrade`, `cancelTrade`).

**Fix:**
1. In `trade_handler.dart`, add `_writeLog` calls after each successful trade operation,
   matching the pattern used in action_handler.dart. Use descriptive messages:
   - propose: "Player A proposed a trade with Player B"
   - accept: "Player B accepted Player A's trade"
   - reject: "Player B rejected Player A's trade"
   - counter: "Player B countered Player A's trade"
   - cancel: "Player A cancelled the trade offer"

2. In `activity_log.dart` `_formatEntry`, add switch cases for all five trade GameActions,
   returning appropriately formatted strings. Pull player names from the log entry payload.

---

## Bug 6 — Free Parking amount not shown on square

**File:** `packages/spoomn_client/lib/src/game/components/board_component.dart`
(method `_drawLabel`, lines 174-230)

**Problem:** Free Parking square (index 20, `SquareType.freeParking`) has no special
rendering when `free_parking_jackpot` config is enabled and `free_parking_pot > 0`.

**Fix:**
- In `_drawLabel` (or a new `_drawFreeParkingLabel` helper), add a case for
  `SquareType.freeParking`.
- Read `gameState.freeParkingPot` (or however the pot is stored in GameState) and
  `roomConfig.freeParkingJackpot`.
- When jackpot setting is on and pot > 0, render the amount as an additional text element
  on the square — e.g. "£4,200" in gold text below the car icon.
- If pot is 0 or setting is off, render the square normally.
- Confirm the field name in `game_state.dart` — search for `free_parking` or `parking_pot`.

---

## Bug 7 — Persistent card mechanic

**Files:**
- `packages/spoomn_client/lib/src/screens/game_screen.dart`
- `packages/spoomn_client/lib/src/widgets/game/card_draw_overlay.dart`
- New file: `packages/spoomn_client/lib/src/widgets/game/persistent_card_widget.dart`
- `packages/spoomn_server/lib/src/game/card_engine.dart`
- `packages/spoomn_core/lib/src/models/game_state.dart`

**Problem:** Cards that are "keep until used" (e.g. Get Out of Jail Free) are not
persistently displayed to the holder. Currently the draw overlay auto-dismisses and the
card is forgotten visually.

**Implementation plan:**

### 1. Core/Server — mark persistent cards

- In `cards.dart` / `card_engine.dart`, identify which card types are persistent (GOOJF,
  any other keep cards). Add a `persistent: true` field to those card definitions if not
  already present.
- In `game_state.dart`, ensure `heldCards` (or equivalent) per player is tracked in state
  so clients can read it.

### 2. Client — persistent card widget

- Create `persistent_card_widget.dart`:
  - Displays a mini card face (icon + short text) below the dice area in `game_screen.dart`.
  - Only shown to the holding player (check `myPlayerId == holderId`).
  - Tappable. On tap, sends a `useCard` action to server if in an appropriate game phase
    (e.g. tapping GOOJF during jail roll phase).
  - Show tooltip or disabled state if card can't be used yet.

### 3. Client — "card used" broadcast

- When server confirms card use, emit an event that triggers:
  - A `game_toast.dart` message to all players: "Player X used [Card Name]".
  - Brief card-flip or slide-out animation on the persistent widget before it disappears.

### 4. Integration in game_screen.dart

- Add `PersistentCardWidget` to the Stack layout, positioned between dice and the board
  centre (below dice area, above the board's central text).
- Only render if `heldCards` for the local player is non-empty.

### 5. Sequence

1. Update GameState model to track `heldCards` per player.
2. Update card_engine.dart to populate `heldCards` on pickup.
3. Create PersistentCardWidget.
4. Wire tap → server action → broadcast.
5. Add toast notification on use.

---

## Test plan

**Bug 4:**
- Propose a trade → activity log shows "proposed trade" entry.
- Accept / reject / counter → log entries appear.
- Cancel → log entry appears.

**Bug 6:**
- Enable free parking jackpot in room config.
- Land on tax/chance squares that add to pot.
- Verify pot amount visible on Free Parking square.
- Collect pot → amount resets to 0 / disappears.

**Bug 7:**
- Draw a GOOJF card → mini card widget appears below dice.
- Attempt to use on wrong phase → disabled / tooltip shown.
- Land in jail → use GOOJF → card disappears, toast notifies all players.
- Other players see toast but not the persistent widget (privacy check).
