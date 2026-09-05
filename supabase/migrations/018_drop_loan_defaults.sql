-- Loan amount, interest rate and repayment length are no longer game settings.
-- Players choose these per deal in the trade window, so the room-config columns
-- and their defaults are removed.

alter table public.room_configs
  drop column if exists loan_amount,
  drop column if exists loan_interest_rate,
  drop column if exists loan_turns;
