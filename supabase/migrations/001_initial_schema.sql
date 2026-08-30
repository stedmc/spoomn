-- Initial schema for Spoomn
-- Run via: supabase db push

create extension if not exists "uuid-ossp";

-- ============================================================
-- PROFILES
-- ============================================================

create table public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  display_name  text not null,
  is_anonymous  boolean not null default true,
  device_token  text,
  push_token    text,
  push_platform text check (push_platform in ('ios', 'android', 'web')),
  created_at    timestamptz not null default now()
);

-- Auto-create profile row when Supabase Auth creates a user
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, display_name, is_anonymous)
  values (
    new.id,
    'Guest_' || upper(substring(replace(new.id::text, '-', ''), 1, 4)),
    true
  )
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ============================================================
-- GAME ROOMS
-- ============================================================

create table public.game_rooms (
  id                uuid primary key default gen_random_uuid(),
  room_code         text not null unique,
  status            text not null default 'lobby'
                      check (status in ('lobby', 'active', 'paused', 'finished')),
  host_id           uuid not null references public.profiles(id),
  current_player_id uuid references public.profiles(id),
  play_mode         text not null default 'realtime'
                      check (play_mode in ('realtime', 'async')),
  turn_started_at   timestamptz,
  player_count      int not null default 0 check (player_count between 0 and 8),
  max_players       int not null default 8 check (max_players between 2 and 8),
  created_at        timestamptz not null default now(),
  started_at        timestamptz,
  paused_at         timestamptz,
  finished_at       timestamptz,
  constraint room_code_format check (room_code ~ '^[A-Z0-9]{6}$')
);

-- ============================================================
-- ROOM PLAYERS
-- ============================================================

create table public.room_players (
  id           uuid primary key default gen_random_uuid(),
  room_id      uuid not null references public.game_rooms(id) on delete cascade,
  player_id    uuid not null references public.profiles(id),
  seat_order   int,
  token_colour text,
  is_bankrupt  boolean not null default false,
  is_connected boolean not null default false,
  joined_at    timestamptz not null default now(),
  left_at      timestamptz,
  unique (room_id, player_id)
);

-- Partial unique indexes: only enforce uniqueness for active players
create unique index room_players_seat_order_idx
  on public.room_players (room_id, seat_order)
  where seat_order is not null and left_at is null;

create unique index room_players_token_colour_idx
  on public.room_players (room_id, token_colour)
  where token_colour is not null and left_at is null;

-- ============================================================
-- ROOM CONFIGS
-- ============================================================

create table public.room_configs (
  room_id                      uuid primary key references public.game_rooms(id) on delete cascade,
  -- Setup
  starting_money               int not null default 1500,
  bank_unlimited               boolean not null default false,
  bank_starting_amount         int not null default 20580,
  house_limit                  int default 32,
  hotel_limit                  int default 12,
  turn_order_method            text not null default 'highest_roll',
  -- Dice
  dice_count                   int not null default 2,
  dice_sides                   int not null default 6,
  doubles_enabled              boolean not null default true,
  doubles_extra_turn           boolean not null default true,
  jail_on_consecutive_doubles  int default 3,
  -- Movement
  go_salary                    int not null default 200,
  go_landing_bonus             int not null default 0,
  -- Rent
  auto_claim_rent              boolean not null default true,
  -- Tax
  income_tax_type              text not null default 'fixed',
  income_tax_amount            int not null default 200,
  income_tax_percentage        int not null default 10,
  super_tax_amount             int not null default 100,
  -- Free parking
  free_parking_jackpot         boolean not null default false,
  free_parking_starting_amount int not null default 0,
  -- Turn timer
  max_turn_time_secs           int,
  -- Jail
  jail_fine                    int not null default 50,
  jail_turns                   int not null default 3,
  jail_doubles_escape          boolean not null default true,
  collect_go_while_in_jail     boolean not null default false,
  -- Jailbreak
  jailbreak_enabled            boolean not null default false,
  jailbreak_mandatory_turns    int not null default 3,
  jailbreak_fine_multiplier    int not null default 2,
  police_check_mode            text not null default 'final',
  police_duration              int,
  -- Buildings
  must_build_evenly            boolean not null default true,
  hotel_requires_four_houses   boolean not null default true,
  houses_returned_on_hotel     boolean not null default true,
  build_own_turn_only          boolean not null default false,
  sell_building_rate           numeric(3,2) not null default 0.50,
  -- Mortgage
  mortgage_rate                numeric(3,2) not null default 0.50,
  unmortgage_interest_rate     numeric(3,2) not null default 0.10,
  trade_mortgaged_properties   boolean not null default true,
  mortgage_transfer_penalty    numeric(3,2) not null default 0.10,
  -- Auctions
  auction_on_decline           boolean not null default true,
  auction_style                text not null default 'ascending',
  auction_starting_bid         int not null default 1,
  auction_min_raise            int not null default 1,
  auction_time_per_bid_secs    int not null default 30,
  auction_blind_time_secs      int not null default 60,
  auction_min_bid              int not null default 1,
  dutch_start_price            int,
  dutch_decrement              int not null default 10,
  dutch_interval_secs          int not null default 5,
  dutch_floor_price            int not null default 1,
  -- Trading
  trade_any_turn               boolean not null default false,
  multi_party_trades           boolean not null default false,
  trade_futures                boolean not null default false,
  trade_timeout_secs           int,
  -- Cards
  custom_community_chest       jsonb,
  custom_chance                jsonb,
  -- Winning
  winning_condition            text not null default 'last_player_standing',
  net_worth_target             int not null default 10000,
  net_worth_check              text not null default 'end_of_turn',
  turn_limit                   int not null default 30,
  time_limit_mins              int not null default 60,
  -- Bankruptcy
  bankruptcy_assets_to         text not null default 'creditor',
  allow_bankruptcy_negotiation boolean not null default false,
  negotiation_timeout_secs     int not null default 120,
  repayment_interest_rate      numeric(4,3) not null default 0.000,
  -- Loans
  loans_enabled                boolean not null default false,
  loan_amount                  int not null default 200,
  loan_interest_rate           numeric(3,2) not null default 0.10,
  max_loans_per_player         int not null default 3,
  -- Async
  async_turn_timeout_hours     int,
  async_turn_reminder_hours    int,

  created_at timestamptz not null default now()
);

-- ============================================================
-- GAME STATE
-- ============================================================

create table public.game_state (
  room_id               uuid primary key references public.game_rooms(id) on delete cascade,
  turn_number           int not null default 0,
  phase                 text not null default 'roll',
  dice_roll             int[],
  consecutive_doubles   int not null default 0,
  board_positions       jsonb not null default '{}',   -- { player_id: square_index }
  property_ownership    jsonb not null default '{}',   -- { square_index: player_id }
  houses                jsonb not null default '{}',   -- { square_index: count }
  hotels                jsonb not null default '{}',   -- { square_index: true }
  mortgaged             jsonb not null default '[]',   -- [square_index]
  balances              jsonb not null default '{}',   -- { player_id: amount }
  jail_status           jsonb not null default '{}',   -- { player_id: JailStatus }
  get_out_of_jail_cards jsonb not null default '{}',   -- { player_id: count }
  community_chest_index int not null default 0,
  chance_index          int not null default 0,
  free_parking_pot      int not null default 0,
  active_police_pawns   jsonb not null default '[]',   -- [PolicePawn]
  rent_modifiers        jsonb not null default '{}',   -- { player_id: RentModifiers }
  repayment_plans       jsonb not null default '[]',   -- [RepaymentPlan]
  pending_action        jsonb,
  active_auction        jsonb,
  updated_at            timestamptz not null default now()
);

-- ============================================================
-- ACTIVE TRAPS (separate table for RLS-based visibility)
-- ============================================================

create table public.active_traps (
  id                 uuid primary key default gen_random_uuid(),
  room_id            uuid not null references public.game_rooms(id) on delete cascade,
  owner_id           uuid not null references public.profiles(id),
  square_index       int not null,
  visible            boolean not null default true,
  source_card_id     text not null,
  triggers_remaining int,              -- null = unlimited
  placed_turn        int not null,
  trigger_effect     jsonb not null,
  created_at         timestamptz not null default now()
);

-- ============================================================
-- PENDING TRADES
-- ============================================================

create table public.pending_trades (
  id           uuid primary key default gen_random_uuid(),
  room_id      uuid not null references public.game_rooms(id) on delete cascade,
  proposer_id  uuid not null references public.profiles(id),
  participants uuid[] not null,
  legs         jsonb not null,         -- [{ from, to, properties, money, jail_cards, futures }]
  status       text not null default 'pending'
                 check (status in ('pending', 'countered', 'accepted', 'rejected', 'cancelled')),
  created_at   timestamptz not null default now(),
  resolved_at  timestamptz
);

-- ============================================================
-- GAME LOG
-- ============================================================

create table public.game_log (
  id          bigint primary key generated always as identity,
  room_id     uuid not null references public.game_rooms(id) on delete cascade,
  player_id   uuid references public.profiles(id),
  turn_number int not null,
  action      text not null,
  payload     jsonb not null default '{}',
  created_at  timestamptz not null default now()
);

-- ============================================================
-- INDEXES
-- ============================================================

create unique index game_rooms_room_code_idx
  on public.game_rooms (room_code);

create index room_players_player_active_idx
  on public.room_players (player_id)
  where left_at is null;

create index game_log_room_idx
  on public.game_log (room_id, created_at desc);

create index active_traps_room_idx
  on public.active_traps (room_id);

create index pending_trades_room_active_idx
  on public.pending_trades (room_id)
  where status in ('pending', 'countered');
