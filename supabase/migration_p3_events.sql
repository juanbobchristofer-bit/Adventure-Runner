-- ============================================================================
-- MIGRASI TAHAP 3: ACARA BERLEVEL + KUOTA PESERTA + RUANG DISKUSI ACARA
-- Jalankan skrip ini SEKALI di Supabase Dashboard -> SQL Editor -> New Query -> Run
-- ============================================================================

-- 1. Tambah kolom syarat level & kuota maksimal pada community_events
alter table public.community_events
  add column if not exists min_level integer not null default 1,
  add column if not exists max_participants integer not null default 50;

update public.community_events set min_level = 1, max_participants = 50 where id = '22222222-2222-2222-2222-222222222201';
update public.community_events set min_level = 2, max_participants = 40 where id = '22222222-2222-2222-2222-222222222202';
update public.community_events set min_level = 3, max_participants = 25 where id = '22222222-2222-2222-2222-222222222203';

-- 2. Tabel pesan ruang diskusi acara
create table if not exists public.event_messages (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.community_events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  content text not null check (char_length(trim(content)) > 0 and char_length(content) <= 500),
  created_at timestamptz not null default now()
);

create index if not exists idx_event_messages_event_created
  on public.event_messages(event_id, created_at asc);

-- 3. Table Privileges (GRANT)
grant select on public.event_messages to anon, authenticated;
grant insert, delete on public.event_messages to authenticated;

-- 4. Row Level Security (Hanya peserta terdaftar RSVP atau pembuat acara yang boleh mengirim pesan)
alter table public.event_messages enable row level security;

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

-- 5. Aktifkan Supabase Realtime pada tabel event_messages (idempotent)
do $$
begin
  alter publication supabase_realtime add table public.event_messages;
exception
  when duplicate_object then null;
end $$;
