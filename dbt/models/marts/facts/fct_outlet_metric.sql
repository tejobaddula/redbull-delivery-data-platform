{{ config(materialized="table") }}

/*
  Grain: one outlet listing (id_ext_link). Platform-reported metrics for each
  listing: ratings, price tier, delivery economics. All 3 markets (with heavy
  per-market nulls - see data_quality.md #20).
*/

with outlet as (
    select * from {{ ref('stg_outlet') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['o.id_ext_link']) }} as outlet_metric_key,
    o.id_ext_link,
    d.outlet_key,
    pf.platform_key,
    mk.market_key,
    o.scraped_date,

    o.num_ratings,
    o.avg_rating,
    o.price_tier,
    o.min_order_amount,
    o.delivery_fee
from outlet o
left join {{ ref('dim_outlet') }}   d  on d.id_outlet   = o.id_outlet
left join {{ ref('dim_platform') }} pf on pf.id_platform = o.id_platform
left join {{ ref('dim_market') }}   mk on mk.market_code = o.market_code
