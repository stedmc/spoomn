-- Cleanup service: purges stale guest profiles and abandoned/inactive games.
--
-- Safe to run any time: deleting a game_rooms row cascades (via FK) to
-- room_players, room_configs, game_state, active_traps, pending_trades and
-- game_log, so no separate per-table cleanup is needed for a game's data.
--
-- Nothing here touches player_stats / property_stats / trade_stats -- those
-- are permanent, keyed by profile_id, and already fully rolled up the moment
-- a game finishes (recordGameStats runs synchronously right after
-- game_rooms.status becomes 'finished' -- see stats_handler.dart). By the
-- time a finished game is old enough to be swept up here, its stats have
-- long since been recorded, so there is nothing left to capture before
-- deletion.

create extension if not exists pg_cron with schema extensions;

create or replace function public.last_room_activity(p_room_id uuid)
returns timestamptz
language sql
stable
as $$
  select greatest(
    gr.created_at,
    gr.started_at,
    gr.paused_at,
    gr.finished_at,
    gs.updated_at,
    (select max(gl.created_at) from public.game_log gl where gl.room_id = p_room_id)
  )
  from public.game_rooms gr
  left join public.game_state gs on gs.room_id = gr.id
  where gr.id = p_room_id;
$$;

create or replace function public.cleanup_stale_data()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Games made up entirely of guest profiles, dead for 14+ days (any status --
  -- lobbies nobody ever started included). Named-account games are kept
  -- regardless of activity so players can always find their history.
  delete from public.game_rooms gr
  where public.last_room_activity(gr.id) < now() - interval '14 days'
    and not exists (
      select 1
      from public.room_players rp
      join public.profiles p on p.id = rp.player_id
      where rp.room_id = gr.id
        and p.is_anonymous = false
    );

  -- Any game (guest or named) that never finished and has been dead for a
  -- month -- abandoned lobby/active/paused games nobody came back to.
  delete from public.game_rooms gr
  where gr.status <> 'finished'
    and public.last_room_activity(gr.id) < now() - interval '30 days';

  -- Guest profiles older than a day that are no longer part of any game.
  -- Run last so profiles freed up by the deletes above are swept in the
  -- same pass instead of waiting for the next run.
  delete from public.profiles p
  where p.is_anonymous = true
    and p.created_at < now() - interval '1 day'
    and not exists (select 1 from public.room_players rp where rp.player_id = p.id)
    and not exists (
      select 1 from public.game_rooms gr
      where gr.host_id = p.id or gr.current_player_id = p.id
    )
    and not exists (select 1 from public.active_traps trap where trap.owner_id = p.id)
    and not exists (
      select 1 from public.pending_trades pt
      where pt.proposer_id = p.id or p.id = any(pt.participants)
    );
end;
$$;

select cron.schedule(
  'spoomn-cleanup-stale-data',
  '17 3 * * *', -- daily at 03:17, off the hour to avoid piling up with other cron jobs
  $$select public.cleanup_stale_data();$$
);
