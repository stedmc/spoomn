All items below implemented:

- host can delete a game from the lobby (AppBar overflow menu) or the home game list
  (per-card overflow menu). New `POST /api/rooms/<roomId>/delete` (`deleteRoom` in
  `room_handler.dart`) is host-gated; the row delete cascades to all child tables via FK.
  Confirmation dialog on both entry points.
- loans moved from their own settings section into "Trading". Toggle subtext now reads
  "Players can lend cash to each other as part of a trade". `max_loans_per_player` removed
  entirely -- settings tile, `kRoomConfigDefaults`, custom-rule label, server allow-list,
  `RoomConfig` model, and the per-borrower cap checks in `trade_handler.dart`. Column drop:
  `supabase/migrations/016_drop_max_loans_per_player.sql`.
