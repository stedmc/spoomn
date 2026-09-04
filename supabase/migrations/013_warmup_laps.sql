alter table public.room_configs
  add column warmup_laps int not null default 0;

alter table public.game_state
  add column laps_completed jsonb not null default '{}';
