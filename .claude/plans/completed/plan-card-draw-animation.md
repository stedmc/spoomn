# Plan: Card Draw Animation Fix

## Problems

1. Animation not visible / not noticeable -- slide offset too subtle (15% of widget height).
2. Non-drawing players see card back instead of card face -- defeats the "open for all to
   see" requirement.

## Fix

### Step 1 -- Show card face to all players (`card_draw_overlay.dart`)

Remove `isMyCard` entirely. Always render `_CardFace`. Delete `_CardBack` class.

```dart
// Remove field:
// final bool isMyCard;

// Replace conditional with direct:
// widget.isMyCard ? _CardFace(...) : _CardBack(...)
_CardFace(
  deckLabel: deckLabel,
  label: label,
  faceColor: faceColor,
  bgColor: bgColor,
)

// Delete entire _CardBack class
```

### Step 2 -- Fix call site (`game_screen.dart`, line ~168)

```dart
// Before
CardDrawOverlay(
  entry: _cardDrawEntry!,
  isMyCard: myId != null && myId == (_cardDrawEntry!['player_id'] as String?),
  onDismiss: ...,
)

// After
CardDrawOverlay(
  entry: _cardDrawEntry!,
  onDismiss: ...,
)
```

### Step 3 -- Make animation dramatic (`card_draw_overlay.dart`)

Replace the subtle slide/fade with a pop-in scale effect that is unmissable:

- `_scale`: `Tween<double>(begin: 0.0, end: 1.0)` with `Curves.elasticOut`, 600ms
- `_fade`: keep existing but shorten to 150ms (card appears fast, scale does the drama)
- Remove `_slide` (replaced by scale)

```dart
_controller = AnimationController(
  vsync: this,
  duration: const Duration(milliseconds: 600),
);
_scale = Tween<double>(begin: 0.0, end: 1.0)
    .animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
_fade = Tween<double>(begin: 0.0, end: 1.0)
    .animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.25, curve: Curves.easeIn),
    ));
```

Wrap card widget:
```dart
FadeTransition(
  opacity: _fade,
  child: ScaleTransition(
    scale: _scale,
    child: _CardFace(...),
  ),
)
```

Auto-dismiss timer stays at 5s. `_controller.forward()` in `initState` unchanged.

### Optional -- Flip reveal (if simple pop-in feels insufficient)

Phase 1 (0-300ms): scale X from 1.0 -> 0.0 while showing a card back placeholder
Phase 2 (300-600ms): scale X from 0.0 -> 1.0 while showing the card face

Implement with a second `AnimationController` and a `bool _flipped` toggled at the midpoint
via `addStatusListener`. More impressive but more code -- implement as enhancement if the
elasticOut pop-in is not satisfying enough.

## Files Changed

| File | Change |
|------|--------|
| `packages/spoomn_client/lib/src/widgets/game/card_draw_overlay.dart` | Remove `isMyCard`, delete `_CardBack`, replace slide with scale animation |
| `packages/spoomn_client/lib/src/screens/game_screen.dart` | Remove `isMyCard:` param |

## Verification

1. Any player lands on chance/community chest
2. All players (including non-drawers) see the card face with the card text visible
3. Animation is clearly visible: card pops in from nothing, elasticOut gives slight overshoot
4. Card stays for 5s then dismisses (or tap to dismiss early)
