# Plan: Turn Flow Fixes

Bugs 1, 8, 10 from needtofix.md. All involve the action menu failing to appear or the
trade button not being shown at the right time.

---

## Bug 1 — Trade button not visible for full turn

**File:** `packages/spoomn_client/lib/src/widgets/game/action_bar.dart`

**Problem:** Trade button only rendered when `config['trade_any_turn'] == true` during roll
phase (lines 127-134). It is always shown during trade phase. It should be visible during
the entire player turn (roll + action + trade phases), matching the other buttons.

**Fix:**
- In action_bar.dart, remove (or widen) the `trade_any_turn` guard so the trade button
  renders in every phase that belongs to the current player's turn, not just trade phase.
- Confirm button is hidden when it's not this player's turn (guard on `isMyTurn`, not phase).

---

## Bug 8 — Jail via card/speeding breaks next player action menu

**File:** `packages/spoomn_server/lib/src/handlers/action_handler.dart`

**Problem:** `_sendToJail` (around line 1129) sets `phase: 'roll'` and `pending_action: null`
then calls `_endTurn`. But it bypasses `_resolveSquareLanding`, so the next player's
turn starts without proper state. The action bar never appears.

**Callers of _sendToJail:** lines ~158, 833, 872, 1051.

**Fix options (pick one):**
1. After updating state in `_sendToJail`, invoke `_endTurn` with the correct next-player
   context so phase transitions run properly.
2. Alternatively, call `_resolveSquareLanding` for the jail square (index 10, SquareType.jail)
   before ending the turn.

Preferred: option 1 — ensure `_sendToJail` calls the same `_endTurn` path used by normal
square landings, passing the updated state. Verify the chain: `_sendToJail` → `_endTurn`
→ next player gets `phase: 'roll'` and action bar triggers on client.

---

## Bug 10 — Income Tax landing breaks next player action menu

**File:** `packages/spoomn_server/lib/src/handlers/action_handler.dart`

**Problem:** Income Tax handler (lines 1007-1024) sets `pending_action: null` and
`phase: 'trade'` immediately after deducting tax. This means the current player never
sees an action menu, and the state transition for the NEXT player may also be broken
(same root cause as bug 8 — bypasses normal end-turn pipeline).

**Fix:**
1. After deducting tax, set `phase: 'action'` with appropriate `pending_action` so the
   current player sees the normal action bar (Build / Mortgage / Trade / End Turn).
2. OR: verify that jumping straight to `phase: 'trade'` is intentional and that the
   action bar IS shown in trade phase for the current player. If trade phase already shows
   the action bar correctly, the bug may only be the next-player transition.
3. Confirm `_endTurn` is called via the normal path after tax resolution — not a shortcut
   that skips phase wiring.

Cross-check with bug 8 fix: if `_endTurn` is corrected there, income tax may resolve
itself if it uses the same path.

---

## Test plan

- Roll dice → land on tax square → verify action bar appears for current player, then
  end turn and verify next player's action bar appears.
- Trigger jail via Chance/Community Chest card → verify next player's action bar appears.
- Trigger jail via speeding (3 doubles) → verify next player's action bar appears.
- Confirm trade button visible on all turns regardless of phase.
