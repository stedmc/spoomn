-- Add shuffled deck order to game_state
-- community_chest_deck / chance_deck: array of card indices in draw order
-- index 0 = top of deck; community_chest_index / chance_index = next draw position

alter table public.game_state
  add column community_chest_deck jsonb not null default '[]',
  add column chance_deck          jsonb not null default '[]';
