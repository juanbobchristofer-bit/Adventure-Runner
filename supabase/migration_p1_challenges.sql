-- ============================================================================
-- MIGRASI TAHAP 1: GAMIFIKASI TANTANGAN (LEVEL GATING + KLAIM BONUS XP)
-- Jalankan skrip ini SEKALI di Supabase Dashboard -> SQL Editor -> New Query -> Run
-- ============================================================================

-- 1. Tambah kolom XP & Level pada profiles
alter table public.profiles
  add column if not exists bonus_xp integer not null default 0,
  add column if not exists total_xp integer not null default 0,
  add column if not exists runner_level integer not null default 1;

-- 2. Tambah kolom syarat level & hadiah XP pada challenges
alter table public.challenges
  add column if not exists min_level integer not null default 1,
  add column if not exists xp_reward integer not null default 150;

-- 3. Tambah status klaim hadiah pada challenge_participants
alter table public.challenge_participants
  add column if not exists reward_claimed boolean not null default false,
  add column if not exists claimed_at timestamptz;

-- 4. Perbarui tier level & hadiah XP untuk tantangan bawaan + tambah tantangan pemula Lv. 1
insert into public.challenges (slug, title, description, badge_text, target_value, unit, accent_hex, min_level, xp_reward)
values
  ('first-stride-1k', 'First Stride 1K Starter', 'Tantangan pembuka untuk pelari baru: kumpulkan total jarak 1 km pertama.', 'STARTER 1K', 1.0, 'km', '#00E676', 1, 100)
on conflict (slug) do update set
  min_level = excluded.min_level,
  xp_reward = excluded.xp_reward;

update public.challenges set min_level = 1, xp_reward = 150 where slug = 'finisher-5k';
update public.challenges set min_level = 2, xp_reward = 250 where slug = 'streak-5x';
update public.challenges set min_level = 3, xp_reward = 400 where slug = 'endurance-25k';
update public.challenges set min_level = 4, xp_reward = 500 where slug = 'burn-1500kcal';
