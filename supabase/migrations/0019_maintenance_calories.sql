-- =====================================================================
-- 0019_maintenance_calories.sql
--
-- Inputs for the maintenance-calorie estimate: a per-user body profile and
-- a weigh-in history. Strictly per user, like the food diary. Weights are
-- stored in kilograms; the app converts for display.
-- =====================================================================

create table if not exists public.body_profile (
  user_id uuid primary key references auth.users(id) on delete cascade,
  sex text not null check (sex in ('male', 'female')),
  age_years integer not null check (age_years between 18 and 100),
  height_cm numeric(5,1) not null check (height_cm between 120 and 230),
  weight_kg numeric(5,1) not null check (weight_kg between 30 and 400),
  activity text not null default 'sedentary'
    check (activity in ('sedentary', 'light', 'moderate', 'very', 'extreme')),
  equation text not null default 'mifflinStJeor'
    check (equation in ('mifflinStJeor', 'revisedHarrisBenedict', 'cunningham', 'tenHaaf')),
  body_fat_percent numeric(4,1) check (body_fat_percent between 3 and 65),
  body_fat_measured boolean not null default false,
  weight_unit text not null default 'lb' check (weight_unit in ('kg', 'lb')),
  updated_at timestamptz not null default now()
);
alter table public.body_profile enable row level security;

drop policy if exists body_profile_own on public.body_profile;
create policy body_profile_own on public.body_profile
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create table if not exists public.weigh_ins (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  weighed_on date not null default current_date,
  weight_kg numeric(5,1) not null check (weight_kg between 30 and 400),
  created_at timestamptz not null default now(),
  primary key (user_id, weighed_on)
);
alter table public.weigh_ins enable row level security;

drop policy if exists weigh_ins_own on public.weigh_ins;
create policy weigh_ins_own on public.weigh_ins
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
