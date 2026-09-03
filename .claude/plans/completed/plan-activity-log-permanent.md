# Plan: Activity Log Permanently Open

## Problem

The activity log is hidden behind a toggle button in the side panel. The toggle row
(`_showLog`, IconButton, the "Property Info" / "Activity Log" label) takes up space
and adds friction. The log should always be visible.

The property card is being moved to a floating popup (see plan-property-card-popup.md),
so the side panel no longer needs a toggle between two modes.

## Current state in side_panel.dart

```dart
bool _showLog = false;  // state field

Row(
  children: [
    Padding(..., child: Text(_showLog ? 'Activity Log' : 'Property Info', ...)),
    const Spacer(),
    IconButton(
      icon: Icon(_showLog ? Icons.close : Icons.history),
      onPressed: () => setState(() => _showLog = !_showLog),
    ),
  ],
),
const Divider(height: 1),
Expanded(
  child: _showLog
      ? GameActivityLog(roomId: widget.roomId)
      : GameSquareHoverCard(roomId: widget.roomId, game: widget.game),
),
```

## Fix

### Step 1 -- Delete toggle state and Row

Remove `bool _showLog` field. Delete the entire `Row(...)` + its `Padding` + the `Divider`
that follows it.

### Step 2 -- Replace Expanded with always-open log

```dart
Expanded(child: GameActivityLog(roomId: widget.roomId)),
```

### Step 3 -- Remove GameSquareHoverCard import (if now unused)

`property_card.dart` import is still needed if `GamePropertyCard` is used elsewhere (it is,
in the floating popup from plan-property-card-popup). Keep the import.

### Step 4 -- Optional: add section label

Above the Expanded log, add a small persistent label:

```dart
Padding(
  padding: const EdgeInsets.fromLTRB(12, 4, 0, 2),
  child: Text('Activity Log', style: Theme.of(context).textTheme.labelSmall),
),
const Divider(height: 1),
```

## Files changed

| File | Change |
|------|--------|
| `side_panel.dart` | Remove `_showLog` field, toggle Row, and conditional; always render `GameActivityLog` |

## Verification

1. Start a game
2. Side panel shows activity log immediately without pressing any button
3. Log scrolls as turns happen
4. Property card no longer appears in the side panel (only as floating popup)
