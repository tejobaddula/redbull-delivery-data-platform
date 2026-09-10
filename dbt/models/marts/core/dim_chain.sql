{{ config(materialized="table") }}

/*
  One row per chain (global, not per-market). 140 chains; 21 span >1 market.
  chain_size (num_restaurants) is undated / unscoped upstream -> take the max
  value observed and expose market coverage alongside it.
*/

with chains as (
    select
        chain_name,
        max(chain_size)                                                     as chain_size,
        count(distinct market_code)                                         as market_count,
        array_agg(distinct market_code) within group (order by market_code)  as markets
    from {{ ref('stg_matching') }}
    where chain_name is not null and is_chain
    group by 1
)

select
    {{ dbt_utils.generate_surrogate_key(['chain_name']) }} as chain_key,
    chain_name,
    chain_size,
    market_count,
    markets
from chains
