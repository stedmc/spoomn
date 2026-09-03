# Plan: Card-Initiated Move Landing Resolution + Pass Go

## Problem

When a Chance or Community Chest card moves the player (move_to, move_relative,
move_to_nearest), the server NEVER calls `_resolveSquareLanding` for the NEW square.

Results:
- Player lands on an owned property via card → no rent charged
- Player lands on unowned property via card → no purchase offered
- `move_to_nearest` sets `pending_action.type = 'card_move_landing'` but there is no
  action handler for this type → player stuck in 'action' phase with no valid action

Pass-go salary IS applied by the card engine (stateUpdates include balances), but rent
triggers for the new square are never resolved, which makes the overall turn flow broken.

## Root cause

`_resolveSquareLanding` in `action_handler.dart` for `SquareType.communityChest` /
`SquareType.chance` (lines ~959-991):

```dart
case SquareType.communityChest:
  final result = await drawAndApply(...);
  await supabase.from('game_state').update({
    ...result.stateUpdates,       // board_positions updated if card moves player
    'pending_action': null,       // ← problem: clears pending without resolving new square
    'phase': result.phaseOverride ?? 'trade', // ← goes to 'trade' skipping new landing
  }).eq('room_id', roomId);
  // ← _resolveSquareLanding never called for the new position
```

For `move_to_nearest`, `phaseOverride = 'action'` and `pending_action = {type: 'card_move_landing'}`.
No handler matches `card_move_landing` in `handleAction` → player stuck.

## Fix

### Step 1 -- Update `_resolveSquareLanding` signature

Add optional `rentMultiplier` parameter:

```dart
Future<void> _resolveSquareLanding(
  String roomId,
  String playerId,
  int squareIndex,
  Map<String, dynamic> state,
  Map<String, dynamic> config, {
  double rentMultiplier = 1.0,  // new param
}) async {
```

Apply multiplier in the rent payment block:

```dart
final rent = (_calculateRent(square, squareIndex, ownerId!, state) * rentMultiplier).round();
```

### Step 2 -- Resolve landing after card move

In the `communityChest` and `chance` cases, after the DB write, check if the card moved
the player and recurse:

```dart
case SquareType.communityChest:
case SquareType.chance:
  final result = await drawAndApply(
    deckType: square.type == SquareType.communityChest ? 'community_chest' : 'chance',
    roomId: roomId, playerId: playerId, state: state, config: config,
  );

  // Extract rent multiplier BEFORE writing pending_action: null
  final cardPendingAction = result.stateUpdates['pending_action'] as Map<String, dynamic>?;
  final cardRentMultiplier = (cardPendingAction?['rent_multiplier'] as num?)?.toDouble() ?? 1.0;

  // Write card effects to DB (omit pending_action from stateUpdates since we handle it)
  final cardUpdates = Map<String, dynamic>.from(result.stateUpdates)
    ..remove('pending_action');
  await supabase.from('game_state').update({
    ...cardUpdates,
    'pending_action': null,
    'phase': 'trade', // always reset; landing resolution below will override if needed
    'updated_at': now,
  }).eq('room_id', roomId);

  await _writeLog(roomId, playerId, state['turn_number'] as int,
      'draw_card', result.logPayload);

  // If card moved the player, resolve landing on the new square
  final newPositions = result.stateUpdates['board_positions'] as Map<String, dynamic>?;
  if (newPositions != null) {
    final newPos = newPositions[playerId] as int?;
    if (newPos != null && newPos != squareIndex) {
      // Build merged state so landing resolution sees up-to-date balances
      final mergedState = Map<String, dynamic>.from(state)
        ..addAll(cardUpdates);
      await _resolveSquareLanding(
        roomId, playerId, newPos, mergedState, config,
        rentMultiplier: cardRentMultiplier,
      );
    }
  }
```

### Step 3 -- Prevent infinite recursion

Add a `depth` guard to `_resolveSquareLanding`:

```dart
Future<void> _resolveSquareLanding(
  ...
  {double rentMultiplier = 1.0, int depth = 0}
) async {
```

In the card landing recursion call:
```dart
await _resolveSquareLanding(
  ..., rentMultiplier: cardRentMultiplier, depth: depth + 1);
```

At the top of `_resolveSquareLanding`:
```dart
// Guard: a card can move player to another card square (rare but possible)
// Allow one level of recursion; a second card landing just sets phase = 'trade'
if (depth > 1) {
  await supabase.from('game_state').update({'phase': 'trade', 'pending_action': null, 'updated_at': now}).eq('room_id', roomId);
  return;
}
```

### Step 4 -- Remove card_move_landing pending_action from card engine

In `card_engine.dart` `_effectMoveToNearest`, remove the pending_action from stateUpdates
and the phaseOverride:

```dart
// Before
return _EffectResult(
  stateUpdates: {
    'board_positions': positions,
    'balances': balances,
    'pending_action': {'type': 'card_move_landing', 'square': target, 'rent_multiplier': effect['rent_multiplier']},
  },
  phaseOverride: 'action',
);

// After
return _EffectResult(
  stateUpdates: {
    'board_positions': positions,
    'balances': balances,
    '_card_rent_multiplier': effect['rent_multiplier'], // internal key, extracted in handler
  },
  // phaseOverride: null → 'trade' by default, overridden by landing resolution
);
```

The handler reads `_card_rent_multiplier` and strips it before writing to DB (it's not a
real DB column). The `rentMultiplier` is passed to `_resolveSquareLanding`.

Alternatively: keep the key in `result.stateUpdates` as `pending_action` temporarily and
extract before DB write (as shown in step 2 above).

## Files changed

| File | Change |
|------|--------|
| `action_handler.dart` | Update `_resolveSquareLanding` signature; add recursion call after card move; add depth guard |
| `card_engine.dart` | `_effectMoveToNearest`: remove `pending_action` from stateUpdates; remove `phaseOverride: 'action'` |

## Verification

| Scenario | Before | After |
|----------|--------|-------|
| CC card "Advance to Go" | Moved; no Go landing effect | Moved; phase=trade (Go landing is no-op) |
| Chance "Advance to Trafalgar Square" (owned) | Moved; no rent charged | Moved; rent charged |
| Chance "Advance to nearest Station" (owned) | Stuck in 'action' phase | Moved; rent×2 charged; phase=trade |
| Chance "Advance to nearest Utility" (unowned) | Stuck; no purchase offer | Moved; purchase offered; phase=action |
| Any card move that passes Go | Go salary applied; new square NOT resolved | Go salary applied; new square resolved |
