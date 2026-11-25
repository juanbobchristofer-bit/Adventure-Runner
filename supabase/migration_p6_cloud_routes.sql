-- ============================================================================
-- MIGRASI TAHAP 6: AVATAR CLOUD (STORAGE), CLOUD BACKUP RIWAYAT LARI,
--                  & RUTE KOMUNITAS DINAMIS (PETA JELAJAH)
-- Jalankan skrip ini SEKALI di Supabase Dashboard -> SQL Editor -> New Query -> Run
-- ============================================================================

-- 1. Kolom avatar_url pada profiles
alter table public.profiles
  add column if not exists avatar_url text;

-- 2. Bucket Supabase Storage "avatars" (public read, owner-only write/delete)
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = true;

drop policy if exists "Avatar images are publicly readable" on storage.objects;
create policy "Avatar images are publicly readable"
  on storage.objects for select
  using (bucket_id = 'avatars');

drop policy if exists "Users can upload own avatar" on storage.objects;
create policy "Users can upload own avatar"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Users can update own avatar" on storage.objects;
create policy "Users can update own avatar"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Users can delete own avatar" on storage.objects;
create policy "Users can delete own avatar"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- 3. Tabel Cloud Backup Riwayat Lari (privat milik masing-masing pelari)
create table if not exists public.user_runs (
  id uuid primary key default gen_random_uuid(),
  local_run_id text not null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  date_label text not null default '',
  created_at timestamptz not null default now(),
  distance_km double precision not null default 0.0,
  duration_seconds integer not null default 0,
  pace text not null default '--:--',
  steps integer not null default 0,
  calories double precision not null default 0.0,
  elevation_gain_m double precision not null default 0.0,
  notes text not null default '',
  feeling text not null default 'Luar Biasa 🔥',
  route_points jsonb not null default '[]'::jsonb,
  track_points jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  constraint user_runs_owner_local_unique unique (user_id, local_run_id)
);

create index if not exists idx_user_runs_user_created on public.user_runs(user_id, created_at desc);

grant select, insert, update, delete on public.user_runs to authenticated;
alter table public.user_runs enable row level security;

drop policy if exists "Users can view own backed up runs" on public.user_runs;
create policy "Users can view own backed up runs"
  on public.user_runs for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own backed up runs" on public.user_runs;
create policy "Users can insert own backed up runs"
  on public.user_runs for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own backed up runs" on public.user_runs;
create policy "Users can update own backed up runs"
  on public.user_runs for update
  using (auth.uid() = user_id);

drop policy if exists "Users can delete own backed up runs" on public.user_runs;
create policy "Users can delete own backed up runs"
  on public.user_runs for delete
  using (auth.uid() = user_id);

-- 4. Tabel Rute Komunitas Dinamis (tampil di Peta Jelajah untuk semua pelari)
create table if not exists public.community_routes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  local_run_id text not null,
  name text not null,
  location text not null default 'Indonesia',
  category text not null default 'Komunitas',
  distance_km double precision not null default 0.0,
  elevation_gain_m integer not null default 0,
  surface text not null default 'GPS Komunitas',
  difficulty text not null default 'Menengah',
  points jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  constraint community_routes_owner_run_unique unique (user_id, local_run_id)
);

create index if not exists idx_community_routes_created on public.community_routes(created_at desc);

grant select on public.community_routes to anon, authenticated;
grant insert, update, delete on public.community_routes to authenticated;
alter table public.community_routes enable row level security;

drop policy if exists "Community routes are viewable by everyone" on public.community_routes;
create policy "Community routes are viewable by everyone"
  on public.community_routes for select
  using (true);

drop policy if exists "Users can share own community routes" on public.community_routes;
create policy "Users can share own community routes"
  on public.community_routes for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own community routes" on public.community_routes;
create policy "Users can update own community routes"
  on public.community_routes for update
  using (auth.uid() = user_id);

drop policy if exists "Users can delete own community routes" on public.community_routes;
create policy "Users can delete own community routes"
  on public.community_routes for delete
  using (auth.uid() = user_id);
