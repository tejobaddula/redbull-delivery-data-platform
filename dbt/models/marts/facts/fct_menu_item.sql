{{ config(materialized="table") }}

/*
  Grain: one drink menu line (id_beverage). GBR + DEU only (no USA portfolio).
  line_price is the MENU-LINE price (often a combo/deal), not the drink price.
  volume_ml is per line (kept here, NOT on dim_product - id_drink is a family).
*/

with portfolio as (
    select * from {{ ref('stg_portfolio') }}
),

listing as (
    select id_ext_link, id_platform from {{ ref('stg_outlet') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['p.id_beverage']) }} as menu_item_key,
    p.id_beverage,
    p.id_ext_link,
    o.outlet_key,
    pr.product_key,
    pf.platform_key,
    mk.market_key,
    p.market_code,          -- denormalized: row access policy filter column
    p.menu_snapshot_date,

    p.menu_section,
    p.menu_position,
    p.line_price,
    p.volume_ml,
    p.is_addon,

    pr.brand,
    pr.drink_subcategory,
    pr.is_red_bull,
    pr.is_competitor_energy,
    pr.is_coca_cola
from portfolio p
left join listing l                 on l.id_ext_link = p.id_ext_link
left join {{ ref('dim_outlet') }}   o  on o.id_outlet   = p.id_outlet
left join {{ ref('dim_product') }}  pr on pr.id_drink   = p.id_drink
left join {{ ref('dim_platform') }} pf on pf.id_platform = l.id_platform
left join {{ ref('dim_market') }}   mk on mk.market_code = p.market_code
