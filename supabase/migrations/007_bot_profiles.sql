-- Allow bot profiles without a backing auth user
alter table public.profiles drop constraint profiles_id_fkey;
alter table public.profiles add column is_bot boolean not null default false;
