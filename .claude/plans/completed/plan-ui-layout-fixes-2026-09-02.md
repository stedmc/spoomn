# Plan: UI / Layout Fixes

Bugs 2, 3, 5, 9 from needtofix.md. Pure client-side rendering and positioning issues.

---

## Bug 2 — Property card popup clips off screen on bottom row

**Files:**
- `packages/spoomn_client/lib/src/screens/game_screen.dart` (lines 207-221)
- `packages/spoomn_client/lib/src/widgets/game/property_card.dart`

**Problem:** Bottom-row board squares anchor the popup using `top = (anchor.dy - 40).clamp(...)`.
For squares near the bottom of the screen the clamped value still places the card too low
and the "Assign Owner" section (rendered below the main card body) is hidden.

**Fix:**
- Detect when the anchor's Y position is in the bottom half of the screen.
- When true, render the popup ABOVE the anchor instead of below:
  `top = anchor.dy - cardH - padding` (unclamped from below, clamped from above to 0).
- Same logic for left/right: flip to left-anchored if anchor is near right edge.
- Consider extracting this into a `_smartPopupPosition(anchor, cardSize, screenSize)`
  helper so it's easy to test.

---

## Bug 3 — Toast position wrong (should be centred, below top row, above card piles)

**Files:**
- `packages/spoomn_client/lib/src/screens/game_screen.dart` (lines 223-236)
- `packages/spoomn_client/lib/src/widgets/game/game_toast.dart`

**Problem:** Toast is positioned with hardcoded `top: 32` and `left: 0; right: 280`. This
doesn't account for the top property row height or the card pile area.

**Fix:**
- Measure (or use a constant for) the top row height — the area above the board squares.
- Position toast with `top: <topRowHeight> + <small padding>`, centred horizontally
  excluding the right panel (player strip + panels).
- Keep toast above the card piles by capping its bottom at the board centre Y.
- If the layout uses a Stack, ensure toast Positioned widget uses the correct insets.

---

## Bug 5 — No icons in activity log entries

**File:** `packages/spoomn_client/lib/src/widgets/game/activity_log.dart` (lines 101-109)

**Problem:** Activity log itemBuilder renders plain text rows. No icons to distinguish
move, chance, trade, buy, mortgage, etc.

**Fix:**
- Add a `_iconForAction(GameAction action)` helper that maps action types to Material icons:
  - move → `Icons.directions_walk`
  - chance / community chest → `Icons.help_outline`
  - trade → `Icons.swap_horiz`
  - buy property → `Icons.home`
  - mortgage / unmortgage → `Icons.account_balance`
  - build house/hotel → `Icons.house`
  - go to jail → `Icons.lock`
  - pay tax → `Icons.receipt`
  - collect salary / pass go → `Icons.monetization_on`
  - free parking → `Icons.local_parking`
- Wrap each log row in a `Row` with a leading icon + text.
- Icon colour can match the action category (e.g. red for jail, green for collect).

---

## Bug 9 — Current player not highlighted in player list

**File:** `packages/spoomn_client/lib/src/widgets/game/player_strip.dart` (lines 74-129)

**Problem:** Highlight applied only on hover/lock tap (`isActive || isGameHovered`). The
active player should always have a visible indicator without requiring mouse interaction.

**Fix:**
- Add a persistent highlight for `isActive == true`: e.g. a left border accent, a coloured
  background, or a leading badge icon (`Icons.play_arrow`).
- Keep the hover highlight as-is (it already works).
- Ensure the active-player indicator updates reactively when `currentPlayerIndex` changes
  in game state (provider/watch pattern already in place — just bind the visual).

---

## Test plan

- Click a bottom-row property card → full card including "Assign Owner" visible above anchor.
- Trigger a toast → appears centred below top property row, does not overlap card piles.
- Open activity log → each entry has a category icon.
- Roll dice to start a turn → active player row in player strip is visibly highlighted
  without hovering.
