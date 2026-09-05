-- Loans are player-to-player deals struck inside a trade; there is no
-- per-borrower cap any more, so the setting and its column are removed.

alter table public.room_configs
  drop column if exists max_loans_per_player;
