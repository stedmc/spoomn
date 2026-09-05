-- Default repayment length for a trade loan, measured in the borrower's turns.
-- Pre-filled into the loan card in the trade menu; the lender can still change
-- it per deal. Repayment is collected in equal instalments by
-- action_handler._processRepayments.

alter table public.room_configs
  add column if not exists loan_turns int not null default 10;
