{{ config(materialized="table") }}

/*
  The drink catalogue that was never supplied. One row per id_drink.

  Profiling (331 distinct drinks):
    - brand and drink_subcategory are 100% consistent per id_drink -> mode is exact,
      no agreement-% column needed.
    - id_drink is a product FAMILY, not a SKU: 248/331 have 2+ distinct volumes.
      -> modal_volume_ml is "typical pack size" only; real volume lives on fct_menu_item.
*/

with lines as (
    select * from {{ ref('stg_portfolio') }}
),

agg as (
    select
        id_drink,
        mode(brand)                   as brand,
        mode(manufacturer)            as manufacturer,
        mode(drink_category)          as drink_category,
        mode(drink_subcategory)       as drink_subcategory,
        mode(volume_ml)               as modal_volume_ml,
        count(*)                      as menu_line_count,
        count(distinct volume_ml)     as distinct_volume_count,
        count(distinct id_ext_link)   as outlet_listing_count,
        count(distinct market_code)   as market_count
    from lines
    group by 1
)

select
    {{ dbt_utils.generate_surrogate_key(['id_drink']) }}          as product_key,
    id_drink,
    brand,
    manufacturer,
    drink_category,
    drink_subcategory,
    modal_volume_ml,
    distinct_volume_count,
    menu_line_count,
    outlet_listing_count,
    market_count,
    -- classification
    lower(brand) like '%red bull%'                                as is_red_bull,
    drink_subcategory = 'Energy'                                  as is_energy_drink,
    (drink_subcategory = 'Energy'
        and lower(brand) not like '%red bull%')                   as is_competitor_energy,
    lower(brand) = 'coca-cola'                                    as is_coca_cola
from agg
