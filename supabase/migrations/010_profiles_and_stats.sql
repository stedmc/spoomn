-- Named accounts: password auth, avatar/pawn photos, permanent stats

alter table public.profiles
  add column avatar_url     text,
  add column pawn_photo_url text;

-- ============================================================
-- PLAYER STATS (1:1 profiles, server-only writes)
-- ============================================================

create table public.player_stats (
  profile_id           uuid primary key references public.profiles(id) on delete cascade,
  games_played         int not null default 0,
  wins                 int not null default 0,
  losses               int not null default 0,
  bankruptcies         int not null default 0,
  avg_placement        numeric not null default 0,
  peak_net_worth       int not null default 0,
  properties_bought    int not null default 0,
  monopolies_completed int not null default 0,
  jail_visits          int not null default 0,
  tax_paid_total       int not null default 0,
  fastest_win_turns    int,
  updated_at           timestamptz not null default now()
);

-- Per (profile, board square) ownership counts -- drives "favourite property"
create table public.property_stats (
  profile_id   uuid not null references public.profiles(id) on delete cascade,
  square_index int not null,
  times_owned  int not null default 0,
  primary key (profile_id, square_index)
);

-- Per (profile, partner) completed trade counts -- drives "favourite trading partner"
create table public.trade_stats (
  profile_id       uuid not null references public.profiles(id) on delete cascade,
  partner_id       uuid not null references public.profiles(id) on delete cascade,
  trades_completed int not null default 0,
  primary key (profile_id, partner_id)
);

-- ============================================================
-- RLS
-- ============================================================

alter table public.player_stats enable row level security;
alter table public.property_stats enable row level security;
alter table public.trade_stats enable row level security;

create policy "player_stats_select_own"
  on public.player_stats for select
  using (profile_id = auth.uid());

create policy "property_stats_select_own"
  on public.property_stats for select
  using (profile_id = auth.uid());

create policy "trade_stats_select_own"
  on public.trade_stats for select
  using (profile_id = auth.uid());

-- No client insert/update/delete on any of these -- server writes via service role.

-- ============================================================
-- AVATAR / PAWN PHOTO STORAGE
-- ============================================================

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- Path convention: {user_id}/avatar.jpg, {user_id}/pawn.jpg
create policy "avatar_public_read"
  on storage.objects for select
  using (bucket_id = 'avatars');

create policy "avatar_owner_write"
  on storage.objects for insert
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "avatar_owner_update"
  on storage.objects for update
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "avatar_owner_delete"
  on storage.objects for delete
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
