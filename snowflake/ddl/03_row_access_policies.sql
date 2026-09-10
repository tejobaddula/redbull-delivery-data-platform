-- 03_row_access_policies.sql
-- Market-scoped row-level security for the MARTS layer.
--   RB_ANALYST_USA/GBR/DEU  -> only their market's rows
--   RB_ANALYST_HQ / RB_TRANSFORMER / admins -> all rows
-- Run as ACCOUNTADMIN (needs CREATE ROW ACCESS POLICY + APPLY). Idempotent.
--
-- The policy is ATTACHED to tables by the dbt post-hook (macros/apply_market_row_access_policy.sql)
-- because dbt rebuilds MARTS tables with CREATE OR REPLACE, which drops attachments.

USE ROLE ACCOUNTADMIN;
USE DATABASE REDBULL_DELIVERY;
USE SCHEMA UTIL;

------------------------------------------------------------------------------
-- Role -> market mapping. Add a market = add a row (no policy change).
------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS UTIL.ROLE_MARKET_MAP (
    role_name    VARCHAR NOT NULL,
    market_code  VARCHAR NOT NULL,
    CONSTRAINT pk_role_market PRIMARY KEY (role_name, market_code)
);

MERGE INTO UTIL.ROLE_MARKET_MAP t
USING (
    SELECT 'RB_ANALYST_USA' role_name, 'USA' market_code
    UNION ALL SELECT 'RB_ANALYST_GBR', 'GBR'
    UNION ALL SELECT 'RB_ANALYST_DEU', 'DEU'
) s
ON t.role_name = s.role_name AND t.market_code = s.market_code
WHEN NOT MATCHED THEN INSERT (role_name, market_code) VALUES (s.role_name, s.market_code);

------------------------------------------------------------------------------
-- The policy. Bare `market_code` = the value from the protected row (policy arg);
-- `rm.market_code` = the mapping table column.
------------------------------------------------------------------------------
CREATE ROW ACCESS POLICY IF NOT EXISTS UTIL.RAP_MARKET
    AS (market_code VARCHAR) RETURNS BOOLEAN ->
        CURRENT_ROLE() IN (
            'ACCOUNTADMIN', 'SYSADMIN', 'RB_TRANSFORMER', 'RB_LOADER', 'RB_ANALYST_HQ'
        )
        OR EXISTS (
            SELECT 1
            FROM UTIL.ROLE_MARKET_MAP rm
            WHERE rm.role_name = CURRENT_ROLE()
              AND rm.market_code = market_code
        );

------------------------------------------------------------------------------
-- Let dbt (RB_TRANSFORMER) attach the policy to the tables it owns.
------------------------------------------------------------------------------
GRANT APPLY ON ROW ACCESS POLICY UTIL.RAP_MARKET TO ROLE RB_TRANSFORMER;
GRANT SELECT ON UTIL.ROLE_MARKET_MAP TO ROLE RB_TRANSFORMER;
-- the policy body reads the map at query time, as the querying role:
GRANT SELECT ON UTIL.ROLE_MARKET_MAP TO ROLE RB_ANALYST_HQ;
GRANT SELECT ON UTIL.ROLE_MARKET_MAP TO ROLE RB_ANALYST_USA;
GRANT SELECT ON UTIL.ROLE_MARKET_MAP TO ROLE RB_ANALYST_GBR;
GRANT SELECT ON UTIL.ROLE_MARKET_MAP TO ROLE RB_ANALYST_DEU;
