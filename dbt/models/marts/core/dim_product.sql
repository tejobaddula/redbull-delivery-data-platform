{{ config(materialized="table") }}

select
    product_key,
    id_drink,
    brand,
    manufacturer,
    drink_category,
    drink_subcategory,
    modal_volume_ml,
    distinct_volume_count,          -- >1 => id_drink is a product family, not a SKU
    menu_line_count,
    is_red_bull,
    is_energy_drink,
    is_competitor_energy,
    is_coca_cola
from {{ ref('int_product__canonical') }}
