-- Leaders log captures themselves. Run once in Supabase > SQL Editor, AFTER the other two files.
-- Only touches "manhunt_" objects. It also replaces manhunt_save so the scorekeeper's phone can never
-- silently overwrite a capture a leader just logged (it refuses stale saves instead).

drop function if exists public.manhunt_save(text, jsonb);

create or replace function public.manhunt_save(pw text, new_state jsonb, base_at timestamptz default null)
returns timestamptz
language plpgsql security definer set search_path = public as $$
declare cur timestamptz;
begin
  if not manhunt_check(pw) then raise exception 'bad password'; end if;
  select updated_at into cur from manhunt_state where id = 1 for update;
  if base_at is not null and cur > base_at then raise exception 'stale'; end if;
  update manhunt_state set state = new_state, updated_at = now() where id = 1 returning updated_at into cur;
  return cur;
end;
$$;

-- A leader records that a team captured them. Time comes from the server clock (Purdue local time),
-- optionally backdated by p_ago seconds (max 15 min). One capture per team per leader.
create or replace function public.manhunt_capture(pw text, p_team text, p_leader text, p_ago int default 0)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare st jsonb; idx int := null; i int; at_s int;
begin
  if not manhunt_leader_check(pw) then raise exception 'bad password'; end if;
  if p_leader not in ('Kevin','Owen','Gabe','Jack') then raise exception 'bad leader'; end if;
  select state into st from manhunt_state where id = 1 for update;
  for i in 0 .. coalesce(jsonb_array_length(st->'teams'), 0) - 1 loop
    if st->'teams'->i->>'id' = p_team then idx := i; end if;
  end loop;
  if idx is null then raise exception 'unknown team'; end if;
  if (st->'teams'->idx->'caps'->p_leader) is not null then raise exception 'already captured'; end if;
  at_s := floor(extract(epoch from ((now() at time zone 'America/Indiana/Indianapolis')::time)))::int
          - greatest(0, least(coalesce(p_ago, 0), 900));
  st := jsonb_set(st, array['teams', idx::text, 'caps', p_leader],
                  jsonb_build_object('at', at_s, 'disputed', false), true);
  update manhunt_state set state = st, updated_at = now() where id = 1;
  return jsonb_build_object('at', at_s);
end;
$$;

grant execute on function public.manhunt_save(text, jsonb, timestamptz) to anon, authenticated;
grant execute on function public.manhunt_capture(text, text, text, int) to anon, authenticated;
