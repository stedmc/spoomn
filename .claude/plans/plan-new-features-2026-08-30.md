# Plan: New Features

Items from needtofix.md: 10, 16

---

## Item 10 — Activity log (collapsible overlay)

A scrollable, collapsible overlay showing a reverse-chronological log of game events.

### What to log

- Dice rolls (player, values, total)
- Player movement (player, from, to, property name)
- Property purchases
- Rent payments (payer, payee, amount, property)
- House/hotel builds and sells
- Mortgage / unmortgage events
- Trades (parties, assets exchanged)
- Go to Jail / Get out of Jail
- Card draws (Chance / Community Chest, card text)
- Bankruptcy
- Game start / end

### Implementation steps

1. Define an `ActivityLogEntry` model (timestamp, message string, optional player colour tag).
2. Maintain a log list in game state (server-authoritative or client-side append-on-event).
3. Build a collapsible overlay widget:
   - Toggle button (e.g. icon in a corner).
   - When expanded: scrollable `ListView` of log entries, newest at top.
   - Dismiss on tap-outside or a close button.
4. Hook event handlers throughout the game to append entries as actions occur.

### Files to create / modify

- New: `activity_log_entry.dart` model.
- New: `activity_log_overlay.dart` widget.
- Modify: game state/provider to hold the log list.
- Modify: all game event handlers to append log entries.

---

## Item 16 — Set player names in lobby

Players should be able to enter their name before the game starts.

### Implementation steps

1. Add a `name` field to the player/lobby participant model (server + client).
2. In the lobby screen, render a `TextField` for each player slot (or just the local player) to enter their name.
3. Persist the name to Supabase when confirmed (on submit / focus-out).
4. Display names throughout the game (board, activity log, turn indicator) instead of default "Player X" / "Bot X" labels.

### Files to create / modify

- Supabase: add `name` column to the relevant players/participants table (migration).
- Client: lobby screen widget — add name input field(s).
- Client: everywhere `"Player X"` is rendered, replace with the stored name.
