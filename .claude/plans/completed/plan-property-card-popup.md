# Plan: Property Card Popup Near Tap/Hover

## Problem

`GameSquareHoverCard` renders inside the side panel's Expanded section. User wants the card
to float near the mouse cursor (desktop) or tap position (mobile), and tap anywhere to dismiss.

## Current state

- `SpoomnGame` exposes `ValueNotifier<int?> hoveredSquare` and `tappedSquare`
- `side_panel.dart` renders `GameSquareHoverCard` in its Expanded area when either is set
- No position tracking exists

## Fix

### Step 1 -- Track interaction position in SpoomnGame (`spoomn_game.dart`)

Add a new notifier alongside the existing square-index ones:

```dart
final ValueNotifier<Offset?> squareTapAnchor = ValueNotifier(null);
```

### Step 2 -- Emit position from board_component.dart

In the tap/hover handlers that currently set `game.tappedSquare` / `game.hoveredSquare`,
also set `game.squareTapAnchor`:

```dart
// On tap
game.squareTapAnchor.value = Offset(info.eventPosition.global.x, info.eventPosition.global.y);
// On hover
game.squareTapAnchor.value = Offset(info.eventPosition.global.x, info.eventPosition.global.y);
// On hover exit / tap clear
game.squareTapAnchor.value = null;
```

### Step 3 -- Add floating popup to game_screen.dart Stack

In `_GameScreenState.build`, add a `ListenableBuilder` watching both notifiers:

```dart
ListenableBuilder(
  listenable: Listenable.merge([_game.tappedSquare, _game.hoveredSquare, _game.squareTapAnchor]),
  builder: (context, _) {
    final squareIdx = _game.tappedSquare.value ?? _game.hoveredSquare.value;
    final anchor = _game.squareTapAnchor.value;
    if (squareIdx == null || anchor == null) return const SizedBox.shrink();
    const cardW = 220.0;
    const cardH = 360.0;
    final screenW = MediaQuery.sizeOf(context).width;
    final screenH = MediaQuery.sizeOf(context).height;
    final left = (anchor.dx + 16).clamp(0.0, screenW - cardW);
    final top = (anchor.dy - 40).clamp(0.0, screenH - cardH);
    return Positioned(
      left: left, top: top,
      child: _PropertyPopup(roomId: widget.roomId, game: _game, squareIndex: squareIdx),
    );
  },
),
```

`_PropertyPopup` is a new private widget that composes `GamePropertyCard` + `GameDebugAssignCard`
(the same content currently in `GameSquareHoverCard`, just extracted). Pass `roomId` and `squareIndex`.

### Step 4 -- Tap-to-dismiss

In `board_component.dart`, in the handler that sets `tappedSquare`, add toggle logic:

```dart
if (game.tappedSquare.value == tappedSquareIndex) {
  // same square tapped again → dismiss
  game.tappedSquare.value = null;
  game.squareTapAnchor.value = null;
} else {
  game.tappedSquare.value = tappedSquareIndex;
}
```

For tapping a non-property area (board centre, etc.), set both to null.

Debug mode exception: when debug assign dropdown is open (`GameDebugAssignCard`), do NOT
dismiss on outside tap. `_PropertyPopup` can expose a `bool isAssigning` state and if true,
skip the dismiss logic.

### Step 5 -- Remove from side_panel.dart

Delete the toggle row (the Row with `_showLog`, the IconButton, and the `Divider`).
Replace the `Expanded` child with `GameActivityLog` unconditionally (ties to plan-activity-log-permanent).

## Files changed

| File | Change |
|------|--------|
| `spoomn_game.dart` | Add `squareTapAnchor` ValueNotifier |
| `board_component.dart` | Set anchor on tap/hover; toggle dismiss |
| `game_screen.dart` | Add ListenableBuilder + Positioned popup in Stack |
| `side_panel.dart` | Remove toggle row and `GameSquareHoverCard` reference |
| `property_card.dart` | Extract popup widget (`_PropertyPopup`) or reuse `GameSquareHoverCard` body |

## Verification

1. Hover over a board square → card floats near cursor
2. Tap a board square → card floats near tap point
3. Tap same square again → card dismisses
4. Tap centre of board (no square) → card dismisses
5. In debug mode, open assign dropdown → card stays open until explicitly changed
