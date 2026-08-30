alter table public.game_rooms
  drop constraint if exists game_rooms_status_check,
  add constraint game_rooms_status_check
    check (status in ('lobby', 'starting', 'active', 'paused', 'finished'));
