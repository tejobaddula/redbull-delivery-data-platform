{{ config(materialized="table") }}

select
    {{ dbt_utils.generate_surrogate_key(['market_code']) }} as market_key,
    market_code,
    market_name,
    country_iso2,
    country_iso3,
    currency_code
from {{ ref('seed_market') }}
