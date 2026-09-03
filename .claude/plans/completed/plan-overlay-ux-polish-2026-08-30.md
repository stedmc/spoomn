# Plan: Overlay / UX Polish

Items from needtofix.md: 4, 6

---

## Item 4 — Remove debug toggle from 'Start game' overlay

- Find the Start Game overlay widget.
- Remove the debug toggle control entirely.
- Verify no other code depends on the toggle value (if it was wiring to a debug flag, confirm the flag can be safely removed or hardcoded to off).

## Item 6 — Move close button to top-right of 'game is starting' overlay

- Find the "game is starting / play order" overlay widget.
- Reposition the close/dismiss button to the top-right corner.
- Standard approach: wrap in a `Stack` with a `Positioned` close button, or use a `Row`/`AppBar`-style header with the close icon on the right.

---

## Files to investigate

- `packages/spoomn_client/lib/` — search for start game overlay and game-starting / play order overlay widgets.
