{{ config(materialized="table") }}

/*
  Physical-outlet dimension. Built on int_outlet__unified, enriched with:
    - market_key / chain_key foreign keys
    - Red Bull / competitor availability ROLLED UP from the outlet's listings.
      28,118 outlets have listings that disagree on serves_red_bull, so:
        serves_red_bull          = BOOL_OR  (available on ANY platform)
        serves_red_bull_primary  = value on the primary listing
        has_red_bull_conflict    = listings disagree
*/

with outlet as (
    select * from {{ ref('int_outlet__unified') }}
),

availability as (
    select
        id_outlet,
        boolor_agg(coalesce(serves_red_bull, false))           as serves_red_bull,
        boolor_agg(coalesce(serves_competitor_energy, false))  as serves_competitor_energy,
        boolor_agg(coalesce(serves_coca_cola, false))          as serves_coca_cola,
        boolor_agg(coalesce(is_red_bull_opportunity, false))   as is_red_bull_opportunity,
        count(distinct serves_red_bull) > 1                 as has_red_bull_conflict,
        max_by(serves_red_bull, coalesce(is_primary_listing, false)::int) as serves_red_bull_primary
    from {{ ref('stg_matching') }}
    group by 1
)

select
    o.outlet_key,
    o.id_outlet,
    o.outlet_name,
    o.chain_name,
    o.chain_name_raw,
    o.is_chain,
    ch.chain_key,
    o.street_address,
    o.postal_code,
    o.sub_region,
    o.admin_area,
    o.address_full,
    o.latitude,
    o.longitude,
    o.google_place_id,
    o.category_primary,
    o.segment_type,
    o.market_code,
    mk.market_key,
    o.currency_code,
    o.platform_list,
    o.listing_count,
    o.first_scraped_date,
    o.last_scraped_date,
    o.has_name_conflict,
    o.has_category_conflict,
    o.has_postal_conflict,
    coalesce(a.serves_red_bull, false)          as serves_red_bull,
    coalesce(a.serves_red_bull_primary, false)  as serves_red_bull_primary,
    coalesce(a.has_red_bull_conflict, false)    as has_red_bull_conflict,
    coalesce(a.serves_competitor_energy, false) as serves_competitor_energy,
    coalesce(a.serves_coca_cola, false)         as serves_coca_cola,
    coalesce(a.is_red_bull_opportunity, false)  as is_red_bull_opportunity
from outlet o
left join availability a on a.id_outlet = o.id_outlet
left join {{ ref('dim_market') }} mk on mk.market_code = o.market_code
left join {{ ref('dim_chain') }} ch on ch.chain_name = o.chain_name
