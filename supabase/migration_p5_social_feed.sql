-- ============================================================================
-- MIGRASI TAHAP 5: FEED AKTIVITAS TEMAN + TOMBOL KUDOS (ALA STRAVA)
-- Jalankan skrip ini SEKALI di Supabase Dashboard -> SQL Editor -> New Query -> Run
-- ============================================================================

create table if not exists public.activity_posts (
  id uuid primary key default gen_random_uuid(),
  local_run_id text not null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  notes text not null default '',
  feeling text not null default 'Luar Biasa 🔥',
  distance_km double precision not null default 0.0,
  duration_seconds integer not null default 0,
  pace text not null default '--:--',
  calories double precision not null default 0.0,
  elevation_gain_m double precision not null default 0.0,
  route_preview jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  constraint activity_posts_user_run_unique unique (user_id, local_run_id)
);

create index if not exists idx_activity_posts_created on public.activity_posts(created_at desc);
create index if not exists idx_activity_posts_user on public.activity_posts(user_id);

create table if not exists public.activity_kudos (
  post_id uuid not null references public.activity_posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

-- Table Privileges
grant select on public.activity_posts, public.activity_kudos to anon, authenticated;
grant insert, update, delete on public.activity_posts to authenticated;
grant insert, update, delete on public.activity_kudos to authenticated;

-- Row Level Security
alter table public.activity_posts enable row level security;
alter table public.activity_kudos enable row level security;

drop policy if exists "Activity posts viewable by self and accepted friends" on public.activity_posts;
create policy "Activity posts viewable by self and accepted friends"
  on public.activity_posts for select
  using (
    auth.uid() = user_id
    or exists (
      select 1 from public.friendships f
      where f.status = 'accepted'
        and (
          (f.requester_id = auth.uid() and f.addressee_id = activity_posts.user_id)
          or (f.addressee_id = auth.uid() and f.requester_id = activity_posts.user_id)
        )
    )
  );

drop policy if exists "Users can insert own activity posts" on public.activity_posts;
create policy "Users can insert own activity posts"
  on public.activity_posts for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own activity posts" on public.activity_posts;
create policy "Users can update own activity posts"
  on public.activity_posts for update
  using (auth.uid() = user_id);

drop policy if exists "Users can delete own activity posts" on public.activity_posts;
create policy "Users can delete own activity posts"
  on public.activity_posts for delete
  using (auth.uid() = user_id);

drop policy if exists "Kudos are viewable by authenticated users" on public.activity_kudos;
create policy "Kudos are viewable by authenticated users"
  on public.activity_kudos for select using (true);

drop policy if exists "Users can give kudos" on public.activity_kudos;
create policy "Users can give kudos"
  on public.activity_kudos for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own kudos" on public.activity_kudos;
create policy "Users can update own kudos"
  on public.activity_kudos for update
  using (auth.uid() = user_id);

drop policy if exists "Users can remove own kudos" on public.activity_kudos;
create policy "Users can remove own kudos"
  on public.activity_kudos for delete
  using (auth.uid() = user_id);
