-- Without FULL replica identity, UPDATE events (e.g. accepted_by changing) only
-- carry the primary key in the WAL, so Supabase Realtime clients don't receive
-- the full updated row. Setting FULL ensures all columns stream on every UPDATE,
-- so the trade overlay reflects live acceptance/counter state for all players.
alter table public.pending_trades replica identity full;
