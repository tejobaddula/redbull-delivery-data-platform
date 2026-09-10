{{ config(materialized="table") }}

/*
  One row per physical outlet (id_outlet). Collapses the ~1.7 platform listings
  each physical outlet has.

  Profiling: name / category / postal_code drift across a physical outlet's
  listings in ~30-36% of cases; market_code never drifts.

  Reconciliation:
    categoricals  -> mode across listings
    address_full  -> the most complete value (longest string)
    geo + address -> taken from the primary listing (matching.is_primary_listing,
                     then latest _load_ts)
    *_conflict    -> flags so the marts / analysts know reconciliation happened
*/

with listings as (
    select
        o.*,
        m.is_primary_listing,
        m.google_place_id,
        m.is_chain,
        m.chain_name
    from {{ ref('stg_outlet') }} o
    left join {{ ref('stg_matching') }} m using (id_ext_link)
),

primary_listing as (
    select
        id_outlet, latitude, longitude, street_address, postal_code, google_place_id,
        row_number() over (
            partition by id_outlet
            order by coalesce(is_primary_listing, false) desc, _load_ts desc
        ) as rn
    from listings
),

agg as (
    select
        id_outlet,
        mode(outlet_name)                         as outlet_name,
        mode(chain_name_raw)                      as chain_name_raw,
        mode(chain_name)                          as chain_name,
        boolor_agg(coalesce(is_chain, false))        as is_chain,
        mode(category_primary)                    as category_primary,
        mode(sub_region)                          as sub_region,
        mode(admin_area)                          as admin_area,
        max_by(address_full, length(address_full)) as address_full,
        mode(market_code)                         as market_code,
        mode(currency_code)                       as currency_code,
        mode(segment_type)                        as segment_type,
        array_agg(distinct platform_name) within group (order by platform_name) as platform_list,
        count(*)                                  as listing_count,
        min(scraped_date)                         as first_scraped_date,
        max(scraped_date)                         as last_scraped_date,
        count(distinct lower(outlet_name)) > 1    as has_name_conflict,
        count(distinct category_primary) > 1      as has_category_conflict,
        count(distinct postal_code) > 1           as has_postal_conflict
    from listings
    group by 1
)

select
    {{ dbt_utils.generate_surrogate_key(['a.id_outlet']) }} as outlet_key,
    a.id_outlet,
    a.outlet_name,
    a.chain_name_raw,
    a.chain_name,
    a.is_chain,
    p.street_address,
    p.postal_code,
    a.sub_region,
    a.admin_area,
    a.address_full,
    p.latitude,
    p.longitude,
    p.google_place_id,
    a.category_primary,
    a.segment_type,
    a.market_code,
    a.currency_code,
    a.platform_list,
    a.listing_count,
    a.first_scraped_date,
    a.last_scraped_date,
    a.has_name_conflict,
    a.has_category_conflict,
    a.has_postal_conflict
from agg a
left join primary_listing p on p.id_outlet = a.id_outlet and p.rn = 1
