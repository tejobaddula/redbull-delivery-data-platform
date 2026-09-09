{{ config(materialized="view") }}

/*
  Outlet listings, typed and cleaned. Grain: id_ext_link (one outlet on one platform).
  RAW.OUTLET has 0 duplicate id_ext_link and 0 nulls, but the QUALIFY keeps this
  idempotent if a file is ever re-loaded (keeps the latest _load_ts).

  Column renames vs source (mislabeled upstream):
    address_locality -> admin_area   (actually holds state / nation)
    city             -> sub_region   (actually holds county / borough)
  Dropped (dead / redundant): business_url, telephone_platform, ghost_kitchen,
    banner_available (const 'true'), banner_img_hash, cuisine (= category;description).
*/

with src as (
    select * from {{ source('raw', 'outlet') }}
),

cleaned as (
    select
        -- identifiers (kept as text: 20-digit ids, never arithmetic)
        id_ext_link,
        id_outlet,
        id_platform,
        initcap({{ nullify_blank('platform_name') }})              as platform_name,

        -- names / text (embedded newlines collapsed)
        {{ collapse_ws('name') }}                                  as outlet_name,
        {{ collapse_ws('business') }}                              as chain_name_raw,
        {{ collapse_ws('address_bulk') }}                          as address_full,
        {{ collapse_ws('street_address') }}                        as street_address,
        {{ nullify_blank('postal_code') }}                         as postal_code,
        {{ collapse_ws('city') }}                                  as sub_region,
        {{ collapse_ws('address_locality') }}                      as admin_area,
        {{ nullify_blank('link') }}                                as listing_url,

        -- category: primary cuisine + ';'-delimited secondary tags
        lower({{ nullify_blank('category') }})                     as category_primary,
        {{ nullify_blank('description') }}                         as category_tags_raw,

        -- geo
        {{ to_float('latitude') }}                                 as latitude,
        {{ to_float('longitude') }}                                as longitude,

        -- ratings / economics
        {{ to_int('num_ratings') }}                                as num_ratings,
        {{ to_int('average_rating') }}                             as avg_rating,      -- integer 1-5 upstream
        -- average_cost is a 1-4 price tier; ~39 rows carry junk (5, 23, 599, ...) -> NULL
        case when {{ to_int('average_cost') }} between 1 and 4
             then {{ to_int('average_cost') }} end                as price_tier,
        {{ to_number('min_order_amount', 12, 2) }}                 as min_order_amount,
        {{ to_number('delivery', 12, 2) }}                         as delivery_fee,

        -- classification
        {{ nullify_blank('segment_type') }}                        as segment_type,
        {{ nullify_blank('local_currency') }}                      as currency_code,

        {{ to_date('created_at') }}                                as scraped_date,

        -- lineage
        _market                                                   as market_code,
        _period                                                   as load_period,
        _stg_file_name,
        _stg_file_row_number,
        _load_ts

    from src
    qualify row_number() over (partition by id_ext_link order by _load_ts desc) = 1
)

select
    *,
    -- convenience: physical outlet may appear on several platforms
    md5(id_outlet)                                                 as outlet_key,
    md5(id_ext_link)                                               as listing_key
from cleaned
