-- ============================================================================
-- MIGRASI TAHAP 2: KLUB BERLEVEL + RUANG OBROLAN KLUB (LIVE CHAT + RLS)
-- Jalankan skrip ini SEKALI di Supabase Dashboard -> SQL Editor -> New Query -> Run
-- ============================================================================

-- 1. Tambah syarat level minimal pada tabel clubs
alter table public.clubs
  add column if not exists min_level integer not null default 1;

update public.clubs set min_level = 1 where id = '11111111-1111-1111-1111-111111111101';
update public.clubs set min_level = 2 where id = '11111111-1111-1111-1111-111111111102';
update public.clubs set min_level = 1 where id = '11111111-1111-1111-1111-111111111103';

-- 2. Tabel pesan ruang obrolan klub
create table if not exists public.club_messages (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  content text not null check (char_length(trim(content)) > 0 and char_length(content) <= 500),
  created_at timestamptz not null default now()
);

create index if not exists idx_club_messages_club_created
  on public.club_messages(club_id, created_at asc);

-- 3. Table Privileges (GRANT)
grant select on public.club_messages to anon, authenticated;
grant insert, delete on public.club_messages to authenticated;

-- 4. Row Level Security (Hanya anggota klub yang boleh mengirim pesan)
alter table public.club_messages enable row level security;

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

-- 5. Aktifkan Supabase Realtime pada tabel club_messages (idempotent)
do $$
begin
  alter publication supabase_realtime add table public.club_messages;
exception
  when duplicate_object then null;
end $$;
