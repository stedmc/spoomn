# Plan: Turn Processing Sequence (Dice → Move → Card → Resolve)

## Problem

The server resolves the entire turn synchronously in one HTTP request. The client has no
mechanism to sequence animations before showing the action bar. Current observed issues:

- Action bar (Roll/End Turn) reappears immediately after the server responds, before dice
  or movement animations complete
- Card overlay shows but the action bar appears alongside it (should wait)
- After a card-initiated move (fixed by plan-card-landing-resolution.md), the action mode
  never advances because the client doesn't know it should wait for a second movement

The user-facing sequence should be:
```
1. Click Roll
2. Dice animate (spin) on screen         ~1-2s
3. Dice stop → activity log updates
4. Player token animates to new square   Flame handles
5. [If card drawn] Card overlay appears  existing CardDrawOverlay
6. [If card moves player] Wait 5s        card stays visible
7. [If card moves player] Token animates to card destination
8. After token arrives, wait 2s → card dismissed
9. Rent / other effects resolved (server, via plan-card-landing-resolution.md)
10. Action bar re-appears (Roll again or End Turn)
```

## Architecture decision

Do NOT refactor server to send incremental updates. Keep one-shot server resolution.
The client orchestrates animation timing using a local state machine that gates the
action bar and card dismiss on animation callbacks.

## Implementation

### Step 1 -- Animation gate in _GameScreenState

Add to `_GameScreenState`:

```dart
bool _isAnimating = false;  // suppresses action bar while animating
```

### Step 2 -- SpoomnGame animation callbacks

`SpoomnGame` (Flame) must call back when:
a) Dice animation completes
b) Token movement animation completes (each time a token stops)

Add to `SpoomnGame`:

```dart
VoidCallback? onDiceAnimationComplete;
VoidCallback? onTokenAnimationComplete;
```

In the dice component, after animation finishes:
```dart
game.onDiceAnimationComplete?.call();
```

In the token component, after each move animation finishes:
```dart
game.onTokenAnimationComplete?.call();
```

### Step 3 -- Orchestration in game_screen.dart

Replace the existing `gameLogProvider` listener logic with a sequenced orchestrator.
Track phase transitions:

```dart
// State added to _GameScreenState
_MovePhase _movePhase = _MovePhase.idle;
Timer? _sequenceTimer;
```

```dart
enum _MovePhase {
  idle,
  diceAnimating,
  tokenMoving,
  cardShowing,     // card visible, player didn't move
  cardMoveWaiting, // card visible, token move about to start
  cardTokenMoving, // second token animation (card-initiated move)
  cardHoldAfterMove, // token arrived, 2s hold before dismissing card
}
```

### Step 4 -- Hook game log listener

```dart
ref.listen(gameLogProvider(widget.roomId), (_, next) {
  next.whenData((entries) {
    if (entries.isEmpty) return;
    final top = entries.first;
    if (top['action'] == GameAction.rollDice) {
      _beginRollSequence(top);
    } else if (top['action'] == GameAction.drawCard) {
      _handleCardDraw(top);
    }
  });
});
```

### Step 5 -- _beginRollSequence

```dart
void _beginRollSequence(Map<String, dynamic> entry) {
  setState(() {
    _isAnimating = true;
    _movePhase = _MovePhase.diceAnimating;
  });

  // Dice animation fires from Flame; register one-shot callback
  _game.onDiceAnimationComplete = () {
    _game.onDiceAnimationComplete = null;
    setState(() => _movePhase = _MovePhase.tokenMoving);

    // Register token-arrived callback
    _game.onTokenAnimationComplete = () {
      _game.onTokenAnimationComplete = null;
      // Token is at new square. If a card is pending, _handleCardDraw will fire.
      // If no card, animation is done.
      if (_movePhase == _MovePhase.tokenMoving) {
        // No card drawn → sequence complete
        setState(() { _isAnimating = false; _movePhase = _MovePhase.idle; });
      }
    };
  };
}
```

### Step 6 -- _handleCardDraw

```dart
void _handleCardDraw(Map<String, dynamic> entry) {
  final id = entry['id']?.toString();
  if (id == null || id == _lastShownCardEntryId) return;
  _lastShownCardEntryId = id;
  _cardDismissTimer?.cancel();

  // Determine if this card moves the player
  final effect = entry['payload']?['effect'] as Map<String, dynamic>?;
  final isMovementCard = effect != null &&
    ['move_to', 'move_relative', 'move_to_nearest'].contains(effect['type']);

  setState(() {
    _cardDrawEntry = entry;
    _showCardDraw = true;
    _movePhase = isMovementCard ? _MovePhase.cardMoveWaiting : _MovePhase.cardShowing;
  });

  if (isMovementCard) {
    // Wait 5s with card showing, then start second token movement
    _cardDismissTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _movePhase = _MovePhase.cardTokenMoving);

      // Token will animate to card destination (state already updated by server)
      _game.onTokenAnimationComplete = () {
        _game.onTokenAnimationComplete = null;
        setState(() => _movePhase = _MovePhase.cardHoldAfterMove);
        // Hold 2s then dismiss card
        _cardDismissTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() {
            _showCardDraw = false;
            _isAnimating = false;
            _movePhase = _MovePhase.idle;
          });
        });
      };
    });
  } else {
    // Non-movement card: auto-dismiss after 5s, no second animation
    _cardDismissTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() {
        _showCardDraw = false;
        _isAnimating = false;
        _movePhase = _MovePhase.idle;
      });
    });
  }
}
```

### Step 7 -- Suppress action bar during animation

In `side_panel.dart`, the action bar is conditionally shown:
```dart
if (isDebug || isMyTurn || isMyAuctionTurn) ...
```

Pass `_isAnimating` down to `GameSidePanel` (or use a provider/callback) and suppress:
```dart
if ((isDebug || isMyTurn || isMyAuctionTurn) && !isAnimating) ...
```

This prevents the "Roll" or "End Turn" button appearing before animations complete.

Alternatively: add an `isAnimating` `StateProvider` in Riverpod and watch it in `side_panel.dart`.

### Step 8 -- Manual dismiss during animation

If the user taps "dismiss" on the card overlay while `_isAnimating`, do NOT re-enable
the action bar immediately. Instead, skip to the appropriate next phase:

```dart
onDismiss: () {
  _cardDismissTimer?.cancel();
  if (_movePhase == _MovePhase.cardMoveWaiting || _movePhase == _MovePhase.cardShowing) {
    // User dismissed early — run the remaining logic now
    if (_movePhase == _MovePhase.cardMoveWaiting) {
      setState(() => _movePhase = _MovePhase.cardTokenMoving);
      // register token callback as above
    } else {
      setState(() { _showCardDraw = false; _isAnimating = false; _movePhase = _MovePhase.idle; });
    }
  }
},
```

## Files changed

| File | Change |
|------|--------|
| `game_screen.dart` | Add `_isAnimating`, `_movePhase`, orchestration methods; update listeners |
| `spoomn_game.dart` | Add `onDiceAnimationComplete`, `onTokenAnimationComplete` callbacks |
| `dice_component.dart` | Call `game.onDiceAnimationComplete` when dice settle |
| `token_component.dart` | Call `game.onTokenAnimationComplete` when token reaches destination |
| `side_panel.dart` | Accept / watch `isAnimating`; suppress action bar while true |

## Dependencies

- plan-card-landing-resolution.md MUST be implemented first so the server correctly sets
  phase after card-initiated moves (otherwise action bar suppression hides a broken phase)
- plan-card-draw-animation.md (existing) -- card overlay animation improvements are complementary

## Verification

1. Roll dice → dice spin, action bar hidden
2. Dice settle → token moves, action bar still hidden
3. Land on chance/CC → card appears, action bar still hidden
4. (Movement card) → 5s passes, token animates to destination, card stays visible
5. Token arrives → 2s pause → card dismisses → action bar appears
6. (Non-movement card) → 5s passes → card dismisses → action bar appears
7. Manual dismiss → skips remaining wait, action bar appears promptly
