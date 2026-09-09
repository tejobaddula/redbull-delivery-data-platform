{{ config(materialized="view") }}

/*
  Drink menu line items, typed and cleaned. Grain: id_beverage. GBR + DEU only.

  Notes:
    - item_price is the price of the MENU LINE (often a combo/deal), not the drink alone.
    - created_at is 100% empty upstream -> menu_snapshot_date falls back to the load period.
    - item_subbrand '<brand> Unspecified' is a sentinel -> NULL.
    - item_drink_category_1 is ~always 'Soft Drink' (near-constant) -> kept, documented.
  Dropped (dead): banner_available (const 'false'), banner_img_link, banner_img_hash.
*/

with src as (
    select * from {{ source('raw', 'portfolio') }}
),

cleaned as (
    select
        id_beverage,
        id_ext_link,
        id_outlet,
        id_drink,
        id_category,

        {{ nullify_blank('item_position') }}                       as menu_position,
        {{ collapse_ws('item_category') }}                         as menu_section,

        {{ collapse_ws('item_name') }}                             as item_name,
        {{ collapse_ws('item_desc') }}                             as item_description,

        {{ nullify_blank('item_manufacturer') }}                   as manufacturer,
        {{ nullify_blank('item_brand') }}                          as brand,
        case
            when trim(item_subbrand) ilike '% Unspecified' then null
            else {{ nullify_blank('item_subbrand') }}
        end                                                        as sub_brand,

        {{ nullify_blank('item_drink_category_1') }}               as drink_category,     -- near-constant 'Soft Drink'
        {{ nullify_blank('item_drink_category_2') }}               as drink_subcategory,  -- Cola / Energy / Tonic Water / ...

        {{ to_number('item_volume', 12, 2) }}                      as volume_ml,
        {{ to_number('item_price', 12, 4) }}                       as line_price,

        {{ to_bool('addon_prompt') }}                              as is_addon,
        {{ collapse_ws('addon_prompt_text') }}                     as addon_text,
        {{ nullify_blank('packaging_size') }}                      as packaging_size_raw,
        {{ nullify_blank('item_image_url') }}                      as image_url,

        -- lineage
        _market                                                   as market_code,
        _period                                                   as load_period,
        {{ to_date('created_at') }}                                as scraped_date,      -- always NULL upstream
        coalesce(
            {{ to_date('created_at') }},
            to_date(left(_period, 4) || '-' || right(_period, 2) || '-01')
        )                                                          as menu_snapshot_date,
        _stg_file_name,
        _stg_file_row_number,
        _load_ts

    from src
    qualify row_number() over (partition by id_beverage order by _load_ts desc) = 1
)

select
    *,
    md5(id_ext_link)                                              as listing_key,
    md5(id_drink)                                                 as drink_key
from cleaned
