-- verify_rbac.sql
-- Live demo of market-scoped row-level security. Run top to bottom in a Snowsight
-- worksheet. Your user (TEJOB1706) has been granted all six RB_ roles so you can
-- switch between them.
--
-- Mechanism: ROW ACCESS POLICY REDBULL_DELIVERY.UTIL.RAP_MARKET, attached to every
-- MARTS table that carries a market_code column. It reads UTIL.ROLE_MARKET_MAP at
-- query time and compares CURRENT_ROLE() to the row's market_code.

USE DATABASE REDBULL_DELIVERY;
USE WAREHOUSE RB_BI_WH;

-- ============================================================================
-- 1. Where is the policy attached?
-- ============================================================================
SELECT ref_entity_name AS protected_table, policy_name
FROM TABLE(INFORMATION_SCHEMA.POLICY_REFERENCES(
    policy_name => 'REDBULL_DELIVERY.UTIL.RAP_MARKET'))
ORDER BY 1;
--  DIM_MARKET / DIM_OUTLET / FCT_MENU_ITEM / FCT_OUTLET_AVAILABILITY / FCT_OUTLET_METRIC

-- The role -> market mapping (add a market = add a row, no policy change):
SELECT * FROM UTIL.ROLE_MARKET_MAP ORDER BY 1;

-- ============================================================================
-- 2. A market analyst sees ONLY their market
-- ============================================================================
USE ROLE RB_ANALYST_USA;
SELECT market_code, COUNT(*) AS outlets FROM MARTS.DIM_OUTLET GROUP BY 1;
--  USA | 932,363         <- GBR and DEU are invisible, not zero-ed: they don't exist for this role

SELECT market_code, COUNT(*) FROM MARTS.FCT_MENU_ITEM GROUP BY 1;
--  (empty)               <- correct: USA has no portfolio data at all

SELECT * FROM MARTS.DIM_MARKET;
--  1 row: USA

USE ROLE RB_ANALYST_GBR;
SELECT market_code, COUNT(*) AS menu_lines FROM MARTS.FCT_MENU_ITEM GROUP BY 1;
--  GBR | 12,506,070      <- DEU's 1.3M rows are filtered out

USE ROLE RB_ANALYST_DEU;
SELECT market_code, COUNT(*) FROM MARTS.FCT_OUTLET_AVAILABILITY GROUP BY 1;
--  DEU | 51,128

-- ============================================================================
-- 3. HQ sees everything
-- ============================================================================
USE ROLE RB_ANALYST_HQ;
SELECT market_code, COUNT(*) AS outlets,
       ROUND(100 * AVG(IFF(serves_red_bull, 1, 0)), 1) AS pct_serves_red_bull
FROM MARTS.DIM_OUTLET GROUP BY 1 ORDER BY 1;
--  DEU 47,634  26.6
--  GBR 177,236 18.7
--  USA 932,363 14.3

-- ============================================================================
-- 4. Global reference dims are NOT filtered (no market_code column)
-- ============================================================================
USE ROLE RB_ANALYST_DEU;
SELECT COUNT(*) AS all_drinks_visible FROM MARTS.DIM_PRODUCT;   -- 331 for every role
SELECT COUNT(*) AS all_platforms_visible FROM MARTS.DIM_PLATFORM; -- 6 for every role

-- ============================================================================
-- 5. The policy cannot be bypassed by joining
-- ============================================================================
USE ROLE RB_ANALYST_GBR;
-- try to reach DEU data through a join to an unprotected dim:
SELECT o.market_code, COUNT(*)
FROM MARTS.FCT_OUTLET_AVAILABILITY f
JOIN MARTS.DIM_OUTLET o USING (outlet_key)
GROUP BY 1;
--  GBR only - both sides of the join are policy-protected

USE ROLE ACCOUNTADMIN;
