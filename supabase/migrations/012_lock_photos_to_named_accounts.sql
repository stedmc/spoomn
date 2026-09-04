-- Avatar/pawn photos are only editable once a profile has a permanent
-- (named) account. The client already hides the upload UI for anonymous
-- users, but that's cosmetic only -- enforce it server-side too, since
-- profiles_update_own otherwise lets any authenticated user (including
-- anonymous ones) write any column on their own row.
create or replace function public.check_anonymous_photo_lock()
returns trigger
language plpgsql
as $$
begin
  if old.is_anonymous
    and (new.avatar_url is distinct from old.avatar_url
      or new.pawn_photo_url is distinct from old.pawn_photo_url)
  then
    raise exception 'avatar_url/pawn_photo_url can only be set on a named account';
  end if;
  return new;
end;
$$;

create trigger lock_anonymous_photos
  before update on public.profiles
  for each row
  execute function public.check_anonymous_photo_lock();
