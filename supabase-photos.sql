-- Manhunt leader check-ins (photos). Run AFTER supabase.sql, once, in Supabase > SQL Editor.
-- Only creates NEW "manhunt_" objects; nothing existing is touched.
-- Replace LEADER_PASSWORD below with the password the four leaders will use to post.

create table if not exists public.manhunt_checkins (
  id bigint generated always as identity primary key,
  leader text not null check (leader in ('Kevin','Owen','Gabe','Jack')),
  image text not null,                 -- small JPEG as a data URL, resized on the phone
  note text not null default '',
  created_at timestamptz not null default now()
);
alter table public.manhunt_checkins enable row level security;
drop policy if exists "manhunt_checkins_read" on public.manhunt_checkins;
create policy "manhunt_checkins_read" on public.manhunt_checkins for select to anon, authenticated using (true);
-- No insert/update/delete policies: writes only happen through the functions below.

insert into public.manhunt_secrets (k, v)
  values ('leader_pw', encode(sha256(convert_to('LEADER_PASSWORD', 'utf8')), 'hex'))
  on conflict (k) do update set v = excluded.v;

-- True for the leader password (or the scorekeeper password).
create or replace function public.manhunt_leader_check(pw text) returns boolean
language sql security definer set search_path = public as $$
  select exists (select 1 from manhunt_secrets
                 where k in ('leader_pw', 'keeper_pw') and v = encode(sha256(convert_to(pw, 'utf8')), 'hex'));
$$;

create or replace function public.manhunt_checkin(pw text, p_leader text, p_image text, p_note text) returns bigint
language plpgsql security definer set search_path = public as $$
declare new_id bigint;
begin
  if not manhunt_leader_check(pw) then raise exception 'bad password'; end if;
  if p_image is null or length(p_image) > 600000 or left(p_image, 11) <> 'data:image/' then
    raise exception 'bad image';
  end if;
  insert into manhunt_checkins (leader, image, note)
    values (p_leader, p_image, left(coalesce(p_note, ''), 200))
    returning id into new_id;
  return new_id;
end;
$$;

-- Scorekeeper only: wipe test check-ins before the game.
create or replace function public.manhunt_clear_checkins(pw text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not manhunt_check(pw) then raise exception 'bad password'; end if;
  delete from manhunt_checkins where true;
end;
$$;

grant execute on function public.manhunt_leader_check(text) to anon, authenticated;
grant execute on function public.manhunt_checkin(text, text, text, text) to anon, authenticated;
grant execute on function public.manhunt_clear_checkins(text) to anon, authenticated;
