{{ config(materialized="table") }}

-- Full 2024 calendar (data spans 2024-01-29 .. 2024-03-15; buffer for future loads).
{{ dbt_date.get_date_dimension("2024-01-01", "2024-12-31") }}
