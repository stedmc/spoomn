# Plan: Persistent Turn Indicator

## Problem

No persistent visual in the board area showing whose turn it is. The status banner is in the
side panel; it's not visible while looking at the board. Users need a small always-visible
indicator in the board area showing the current player's pawn colour and name.

## Design

- Positioned in the TOP-LEFT of the board area (or top-center, to be decided)
- Content: `[coloured circle] "Alice's turn"`
- Always visible when game is active (never hidden)
- Updates immediately when `gameRoomProvider.currentPlayerId` changes

## Implementation

### Step 1 -- New widget `TurnIndicatorWidget`

New file `widgets/game/turn_indicator.dart`:

```dart
class TurnIndicatorWidget extends ConsumerWidget {
  const TurnIndicatorWidget({super.key, required this.roomId, required this.game});
  final String roomId;
  final SpoomnGame game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref.watch(gameRoomProvider(roomId)).valueOrNull;
    final players = ref.watch(roomPlayersProvider(roomId)).valueOrNull ?? [];
    final currentId = room?.currentPlayerId;
    if (currentId == null) return const SizedBox.shrink();

    final player = players.firstWhereOrNull((p) => p.playerId == currentId);
    final name = player?.displayName ?? 'Player';

    return ListenableBuilder(
      listenable: game.playerColoursListenable, // see step 2
      builder: (_, __) {
        final colour = game.playerColours[currentId] ?? Colors.grey;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14, height: 14,
                decoration: BoxDecoration(
                  color: colour,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "$name's turn",
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      },
    );
  }
}
```

### Step 2 -- Expose playerColours from SpoomnGame

`SpoomnGame` already maintains `Map<String, Color> playerColours` (used for token rendering).
Add a `ChangeNotifier` or `ValueNotifier` that fires when `playerColours` is updated:

```dart
// In SpoomnGame
final playerColoursNotifier = ChangeNotifier();

void setPlayerTokenColours(Map<String, Color> colours) {
  playerColours = colours;
  playerColoursNotifier.notifyListeners();
}

Listenable get playerColoursListenable => playerColoursNotifier;
```

### Step 3 -- Add to game_screen.dart Stack

In `_GameScreenState.build`, inside the Stack, add:

```dart
Positioned(
  top: 12,
  left: 12,
  child: TurnIndicatorWidget(roomId: widget.roomId, game: _game),
),
```

Place this AFTER the `Row(GameWidget + SidePanel)` child so it renders on top of the board.

### Step 4 -- Ensure it doesn't overlap toasts

If plan-game-toast.md is also implemented, toasts are centred and the indicator is
top-left, so no collision. Verify on small screens.

## Files changed

| File | Change |
|------|--------|
| `widgets/game/turn_indicator.dart` | New file: `TurnIndicatorWidget` |
| `spoomn_game.dart` | Expose `playerColoursListenable` notifier, fire on `setPlayerTokenColours` |
| `game_screen.dart` | Add `Positioned` turn indicator to Stack |

## Verification

1. Start a game → indicator shows current player's name and colour dot
2. End turn → indicator updates to next player immediately
3. During auction, indicator still shows the "main turn" player (current_player_id), not bidder
4. Indicator visible on all screen sizes without obscuring key board squares
