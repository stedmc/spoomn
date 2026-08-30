alter table public.room_configs
  add column if not exists debug_mode boolean not null default false;
