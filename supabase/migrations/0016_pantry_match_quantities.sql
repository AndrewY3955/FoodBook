-- =====================================================================
-- 0016_pantry_match_quantities.sql
--
-- pantry_match used to count an ingredient as "matched" whenever the
-- pantry held any amount of it, so 50 g of flour satisfied a recipe
-- that needs 200 g. It also scanned every recipe the caller could see
-- (other libraries, public recipes) rather than the library asked for.
--
-- Now an ingredient is matched only when the pantry holds enough:
--   * Same unit family (mass, volume, or the very same counting unit):
--     quantities are converted to a common base and compared.
--   * Quantity or unit is missing, the unit is "to taste" or "pinch", or
--     the units cannot be compared (cups of flour against grams of
--     flour; "piece" against "can"): having the ingredient counts.
--   * Optional ingredients never count against a recipe.
-- Only recipes in p_library_id are considered. The signature and result
-- columns are unchanged, so the client needs no change.
-- =====================================================================

begin;

create or replace function public._unit_family(p_unit public.measure_unit)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_unit::text
    when 'g'     then 'mass'  when 'kg'   then 'mass'
    when 'oz'    then 'mass'  when 'lb'   then 'mass'
    when 'ml'    then 'vol'   when 'l'    then 'vol'
    when 'tsp'   then 'vol'   when 'tbsp' then 'vol'
    when 'cup'   then 'vol'   when 'fl_oz' then 'vol'
    else p_unit::text
  end;
$$;

create or replace function public._unit_factor(p_unit public.measure_unit)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select case p_unit::text
    when 'g'     then 1::numeric
    when 'kg'    then 1000
    when 'oz'    then 28.3495
    when 'lb'    then 453.592
    when 'ml'    then 1
    when 'l'     then 1000
    when 'tsp'   then 4.92892
    when 'tbsp'  then 14.7868
    when 'cup'   then 236.588
    when 'fl_oz' then 29.5735
    else 1
  end;
$$;

grant execute on function public._unit_family(public.measure_unit) to authenticated;
grant execute on function public._unit_factor(public.measure_unit) to authenticated;

create or replace function public.pantry_match(
  p_library_id uuid,
  p_min_pct    numeric default 0,
  p_meal_type  public.meal_type default null,
  p_season     public.season default null,
  p_limit      integer default 50
)
returns table (
  recipe_id       uuid,
  title           text,
  meal_type       public.meal_type,
  season          public.season,
  required_count  integer,
  matched_count   integer,
  match_pct       numeric
)
language sql
stable
set search_path = public, pg_temp
as $$
  with pantry as (
    select pi.ingredient_id, pi.quantity, pi.unit
      from public.pantry_items pi
     where pi.library_id = p_library_id
       and pi.quantity > 0
  ),
  lines as (
    select r.id as rid, r.title, r.meal_type, r.season, ri.is_optional,
           case
             when p.ingredient_id is null then false
             when ri.quantity is null or ri.quantity <= 0 or ri.unit is null
               or ri.unit::text in ('to_taste', 'pinch') then true
             when public._unit_family(ri.unit) = public._unit_family(p.unit)
               then p.quantity * public._unit_factor(p.unit)
                    >= ri.quantity * public._unit_factor(ri.unit) * 0.999
             else true
           end as enough
      from public.recipes r
      join public.recipe_ingredients ri on ri.recipe_id = r.id
      left join pantry p on p.ingredient_id = ri.ingredient_id
     where r.library_id = p_library_id
       and (p_meal_type is null or r.meal_type = p_meal_type)
       and (p_season   is null or r.season in (p_season, 'all_year'))
  )
  select l.rid,
         l.title,
         l.meal_type,
         l.season,
         count(*) filter (where not l.is_optional)::integer,
         count(*) filter (where not l.is_optional and l.enough)::integer,
         round(
           100.0 * count(*) filter (where not l.is_optional and l.enough)
                 / nullif(count(*) filter (where not l.is_optional), 0),
           0
         )
    from lines l
   group by l.rid, l.title, l.meal_type, l.season
  having coalesce(
           round(
             100.0 * count(*) filter (where not l.is_optional and l.enough)
                   / nullif(count(*) filter (where not l.is_optional), 0),
             0), 0) >= p_min_pct
   order by 7 desc nulls last, l.title asc
   limit greatest(1, least(coalesce(p_limit, 50), 200));
$$;

grant execute on function public.pantry_match(uuid, numeric, public.meal_type, public.season, integer) to authenticated;

commit;
