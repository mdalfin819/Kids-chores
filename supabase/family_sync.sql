-- Family sync for Chore Tracker
-- Paste this entire file into the Supabase SQL Editor and run it once.
--
-- Security model:
--   * The table is not readable or writable directly by the public anon key.
--   * All access goes through the RPCs below, which require the full family id.
--   * The family id is a long random secret (at least 24 characters; generate
--     64 hex characters). It is not a guessable name like "dalfin".
--   * Without that secret, the API cannot list, read, or change any family row.

create table if not exists public.family_state (
  id text primary key,
  state jsonb not null,
  updated_at timestamptz not null default now(),
  constraint family_state_id_len check (char_length(id) >= 24)
);

create index if not exists family_state_updated_at_idx
  on public.family_state (updated_at);

alter table public.family_state enable row level security;

-- No policies on purpose: the anon and authenticated roles cannot select,
-- insert, update, or delete rows directly, even if they guess a filter.
revoke all on table public.family_state from public, anon, authenticated;

create or replace function public._family_id_ok(p_family_id text)
returns boolean
language sql
immutable
as $$
  select p_family_id is not null and char_length(p_family_id) >= 24;
$$;

create or replace function public.get_family_state(p_family_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  rec public.family_state%rowtype;
begin
  if not public._family_id_ok(p_family_id) then
    raise exception 'invalid family id' using errcode = '22023';
  end if;

  select * into rec from public.family_state where id = p_family_id;
  if rec.id is null then
    return jsonb_build_object('found', false);
  end if;

  return jsonb_build_object(
    'found', true,
    'state', rec.state,
    'updated_at', rec.updated_at
  );
end;
$$;

-- First upload only. If a row already exists, this does not overwrite it;
-- it returns the existing row with seeded=false so other phones cannot
-- clobber the first upload by accident.
create or replace function public.seed_family_state(p_family_id text, p_state jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  rec public.family_state%rowtype;
begin
  if not public._family_id_ok(p_family_id) then
    raise exception 'invalid family id' using errcode = '22023';
  end if;
  if p_state is null or jsonb_typeof(p_state) <> 'object' then
    raise exception 'state required' using errcode = '22023';
  end if;

  insert into public.family_state (id, state, updated_at)
  values (p_family_id, p_state, now())
  on conflict (id) do nothing
  returning * into rec;

  if rec.id is null then
    select * into rec from public.family_state where id = p_family_id;
    return jsonb_build_object(
      'seeded', false,
      'state', rec.state,
      'updated_at', rec.updated_at
    );
  end if;

  return jsonb_build_object(
    'seeded', true,
    'state', rec.state,
    'updated_at', rec.updated_at
  );
end;
$$;

-- Last-write-wins with optimistic concurrency.
-- p_expected_updated_at should be the updated_at last seen by this phone.
-- If it does not match (another phone wrote first), the function returns
-- conflict=true and the current row, and does not change anything.
-- p_force=true overwrites anyway (used after a local merge, or when a parent
-- explicitly replaces the family data).
create or replace function public.push_family_state(
  p_family_id text,
  p_state jsonb,
  p_expected_updated_at timestamptz default null,
  p_force boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  rec public.family_state%rowtype;
begin
  if not public._family_id_ok(p_family_id) then
    raise exception 'invalid family id' using errcode = '22023';
  end if;
  if p_state is null or jsonb_typeof(p_state) <> 'object' then
    raise exception 'state required' using errcode = '22023';
  end if;

  select * into rec from public.family_state where id = p_family_id;
  if rec.id is null then
    return jsonb_build_object('written', false, 'missing', true);
  end if;

  if not coalesce(p_force, false)
     and p_expected_updated_at is not null
     and rec.updated_at is distinct from p_expected_updated_at then
    return jsonb_build_object(
      'written', false,
      'conflict', true,
      'state', rec.state,
      'updated_at', rec.updated_at
    );
  end if;

  update public.family_state
     set state = p_state,
         updated_at = now()
   where id = p_family_id
  returning * into rec;

  return jsonb_build_object(
    'written', true,
    'state', rec.state,
    'updated_at', rec.updated_at
  );
end;
$$;

revoke all on function public._family_id_ok(text) from public, anon, authenticated;
revoke all on function public.get_family_state(text) from public;
revoke all on function public.seed_family_state(text, jsonb) from public;
revoke all on function public.push_family_state(text, jsonb, timestamptz, boolean) from public;

grant execute on function public.get_family_state(text) to anon, authenticated;
grant execute on function public.seed_family_state(text, jsonb) to anon, authenticated;
grant execute on function public.push_family_state(text, jsonb, timestamptz, boolean) to anon, authenticated;
