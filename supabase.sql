-- Manhunt backend. Safe to run in a shared Supabase project: it only creates NEW objects
-- prefixed "manhunt_" and never alters or reads any existing table.
-- Run once in Supabase > SQL Editor. Replace CHANGE_ME with the scorekeeper password first.

-- Standings: one row, readable by everyone, writable only through manhunt_save() below.
create table if not exists public.manhunt_state (
  id int primary key default 1 check (id = 1),
  state jsonb not null default '{"teams":[]}'::jsonb,
  updated_at timestamptz not null default now()
);
insert into public.manhunt_state (id) values (1) on conflict (id) do nothing;

alter table public.manhunt_state enable row level security;
drop policy if exists "manhunt_read" on public.manhunt_state;
create policy "manhunt_read" on public.manhunt_state for select to anon, authenticated using (true);
-- No insert/update/delete policies: the public key cannot write directly.

-- Password (stored as a hash). RLS on with no policies means the public key can't read it.
create table if not exists public.manhunt_secrets (k text primary key, v text not null);
alter table public.manhunt_secrets enable row level security;
insert into public.manhunt_secrets (k, v)
  values ('keeper_pw', encode(sha256(convert_to('CHANGE_ME', 'utf8')), 'hex'))
  on conflict (k) do update set v = excluded.v;

create or replace function public.manhunt_check(pw text) returns boolean
language sql security definer set search_path = public as $$
  select exists (select 1 from manhunt_secrets
                 where k = 'keeper_pw' and v = encode(sha256(convert_to(pw, 'utf8')), 'hex'));
$$;

create or replace function public.manhunt_save(pw text, new_state jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not manhunt_check(pw) then raise exception 'bad password'; end if;
  update manhunt_state set state = new_state, updated_at = now() where id = 1;
end;
$$;

grant execute on function public.manhunt_check(text) to anon, authenticated;
grant execute on function public.manhunt_save(text, jsonb) to anon, authenticated;
