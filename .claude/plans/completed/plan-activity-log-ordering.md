# Plan: Activity Log Ordering Fix

## Problem

`game_log` sorted by `created_at DESC` with no secondary key. `roll_dice` and `draw_card`
inserts happen within milliseconds of each other → near-identical timestamps → non-deterministic
ordering from PostgreSQL. User sees dice roll appearing after "landed on community chest" in
some cases.

## Root Cause

In `action_handler.dart` `_rollDice`, write order is:

1. `_resolveSquareLanding(...)` called → inside, `_writeLog('draw_card', ...)` fires (id=N)
2. `_writeLog('roll_dice', ...)` fires after (id=N+1)

With `ORDER BY created_at DESC` and sub-millisecond timestamp collisions, ordering is
non-deterministic. `game_log.id` is `BIGINT GENERATED ALWAYS AS IDENTITY` (BIGSERIAL) --
perfect tie-breaker that already exists, no migration needed.

## Fix

### Step 1 -- Client sort key (`providers.dart`)

Change single line in `gameLog` provider:

```dart
// Before
.order('created_at', ascending: false)

// After
.order('id', ascending: false)
```

`id` is BIGSERIAL: monotonic, no ties, guaranteed insertion order.

### Step 2 -- Write order in `_rollDice` (`action_handler.dart`, lines 196--203)

Move `_writeLog('roll_dice')` to BEFORE `_resolveSquareLanding`. Result: roll_dice gets
smaller id, draw_card gets larger id. In DESC order: draw_card at top (newest/most recent
effect), roll_dice below (the cause). Consistent and semantically correct for newest-first feed.

```dart
await supabase.from('game_state').update(updates).eq('room_id', roomId);

// Write roll log BEFORE resolving landing (so draw_card always gets a larger id)
await _writeLog(roomId, playerId, state['turn_number'] as int, 'roll_dice',
    {'roll': roll, 'new_position': newPos, 'passed_go': passedGo});

await _resolveSquareLanding(roomId, playerId, newPos, stateForLanding, config);

// Remove the _writeLog call that was here at lines 201-202
return okJson({'roll': roll, 'new_position': newPos, 'passed_go': passedGo});
```

### Step 3 -- Same fix in `_rollDiceInJail`

Each return path writes its own `_writeLog('roll_dice')`. Move each one to BEFORE the
corresponding `_resolveSquareLanding` call (the doubles-escape path at line ~832).

The two paths that do NOT call `_resolveSquareLanding` (mandatory turns, normal failed roll)
are unaffected -- their log writes are already the last meaningful operation.

## Files Changed

| File | Change |
|------|--------|
| `packages/spoomn_client/lib/src/providers/providers.dart` | 1 line: `created_at` -> `id` |
| `packages/spoomn_server/lib/src/handlers/action_handler.dart` | Move 2 `_writeLog` calls earlier |

## Verification

After fix: in any turn where player lands on community chest or chance, the activity log
should always show draw_card above roll_dice (draw_card has larger id -> appears first in
DESC order). Run 5+ test turns landing on card squares, confirm consistent ordering each time.
