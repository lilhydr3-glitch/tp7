-- TP7 — Multi-user management for the shared waiting queue.
--
-- Goals:
--   * Every queue entry belongs to a Supabase Auth user.
--   * A profile row is created automatically for every new account.
--   * Signed-in users can read the shared queue but only modify their own entry.
--   * The previous anonymous access is removed.
--
-- This migration is idempotent and can be applied on top of the Workshop 4/6
-- schema.

-- ---------------------------------------------------------------------------
-- 1. Base table and queue columns
-- ---------------------------------------------------------------------------

create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) > 0),
  created_at timestamptz not null default now()
);

alter table public.clients
  add column if not exists lat double precision,
  add column if not exists lng double precision,
  add column if not exists location_accuracy_m double precision,
  add column if not exists location_captured_at timestamptz,
  add column if not exists user_id uuid references auth.users (id) on delete cascade;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'valid_latitude'
  ) then
    alter table public.clients
      add constraint valid_latitude check (lat is null or lat between -90 and 90);
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'valid_longitude'
  ) then
    alter table public.clients
      add constraint valid_longitude check (lng is null or lng between -180 and 180);
  end if;
end
$$;

create index if not exists clients_user_id_idx
  on public.clients (user_id);
create index if not exists clients_created_at_idx
  on public.clients (created_at, id);

-- ---------------------------------------------------------------------------
-- 2. Profiles
-- ---------------------------------------------------------------------------

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null
    check (length(btrim(display_name)) between 1 and 80),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

revoke all on public.profiles from anon;
revoke all on public.profiles from public;
revoke all on public.profiles from authenticated;
grant select, update on public.profiles to authenticated;

drop policy if exists "Users can read their own profile" on public.profiles;
create policy "Users can read their own profile"
  on public.profiles for select to authenticated
  using ((select auth.uid()) = id);

drop policy if exists "Users can update their own profile" on public.profiles;
create policy "Users can update their own profile"
  on public.profiles for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Trigger functions are invoked by the trigger machinery, not by clients.
revoke all on function public.set_updated_at() from public, anon, authenticated;

-- Create a profile for every new Supabase Auth user.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(
      nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''),
      split_part(coalesce(new.email, 'guest'), '@', 1)
    )
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Backfill profiles for accounts created before this migration.
insert into public.profiles (id, display_name)
select
  users.id,
  split_part(coalesce(users.email, 'guest'), '@', 1)
from auth.users as users
on conflict (id) do nothing;

revoke all on function public.handle_new_user()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Row Level Security for queue entries
-- ---------------------------------------------------------------------------

alter table public.clients enable row level security;

revoke all on public.clients from anon;
revoke all on public.clients from public;
revoke all on public.clients from authenticated;
grant select, insert, update, delete on public.clients to authenticated;

-- The waiting room is shared: signed-in users can read every entry.
drop policy if exists "Authenticated users can view clients" on public.clients;
drop policy if exists "Authenticated users can add clients" on public.clients;
drop policy if exists "Authenticated users can remove clients" on public.clients;
drop policy if exists "Signed-in users can read the shared queue" on public.clients;
drop policy if exists "Users can join the queue as themselves" on public.clients;
drop policy if exists "Users can update their own queue entry" on public.clients;
drop policy if exists "Users can leave the queue" on public.clients;
-- Policies left over from the anonymous versions of the app.
drop policy if exists "Public can read clients" on public.clients;
drop policy if exists "Public can add clients" on public.clients;
drop policy if exists "Public can remove clients" on public.clients;

create policy "Signed-in users can read the shared queue"
  on public.clients for select to authenticated
  using (true);

create policy "Users can join the queue as themselves"
  on public.clients for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Users can update their own queue entry"
  on public.clients for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Users can leave the queue"
  on public.clients for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- 4. Queue view: names, ordering and ownership only
-- ---------------------------------------------------------------------------

drop view if exists public.queue_clients;
create view public.queue_clients
with (security_invoker = true)
as
select
  clients.id,
  clients.name,
  clients.created_at,
  clients.user_id,
  (clients.user_id = (select auth.uid())) as is_mine,
  row_number() over (order by clients.created_at asc, clients.id asc)::int
    as position
from public.clients;

revoke all on public.queue_clients from anon;
revoke all on public.queue_clients from public;
revoke all on public.queue_clients from authenticated;
grant select on public.queue_clients to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Server-side registration RPC (authoritative queue entry)
-- ---------------------------------------------------------------------------

create or replace function public.register_queue_client(
  p_id uuid,
  p_name text,
  p_lat double precision,
  p_lng double precision,
  p_accuracy double precision,
  p_location_captured_at timestamptz,
  p_created_at timestamptz
)
returns setof public.clients
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Authentication required'
      using errcode = '42501';
  end if;

  return query
  insert into public.clients (
    id,
    user_id,
    name,
    lat,
    lng,
    location_accuracy_m,
    location_captured_at,
    created_at
  )
  values (
    p_id,
    v_user_id,
    btrim(p_name),
    p_lat,
    p_lng,
    p_accuracy,
    p_location_captured_at,
    coalesce(p_created_at, now())
  )
  on conflict (id) do update
    set name = excluded.name
    where public.clients.user_id = v_user_id
  returning *;
end;
$$;

revoke all on function public.register_queue_client(
  uuid, text, double precision, double precision, double precision,
  timestamptz, timestamptz
) from public;
revoke all on function public.register_queue_client(
  uuid, text, double precision, double precision, double precision,
  timestamptz, timestamptz
) from anon;
grant execute on function public.register_queue_client(
  uuid, text, double precision, double precision, double precision,
  timestamptz, timestamptz
) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Realtime broadcast on insert and delete
-- ---------------------------------------------------------------------------

create or replace function public.broadcast_queue_client_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform realtime.send(
    jsonb_build_object('id', new.id),
    'queue_client_inserted',
    'waiting-room',
    false
  );
  return new;
end;
$$;

create or replace function public.broadcast_queue_client_delete()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform realtime.send(
    jsonb_build_object('id', old.id),
    'queue_client_deleted',
    'waiting-room',
    false
  );
  return old;
end;
$$;

revoke all on function public.broadcast_queue_client_insert()
  from public, anon, authenticated;
revoke all on function public.broadcast_queue_client_delete()
  from public, anon, authenticated;

drop trigger if exists queue_client_insert_broadcast on public.clients;
create trigger queue_client_insert_broadcast
  after insert on public.clients
  for each row execute function public.broadcast_queue_client_insert();

drop trigger if exists queue_client_delete_broadcast on public.clients;
create trigger queue_client_delete_broadcast
  after delete on public.clients
  for each row execute function public.broadcast_queue_client_delete();
