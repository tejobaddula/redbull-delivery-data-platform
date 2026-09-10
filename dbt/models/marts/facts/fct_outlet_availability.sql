{{ config(materialized="table") }}

/*
  Grain: one outlet listing (id_ext_link) - 1:1 with stg_matching / stg_outlet.
  The Red Bull / competitor availability flags at their finest grain (per platform
  listing), before the dim_outlet roll-up. All 3 markets.
*/

with matching as (
    select * from {{ ref('stg_matching') }}
),

listing as (
    select id_ext_link, id_platform, scraped_date from {{ ref('stg_outlet') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['m.id_ext_link']) }} as availability_key,
    m.id_ext_link,
    o.outlet_key,
    pf.platform_key,
    mk.market_key,
    ch.chain_key,
    m.market_code,          -- denormalized: row access policy filter column
    l.scraped_date,

    m.google_place_id,
    m.match_score_name,
    m.match_score_address,
    m.is_chain,

    m.serves_drinks,
    m.serves_red_bull,
    m.has_red_bull_sugarfree,
    m.has_red_bull_editions,
    m.has_organics_by_red_bull,
    m.serves_energy_drink,
    m.serves_competitor_energy,
    m.serves_soft_drink,
    m.serves_coca_cola,
    m.is_primary_listing,
    m.is_red_bull_opportunity
from matching m
left join listing l               on l.id_ext_link = m.id_ext_link
left join {{ ref('dim_outlet') }}   o on o.id_outlet   = m.id_outlet
left join {{ ref('dim_platform') }} pf on pf.id_platform = l.id_platform
left join {{ ref('dim_market') }}   mk on mk.market_code = m.market_code
left join {{ ref('dim_chain') }}    ch on ch.chain_name  = m.chain_name
