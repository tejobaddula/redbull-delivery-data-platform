{{ config(materialized="table") }}

with distinct_platforms as (
    select distinct id_platform, platform_name
    from {{ ref('stg_outlet') }}
    where platform_name is not null
)

select
    {{ dbt_utils.generate_surrogate_key(['id_platform']) }} as platform_key,
    id_platform,
    platform_name
from distinct_platforms
