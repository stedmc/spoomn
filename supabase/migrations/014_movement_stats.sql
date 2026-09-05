-- Movement stats: total squares moved, and the subset of that moved backward
-- (currently only possible via the "Go back three spaces" chance card).
-- Rolled up by recordGameStats alongside the rest of player_stats.

alter table public.player_stats
  add column total_squares_moved          int not null default 0,
  add column total_squares_moved_backward int not null default 0;
