-- profiles was never added to the realtime publication, so myProfileProvider's
-- .stream() subscribe fails (RealtimeSubscribeException), causing the profile
-- screen to loop retrying the REST fallback fetch.
alter publication supabase_realtime add table public.profiles;
