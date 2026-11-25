-- ============================================================================
-- ADVENTURE RUNNER — SUPABASE DATABASE SCHEMA & ROW LEVEL SECURITY (RLS)
-- Jalankan skrip ini SEKALI di Supabase Dashboard -> SQL Editor -> New Query -> Run
-- ============================================================================

create extension if not exists "pgcrypto";

-- 1. PROFILES (Sinkronisasi profil & statistik mingguan pelari)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Pelari Adventure',
  bio text not null default 'Chasing new personal records every mile.',
  city text not null default 'Indonesia',
  weight_kg double precision not null default 65.0,
  weekly_goal_km double precision not null default 15.0,
  weekly_distance_km double precision not null default 0.0,
  weekly_runs_count integer not null default 0,
  total_distance_km double precision not null default 0.0,
  total_runs_count integer not null default 0,
  total_calories double precision not null default 0.0,
  longest_run_km double precision not null default 0.0,
  bonus_xp integer not null default 0,
  total_xp integer not null default 0,
  runner_level integer not null default 1,
  week_start_iso text not null default '',
  updated_at timestamptz not null default now()
);

-- Trigger otomatis membuat baris profil saat user baru mendaftar
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), split_part(new.email, '@', 1), 'Pelari Adventure')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 2. CHALLENGES (Tantangan komunitas)
create table if not exists public.challenges (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  title text not null,
  description text not null,
  badge_text text not null,
  target_value double precision not null,
  unit text not null check (unit in ('km', 'single_km', 'runs', 'kcal')),
  accent_hex text not null default '#FC4C02',
  min_level integer not null default 1,
  xp_reward integer not null default 150,
  created_at timestamptz not null default now()
);

create table if not exists public.challenge_participants (
  challenge_id uuid not null references public.challenges(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  reward_claimed boolean not null default false,
  claimed_at timestamptz,
  joined_at timestamptz not null default now(),
  primary key (challenge_id, user_id)
);

-- 3. CLUBS, MEMBERS & CHAT (Klub lari online berlevel + Leaderboard + Live Chat)
create table if not exists public.clubs (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  location text not null,
  description text not null,
  schedule text not null,
  color_hex text not null default '#FC4C02',
  min_level integer not null default 1,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.club_members (
  club_id uuid not null references public.clubs(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (club_id, user_id)
);

create table if not exists public.club_messages (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  content text not null check (char_length(trim(content)) > 0 and char_length(content) <= 500),
  created_at timestamptz not null default now()
);

create index if not exists idx_club_messages_club_created
  on public.club_messages(club_id, created_at asc);

-- 4. COMMUNITY EVENTS, RSVPS & DISCUSSION (Acara berlevel + kuota + diskusi live)
create table if not exists public.community_events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  date_str text not null,
  location text not null,
  distance_tag text not null default '5.0 KM',
  pace_group text not null default 'All Pace',
  description text not null default '',
  min_level integer not null default 1,
  max_participants integer not null default 50,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.event_rsvps (
  event_id uuid not null references public.community_events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  rsvped_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

create table if not exists public.event_messages (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.community_events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  content text not null check (char_length(trim(content)) > 0 and char_length(content) <= 500),
  created_at timestamptz not null default now()
);

create index if not exists idx_event_messages_event_created
  on public.event_messages(event_id, created_at asc);

-- 5. FRIENDSHIPS (Pertemanan antar-pelari: Add Friend, Terima/Tolak, Leaderboard Teman)
create table if not exists public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  addressee_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint friendships_no_self check (requester_id <> addressee_id),
  constraint friendships_unique_pair unique (requester_id, addressee_id)
);

create index if not exists idx_friendships_requester on public.friendships(requester_id);
create index if not exists idx_friendships_addressee on public.friendships(addressee_id);

-- ============================================================================
-- TABLE PRIVILEGES (WAJIB DI SUPABASE TERBARU AGAR ROLE ANON & AUTHENTICATED BISA AKSES)
-- ============================================================================
grant usage on schema public to anon, authenticated;

grant select on
  public.profiles,
  public.challenges,
  public.challenge_participants,
  public.clubs,
  public.club_members,
  public.club_messages,
  public.community_events,
  public.event_rsvps,
  public.event_messages
to anon, authenticated;

grant insert, update on public.profiles to authenticated;
grant insert, update, delete on public.challenge_participants to authenticated;
grant insert, update, delete on public.clubs to authenticated;
grant insert, update, delete on public.club_members to authenticated;
grant insert, delete on public.club_messages to authenticated;
grant insert, update, delete on public.community_events to authenticated;
grant insert, update, delete on public.event_rsvps to authenticated;
grant insert, delete on public.event_messages to authenticated;
grant select, insert, update, delete on public.friendships to authenticated;

-- ============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================================
alter table public.profiles enable row level security;
alter table public.challenges enable row level security;
alter table public.challenge_participants enable row level security;
alter table public.clubs enable row level security;
alter table public.club_members enable row level security;
alter table public.club_messages enable row level security;
alter table public.community_events enable row level security;
alter table public.event_rsvps enable row level security;
alter table public.event_messages enable row level security;
alter table public.friendships enable row level security;

-- PROFILES
drop policy if exists "Profiles are viewable by everyone" on public.profiles;
create policy "Profiles are viewable by everyone"
  on public.profiles for select using (true);

drop policy if exists "Users can insert own profile" on public.profiles;
create policy "Users can insert own profile"
  on public.profiles for insert with check (auth.uid() = id);

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile"
  on public.profiles for update using (auth.uid() = id);

-- CHALLENGES
drop policy if exists "Challenges are viewable by everyone" on public.challenges;
create policy "Challenges are viewable by everyone"
  on public.challenges for select using (true);

drop policy if exists "Challenge participants viewable by everyone" on public.challenge_participants;
create policy "Challenge participants viewable by everyone"
  on public.challenge_participants for select using (true);

drop policy if exists "Users can join challenges" on public.challenge_participants;
create policy "Users can join challenges"
  on public.challenge_participants for insert with check (auth.uid() = user_id);

drop policy if exists "Users can update own challenge participation" on public.challenge_participants;
create policy "Users can update own challenge participation"
  on public.challenge_participants for update using (auth.uid() = user_id);

drop policy if exists "Users can leave challenges" on public.challenge_participants;
create policy "Users can leave challenges"
  on public.challenge_participants for delete using (auth.uid() = user_id);

-- CLUBS
drop policy if exists "Clubs are viewable by everyone" on public.clubs;
create policy "Clubs are viewable by everyone"
  on public.clubs for select using (true);

drop policy if exists "Authenticated users can create clubs" on public.clubs;
create policy "Authenticated users can create clubs"
  on public.clubs for insert with check (auth.uid() is not null and auth.uid() = created_by);

drop policy if exists "Creators can delete own clubs" on public.clubs;
create policy "Creators can delete own clubs"
  on public.clubs for delete using (auth.uid() = created_by);

drop policy if exists "Club members are viewable by everyone" on public.club_members;
create policy "Club members are viewable by everyone"
  on public.club_members for select using (true);

drop policy if exists "Users can join clubs" on public.club_members;
create policy "Users can join clubs"
  on public.club_members for insert with check (auth.uid() = user_id);

drop policy if exists "Users can update own club membership" on public.club_members;
create policy "Users can update own club membership"
  on public.club_members for update using (auth.uid() = user_id);

drop policy if exists "Users can leave clubs" on public.club_members;
create policy "Users can leave clubs"
  on public.club_members for delete using (auth.uid() = user_id);

-- CLUB MESSAGES (Hanya anggota klub yang boleh mengirim pesan)
drop policy if exists "Club messages are viewable by everyone" on public.club_messages;
create policy "Club messages are viewable by everyone"
  on public.club_messages for select using (true);

drop policy if exists "Club members can send messages" on public.club_messages;
create policy "Club members can send messages"
  on public.club_messages for insert
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.club_members cm
      where cm.club_id = club_messages.club_id
        and cm.user_id = auth.uid()
    )
  );

drop policy if exists "Users can delete own club messages" on public.club_messages;
create policy "Users can delete own club messages"
  on public.club_messages for delete using (auth.uid() = user_id);

-- EVENTS
drop policy if exists "Events are viewable by everyone" on public.community_events;
create policy "Events are viewable by everyone"
  on public.community_events for select using (true);

drop policy if exists "Authenticated users can create events" on public.community_events;
create policy "Authenticated users can create events"
  on public.community_events for insert with check (auth.uid() is not null and auth.uid() = created_by);

drop policy if exists "Creators can delete own events" on public.community_events;
create policy "Creators can delete own events"
  on public.community_events for delete using (auth.uid() = created_by);

drop policy if exists "Event RSVPs are viewable by everyone" on public.event_rsvps;
create policy "Event RSVPs are viewable by everyone"
  on public.event_rsvps for select using (true);

drop policy if exists "Users can RSVP to events" on public.event_rsvps;
create policy "Users can RSVP to events"
  on public.event_rsvps for insert with check (auth.uid() = user_id);

drop policy if exists "Users can update own RSVP" on public.event_rsvps;
create policy "Users can update own RSVP"
  on public.event_rsvps for update using (auth.uid() = user_id);

drop policy if exists "Users can cancel own RSVP" on public.event_rsvps;
create policy "Users can cancel own RSVP"
  on public.event_rsvps for delete using (auth.uid() = user_id);

-- EVENT MESSAGES (Hanya peserta terdaftar atau pembuat acara yang boleh mengirim pesan)
drop policy if exists "Event messages are viewable by everyone" on public.event_messages;
create policy "Event messages are viewable by everyone"
  on public.event_messages for select using (true);

drop policy if exists "Event attendees can send messages" on public.event_messages;
create policy "Event attendees can send messages"
  on public.event_messages for insert
  with check (
    auth.uid() = user_id
    and (
      exists (
        select 1 from public.event_rsvps er
        where er.event_id = event_messages.event_id
          and er.user_id = auth.uid()
      )
      or exists (
        select 1 from public.community_events ev
        where ev.id = event_messages.event_id
          and ev.created_by = auth.uid()
      )
    )
  );

drop policy if exists "Users can delete own event messages" on public.event_messages;
create policy "Users can delete own event messages"
  on public.event_messages for delete using (auth.uid() = user_id);

-- FRIENDSHIPS
drop policy if exists "Users can view own friendships" on public.friendships;
create policy "Users can view own friendships"
  on public.friendships for select
  using (auth.uid() = requester_id or auth.uid() = addressee_id);

drop policy if exists "Users can send friend requests" on public.friendships;
create policy "Users can send friend requests"
  on public.friendships for insert
  with check (auth.uid() = requester_id and status = 'pending');

drop policy if exists "Addressees can accept friend requests" on public.friendships;
create policy "Addressees can accept friend requests"
  on public.friendships for update
  using (auth.uid() = addressee_id)
  with check (auth.uid() = addressee_id and status = 'accepted');

drop policy if exists "Users can delete own friendships" on public.friendships;
create policy "Users can delete own friendships"
  on public.friendships for delete
  using (auth.uid() = requester_id or auth.uid() = addressee_id);

-- 6. ACTIVITY POSTS & KUDOS (Feed Aktivitas Teman ala Strava)
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

grant select on public.activity_posts, public.activity_kudos to anon, authenticated;
grant insert, update, delete on public.activity_posts to authenticated;
grant insert, update, delete on public.activity_kudos to authenticated;

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
  on public.activity_posts for insert with check (auth.uid() = user_id);

drop policy if exists "Users can update own activity posts" on public.activity_posts;
create policy "Users can update own activity posts"
  on public.activity_posts for update using (auth.uid() = user_id);

drop policy if exists "Users can delete own activity posts" on public.activity_posts;
create policy "Users can delete own activity posts"
  on public.activity_posts for delete using (auth.uid() = user_id);

drop policy if exists "Kudos are viewable by authenticated users" on public.activity_kudos;
create policy "Kudos are viewable by authenticated users"
  on public.activity_kudos for select using (true);

drop policy if exists "Users can give kudos" on public.activity_kudos;
create policy "Users can give kudos"
  on public.activity_kudos for insert with check (auth.uid() = user_id);

drop policy if exists "Users can update own kudos" on public.activity_kudos;
create policy "Users can update own kudos"
  on public.activity_kudos for update using (auth.uid() = user_id);

drop policy if exists "Users can remove own kudos" on public.activity_kudos;
create policy "Users can remove own kudos"
  on public.activity_kudos for delete using (auth.uid() = user_id);

-- ============================================================================
-- DATA AWAL KOMUNITAS (IDEMPOTENT / AMAN DIJALANKAN ULANG)
-- ============================================================================
insert into public.challenges (slug, title, description, badge_text, target_value, unit, accent_hex, min_level, xp_reward)
values
  ('first-stride-1k', 'First Stride 1K Starter', 'Tantangan pembuka untuk pelari baru: kumpulkan total jarak 1 km pertama.', 'STARTER 1K', 1.0, 'km', '#00E676', 1, 100),
  ('finisher-5k', '5K Finisher Challenge', 'Selesaikan minimal 5 km dalam satu kali sesi lari tanpa henti.', '5K MILESTONE', 5.0, 'single_km', '#29B6F6', 1, 150),
  ('streak-5x', '5x Active Runner Streak', 'Selesaikan minimal 5 sesi lari yang tercatat di riwayat aktivitas.', 'CONSISTENCY', 5.0, 'runs', '#00E676', 2, 250),
  ('endurance-25k', 'Adventure 25K Endurance', 'Kumpulkan total jarak lari 25 km dari seluruh sesi rekamanmu.', 'ENDURANCE 25K', 25.0, 'km', '#FC4C02', 3, 400),
  ('burn-1500kcal', '1,500 kcal Burn Target', 'Bakar total 1.500 kalori dari aktivitas lari maupun trail.', 'CALORIE BURN', 1500.0, 'kcal', '#FFC107', 4, 500)
on conflict (slug) do update set
  min_level = excluded.min_level,
  xp_reward = excluded.xp_reward;

insert into public.clubs (id, name, location, description, schedule, color_hex, min_level)
values
  ('11111111-1111-1111-1111-111111111101', 'Runner Club Sumedang', 'Jatinangor & Sumedang', 'Komunitas lari terbuka untuk mahasiswa dan warga kawasan Jatinangor–Sumedang.', 'Rabu 19:30 & Minggu 06:00', '#FC4C02', 1),
  ('11111111-1111-1111-1111-111111111102', 'Bandung Timur Trail Runners', 'Cileunyi & Kaki Manglayang', 'Fokus latihan elevasi, lari lintas alam, dan persiapan trail run Jawa Barat.', 'Sabtu 06:15 • Basecamp Manglayang', '#00E676', 2),
  ('11111111-1111-1111-1111-111111111103', 'Adventure Runners Indonesia', 'Nasional • Online Club', 'Klub terbuka seluruh pelari Adventure Runner dari berbagai kota di Indonesia.', 'Bebas • Sync Mingguan', '#29B6F6', 1)
on conflict (id) do update set min_level = excluded.min_level;

insert into public.community_events (id, title, date_str, location, distance_tag, pace_group, description, min_level, max_participants)
values
  ('22222222-2222-2222-2222-222222222201', 'Jatinangor Loop Night Run 5K', 'Sabtu • 19:30 WIB', 'Gerbang Utama Unpad, Jatinangor', '5.0 KM', 'All Pace (6:00 - 7:30 /km)', 'Lari malam santai bersama komunitas lokal mengelilingi rute utama Jatinangor.', 1, 50),
  ('22222222-2222-2222-2222-222222222202', 'Sunday Morning Long Run 10K', 'Minggu • 06:00 WIB', 'Stadion Siliwangi, Bandung', '10.0 KM', 'Tempo & Endurance', 'Latihan long run akhir pekan bersama pacer komunitas untuk persiapan 10K.', 2, 40),
  ('22222222-2222-2222-2222-222222222203', 'Manglayang Sunrise Fun Trail', 'Minggu • 06:15 WIB', 'Pos Pendakian Barubereum, Cileunyi', '6.5 KM', 'Trail / Elevasi +240m', 'Eksplorasi jalur tanah dan kebun pinus kaki Gunung Manglayang saat matahari terbit.', 3, 25)
on conflict (id) do update set
  min_level = excluded.min_level,
  max_participants = excluded.max_participants;
