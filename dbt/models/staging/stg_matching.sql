{{ config(materialized="view") }}

/*
  Outlet listing <-> Google Maps match + on-menu availability flags.
  Grain: id_ext_link (1:1 with stg_outlet). id_platform / platform_name are constant
  (Google Maps) and dropped.

  Flag semantics (verified against the data, not documented upstream):
    serves_red_bull      Red Bull present on the menu
    sugar_free_available Red Bull Sugarfree present
    editions_available   Red Bull Editions present
    organics_available   Organics by Red Bull present
    ed        any energy drink present         (superset of serves_red_bull: 0 rows RB & not ed)
    ed_comp   competitor energy drink present
    sd        any soft drink present           (superset of sd_coke)
    sd_coke   Coca-Cola soft drink present
    serves_drinks  outlet sells beverages at all
  leading_id_ext_link is 0/1, NOT an id -> renamed is_primary_listing.
*/

with src as (
    select * from {{ source('raw', 'matching') }}
),

cleaned as (
    select
        id_ext_link,
        id_outlet,
        {{ nullify_blank('place_id') }}                            as google_place_id,

        {{ to_float('similarity_score_name') }}                    as match_score_name,
        {{ to_float('similarity_score_address') }}                 as match_score_address,

        {{ to_bool('is_chain') }}                                  as is_chain,
        {{ collapse_ws('merged_chain_name') }}                     as chain_name,
        {{ to_int('num_restaurants') }}                            as chain_size,

        {{ to_bool('serves_drinks') }}                             as serves_drinks,
        {{ to_bool('serves_red_bull') }}                           as serves_red_bull,
        {{ to_bool('sugar_free_available') }}                      as has_red_bull_sugarfree,
        {{ to_bool('editions_available') }}                        as has_red_bull_editions,
        {{ to_bool('organics_available') }}                        as has_organics_by_red_bull,
        {{ to_bool('ed') }}                                        as serves_energy_drink,
        {{ to_bool('ed_comp') }}                                   as serves_competitor_energy,
        {{ to_bool('sd') }}                                        as serves_soft_drink,
        {{ to_bool('sd_coke') }}                                   as serves_coca_cola,
        {{ to_bool('leading_id_ext_link') }}                       as is_primary_listing,

        -- lineage
        _market                                                   as market_code,
        _period                                                   as load_period,
        {{ to_date('created_at') }}                                as scraped_date,
        _stg_file_name,
        _stg_file_row_number,
        _load_ts

    from src
    qualify row_number() over (partition by id_ext_link order by _load_ts desc) = 1
)

select
    *,
    -- the white-space segment: competitor energy on the menu, no Red Bull
    (serves_competitor_energy and not serves_red_bull)            as is_red_bull_opportunity
from cleaned
