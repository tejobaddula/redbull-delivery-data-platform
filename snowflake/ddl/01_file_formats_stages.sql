-- 01_file_formats_stages.sql
-- TSV file format + internal named stage for the raw feeds.
-- Run as RB_LOADER (or a role with CREATE on RAW).

USE ROLE RB_LOADER;
USE DATABASE REDBULL_DELIVERY;
USE SCHEMA RAW;

------------------------------------------------------------------------------
-- File format: tab-delimited, double-quoted, header row, UTF-8.
-- Resilience choices:
--   PARSE_HEADER            -> load by column NAME, tolerate column reordering
--   ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE -> ragged rows don't kill the file
--   EMPTY_FIELD_AS_NULL     -> "" becomes NULL at the door
--   REPLACE_INVALID_CHARACTERS -> bad UTF-8 bytes -> U+FFFD instead of failing
------------------------------------------------------------------------------
CREATE OR REPLACE FILE FORMAT RB_TSV
    TYPE = CSV
    FIELD_DELIMITER = '\t'
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    PARSE_HEADER = TRUE
    ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE
    EMPTY_FIELD_AS_NULL = TRUE
    TRIM_SPACE = TRUE
    REPLACE_INVALID_CHARACTERS = TRUE
    ENCODING = 'UTF8'
    COMMENT = 'Case-study raw feeds (outlet / portfolio / matching)';

------------------------------------------------------------------------------
-- Internal named stage. Directory table on so we can list what landed.
-- Swap-in path for production: replace with an external stage on S3 +
-- STORAGE INTEGRATION, then wrap the COPY templates in CREATE PIPE.
------------------------------------------------------------------------------
CREATE STAGE IF NOT EXISTS RB_RAW_STAGE
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Landing stage for raw delivery feeds; path = <feed>/<period>/<market>/';
