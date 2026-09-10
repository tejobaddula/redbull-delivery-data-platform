-- 04_semantic_view.sql
-- Semantic view for Cortex Analyst (the GenAI PoC). Hand-curated: relationships,
-- pre-defined metrics, and synonyms - the parts Autopilot's generator omits and
-- the parts that make natural-language -> SQL accurate and consistent.
--
-- Run as RB_TRANSFORMER (owns MARTS). Cortex Analyst works on the trial account
-- even though SNOWFLAKE.CORTEX.COMPLETE does not.
--
-- Analysts query this via Cortex Analyst; the generated SQL runs under the
-- caller's role, so the RAP_MARKET row access policy still applies
-- (RB_ANALYST_GBR sees only GBR).
--
-- Syntax note: each entry is  <table>.<LOGICAL NAME> AS <sql expression>.

USE ROLE RB_TRANSFORMER;
USE DATABASE REDBULL_DELIVERY;
USE SCHEMA MARTS;

CREATE OR REPLACE SEMANTIC VIEW MARTS.RB_DELIVERY_SV
    TABLES (
        outlets AS REDBULL_DELIVERY.MARTS.DIM_OUTLET PRIMARY KEY (outlet_key)
            WITH SYNONYMS ('outlet', 'store', 'restaurant', 'location', 'venue')
            COMMENT = 'One row per physical outlet. Red Bull / competitor flags rolled up from the outlet''s platform listings (available on ANY platform).',
        availability AS REDBULL_DELIVERY.MARTS.FCT_OUTLET_AVAILABILITY PRIMARY KEY (availability_key)
            WITH SYNONYMS ('listing', 'platform listing')
            COMMENT = 'One row per outlet listing on a delivery platform. Availability at its finest grain plus Google Maps match scores. All 3 markets.',
        menu AS REDBULL_DELIVERY.MARTS.FCT_MENU_ITEM PRIMARY KEY (menu_item_key)
            WITH SYNONYMS ('menu item', 'menu line', 'drink on the menu')
            COMMENT = 'One drink menu line. GBR + DEU only. line_price is the menu-line price, often a combo/deal.',
        outlet_metrics AS REDBULL_DELIVERY.MARTS.FCT_OUTLET_METRIC PRIMARY KEY (outlet_metric_key)
            WITH SYNONYMS ('ratings', 'reviews', 'delivery economics')
            COMMENT = 'Platform-reported ratings, price tier and delivery economics per listing.',
        market AS REDBULL_DELIVERY.MARTS.DIM_MARKET PRIMARY KEY (market_key)
            WITH SYNONYMS ('market', 'country')
            COMMENT = 'The 3 markets: USA, GBR, DEU.',
        platform AS REDBULL_DELIVERY.MARTS.DIM_PLATFORM PRIMARY KEY (platform_key)
            WITH SYNONYMS ('platform', 'delivery app')
            COMMENT = 'Delivery platforms: Doordash / Ubereats / Grubhub (USA), Justeat / Deliveroo / Ubereats (GBR), Lieferando (DEU).',
        chain AS REDBULL_DELIVERY.MARTS.DIM_CHAIN PRIMARY KEY (chain_key)
            WITH SYNONYMS ('chain', 'franchise')
            COMMENT = 'Restaurant chains (global). chain_size = approx number of locations.',
        product AS REDBULL_DELIVERY.MARTS.DIM_PRODUCT PRIMARY KEY (product_key)
            WITH SYNONYMS ('product', 'drink', 'beverage', 'sku')
            COMMENT = 'Canonical drink (331 drinks). modal_volume_ml is a typical pack size only - id_drink is a product family.',
        dates AS REDBULL_DELIVERY.MARTS.DIM_DATE PRIMARY KEY (date_day)
            WITH SYNONYMS ('date', 'day', 'calendar')
            COMMENT = 'Calendar. Data covers 2024-01-29 to 2024-03-15 only.'
    )
    RELATIONSHIPS (
        availability_to_outlet   AS availability (outlet_key)     REFERENCES outlets (outlet_key),
        availability_to_market   AS availability (market_key)     REFERENCES market (market_key),
        availability_to_platform AS availability (platform_key)   REFERENCES platform (platform_key),
        availability_to_chain    AS availability (chain_key)      REFERENCES chain (chain_key),
        availability_to_date     AS availability (scraped_date)   REFERENCES dates (date_day),
        menu_to_outlet           AS menu (outlet_key)             REFERENCES outlets (outlet_key),
        menu_to_product          AS menu (product_key)            REFERENCES product (product_key),
        menu_to_market           AS menu (market_key)             REFERENCES market (market_key),
        menu_to_platform         AS menu (platform_key)           REFERENCES platform (platform_key),
        metrics_to_outlet        AS outlet_metrics (outlet_key)   REFERENCES outlets (outlet_key),
        metrics_to_market        AS outlet_metrics (market_key)   REFERENCES market (market_key),
        metrics_to_platform      AS outlet_metrics (platform_key) REFERENCES platform (platform_key),
        outlets_to_market        AS outlets (market_key)          REFERENCES market (market_key),
        outlets_to_chain         AS outlets (chain_key)           REFERENCES chain (chain_key)
    )
    FACTS (
        availability.match_score_name AS match_score_name,
        availability.match_score_address AS match_score_address,
        menu.line_price AS line_price,
        menu.volume_ml AS volume_ml,
        outlet_metrics.num_ratings AS num_ratings,
        outlet_metrics.rating AS avg_rating,
        outlet_metrics.price_tier AS price_tier,
        outlet_metrics.min_order_amount AS min_order_amount,
        outlet_metrics.delivery_fee AS delivery_fee,
        product.modal_volume_ml AS modal_volume_ml
    )
    DIMENSIONS (
        outlets.outlet_id AS id_outlet,
        outlets.outlet_name AS outlet_name WITH SYNONYMS ('name', 'store name'),
        outlets.market AS market_code WITH SYNONYMS ('market', 'country') COMMENT = 'USA, GBR or DEU.',
        outlets.region AS admin_area WITH SYNONYMS ('region', 'state', 'province', 'bundesland'),
        outlets.county AS sub_region WITH SYNONYMS ('county', 'borough', 'district'),
        outlets.cuisine AS category_primary WITH SYNONYMS ('cuisine', 'category', 'food type'),
        outlets.segment AS segment_type WITH SYNONYMS ('segment', 'restaurant or grocery'),
        outlets.outlet_is_chain AS is_chain,
        outlets.outlet_chain AS chain_name WITH SYNONYMS ('chain', 'franchise'),
        outlets.carries_red_bull AS serves_red_bull WITH SYNONYMS ('has red bull', 'stocks red bull', 'sells red bull') COMMENT = 'TRUE if Red Bull is on the menu on any platform.',
        outlets.carries_competitor_energy AS serves_competitor_energy WITH SYNONYMS ('has monster', 'sells rockstar', 'competitor energy drink'),
        outlets.is_opportunity AS is_red_bull_opportunity WITH SYNONYMS ('white space', 'opportunity', 'gap', 'target') COMMENT = 'Carries a competitor energy drink but NOT Red Bull.',
        outlets.has_availability_conflict AS has_red_bull_conflict,
        outlets.listing_count AS listing_count,
        market.market AS market_code WITH SYNONYMS ('market', 'country', 'market code'),
        market.market_name AS market_name WITH SYNONYMS ('country name'),
        market.market_currency AS currency_code,
        platform.platform_name AS platform_name WITH SYNONYMS ('platform', 'delivery app', 'app'),
        chain.chain_name AS chain_name,
        chain.chain_size AS chain_size WITH SYNONYMS ('number of restaurants', 'locations'),
        product.brand AS brand WITH SYNONYMS ('drink brand'),
        product.manufacturer AS manufacturer,
        product.drink_type AS drink_subcategory WITH SYNONYMS ('drink type', 'energy or cola') COMMENT = 'Cola, Flavored Soft Drink, Energy, Tonic Water.',
        product.is_energy_drink AS is_energy_drink WITH SYNONYMS ('energy drink', 'is an energy drink'),
        product.is_red_bull AS is_red_bull WITH SYNONYMS ('is red bull'),
        product.is_competitor_energy AS is_competitor_energy WITH SYNONYMS ('monster or rockstar', 'competitor energy drink'),
        availability.listing_market AS market_code WITH SYNONYMS ('market', 'country'),
        availability.listing_carries_red_bull AS serves_red_bull,
        availability.listing_carries_competitor_energy AS serves_competitor_energy,
        availability.carries_sugarfree AS has_red_bull_sugarfree WITH SYNONYMS ('red bull sugarfree'),
        availability.carries_editions AS has_red_bull_editions WITH SYNONYMS ('red bull editions', 'flavours'),
        availability.is_primary_listing AS is_primary_listing,
        menu.menu_market AS market_code WITH SYNONYMS ('market', 'country'),
        menu.menu_brand AS brand,
        menu.menu_drink_type AS drink_subcategory WITH SYNONYMS ('drink type'),
        menu.menu_line_is_red_bull AS is_red_bull WITH SYNONYMS ('red bull menu line'),
        menu.menu_line_is_competitor_energy AS is_competitor_energy,
        menu.menu_section AS menu_section WITH SYNONYMS ('menu category'),
        menu.menu_is_addon AS is_addon,
        outlet_metrics.metric_market AS market_code WITH SYNONYMS ('market', 'country'),
        dates.scrape_day AS date_day WITH SYNONYMS ('date'),
        dates.scrape_month AS month_name,
        dates.scrape_weekday AS day_of_week_name
    )
    METRICS (
        outlets.outlet_count AS COUNT(DISTINCT outlets.outlet_key) WITH SYNONYMS ('number of outlets', 'outlet count', 'how many outlets') COMMENT = 'Distinct physical outlets.',
        outlets.red_bull_outlet_count AS COUNT(DISTINCT CASE WHEN outlets.serves_red_bull THEN outlets.outlet_key END) WITH SYNONYMS ('outlets carrying red bull', 'red bull outlets'),
        outlets.opportunity_outlet_count AS COUNT(DISTINCT CASE WHEN outlets.is_red_bull_opportunity THEN outlets.outlet_key END) WITH SYNONYMS ('opportunity outlets', 'white-space outlets'),
        outlets.red_bull_penetration_pct AS 100.0 * COUNT(DISTINCT CASE WHEN outlets.serves_red_bull THEN outlets.outlet_key END) / NULLIF(COUNT(DISTINCT outlets.outlet_key), 0) WITH SYNONYMS ('red bull penetration', 'percent carrying red bull', 'red bull coverage'),
        availability.n_listings AS COUNT(availability.availability_key) WITH SYNONYMS ('number of listings'),
        menu.n_menu_lines AS COUNT(menu.menu_item_key) WITH SYNONYMS ('number of menu items', 'menu lines'),
        menu.avg_line_price AS AVG(menu.line_price) WITH SYNONYMS ('average price', 'mean menu price'),
        outlet_metrics.avg_outlet_rating AS AVG(outlet_metrics.avg_rating) WITH SYNONYMS ('average rating'),
        outlet_metrics.avg_delivery_fee AS AVG(outlet_metrics.delivery_fee) WITH SYNONYMS ('average delivery fee')
    )
    COMMENT = 'Red Bull online food-delivery: outlet distribution, menu assortment, Red Bull vs competitor availability across USA / GBR / DEU (Q1 2024).';
