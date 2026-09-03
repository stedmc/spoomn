# Bug: Player Stuck in Trading Phase After Dice Roll — CLOSED (not a bug)

Items 7 & 8 from needtofix.md.

## Resolution

Logs captured. No server-side phase bug exists. The `trade` phase is the server's normal
post-roll idle state (player can build/mortgage/end turn). The "Player X is trading" label
in the status banner was the entire source of confusion — that was fixed by item 9.

---

## Original Symptom

After rolling dice, the player sees the 'trade' phase UI (End Turn / Build / Mortgage buttons,
"Player X is trading" label) immediately — even before any trade-related action has been taken.
Rolling dice should not put a player into trading mode.

## Debug Logging Added

Phase transition logging added to `_SidePanelState` in
`packages/spoomn_client/lib/src/screens/game_screen.dart` inside the
`ref.listen(gameStateProvider(...))` callback. Each time the phase changes, the console prints:

```
[GamePhase] <prev> → <next> player=<currentPlayerId> dice=<diceRoll> consecutiveDoubles=<n>
```

## Areas to Investigate

### Server: Two-update sequence in `_rollDice`

`action_handler.dart` lines 196--199 do two separate DB writes:

1. First write: position, `dice_roll`, `board_positions` — **phase unchanged** (stays `roll`)
2. Second write: from `_resolveSquareLanding` — sets phase to `trade`, `action`, etc.

The client receives two realtime events. Between them, the phase is still `roll` but the
position has already moved. Capture the logs to confirm whether the client ever briefly sees
`phase=roll` with the new position before the second event arrives.

### Server: `_resolveSquareLanding` always transitions to `trade`

For own property, mortgaged property, and paid-rent paths (lines 941--956), the phase is
unconditionally set to `trade`. This is by design (trade = post-roll idle phase), but the
label "Player X is trading" made it look like a bug. That label is now fixed (item 9).
Verify whether items 7 & 8 were purely a UX/label issue or whether there is also a real
phase-state bug.

### Client: Optimistic phase fallback

`game_screen.dart` line 170:

```dart
final phase = stateAsync.valueOrNull?.phase.name ?? (stateAsync.isLoading ? 'roll' : null);
```

While state is loading, phase defaults to `roll`. If the stream emits a stale cached value
before the server update arrives, the client could show an incorrect phase briefly. Logs will
show whether this race manifests in practice.

## Next Steps

1. Reproduce the bug with the debug logging enabled.
2. Check console output for the `[GamePhase]` lines.
3. If the transition sequence is `roll → trade` immediately after rolling (no intermediate
   `action` or correct phase), the root cause is in `_resolveSquareLanding` logic.
4. If the transition shows an unexpected phase (e.g., `null → trade` skipping `roll`), the
   issue is in the realtime subscription or state initialisation.
5. Implement fix once root cause is confirmed from logs.
