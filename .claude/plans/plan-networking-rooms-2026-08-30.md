# Plan: Networking / Game Rooms

Items from needtofix.md: 5

---

## Item 5 — Duplicate game rooms in game list (1 per player instead of 1 per room)

Each game room appears once per player rather than once per room.

### Debug first (per item 17 rule)

- Add console logs to the game list fetch/subscribe logic to inspect the raw data returned.
- Log: how many rows/records are returned, what fields they have, whether they are deduplicated.
- Create `.claude/bugs/bug-duplicate-game-rooms.md` to track findings.

### Likely cause

- The query joining game rooms to players returns one row per player. The client displays each row instead of grouping/deduplicating by room ID.
- Fix options (once confirmed):
  - Deduplicate on the client by room ID before rendering.
  - Fix the server query/view to return one row per room (with player list aggregated).

### Files to investigate

- Supabase: `supabase/` — check the query or realtime subscription for the game room list.
- Client: the widget/provider that fetches and displays the game list.
