-- COPY body for the PORTFOLIO feed.  Placeholders: {stage_path}
COPY INTO RAW.PORTFOLIO
FROM @RB_RAW_STAGE/{stage_path}
FILE_FORMAT = (FORMAT_NAME = RB_TSV)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
INCLUDE_METADATA = (
    _stg_file_name          = METADATA$FILENAME,
    _stg_file_row_number    = METADATA$FILE_ROW_NUMBER,
    _stg_file_last_modified = METADATA$FILE_LAST_MODIFIED,
    _load_ts                = METADATA$START_SCAN_TIME
)
ON_ERROR = CONTINUE;
