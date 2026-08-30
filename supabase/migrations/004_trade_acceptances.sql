-- Track which participants have accepted a pending trade
alter table public.pending_trades
  add column accepted_by uuid[] not null default '{}';
