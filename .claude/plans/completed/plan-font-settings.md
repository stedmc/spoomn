# Plan: Board Font Size + Settings Menu

## Problem

Board square name text is small and hard to read. There is no font size control and
no settings UI. Need a settings button that opens a menu where players can increase
the board font size (persisted locally).

## Design

- Settings gear icon in the side panel header (top-right of `GamePlayerStrip` or as
  a floating button on the game screen)
- Tapping opens a modal bottom sheet with size options
- Font sizes: Small / Medium / Large / Extra Large (maps to 10 / 12 / 14 / 16 pt board text)
- Persisted in `shared_preferences` under key `board_font_size`
- Applied immediately without restart

## Implementation

### Step 1 -- Confirm shared_preferences is available

Check `pubspec.yaml` in `spoomn_client`. If not present, add:
```yaml
shared_preferences: ^2.2.3
```
Run `flutter pub get`.

### Step 2 -- Settings provider (Riverpod)

New file `providers/settings_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kBoardFontSize = 'board_font_size';
const double kDefaultBoardFontSize = 12.0;

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override in main()');
});

final boardFontSizeProvider = NotifierProvider<BoardFontSizeNotifier, double>(
  BoardFontSizeNotifier.new,
);

class BoardFontSizeNotifier extends Notifier<double> {
  @override
  double build() {
    final prefs = ref.read(sharedPreferencesProvider);
    return prefs.getDouble(_kBoardFontSize) ?? kDefaultBoardFontSize;
  }

  Future<void> set(double size) async {
    state = size;
    await ref.read(sharedPreferencesProvider).setDouble(_kBoardFontSize, size);
  }
}
```

In `main.dart`, initialise before `runApp`:
```dart
final prefs = await SharedPreferences.getInstance();
runApp(
  ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const SpoomnApp(),
  ),
);
```

### Step 3 -- Settings bottom sheet widget

New file `widgets/game/settings_sheet.dart`:

```dart
class GameSettingsSheet extends ConsumerWidget {
  const GameSettingsSheet({super.key});

  static const _sizes = [
    ('Small', 10.0),
    ('Medium', 12.0),
    ('Large', 14.0),
    ('Extra Large', 16.0),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(boardFontSizeProvider);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Settings', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          const Text('Board font size'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _sizes.map(((label, size)) => ChoiceChip(
              label: Text(label),
              selected: current == size,
              onSelected: (_) => ref.read(boardFontSizeProvider.notifier).set(size),
            )).toList(),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
```

### Step 4 -- Settings button in side panel

In `side_panel.dart`, add a settings button to the top `SafeArea` row alongside `GamePlayerStrip`.
Or add as an `IconButton` in the top-right:

```dart
SafeArea(
  bottom: false,
  child: Stack(
    alignment: Alignment.centerRight,
    children: [
      GamePlayerStrip(roomId: widget.roomId, game: widget.game),
      IconButton(
        icon: const Icon(Icons.settings, size: 18),
        onPressed: () => showModalBottomSheet(
          context: context,
          builder: (_) => const GameSettingsSheet(),
        ),
      ),
    ],
  ),
),
```

### Step 5 -- Apply font size to board (Flame)

In `SpoomnGame`, add:
```dart
double boardFontSize = kDefaultBoardFontSize;

void setBoardFontSize(double size) {
  boardFontSize = size;
  // Notify board component to re-render
  _boardComponent?.onFontSizeChanged(size);
}
```

In `game_screen.dart`, `ref.listen` on `boardFontSizeProvider`:
```dart
ref.listen(boardFontSizeProvider, (_, size) {
  _game.setBoardFontSize(size);
});
```

In `board_component.dart`, where square name text is rendered (likely in `render` method
or a `TextComponent`), replace the hardcoded font size with `game.boardFontSize`.

If square names use Flame `TextComponent`, update their `textRenderer` when font size changes
via `onFontSizeChanged`.

## Files changed

| File | Change |
|------|--------|
| `pubspec.yaml` (client) | Add `shared_preferences` if missing |
| `main.dart` | Init SharedPreferences, add ProviderScope override |
| `providers/settings_provider.dart` | New: `sharedPreferencesProvider`, `boardFontSizeProvider` |
| `widgets/game/settings_sheet.dart` | New: `GameSettingsSheet` |
| `side_panel.dart` | Add settings IconButton |
| `spoomn_game.dart` | Add `boardFontSize`, `setBoardFontSize` |
| `game_screen.dart` | `ref.listen(boardFontSizeProvider, ...)` |
| `board_component.dart` | Use `game.boardFontSize` for text rendering |

## Verification

1. Open settings → see font size options
2. Select "Large" → board text immediately increases
3. Close and reopen app → font size preference persists
4. Test on smallest supported screen → Extra Large doesn't clip square names
