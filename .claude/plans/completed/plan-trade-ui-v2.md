# Plan: Trade UI v2 — Issues & Implementation

## Issues

| # | Issue | Priority |
|---|-------|----------|
| 1 | Chips → full property cards | High |
| 2 | Cash as a draggable card | High |
| 3 | Drag broken — essential | Critical |
| 4 | Modal too small | High |
| 5 | Long lists: stack same-colour vertically | Medium |
| 6 | Cash capped at available balance | High |
| 7 | Debug mode: bot accept/counter clickable | Medium |
| 8 | Trade-in-progress: show both sides exactly | High |

---

## Issue Detail & Root Causes

### 1 — Full property cards instead of chips

Current `_AssetChip` is a 9px-text rounded rectangle with a 3-letter abbreviation.

Replace with a new `_TradePropertyCard` widget:
- 100px wide × 130px tall
- Colour band (24px, same as `GamePropertyCard`)
- Property name (bold, 12px, 2-line max)
- Price line (11px)
- Mortgaged badge if applicable
- No rent table (too tall)
- Stations: train icon + name + "£25/50/100/200"
- Utilities: bolt/drop icon + name

Reuse `groupColour()` and the same visual language as `GamePropertyCard`.

### 2 — Cash as a draggable card

Each player section gets a `_CashCard` alongside their property cards.

- Same height as `_TradePropertyCard` (130px), width 90px
- Green gradient background, £ symbol, large amount display
- **Amount entry**: tapping opens a numeric field inline (or bottom sheet)
- Once amount > 0: card becomes `Draggable<_TradeCardData>` (see §3)
- Amount capped at player's current balance (see §6)
- One cash card per player per section — can be dragged to any counterparty header

### 3 — Drag broken — use `Draggable` / `DragTarget`

Root cause: current implementation has `_dragFrom`/`_dragCurrent` state vars but no actual `GestureDetector` `onPan*` handlers wired to chips. Manual pan tracking on a widget inside a `SingleChildScrollView` also fights scroll gestures.

Fix: replace entirely with Flutter's `Draggable<_TradeCardData>` + `DragTarget<_TradeCardData>`.

```dart
// Data passed during drag
class _TradeCardData {
  final String ownerId;
  final int? propIndex;   // null = cash card
  final int? amount;      // non-null for cash card
}
```

Each `_TradePropertyCard` is wrapped in:
```dart
Draggable<_TradeCardData>(
  data: _TradeCardData(ownerId: pid, propIndex: idx),
  feedback: Material(child: _TradePropertyCard(..., width: 90)),  // drag ghost
  childWhenDragging: Opacity(opacity: 0.4, child: _TradePropertyCard(...)),
  child: _TradePropertyCard(...),
)
```

Each player section header becomes:
```dart
DragTarget<_TradeCardData>(
  onWillAcceptWithDetails: (details) => details.data.ownerId != playerId,
  onAcceptWithDetails: (details) {
    if (details.data.propIndex != null) {
      _chipAssignments['${details.data.ownerId}:${details.data.propIndex}'] = playerId;
    } else {
      _moneyAssignments[details.data.ownerId] = (targetPlayerId: playerId, amount: details.data.amount!);
    }
    setState(() {});
  },
  builder: (ctx, candidates, rejected) => _PlayerHeader(
    player: player,
    isTarget: candidates.isNotEmpty,
  ),
)
```

**Arrows**: Keep `CustomPaint` arrows for confirmed assignments. Remove drag ghost arrow state (`_dragFrom`, `_dragCurrent`) — `Draggable.feedback` handles the ghost widget. Simplifies `_ArrowPainter` to only draw confirmed assignments.

**Scroll conflict**: `Draggable` works alongside `SingleChildScrollView` — Flutter resolves the gesture arena correctly (hold briefly to start drag, tap to scroll). No special handling needed.

### 4 — Large modal

Current: `SizedBox(width: 480)` card centered in 54% black scrim.

Fix:
- Phase 2 (assignment): `Dialog.fullscreen` or constrain to `(screenWidth - 32) × (screenHeight - 64)` — nearly full screen.
- Phase 1 (player selection): keep centered card, widen to 500px max.
- Phase 3 (response): two-panel layout (see §8), needs full width.

Use `LayoutBuilder` → read `constraints.maxWidth/maxHeight` → size card accordingly.

### 5 — Vertical stacking for long property lists

Current: `SingleChildScrollView(scrollDirection: Axis.horizontal)` of flat property cards.

Fix: group properties by `colourGroup` (for properties) or type (stations together, utilities together) and display as grouped columns.

Layout per player section:

```
[brown col] [lightBlue col] [pink col] ... [stations col] [utilities col]
  OKR          Angel          PallM       KingsCross       Electric
  Whitechapel  Euston         Whitehall   Marylebone       WaterWorks
               Pentonville    NorthAve    Fenchurch
                                          Liverpool
```

Each column = `Column` of `_TradePropertyCard` widgets.
Row of columns = `SingleChildScrollView(horizontal)` wrapping a `Row` of columns.
Column width: card width (100px) + 8px gap.

Group order: brown, lightBlue, pink, orange, red, yellow, green, darkBlue, stations, utilities.

### 6 — Cash cap at available balance

Current: `TextField` with `FilteringTextInputFormatter.digitsOnly`, no max.

Fix: add `onChanged` validator that clamps to `state?.balances[playerId] ?? 0`. Show balance in small text below the field: "Balance: £N".

```dart
final balance = state?.balances[playerId] ?? 0;
onChanged: (v) {
  final parsed = int.tryParse(v) ?? 0;
  if (parsed > balance) moneyController.text = balance.toString();
},
```

Also disable the cash card drag when amount == 0 or exceeds balance.

### 7 — Debug mode: bot response buttons

Current: response mode only shows buttons for the player matching `effectivePlayerId`.

Fix: when `isDebug` is true, show ALL participants' response buttons. Label each section with the player name.

```dart
if (isDebug) {
  // Show one row per non-proposer participant
  for (final pid in participants.where((p) => p != proposerId)) {
    Column([
      Text('${name(pid)}:'),
      Row([acceptBtn(pid), refuseBtn(pid), counterBtn(pid)]),
    ])
  }
} else {
  // Current single-player logic
}
```

Actions submitted with `debug_as: pid` in the payload so server validates as that player.

### 8 — Trade-in-progress: show both perspectives

Current: single `_TradeLegSummary` text list.

Fix: two-panel layout. For a 2-party trade A→B:

```
┌─────────────────────┬─────────────────────┐
│  Player A (Offering) │  Player B (Receiving) │
│  ─────────────────  │  ─────────────────  │
│  [Their card stack] │  [Their card stack] │
│  → giving to B:     │  ← getting from A:  │
│    [propCard] [£50] │    [propCard] [£50] │
│  ← getting from B:  │  → giving to A:     │
│    [propCard]       │    [propCard]        │
│                     │                     │
│  [Cancel Trade]     │  [Accept][Refuse]   │
│                     │  [Counter]          │
└─────────────────────┴─────────────────────┘
```

Each panel:
- Player avatar + name header with token colour
- "Giving" section: `_TradePropertyCard` widgets for properties going OUT, cash card for money going OUT
- "Receiving" section: property cards + cash coming IN
- Role-appropriate action buttons at bottom of panel

For 3+ party trades: panels stacked vertically or scrollable row of panels.

For spectators: same two-panel view, all buttons disabled (greyed out).

---

## Files to Change

| File | Changes |
|------|---------|
| `trade_overlay.dart` | Full rewrite of phase 2 and phase 3 UI; add `_TradePropertyCard`, `_CashCard`; replace `_AssetChip`; switch to `Draggable`/`DragTarget`; widen modal; cash cap; grouped layout |
| `trade_overlay.dart` | Add `isDebug` param (read from `isDebugModeProvider`) |
| No new files needed | All changes in `trade_overlay.dart` |

Estimated size after rewrite: ~600-700 lines.

---

## Implementation Order

1. Fix drag (`Draggable`/`DragTarget`) — unblocks visual testing
2. Full property cards (`_TradePropertyCard`) + large modal
3. Grouped vertical layout (§5)
4. Cash card + balance cap (§2, §6)
5. Split-screen trade-in-progress view (§8)
6. Debug bot buttons (§7)
