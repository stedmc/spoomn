All items below implemented:

- cleanup service: `supabase/migrations/015_cleanup_stale_data.sql` (`public.cleanup_stale_data`,
  scheduled daily via pg_cron). Deletes guest-only games idle 14+ days, any incomplete game idle
  30+ days, and orphaned guest profiles older than 1 day. Game deletion cascades to all child
  tables via FK. Stats are unaffected -- already permanently rolled up at game-finish time in
  `stats_handler.dart`, before any cleanup runs. See "Data Retention" in
  `docs/architecture/03-data-model.md`.
- game rooms already transition to `status: 'finished'` on completion (`action_handler.dart`) --
  no fix needed there, just confirmed as a precondition for the cleanup rules above.
- new stats: `total_squares_moved`, `total_squares_moved_backward` added to `player_stats`
  (`014_movement_stats.sql`), computed in `stats_handler.dart`. `games_played` already existed.
