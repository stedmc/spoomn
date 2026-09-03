# Plan: Nearest Station/Utility Must Be Forward Direction

## Problem

`Board._nearestOf` uses Dart's `%` operator on possibly-negative values. In Dart,
`(-7) % 40 == -7` (not 33). This means when a station is behind the player, its
computed "distance" is negative, which always wins the `reduce` comparison → player
is moved BACKWARD to a station they already passed.

Example: player at position 22 (Community Chest), draws "advance to nearest station".

```
stationIndices = [5, 15, 25, 35]
distA for 5  = (5  - 22) % 40 = -17  ← wins (smallest)
distB for 15 = (15 - 22) % 40 =  -7
distC for 25 = (25 - 22) % 40 =   3
distD for 35 = (35 - 22) % 40 =  13
```

Result: player moved to station 5, which is 17 squares BEHIND them. Correct forward
target is station 25 (3 squares ahead).

## Root cause

File: `packages/spoomn_core/lib/src/constants/board.dart`, lines 98-104

```dart
static int _nearestOf(int pos, List<int> targets) {
  return targets.reduce((a, b) {
    final distA = (a - pos) % boardSize;
    final distB = (b - pos) % boardSize;
    return distA <= distB ? a : b;
  });
}
```

## Fix

Replace `_nearestOf` with a forward-only distance calculation:

```dart
static int _nearestOf(int pos, List<int> targets) {
  int best = targets.first;
  int bestDist = boardSize + 1; // sentinel > any real distance
  for (final t in targets) {
    final d = (t - pos + boardSize) % boardSize;
    if (d > 0 && d < bestDist) { // d == 0 means already on this square: skip
      bestDist = d;
      best = t;
    }
  }
  return best;
}
```

`(t - pos + boardSize) % boardSize` always gives a positive forward distance (1-40).
`d > 0` excludes the current square (can't "advance" to where you already are).
`d < bestDist` picks the closest target in the forward direction.

## Fallback edge case

If ALL targets have `d == 0` (player is simultaneously on every target — impossible in
standard Monopoly), the sentinel `best = targets.first` is returned. Safe.

## Impact on passedGo in card_engine.dart

`_effectMoveToNearest` uses:
```dart
final passedGo = target < currentPos;
```

With the fix, `target` is now the correct forward station. `target < currentPos` correctly
detects wrapping past Go (e.g. player at 36 → station 5: `5 < 36` → true → £200 awarded).

Previously: player at 22 → station 5 (backward): `5 < 22` → true → £200 WRONGLY awarded
for going backward. Fix also corrects this over-payment.

## Files changed

| File | Change |
|------|--------|
| `packages/spoomn_core/lib/src/constants/board.dart` | Replace `_nearestOf` body (4 lines → 9 lines) |

## Verification

| Scenario | Before | After |
|----------|--------|-------|
| Player at 7 (Chance), nearest station | 5 (backward) | 15 (forward) |
| Player at 22 (CC), nearest station | 5 (backward) | 25 (forward) |
| Player at 36 (Chance), nearest station | 5 (forward, wraps) | 5 (correct) |
| Player at 22, nearest utility | 12 (backward) | 28 (forward) |
| Player at 33 (Chance), nearest utility | 12 (forward, wraps) | 12 (correct, wraps past Go) |
