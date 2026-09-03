# Plan: In-Game Toast Notifications

## Problem

No real-time visual feedback in the board area when events happen. Users need a brief
pop-up message in the middle section (board area) announcing key events: dice rolls,
purchases, rent payments, card draws, etc. Each message disappears after ~3 seconds.

## Design

- Toast appears in the game board area (NOT the side panel), centred horizontally,
  positioned in the upper-third of the board
- Fade-in / slide-down enter animation (~200ms)
- Auto-dismiss after 3 seconds with fade-out (~200ms)
- If multiple events arrive quickly, queue them; show one at a time (FIFO)
- Maximum 1 toast visible at once (simplest UX)

## Implementation

### Step 1 -- Toast data model

In a new file `widgets/game/game_toast.dart`:

```dart
class _ToastEntry {
  final String message;
  final UniqueKey key;
  _ToastEntry(this.message) : key = UniqueKey();
}
```

### Step 2 -- Toast widget

```dart
class GameToastBanner extends StatefulWidget {
  const GameToastBanner({super.key, required this.message, required this.onDone});
  final String message;
  final VoidCallback onDone;
  @override
  State<GameToastBanner> createState() => _GameToastBannerState();
}

class _GameToastBannerState extends State<GameToastBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _opacity = Tween(begin: 0.0, end: 1.0).animate(_ctrl);
    _slide = Tween(begin: const Offset(0, -0.5), end: Offset.zero).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _ctrl.forward();
    Future.delayed(const Duration(seconds: 3), () async {
      if (!mounted) return;
      await _ctrl.reverse();
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(widget.message,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
        ),
      ),
    );
  }
}
```

### Step 3 -- Toast queue in game_screen.dart

Add to `_GameScreenState`:

```dart
final List<_ToastEntry> _toasts = [];
final Map<String, dynamic>? _lastToastLogEntry = null; // track last shown entry
String? _lastToastEntryId;
```

In `build`, add a `ref.listen` on `gameLogProvider`:

```dart
ref.listen(gameLogProvider(widget.roomId), (_, next) {
  next.whenData((entries) {
    if (entries.isEmpty) return;
    final top = entries.first;
    final id = top['id']?.toString();
    if (id == null || id == _lastToastEntryId) return;
    _lastToastEntryId = id;
    final msg = _formatToast(top);
    if (msg == null) return;
    setState(() => _toasts.add(_ToastEntry(msg)));
  });
});
```

### Step 4 -- Toast formatter

```dart
String? _formatToast(Map<String, dynamic> entry) {
  final action = entry['action'] as String?;
  final payload = entry['payload'] as Map<String, dynamic>? ?? {};
  final playerId = entry['player_id'] as String?;
  final players = ref.read(roomPlayersProvider(widget.roomId)).valueOrNull ?? [];
  final name = players.firstWhereOrNull((p) => p.playerId == playerId)?.displayName ?? 'Someone';

  return switch (action) {
    'roll_dice' => () {
      final roll = (payload['roll'] as List?)?.cast<int>() ?? [];
      final total = roll.fold(0, (a, b) => a + b);
      final rollStr = roll.join(' + ');
      return '$name rolled $rollStr = $total';
    }(),
    'buy_property' => () {
      final sq = payload['square'] as int?;
      final sqName = sq != null ? Board.squares[sq].name : 'a property';
      return '$name bought $sqName';
    }(),
    'rent_payment' => () {
      final amount = payload['amount'] as int?;
      return amount != null ? '$name paid £$amount rent' : null;
    }(),
    'draw_card' => '$name drew a card',
    'go_to_jail' => '$name was sent to Jail',
    'jail_break' => '$name broke out of Jail',
    _ => null,
  };
}
```

### Step 5 -- Render toasts in Stack

In `game_screen.dart` Stack, add above side panel column but within the game board area:

```dart
Positioned(
  top: 32,
  left: 0,
  right: 280, // exclude side panel
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: _toasts.map((t) => GameToastBanner(
      key: t.key,
      message: t.message,
      onDone: () => setState(() => _toasts.remove(t)),
    )).toList(),
  ),
),
```

Showing only first toast simplifies sequencing -- replace the `Column` with a single entry:

```dart
if (_toasts.isNotEmpty)
  Positioned(
    top: 32, left: 0, right: 280,
    child: Center(
      child: GameToastBanner(
        key: _toasts.first.key,
        message: _toasts.first.message,
        onDone: () => setState(() => _toasts.removeAt(0)),
      ),
    ),
  ),
```

## Files changed

| File | Change |
|------|--------|
| `game_screen.dart` | Add `_toasts` list, `ref.listen` on gameLog, `_formatToast`, and Positioned toast widget |
| `widgets/game/game_toast.dart` | New file: `_ToastEntry`, `GameToastBanner` |

## Verification

1. Roll dice → toast: "Alice rolled 3 + 4 = 7"
2. Buy property → toast: "Alice bought Mayfair"
3. Pay rent → toast: "Bob paid £200 rent"
4. Land on community chest → toast: "Alice drew a card"
5. Toasts auto-dismiss after ~3s
6. Multiple events in quick succession queue correctly
