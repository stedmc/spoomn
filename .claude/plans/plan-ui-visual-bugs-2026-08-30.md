# Plan: UI / Visual Bugs

Items from needtofix.md: 1, 2, 3, 13, 14

---

## Item 1 — Swap +/- buttons in buy house/hotel overlay

- In the buy house overlay widget, locate the row that renders the +/- controls.
- Swap their positions so `-` is on the left and `+` is on the right.
- Verify both hotel and house overlays are fixed (they may share a widget or be separate).

## Item 2 — Grey out mortgaged properties on the board

- Find the board tile rendering logic.
- When a property's `isMortgaged` flag is true, apply a grey colour overlay or reduced opacity to the tile.
- Ensure the mortgage state is passed down to the tile widget correctly.

## Item 3 — Unreadable selected value in 'Assign owner' and 'Force dice' dropdowns

- Locate the `DropdownButton` / `DropdownButtonFormField` widgets for Assign owner and Force dice.
- The selected value text colour is black on a dark background. Fix by explicitly setting `style: TextStyle(color: ...)` on the selected item to a readable colour (e.g. white or the theme's onSurface).
- Check if a custom `DropdownMenuItem` style is needed for the selected state vs open-menu state.

## Item 13 — Add 'x2 base if whole colour group owned' text to property cards

- Find the property card widget.
- Add a small text label below the base rent value: e.g. `"x2 if full set owned"`.
- Use the existing card text style; keep it small/secondary so it doesn't clutter.

## Item 14 — Highlight the current rent value on property cards

- In the property card widget, determine the active rent tier based on the property's current state (no houses, 1–4 houses, hotel).
- Wrap or style the matching rent row to visually highlight it (e.g. bold, coloured background, border).
- All other tiers should appear at normal/reduced opacity.

---

## Files to investigate

- `packages/spoomn_client/lib/` — search for buy house overlay, board tile widget, property card widget, admin/debug overlay dropdowns.
