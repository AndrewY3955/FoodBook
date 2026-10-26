-- =====================================================================
-- 0002_core_tables.sql
-- Relational core. Every tenant-scoped table carries an explicit
-- kitchen_profile_id column so that RLS is a direct, index-backed
-- predicate rather than a join chain.
-- =====================================================================

-- ---------------------------------------------------------------------
-- profiles — public mirror of auth.users
-- auth.users is never exposed to the client. Anything the app needs to
-- display about a person lives here.
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 1 and 64),
  avatar_path  text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

comment on table public.profiles is 'Per-user public profile. One row per auth.users row, created by trigger.';

-- ---------------------------------------------------------------------
-- kitchen_profiles — the tenant boundary
-- ---------------------------------------------------------------------
create table if not exists public.kitchen_profiles (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(trim(name)) between 1 and 80),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.kitchen_profiles is 'Tenant root. All user data is partitioned by kitchen_profile_id.';

-- ---------------------------------------------------------------------
-- kitchen_members — many users to one kitchen
-- Membership is the authority for RLS. Revoking a row takes effect on
-- the next query, with no dependency on JWT refresh.
-- ---------------------------------------------------------------------
create table if not exists public.kitchen_members (
  kitchen_profile_id uuid not null references public.kitchen_profiles(id) on delete cascade,
  user_id            uuid not null references auth.users(id) on delete cascade,
  member_role        public.member_role not null default 'member',
  invited_by         uuid references auth.users(id) on delete set null,
  joined_at          timestamptz not null default now(),
  revoked_at         timestamptz,
  primary key (kitchen_profile_id, user_id)
);

create index if not exists kitchen_members_user_idx
  on public.kitchen_members (user_id)
  where revoked_at is null;

comment on table public.kitchen_members is 'Join table binding auth users to kitchens. revoked_at IS NULL means active.';

-- ---------------------------------------------------------------------
-- ingredients — canonical catalog plus per-kitchen custom entries
-- kitchen_profile_id IS NULL  -> global read-only catalog row
-- kitchen_profile_id IS NOT NULL -> private to that kitchen
-- ---------------------------------------------------------------------
create table if not exists public.ingredients (
  id                 uuid primary key default gen_random_uuid(),
  kitchen_profile_id uuid references public.kitchen_profiles(id) on delete cascade,
  name               text not null check (char_length(trim(name)) between 1 and 80),
  grocery_category   public.grocery_category not null default 'other',
  default_unit       public.measure_unit not null default 'unit',
  created_at         timestamptz not null default now()
);

create unique index if not exists ingredients_global_name_key
  on public.ingredients (lower(name))
  where kitchen_profile_id is null;

create unique index if not exists ingredients_kitchen_name_key
  on public.ingredients (kitchen_profile_id, lower(name))
  where kitchen_profile_id is not null;

create index if not exists ingredients_name_trgm_idx
  on public.ingredients using gin (name extensions.gin_trgm_ops);

create index if not exists ingredients_category_idx
  on public.ingredients (grocery_category);

-- ---------------------------------------------------------------------
-- recipes
-- ---------------------------------------------------------------------
create table if not exists public.recipes (
  id                    uuid primary key default gen_random_uuid(),
  kitchen_profile_id    uuid not null references public.kitchen_profiles(id) on delete cascade,
  created_by            uuid references auth.users(id) on delete set null,
  title                 text not null check (char_length(trim(title)) between 1 and 160),
  description           text check (char_length(description) <= 4000),
  meal_type             public.meal_type not null default 'dinner',
  season                public.season not null default 'all_year',
  base_servings         integer not null default 4 check (base_servings between 1 and 100),
  prep_minutes          integer check (prep_minutes between 0 and 1440),
  cook_minutes          integer check (cook_minutes between 0 and 1440),
  cover_image_path      text check (cover_image_path is null or public.is_valid_cover_path(cover_image_path)),
  source_url            text check (source_url is null or public.is_safe_http_url(source_url)),
  external_video_url    text check (external_video_url is null or public.is_safe_http_url(external_video_url)),
  import_source         public.import_source not null default 'manual',
  is_public             boolean not null default false,
  forked_from_recipe_id uuid references public.recipes(id) on delete set null,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create index if not exists recipes_kitchen_idx        on public.recipes (kitchen_profile_id);
create index if not exists recipes_filter_idx         on public.recipes (kitchen_profile_id, meal_type, season);
create index if not exists recipes_public_idx         on public.recipes (is_public) where is_public;
create index if not exists recipes_fork_idx           on public.recipes (forked_from_recipe_id) where forked_from_recipe_id is not null;
create index if not exists recipes_title_trgm_idx     on public.recipes using gin (title extensions.gin_trgm_ops);

comment on column public.recipes.external_video_url is
  'Link-out only. No video is hosted or proxied. Validated by is_safe_http_url at the storage boundary.';

-- ---------------------------------------------------------------------
-- recipe_ingredients
-- kitchen_profile_id is denormalised from the parent recipe and kept
-- honest by a trigger (0003). Without the trigger a member could insert
-- a child row carrying their own kitchen id but pointing at a foreign
-- recipe, which would pass a naive RLS check.
-- ---------------------------------------------------------------------
create table if not exists public.recipe_ingredients (
  id                 uuid primary key default gen_random_uuid(),
  recipe_id          uuid not null references public.recipes(id) on delete cascade,
  kitchen_profile_id uuid not null references public.kitchen_profiles(id) on delete cascade,
  ingredient_id      uuid not null references public.ingredients(id) on delete restrict,
  quantity           numeric(10,3) not null default 1 check (quantity > 0 and quantity <= 100000),
  unit               public.measure_unit not null default 'unit',
  note               text check (char_length(note) <= 200),
  is_optional        boolean not null default false,
  sort_order         integer not null default 0 check (sort_order between 0 and 500),
  unique (recipe_id, ingredient_id)
);

create index if not exists recipe_ingredients_recipe_idx     on public.recipe_ingredients (recipe_id);
create index if not exists recipe_ingredients_kitchen_idx    on public.recipe_ingredients (kitchen_profile_id);
create index if not exists recipe_ingredients_ingredient_idx on public.recipe_ingredients (ingredient_id);

-- ---------------------------------------------------------------------
-- recipe_steps — ordered cooking steps for the tap-to-advance stepper
-- ---------------------------------------------------------------------
create table if not exists public.recipe_steps (
  id                 uuid primary key default gen_random_uuid(),
  recipe_id          uuid not null references public.recipes(id) on delete cascade,
  kitchen_profile_id uuid not null references public.kitchen_profiles(id) on delete cascade,
  step_number        integer not null check (step_number between 1 and 200),
  instruction        text not null check (char_length(trim(instruction)) between 1 and 2000),
  timer_seconds      integer check (timer_seconds between 1 and 86400),
  unique (recipe_id, step_number)
);

create index if not exists recipe_steps_recipe_idx  on public.recipe_steps (recipe_id, step_number);
create index if not exists recipe_steps_kitchen_idx on public.recipe_steps (kitchen_profile_id);

comment on column public.recipe_steps.timer_seconds is
  'Duration handed to the native OS clock app via a platform intent. No in-app countdown is implemented.';

-- ---------------------------------------------------------------------
-- tags — free-form custom tags, scoped per kitchen
-- ---------------------------------------------------------------------
create table if not exists public.tags (
  id                 uuid primary key default gen_random_uuid(),
  kitchen_profile_id uuid not null references public.kitchen_profiles(id) on delete cascade,
  name               text not null check (char_length(trim(name)) between 1 and 40),
  created_at         timestamptz not null default now()
);

create unique index if not exists tags_kitchen_name_key
  on public.tags (kitchen_profile_id, lower(name));

create table if not exists public.recipe_tags (
  recipe_id          uuid not null references public.recipes(id) on delete cascade,
  tag_id             uuid not null references public.tags(id) on delete cascade,
  kitchen_profile_id uuid not null references public.kitchen_profiles(id) on delete cascade,
  primary key (recipe_id, tag_id)
);

create index if not exists recipe_tags_tag_idx     on public.recipe_tags (tag_id);
create index if not exists recipe_tags_kitchen_idx on public.recipe_tags (kitchen_profile_id);

-- ---------------------------------------------------------------------
-- pantry_items
-- ---------------------------------------------------------------------
create table if not exists public.pantry_items (
  id                 uuid primary key default gen_random_uuid(),
  kitchen_profile_id uuid not null references public.kitchen_profiles(id) on delete cascade,
  ingredient_id      uuid not null references public.ingredients(id) on delete restrict,
  quantity           numeric(10,3) not null default 1 check (quantity >= 0 and quantity <= 100000),
  unit               public.measure_unit not null default 'unit',
  updated_at         timestamptz not null default now(),
  unique (kitchen_profile_id, ingredient_id)
);

create index if not exists pantry_items_kitchen_idx    on public.pantry_items (kitchen_profile_id);
create index if not exists pantry_items_ingredient_idx on public.pantry_items (ingredient_id);

-- ---------------------------------------------------------------------
-- shopping_list_items
-- grocery_category is stored on the row, not derived at read time, so
-- the categorised sorter groups without a join and free-text entries
-- ("birthday candles") can still land under a header.
-- ---------------------------------------------------------------------
create table if not exists public.shopping_list_items (
  id                 uuid primary key default gen_random_uuid(),
  kitchen_profile_id uuid not null references public.kitchen_profiles(id) on delete cascade,
  ingredient_id      uuid references public.ingredients(id) on delete set null,
  custom_name        text check (char_length(trim(custom_name)) between 1 and 80),
  grocery_category   public.grocery_category not null default 'other',
  quantity           numeric(10,3) not null default 1 check (quantity > 0 and quantity <= 100000),
  unit               public.measure_unit not null default 'unit',
  is_checked         boolean not null default false,
  added_by           uuid references auth.users(id) on delete set null,
  created_at         timestamptz not null default now(),
  constraint shopping_list_items_has_label
    check (ingredient_id is not null or custom_name is not null)
);

create index if not exists shopping_list_kitchen_idx
  on public.shopping_list_items (kitchen_profile_id, grocery_category, is_checked);

-- ---------------------------------------------------------------------
-- meal_plan_entries
-- ---------------------------------------------------------------------
create table if not exists public.meal_plan_entries (
  id                 uuid primary key default gen_random_uuid(),
  kitchen_profile_id uuid not null references public.kitchen_profiles(id) on delete cascade,
  recipe_id          uuid not null references public.recipes(id) on delete cascade,
  plan_date          date not null,
  meal_type          public.meal_type not null,
  servings_override  integer check (servings_override between 1 and 100),
  note               text check (char_length(note) <= 280),
  created_by         uuid references auth.users(id) on delete set null,
  created_at         timestamptz not null default now(),
  unique (kitchen_profile_id, plan_date, meal_type, recipe_id)
);

create index if not exists meal_plan_range_idx
  on public.meal_plan_entries (kitchen_profile_id, plan_date);

-- ---------------------------------------------------------------------
-- Community layer — substitutions and anonymous cook-time analytics.
-- These attach to PUBLIC recipes and are deliberately cross-tenant.
-- ---------------------------------------------------------------------
create table if not exists public.substitution_suggestions (
  id            uuid primary key default gen_random_uuid(),
  recipe_id     uuid not null references public.recipes(id) on delete cascade,
  ingredient_id uuid not null references public.ingredients(id) on delete cascade,
  suggestion    text not null check (char_length(trim(suggestion)) between 1 and 200),
  created_by    uuid references auth.users(id) on delete set null,
  created_at    timestamptz not null default now(),
  unique (recipe_id, ingredient_id, created_by)
);

create index if not exists substitution_recipe_idx on public.substitution_suggestions (recipe_id);

create table if not exists public.substitution_votes (
  suggestion_id uuid not null references public.substitution_suggestions(id) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade,
  vote          smallint not null check (vote in (-1, 1)),
  created_at    timestamptz not null default now(),
  primary key (suggestion_id, user_id)
);

-- cook_logs holds no user reference by design. The brief asks for
-- anonymous analytics; storing a user id would make it pseudonymous at
-- best. The cost is that per-user deduplication is impossible.
create table if not exists public.cook_logs (
  id           uuid primary key default gen_random_uuid(),
  recipe_id    uuid not null references public.recipes(id) on delete cascade,
  cook_minutes integer not null check (cook_minutes between 1 and 1440),
  logged_at    timestamptz not null default now()
);

create index if not exists cook_logs_recipe_idx on public.cook_logs (recipe_id);

comment on table public.cook_logs is
  'Anonymous real-world cook durations. No user column by design; deduplication is traded for non-attribution.';
