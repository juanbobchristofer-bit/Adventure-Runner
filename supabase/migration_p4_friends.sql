-- ============================================================================
-- MIGRASI TAHAP 4: SISTEM PERTEMANAN (ADD FRIEND, TERIMA/TOLAK, LEADERBOARD TEMAN)
-- Jalankan skrip ini SEKALI di Supabase Dashboard -> SQL Editor -> New Query -> Run
-- ============================================================================

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

-- Table Privileges
grant select, insert, update, delete on public.friendships to authenticated;

-- Row Level Security (Hanya pihak terkait yang bisa melihat/mengubah relasi pertemanan)
alter table public.friendships enable row level security;

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
