-- Row-Level Security policies for Spoomn
-- Server connects with service role key (bypasses RLS).
-- Clients connect with anon/user JWT (subject to these policies).

-- ============================================================
-- ENABLE RLS
-- ============================================================

alter table public.profiles enable row level security;
alter table public.game_rooms enable row level security;
alter table public.room_players enable row level security;
alter table public.room_configs enable row level security;
alter table public.game_state enable row level security;
alter table public.active_traps enable row level security;
alter table public.pending_trades enable row level security;
alter table public.game_log enable row level security;

-- ============================================================
-- HELPER
-- ============================================================

-- Stable, inlinable helper used by all room-scoped policies
create or replace function public.player_in_room(room_id uuid)
returns boolean as $$
  select exists (
    select 1 from public.room_players
    where room_players.room_id = $1
      and room_players.player_id = auth.uid()
      and room_players.left_at is null
  );
$$ language sql security definer stable;

-- ============================================================
-- PROFILES
-- ============================================================

-- Players read their own profile only
create policy "profiles_select_own"
  on public.profiles for select
  using (id = auth.uid());

-- Players update their own profile only (display_name, push_token, etc.)
create policy "profiles_update_own"
  on public.profiles for update
  using (id = auth.uid());

-- Players can read profiles of others in same room (for display names)
create policy "profiles_select_roommate"
  on public.profiles for select
  using (
    id in (
      select player_id from public.room_players rp
      where public.player_in_room(rp.room_id)
        and rp.left_at is null
    )
  );

-- ============================================================
-- GAME ROOMS
-- ============================================================

create policy "rooms_select_member"
  on public.game_rooms for select
  using (public.player_in_room(id));

-- ============================================================
-- ROOM PLAYERS
-- ============================================================

create policy "room_players_select_member"
  on public.room_players for select
  using (public.player_in_room(room_id));

-- ============================================================
-- ROOM CONFIGS
-- ============================================================

create policy "room_configs_select_member"
  on public.room_configs for select
  using (public.player_in_room(room_id));

-- ============================================================
-- GAME STATE
-- ============================================================

-- Read-only for clients; all writes go through server service key
create policy "game_state_select_member"
  on public.game_state for select
  using (public.player_in_room(room_id));

-- ============================================================
-- ACTIVE TRAPS
-- ============================================================

-- Visible traps in room: all members can see
-- Invisible traps: only the owner sees them
create policy "active_traps_select"
  on public.active_traps for select
  using (
    public.player_in_room(room_id)
    and (visible = true or owner_id = auth.uid())
  );

-- ============================================================
-- PENDING TRADES
-- ============================================================

create policy "pending_trades_select_member"
  on public.pending_trades for select
  using (public.player_in_room(room_id));

-- ============================================================
-- GAME LOG
-- ============================================================

create policy "game_log_select_member"
  on public.game_log for select
  using (public.player_in_room(room_id));
