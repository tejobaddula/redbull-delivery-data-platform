-- 02_raw_tables.sql
-- RAW landing tables. Everything VARCHAR: RAW never rejects data for a type reason;
-- typing + cleaning happens in dbt STAGING where it is tested.
-- Every table carries _stg_* / _load_* lineage columns, populated by COPY INCLUDE_METADATA.
-- Run as RB_LOADER.

USE ROLE RB_LOADER;
USE DATABASE REDBULL_DELIVERY;
USE SCHEMA RAW;

------------------------------------------------------------------------------
-- OUTLET  (37 source columns)
------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS RAW.OUTLET (
    id_ext_link          VARCHAR,
    id_outlet            VARCHAR,
    id_platform          VARCHAR,
    platform_name        VARCHAR,
    link                 VARCHAR,
    name                 VARCHAR,
    address_bulk         VARCHAR,
    business             VARCHAR,
    business_url         VARCHAR,
    delivery             VARCHAR,
    category             VARCHAR,
    description          VARCHAR,
    telephone            VARCHAR,
    latitude             VARCHAR,
    longitude            VARCHAR,
    num_ratings          VARCHAR,
    average_rating       VARCHAR,
    average_cost         VARCHAR,
    city                 VARCHAR,
    icon_url             VARCHAR,
    local_icon_name      VARCHAR,
    min_order_amount     VARCHAR,
    banner_available     VARCHAR,
    banner_img_link      VARCHAR,
    banner_img_hash      VARCHAR,
    market               VARCHAR,
    street_address       VARCHAR,
    postal_code          VARCHAR,
    address_locality     VARCHAR,
    address_country      VARCHAR,
    telephone_platform   VARCHAR,
    cuisine              VARCHAR,
    website              VARCHAR,
    ghost_kitchen        VARCHAR,
    local_currency       VARCHAR,
    created_at           VARCHAR,
    segment_type         VARCHAR,
    -- lineage
    _market              VARCHAR,          -- market from the stage path (source of truth)
    _period              VARCHAR,          -- yyyymm from the stage path
    _stg_file_name       VARCHAR,
    _stg_file_row_number NUMBER,
    _stg_file_last_modified TIMESTAMP_NTZ,
    _load_ts             TIMESTAMP_NTZ
);

------------------------------------------------------------------------------
-- PORTFOLIO  (25 source columns)   GBR + DEU only
------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS RAW.PORTFOLIO (
    id_beverage          VARCHAR,
    id_ext_link          VARCHAR,
    id_outlet            VARCHAR,
    item_position        VARCHAR,
    item_category        VARCHAR,
    id_drink             VARCHAR,
    item_manufacturer    VARCHAR,
    item_brand           VARCHAR,
    item_subbrand        VARCHAR,
    item_volume          VARCHAR,
    item_price           VARCHAR,
    id_category          VARCHAR,
    item_drink_category_1 VARCHAR,
    item_drink_category_2 VARCHAR,
    item_image_url       VARCHAR,
    item_image_hash      VARCHAR,
    item_name            VARCHAR,
    item_desc            VARCHAR,
    addon_prompt         VARCHAR,
    addon_prompt_text    VARCHAR,
    packaging_size       VARCHAR,
    banner_available     VARCHAR,
    banner_img_link      VARCHAR,
    banner_img_hash      VARCHAR,
    created_at           VARCHAR,
    -- lineage
    _market              VARCHAR,
    _period              VARCHAR,
    _stg_file_name       VARCHAR,
    _stg_file_row_number NUMBER,
    _stg_file_last_modified TIMESTAMP_NTZ,
    _load_ts             TIMESTAMP_NTZ
);

------------------------------------------------------------------------------
-- MATCHING  (21 source columns)
------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS RAW.MATCHING (
    id_outlet                VARCHAR,
    id_platform              VARCHAR,
    platform_name            VARCHAR,
    id_ext_link              VARCHAR,
    place_id                 VARCHAR,
    similarity_score_name    VARCHAR,
    similarity_score_address VARCHAR,
    merged_chain_name        VARCHAR,
    is_chain                 VARCHAR,
    num_restaurants          VARCHAR,
    serves_drinks            VARCHAR,
    serves_red_bull          VARCHAR,
    sugar_free_available     VARCHAR,
    organics_available       VARCHAR,
    editions_available       VARCHAR,
    ed                       VARCHAR,
    ed_comp                  VARCHAR,
    sd_coke                  VARCHAR,
    sd                       VARCHAR,
    leading_id_ext_link      VARCHAR,
    created_at               VARCHAR,
    -- lineage
    _market              VARCHAR,
    _period              VARCHAR,
    _stg_file_name       VARCHAR,
    _stg_file_row_number NUMBER,
    _stg_file_last_modified TIMESTAMP_NTZ,
    _load_ts             TIMESTAMP_NTZ
);

------------------------------------------------------------------------------
-- Load audit — one row per (feed, market, file) COPY result.
------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS UTIL.LOAD_HISTORY (
    run_id           VARCHAR,
    feed             VARCHAR,
    market           VARCHAR,
    period           VARCHAR,
    stage_path       VARCHAR,
    file_name        VARCHAR,
    status           VARCHAR,
    rows_parsed      NUMBER,
    rows_loaded      NUMBER,
    error_count      NUMBER,
    first_error      VARCHAR,
    started_at       TIMESTAMP_NTZ,
    finished_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
